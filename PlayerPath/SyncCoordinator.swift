//
//  SyncCoordinator.swift
//  PlayerPath
//
//  Core service for bidirectional Firestore sync
//  Syncs SwiftData models (Athletes, Seasons, Games, etc.) to Firestore for cross-device access
//

import Foundation
import SwiftData
import FirebaseAuth
import Combine

/// Coordinates bidirectional sync between SwiftData (local) and Firestore (cloud)
/// Implements local-first architecture with background sync and conflict resolution
@MainActor
@Observable
final class SyncCoordinator {

    static let shared = SyncCoordinator()

    // MARK: - Published State

    var isSyncing: Bool = false
    var lastSyncDate: Date?
    var syncErrors: [SyncError] = []

    // MARK: - Private Properties

    private var modelContext: ModelContext?
    private var syncQueue: [SyncOperation] = []
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        print("🔄 SyncCoordinator initialized")
    }

    // MARK: - Configuration

    /// Configure the sync coordinator with a ModelContext
    /// Call this once during app launch with the main ModelContext
    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        startPeriodicSync()
        print("✅ SyncCoordinator configured with ModelContext")
    }

    // MARK: - Public Sync Methods

    /// Syncs all athletes for a user bidirectionally (upload + download + resolve)
    /// - Parameter user: The SwiftData User to sync athletes for
    func syncAthletes(for user: User) async throws {
        guard let context = modelContext else {
            print("⚠️ Cannot sync - ModelContext not configured")
            return
        }

        // Prevent concurrent syncs
        guard !isSyncing else {
            print("⚠️ Sync already in progress, skipping")
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        print("🔄 Starting athlete sync for user: \(user.email)")

        do {
            // Step 1: Upload local changes to Firestore
            try await uploadLocalAthletes(user, context: context)

            // Step 2: Download remote changes from Firestore
            try await downloadRemoteAthletes(user, context: context)

            // Step 3: Resolve conflicts (if any)
            try await resolveConflicts(user: user, context: context)

            lastSyncDate = Date()
            print("✅ Athlete sync completed successfully")

        } catch {
            print("❌ Athlete sync failed: \(error)")
            syncErrors.append(SyncError(
                type: .syncFailed,
                entityId: user.id.uuidString,
                message: error.localizedDescription
            ))
            throw error
        }
    }

    // MARK: - Upload (Local → Firestore)

    private func uploadLocalAthletes(_ user: User, context: ModelContext) async throws {
        let athletes = user.athletes ?? []
        let dirtyAthletes = athletes.filter { $0.needsSync && !$0.isDeletedRemotely }

        guard !dirtyAthletes.isEmpty else {
            print("✅ No local athletes need uploading")
            return
        }

        print("📤 Uploading \(dirtyAthletes.count) local athletes to Firestore")

        for athlete in dirtyAthletes {
            do {
                if let firestoreId = athlete.firestoreId {
                    // Update existing athlete in Firestore
                    try await FirestoreManager.shared.updateAthlete(
                        userId: user.id.uuidString,
                        athleteId: firestoreId,
                        data: athlete.toFirestoreData()
                    )
                    print("✅ Updated athlete '\(athlete.name)' in Firestore")

                } else {
                    // Create new athlete in Firestore
                    let docId = try await FirestoreManager.shared.createAthlete(
                        userId: user.id.uuidString,
                        data: athlete.toFirestoreData()
                    )
                    athlete.firestoreId = docId
                    print("✅ Created athlete '\(athlete.name)' in Firestore with ID: \(docId)")
                }

                // Mark as synced
                athlete.needsSync = false
                athlete.lastSyncDate = Date()
                athlete.version += 1

            } catch {
                print("❌ Failed to upload athlete '\(athlete.name)': \(error)")
                syncErrors.append(SyncError(
                    type: .uploadFailed,
                    entityId: athlete.id.uuidString,
                    message: "Failed to upload '\(athlete.name)': \(error.localizedDescription)"
                ))
            }
        }

        // Save all changes to SwiftData
        try context.save()
        print("✅ Saved athlete upload metadata to SwiftData")
    }

    // MARK: - Download (Firestore → Local)

    private func downloadRemoteAthletes(_ user: User, context: ModelContext) async throws {
        print("📥 Downloading athletes from Firestore for user: \(user.email)")

        let remoteAthletes = try await FirestoreManager.shared.fetchAthletes(
            userId: user.id.uuidString
        )

        guard !remoteAthletes.isEmpty else {
            print("✅ No remote athletes found")
            return
        }

        print("📥 Found \(remoteAthletes.count) athletes in Firestore")

        for remoteData in remoteAthletes {
            // Find local athlete by firestoreId
            let localAthlete = (user.athletes ?? []).first {
                $0.firestoreId == remoteData.id
            }

            if let local = localAthlete {
                // Athlete exists locally - check if remote is newer
                let remoteUpdatedAt = remoteData.updatedAt ?? Date.distantPast
                let localUpdatedAt = local.lastSyncDate ?? Date.distantPast

                if remoteUpdatedAt > localUpdatedAt && !local.needsSync {
                    // Remote is newer and local doesn't have pending changes - merge
                    print("🔄 Merging remote changes for athlete '\(remoteData.name)'")
                    local.name = remoteData.name
                    local.lastSyncDate = Date()
                    local.version = remoteData.version

                } else if local.needsSync {
                    print("⚠️ Conflict detected for athlete '\(local.name)' - local has pending changes")
                    // Will be resolved in resolveConflicts()
                }

            } else {
                // New athlete from another device - create locally
                print("🆕 Creating new local athlete from Firestore: '\(remoteData.name)'")

                let newAthlete = Athlete(name: remoteData.name)
                newAthlete.firestoreId = remoteData.id
                newAthlete.createdAt = remoteData.createdAt
                newAthlete.lastSyncDate = Date()
                newAthlete.needsSync = false
                newAthlete.version = remoteData.version
                newAthlete.user = user

                context.insert(newAthlete)
            }
        }

        // Check for locally deleted athletes that still exist remotely
        let remoteAthleteIds = Set(remoteAthletes.compactMap { $0.id })
        for localAthlete in user.athletes ?? [] {
            if let firestoreId = localAthlete.firestoreId,
               !remoteAthleteIds.contains(firestoreId) {
                // Athlete was deleted on another device
                print("🗑️ Athlete '\(localAthlete.name)' was deleted remotely")
                localAthlete.isDeletedRemotely = true
            }
        }

        // Save all changes
        try context.save()
        print("✅ Saved downloaded athletes to SwiftData")
    }

    // MARK: - Conflict Resolution

    private func resolveConflicts(user: User, context: ModelContext) async throws {
        // Last-write-wins based on updatedAt timestamp
        // More sophisticated conflict resolution can be added in the future

        let athletes = user.athletes ?? []
        let conflictedAthletes = athletes.filter { athlete in
            athlete.needsSync && athlete.firestoreId != nil
        }

        guard !conflictedAthletes.isEmpty else {
            print("✅ No conflicts to resolve")
            return
        }

        print("⚠️ Resolving \(conflictedAthletes.count) conflicts using last-write-wins")

        for athlete in conflictedAthletes {
            // For now, local changes win (already marked needsSync)
            // Upload will overwrite remote version
            print("🔄 Conflict resolution: Local version of '\(athlete.name)' will be uploaded")
        }

        try context.save()
    }

    // MARK: - Seasons Sync

    /// Syncs all seasons for a user bidirectionally (upload + download + resolve)
    /// - Parameter user: The SwiftData User to sync seasons for
    func syncSeasons(for user: User) async throws {
        guard let context = modelContext else {
            print("⚠️ Cannot sync seasons - ModelContext not configured")
            return
        }

        print("🔄 Starting season sync for user: \(user.email)")

        do {
            // Step 1: Upload local changes to Firestore
            try await uploadLocalSeasons(user, context: context)

            // Step 2: Download remote changes from Firestore
            try await downloadRemoteSeasons(user, context: context)

            // Step 3: Resolve conflicts (if any)
            try await resolveSeasonConflicts(user: user, context: context)

            print("✅ Season sync completed successfully")

        } catch {
            print("❌ Season sync failed: \(error)")
            syncErrors.append(SyncError(
                type: .syncFailed,
                entityId: user.id.uuidString,
                message: "Season sync failed: \(error.localizedDescription)"
            ))
            throw error
        }
    }

    private func uploadLocalSeasons(_ user: User, context: ModelContext) async throws {
        // Get all seasons from all athletes for this user
        let athletes = user.athletes ?? []
        let allSeasons = athletes.flatMap { $0.seasons ?? [] }
        let dirtySeasons = allSeasons.filter { $0.needsSync && !$0.isDeletedRemotely }

        guard !dirtySeasons.isEmpty else {
            print("✅ No local seasons need uploading")
            return
        }

        print("📤 Uploading \(dirtySeasons.count) local seasons to Firestore")

        for season in dirtySeasons {
            do {
                if let firestoreId = season.firestoreId {
                    // Update existing season in Firestore
                    try await FirestoreManager.shared.updateSeason(
                        userId: user.id.uuidString,
                        seasonId: firestoreId,
                        data: season.toFirestoreData()
                    )
                    print("✅ Updated season '\(season.name)' in Firestore")

                } else {
                    // Create new season in Firestore
                    let docId = try await FirestoreManager.shared.createSeason(
                        userId: user.id.uuidString,
                        data: season.toFirestoreData()
                    )
                    season.firestoreId = docId
                    print("✅ Created season '\(season.name)' in Firestore with ID: \(docId)")
                }

                // Mark as synced
                season.needsSync = false
                season.lastSyncDate = Date()
                season.version += 1

            } catch {
                print("❌ Failed to upload season '\(season.name)': \(error)")
                syncErrors.append(SyncError(
                    type: .uploadFailed,
                    entityId: season.id.uuidString,
                    message: "Failed to upload '\(season.name)': \(error.localizedDescription)"
                ))
            }
        }

        // Save all changes to SwiftData
        try context.save()
        print("✅ Saved season upload metadata to SwiftData")
    }

    private func downloadRemoteSeasons(_ user: User, context: ModelContext) async throws {
        let remoteSeasons = try await FirestoreManager.shared.fetchSeasons(userId: user.id.uuidString)

        guard !remoteSeasons.isEmpty else {
            print("✅ No remote seasons to download")
            return
        }

        print("📥 Downloaded \(remoteSeasons.count) seasons from Firestore")

        // Get all local seasons
        let athletes = user.athletes ?? []
        let allLocalSeasons = athletes.flatMap { $0.seasons ?? [] }

        for remoteSeason in remoteSeasons {
            // Find local season by firestoreId
            let localSeason = allLocalSeasons.first {
                $0.firestoreId == remoteSeason.id
            }

            // Find parent athlete by athleteId
            let parentAthlete = athletes.first {
                $0.id.uuidString == remoteSeason.athleteId || $0.firestoreId == remoteSeason.athleteId
            }

            if let local = localSeason {
                // Merge if remote is newer
                if (remoteSeason.updatedAt ?? Date.distantPast) > (local.lastSyncDate ?? Date.distantPast) {
                    local.name = remoteSeason.name
                    local.startDate = remoteSeason.startDate
                    local.endDate = remoteSeason.endDate
                    local.isActive = remoteSeason.isActive
                    local.notes = remoteSeason.notes
                    local.lastSyncDate = Date()
                    local.version = remoteSeason.version
                    print("✅ Merged remote changes for season: \(remoteSeason.name)")
                }
            } else if let athlete = parentAthlete {
                // Create new local season from remote
                let newSeason = Season(
                    name: remoteSeason.name,
                    startDate: remoteSeason.startDate ?? Date(),
                    sport: remoteSeason.sport == "Softball" ? .softball : .baseball
                )
                newSeason.firestoreId = remoteSeason.id
                newSeason.endDate = remoteSeason.endDate
                newSeason.isActive = remoteSeason.isActive
                newSeason.notes = remoteSeason.notes
                newSeason.createdAt = remoteSeason.createdAt
                newSeason.lastSyncDate = Date()
                newSeason.needsSync = false
                newSeason.version = remoteSeason.version
                newSeason.athlete = athlete
                context.insert(newSeason)
                print("✅ Created local season from remote: \(remoteSeason.name)")
            } else {
                print("⚠️ Cannot find parent athlete for remote season: \(remoteSeason.name)")
            }
        }

        try context.save()
        print("✅ Saved remote seasons to SwiftData")
    }

    private func resolveSeasonConflicts(user: User, context: ModelContext) async throws {
        // For now, local changes win (already marked needsSync)
        print("✅ Season conflict resolution complete (using local-first)")
    }

    // MARK: - Games Sync

    /// Syncs all games for a user bidirectionally (upload + download + resolve)
    /// - Parameter user: The SwiftData User to sync games for
    func syncGames(for user: User) async throws {
        guard let context = modelContext else {
            print("⚠️ Cannot sync games - ModelContext not configured")
            return
        }

        print("🔄 Starting game sync for user: \(user.email)")

        do {
            // Step 1: Upload local changes to Firestore
            try await uploadLocalGames(user, context: context)

            // Step 2: Download remote changes from Firestore
            try await downloadRemoteGames(user, context: context)

            // Step 3: Resolve conflicts (if any)
            try await resolveGameConflicts(user: user, context: context)

            print("✅ Game sync completed successfully")

        } catch {
            print("❌ Game sync failed: \(error)")
            syncErrors.append(SyncError(
                type: .syncFailed,
                entityId: user.id.uuidString,
                message: "Game sync failed: \(error.localizedDescription)"
            ))
            throw error
        }
    }

    private func uploadLocalGames(_ user: User, context: ModelContext) async throws {
        // Get all games from all athletes for this user
        let athletes = user.athletes ?? []
        let allGames = athletes.flatMap { athlete in
            (athlete.seasons?.flatMap { $0.games ?? [] } ?? []) + (athlete.games ?? [])
        }
        let dirtyGames = allGames.filter { $0.needsSync && !$0.isDeletedRemotely }

        guard !dirtyGames.isEmpty else {
            print("✅ No local games need uploading")
            return
        }

        print("📤 Uploading \(dirtyGames.count) local games to Firestore")

        for game in dirtyGames {
            do {
                if let firestoreId = game.firestoreId {
                    // Update existing game in Firestore
                    try await FirestoreManager.shared.updateGame(
                        userId: user.id.uuidString,
                        gameId: firestoreId,
                        data: game.toFirestoreData()
                    )
                    print("✅ Updated game vs '\(game.opponent)' in Firestore")

                } else {
                    // Create new game in Firestore
                    let docId = try await FirestoreManager.shared.createGame(
                        userId: user.id.uuidString,
                        data: game.toFirestoreData()
                    )
                    game.firestoreId = docId
                    print("✅ Created game vs '\(game.opponent)' in Firestore with ID: \(docId)")
                }

                // Mark as synced
                game.needsSync = false
                game.lastSyncDate = Date()
                game.version += 1

            } catch {
                print("❌ Failed to upload game vs '\(game.opponent)': \(error)")
                syncErrors.append(SyncError(
                    type: .uploadFailed,
                    entityId: game.id.uuidString,
                    message: "Failed to upload game: \(error.localizedDescription)"
                ))
            }
        }

        // Save all changes to SwiftData
        try context.save()
        print("✅ Saved game upload metadata to SwiftData")
    }

    private func downloadRemoteGames(_ user: User, context: ModelContext) async throws {
        let remoteGames = try await FirestoreManager.shared.fetchGames(userId: user.id.uuidString)

        guard !remoteGames.isEmpty else {
            print("✅ No remote games to download")
            return
        }

        print("📥 Downloaded \(remoteGames.count) games from Firestore")

        // Get all local games and athletes/seasons
        let athletes = user.athletes ?? []
        let allLocalGames = athletes.flatMap { athlete in
            (athlete.seasons?.flatMap { $0.games ?? [] } ?? []) + (athlete.games ?? [])
        }
        let allLocalSeasons = athletes.flatMap { $0.seasons ?? [] }

        for remoteGame in remoteGames {
            // Find local game by firestoreId
            let localGame = allLocalGames.first {
                $0.firestoreId == remoteGame.id
            }

            // Find parent athlete by athleteId
            let parentAthlete = athletes.first {
                $0.id.uuidString == remoteGame.athleteId || $0.firestoreId == remoteGame.athleteId
            }

            // Find parent season by seasonId (optional)
            let parentSeason = allLocalSeasons.first {
                if let seasonId = remoteGame.seasonId {
                    return $0.id.uuidString == seasonId || $0.firestoreId == seasonId
                }
                return false
            }

            if let local = localGame {
                // Merge if remote is newer
                if (remoteGame.updatedAt ?? Date.distantPast) > (local.lastSyncDate ?? Date.distantPast) {
                    local.opponent = remoteGame.opponent
                    local.date = remoteGame.date
                    local.isLive = remoteGame.isLive
                    local.isComplete = remoteGame.isComplete
                    local.year = remoteGame.year
                    local.lastSyncDate = Date()
                    local.version = remoteGame.version
                    print("✅ Merged remote changes for game vs: \(remoteGame.opponent)")
                }
            } else if let athlete = parentAthlete {
                // Create new local game from remote
                let newGame = Game(
                    date: remoteGame.date ?? Date(),
                    opponent: remoteGame.opponent
                )
                newGame.firestoreId = remoteGame.id
                newGame.isLive = remoteGame.isLive
                newGame.isComplete = remoteGame.isComplete
                newGame.year = remoteGame.year
                newGame.createdAt = remoteGame.createdAt
                newGame.lastSyncDate = Date()
                newGame.needsSync = false
                newGame.version = remoteGame.version
                newGame.athlete = athlete
                newGame.season = parentSeason
                context.insert(newGame)
                print("✅ Created local game from remote vs: \(remoteGame.opponent)")
            } else {
                print("⚠️ Cannot find parent athlete for remote game vs: \(remoteGame.opponent)")
            }
        }

        try context.save()
        print("✅ Saved remote games to SwiftData")
    }

    private func resolveGameConflicts(user: User, context: ModelContext) async throws {
        // For now, local changes win (already marked needsSync)
        print("✅ Game conflict resolution complete (using local-first)")
    }

    // MARK: - Practices Sync (Phase 3)

    func syncPractices(for user: User) async throws {
        guard let context = modelContext else {
            print("⚠️ Cannot sync practices - ModelContext not configured")
            return
        }

        print("🔄 Starting practice sync for user: \(user.email)")

        do {
            // Step 1: Upload local changes to Firestore
            try await uploadLocalPractices(user, context: context)

            // Step 2: Download remote changes from Firestore
            try await downloadRemotePractices(user, context: context)

            // Step 3: Resolve conflicts (if any)
            try await resolvePracticeConflicts(user: user, context: context)

            print("✅ Practice sync completed successfully")

        } catch {
            print("❌ Practice sync failed: \(error)")
            syncErrors.append(SyncError(
                type: .syncFailed,
                entityId: user.id.uuidString,
                message: "Practice sync failed: \(error.localizedDescription)"
            ))
            throw error
        }
    }

    private func uploadLocalPractices(_ user: User, context: ModelContext) async throws {
        let athletes = user.athletes ?? []
        var allPractices: [Practice] = []

        // Collect all practices from all athletes
        for athlete in athletes {
            let practices = athlete.practices ?? []
            allPractices.append(contentsOf: practices)
        }

        let dirtyPractices = allPractices.filter { $0.needsSync }

        guard !dirtyPractices.isEmpty else {
            print("No local practice changes to upload")
            return
        }

        print("Uploading \(dirtyPractices.count) practices...")

        for practice in dirtyPractices {
            if practice.isDeletedRemotely {
                print("Skipping \(practice.id) - deleted remotely")
                continue
            }

            do {
                if let firestoreId = practice.firestoreId {
                    // Update existing
                    try await FirestoreManager.shared.updatePractice(
                        userId: user.id.uuidString,
                        practiceId: firestoreId,
                        data: practice.toFirestoreData()
                    )
                    print("✅ Updated practice \(practice.id)")
                } else {
                    // Create new
                    let docId = try await FirestoreManager.shared.createPractice(
                        userId: user.id.uuidString,
                        data: practice.toFirestoreData()
                    )
                    practice.firestoreId = docId
                    print("✅ Created practice \(practice.id) with Firestore ID \(docId)")
                }

                practice.needsSync = false
                practice.lastSyncDate = Date()
                practice.version += 1

            } catch {
                syncErrors.append(SyncError(
                    type: .uploadFailed,
                    entityId: practice.id.uuidString,
                    message: "Practice upload failed: \(error.localizedDescription)"
                ))
                print("❌ Failed to sync practice \(practice.id): \(error)")
            }
        }

        try context.save()
    }

    private func downloadRemotePractices(_ user: User, context: ModelContext) async throws {
        print("Downloading remote practices...")

        let remotePractices = try await FirestoreManager.shared.fetchPractices(
            userId: user.id.uuidString
        )

        guard !remotePractices.isEmpty else {
            print("No remote practices found")
            return
        }

        print("Found \(remotePractices.count) remote practices")

        let athletes = user.athletes ?? []

        for remoteData in remotePractices {
            // Find athlete by athleteId
            guard let athlete = athletes.first(where: { $0.id.uuidString == remoteData.athleteId }) else {
                print("⚠️ Skipping practice - athlete not found: \(remoteData.athleteId)")
                continue
            }

            // Find local practice by firestoreId
            let localPractice = (athlete.practices ?? []).first {
                $0.firestoreId == remoteData.id
            }

            if let local = localPractice {
                // Practice exists locally - check if remote is newer
                let remoteUpdatedAt = remoteData.updatedAt ?? Date.distantPast
                let localSyncDate = local.lastSyncDate ?? Date.distantPast

                if remoteUpdatedAt > localSyncDate {
                    print("Updating local practice \(local.id) with remote data")
                    local.date = remoteData.date
                    local.lastSyncDate = Date()
                    local.version = remoteData.version
                    local.needsSync = false
                }
            } else {
                // New practice from remote - create locally
                print("Creating new local practice from remote")
                let newPractice = Practice(date: remoteData.date ?? Date())
                newPractice.firestoreId = remoteData.id
                newPractice.createdAt = remoteData.createdAt
                newPractice.lastSyncDate = Date()
                newPractice.needsSync = false
                newPractice.version = remoteData.version
                newPractice.athlete = athlete

                // Link to season if seasonId provided
                if let seasonId = remoteData.seasonId {
                    if let season = athlete.seasons?.first(where: { $0.id.uuidString == seasonId }) {
                        newPractice.season = season
                    }
                }

                context.insert(newPractice)
            }
        }

        try context.save()
    }

    private func resolvePracticeConflicts(user: User, context: ModelContext) async throws {
        // For now, local changes win (already marked needsSync)
        print("✅ Practice conflict resolution complete (using local-first)")
    }

    // MARK: - Comprehensive Sync (All Entities)

    /// Syncs all entities for a user in dependency order
    /// Order: Athletes → Seasons → Games → Practices
    /// - Parameter user: The SwiftData User to sync all entities for
    func syncAll(for user: User) async throws {
        print("🔄 Starting comprehensive sync (Athletes → Seasons → Games → Practices)")

        // Sync in dependency order
        try await syncAthletes(for: user)
        try await syncSeasons(for: user)
        try await syncGames(for: user)
        try await syncPractices(for: user)

        lastSyncDate = Date()
        print("✅ Comprehensive sync completed successfully")
    }

    // MARK: - Background Sync

    private func startPeriodicSync() {
        // Sync every 60 seconds when app is active
        timer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.syncInBackground()
            }
        }
        print("⏰ Periodic sync enabled (every 60 seconds)")
    }

    private func syncInBackground() async {
        guard let context = modelContext else { return }

        // Get current user from SwiftData
        guard let user = getCurrentUser(context: context) else {
            return
        }

        do {
            // Sync all entities in dependency order
            try await syncAll(for: user)
        } catch {
            print("⚠️ Background sync failed: \(error)")
            // Don't throw - background sync failures shouldn't crash the app
        }
    }

    // MARK: - Helper Methods

    private func getCurrentUser(context: ModelContext) -> User? {
        // Get Firebase user email
        guard let firebaseEmail = Auth.auth().currentUser?.email else {
            return nil
        }

        // Fetch all users and filter by email
        let descriptor = FetchDescriptor<User>()

        do {
            let allUsers = try context.fetch(descriptor)
            let matchedUsers = allUsers.filter { $0.email.lowercased() == firebaseEmail.lowercased() }
            return matchedUsers.first
        } catch {
            print("❌ Failed to fetch current user: \(error)")
            return nil
        }
    }

    /// Clears all sync errors
    func clearErrors() {
        syncErrors.removeAll()
    }

    /// Stops the periodic sync timer
    func stopPeriodicSync() {
        timer?.invalidate()
        timer = nil
        print("⏸️ Periodic sync stopped")
    }
}

// MARK: - Supporting Types

/// Represents a queued sync operation (for future enhancement)
struct SyncOperation {
    enum OperationType {
        case createAthlete
        case updateAthlete
        case deleteAthlete
    }

    let type: OperationType
    let entityId: String
    let timestamp: Date
}

/// Represents a sync error for UI display
struct SyncError: Identifiable {
    enum ErrorType {
        case uploadFailed
        case downloadFailed
        case conflictResolution
        case syncFailed
    }

    let id = UUID()
    let type: ErrorType
    let entityId: String
    let message: String
    let timestamp: Date = Date()
}
