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
    /// Active background video/photo download tasks keyed by a local UUID so they
    /// can self-remove on completion and be bulk-cancelled on sign-out.
    private var pendingDownloadTasks: [UUID: Task<Void, Never>] = [:]

    private init() {
        print("🔄 SyncCoordinator initialized")
    }

    // MARK: - Configuration

    /// Configure the sync coordinator with a ModelContext.
    /// Safe to call multiple times — updates the context and restarts the timer
    /// without leaking additional timers.
    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        startPeriodicSync()
        print("✅ SyncCoordinator configured with ModelContext")
    }

    // MARK: - Public Sync Methods

    /// Syncs all athletes for a user bidirectionally (upload + download + resolve)
    /// - Parameter user: The SwiftData User to sync athletes for
    func syncAthletes(for user: User) async throws {
        guard !isSyncing else {
            print("⚠️ Sync in progress, skipping direct syncAthletes call")
            return
        }
        guard let context = modelContext else {
            print("⚠️ Cannot sync - ModelContext not configured")
            return
        }

        print("🔄 Starting athlete sync for user: \(user.email)")

        do {
            try await uploadLocalAthletes(user, context: context)
            try await downloadRemoteAthletes(user, context: context)
            try await resolveConflicts(user: user, context: context)
            print("✅ Athlete sync completed successfully")
        } catch {
            print("❌ Athlete sync failed: \(error)")
            appendSyncError(SyncError(
                type: .syncFailed,
                entityId: (user.firebaseAuthUid ?? user.id.uuidString),
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
                        userId: (user.firebaseAuthUid ?? user.id.uuidString),
                        athleteId: firestoreId,
                        data: athlete.toFirestoreData()
                    )
                    print("✅ Updated athlete '\(athlete.name)' in Firestore")

                } else {
                    // Create new athlete in Firestore
                    let docId = try await FirestoreManager.shared.createAthlete(
                        userId: (user.firebaseAuthUid ?? user.id.uuidString),
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
                appendSyncError(SyncError(
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
            userId: (user.firebaseAuthUid ?? user.id.uuidString)
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
                    if let roleRaw = remoteData.primaryRole,
                       let role = AthleteRole(rawValue: roleRaw) {
                        local.primaryRole = role
                    }
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
            appendSyncError(SyncError(
                type: .syncFailed,
                entityId: (user.firebaseAuthUid ?? user.id.uuidString),
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
                        userId: (user.firebaseAuthUid ?? user.id.uuidString),
                        seasonId: firestoreId,
                        data: season.toFirestoreData()
                    )
                    print("✅ Updated season '\(season.name)' in Firestore")

                } else {
                    // Create new season in Firestore
                    let docId = try await FirestoreManager.shared.createSeason(
                        userId: (user.firebaseAuthUid ?? user.id.uuidString),
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
                appendSyncError(SyncError(
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
        let remoteSeasons = try await FirestoreManager.shared.fetchSeasons(userId: (user.firebaseAuthUid ?? user.id.uuidString))

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
                // Only merge if remote is newer AND local has no pending changes.
                // If needsSync is true, local edits haven't uploaded yet — don't overwrite them.
                if (remoteSeason.updatedAt ?? Date.distantPast) > (local.lastSyncDate ?? Date.distantPast)
                    && !local.needsSync {
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
        guard !isSyncing else {
            print("⚠️ Sync in progress, skipping direct syncGames call")
            return
        }
        guard let context = modelContext else {
            print("⚠️ Cannot sync games - ModelContext not configured")
            return
        }

        print("🔄 Starting game sync for user: \(user.email)")

        do {
            try await uploadLocalGames(user, context: context)
            try await downloadRemoteGames(user, context: context)
            try await resolveGameConflicts(user: user, context: context)
            print("✅ Game sync completed successfully")
        } catch {
            print("❌ Game sync failed: \(error)")
            appendSyncError(SyncError(
                type: .syncFailed,
                entityId: (user.firebaseAuthUid ?? user.id.uuidString),
                message: "Game sync failed: \(error.localizedDescription)"
            ))
            throw error
        }
    }

    private func uploadLocalGames(_ user: User, context: ModelContext) async throws {
        // Collect games from both athlete.games and season.games, then deduplicate by ID.
        // A game can appear in both collections if it has both athlete + season relationships.
        let athletes = user.athletes ?? []
        let allGamesRaw = athletes.flatMap { athlete in
            (athlete.seasons?.flatMap { $0.games ?? [] } ?? []) + (athlete.games ?? [])
        }
        var seenGameIDs = Set<UUID>()
        let allGames = allGamesRaw.filter { seenGameIDs.insert($0.id).inserted }
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
                        userId: (user.firebaseAuthUid ?? user.id.uuidString),
                        gameId: firestoreId,
                        data: game.toFirestoreData()
                    )
                    print("✅ Updated game vs '\(game.opponent)' in Firestore")

                } else {
                    // Create new game in Firestore
                    let docId = try await FirestoreManager.shared.createGame(
                        userId: (user.firebaseAuthUid ?? user.id.uuidString),
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
                appendSyncError(SyncError(
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
        let remoteGames = try await FirestoreManager.shared.fetchGames(userId: (user.firebaseAuthUid ?? user.id.uuidString))

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
                // Only merge if remote is newer AND local has no pending changes.
                if (remoteGame.updatedAt ?? Date.distantPast) > (local.lastSyncDate ?? Date.distantPast)
                    && !local.needsSync {
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
            appendSyncError(SyncError(
                type: .syncFailed,
                entityId: (user.firebaseAuthUid ?? user.id.uuidString),
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
                        userId: (user.firebaseAuthUid ?? user.id.uuidString),
                        practiceId: firestoreId,
                        data: practice.toFirestoreData()
                    )
                    print("✅ Updated practice \(practice.id)")
                } else {
                    // Create new
                    let docId = try await FirestoreManager.shared.createPractice(
                        userId: (user.firebaseAuthUid ?? user.id.uuidString),
                        data: practice.toFirestoreData()
                    )
                    practice.firestoreId = docId
                    print("✅ Created practice \(practice.id) with Firestore ID \(docId)")
                }

                practice.needsSync = false
                practice.lastSyncDate = Date()
                practice.version += 1

            } catch {
                appendSyncError(SyncError(
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
            userId: (user.firebaseAuthUid ?? user.id.uuidString)
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

    // MARK: - Videos Sync (Cross-Device)

    /// Syncs video metadata for all athletes
    /// Note: Video files are uploaded to Storage via UploadQueueManager
    /// This syncs the Firestore metadata for cross-device discovery
    /// - Parameter user: The SwiftData User to sync videos for
    func syncVideos(for user: User) async throws {
        guard let context = modelContext else {
            print("⚠️ Cannot sync videos - ModelContext not configured")
            return
        }

        print("🔄 Starting video sync for user: \(user.email)")

        do {
            // Step 1: Upload local video metadata that isn't synced yet
            try await uploadLocalVideoMetadata(user, context: context)

            // Step 2: Download remote videos from Firestore
            try await downloadRemoteVideos(user, context: context)

            print("✅ Video sync completed successfully")

        } catch {
            print("❌ Video sync failed: \(error)")
            appendSyncError(SyncError(
                type: .syncFailed,
                entityId: (user.firebaseAuthUid ?? user.id.uuidString),
                message: "Video sync failed: \(error.localizedDescription)"
            ))
            throw error
        }
    }

    private func uploadLocalVideoMetadata(_ user: User, context: ModelContext) async throws {
        let athletes = user.athletes ?? []

        var newVideos: [(VideoClip, Athlete)] = []
        var updatedVideos: [VideoClip] = []

        for athlete in athletes {
            let videos = athlete.videoClips ?? []
            for clip in videos {
                if clip.isUploaded && clip.cloudURL != nil && clip.firestoreId == nil {
                    // New clip — full metadata upload
                    newVideos.append((clip, athlete))
                } else if clip.needsSync && clip.firestoreId != nil && clip.isUploaded {
                    // Existing clip with dirty metadata (e.g. isHighlight or note changed)
                    updatedVideos.append(clip)
                }
            }
        }

        guard !newVideos.isEmpty || !updatedVideos.isEmpty else {
            print("✅ No local video metadata needs Firestore sync")
            return
        }

        print("📤 Syncing \(newVideos.count) new + \(updatedVideos.count) updated video(s) to Firestore")

        for (clip, athlete) in newVideos {
            guard let cloudURL = clip.cloudURL else { continue }
            do {
                try await VideoCloudManager.shared.saveVideoMetadataToFirestore(
                    clip,
                    athlete: athlete,
                    downloadURL: cloudURL
                )
                clip.firestoreId = clip.id.uuidString
                clip.needsSync = false
                print("✅ Synced new video metadata: \(clip.fileName)")
            } catch {
                print("❌ Failed to sync new video metadata \(clip.fileName): \(error)")
            }
        }

        for clip in updatedVideos {
            guard let firestoreId = clip.firestoreId else { continue }
            do {
                try await VideoCloudManager.shared.updateVideoMetadata(
                    clipId: firestoreId,
                    isHighlight: clip.isHighlight,
                    note: clip.note
                )
                clip.needsSync = false
                print("✅ Synced updated video metadata: \(clip.fileName)")
            } catch {
                print("❌ Failed to sync updated video metadata \(clip.fileName): \(error)")
            }
        }

        try context.save()
    }

    private func downloadRemoteVideos(_ user: User, context: ModelContext) async throws {
        let athletes = user.athletes ?? []
        var athletesWithNewClips: [Athlete] = []

        for athlete in athletes {
            // Get video metadata from Firestore
            let remoteVideos = try await VideoCloudManager.shared.syncVideos(for: athlete)

            let localClips = athlete.videoClips ?? []
            let localClipsByID = Dictionary(uniqueKeysWithValues: localClips.map { ($0.id, $0) })

            // Merge updates into existing clips where remote is newer and local has no pending changes
            for remoteVideo in remoteVideos {
                guard let localClip = localClipsByID[remoteVideo.id],
                      remoteVideo.updatedAt > (localClip.lastSyncDate ?? .distantPast),
                      !localClip.needsSync else { continue }

                localClip.isHighlight = remoteVideo.isHighlight
                localClip.note = remoteVideo.note
                if let rawValue = remoteVideo.playResultRawValue,
                   let playResultType = PlayResultType(rawValue: rawValue) {
                    if let existing = localClip.playResult {
                        existing.type = playResultType
                    } else {
                        let playResult = PlayResult(type: playResultType)
                        localClip.playResult = playResult
                        context.insert(playResult)
                    }
                }
                localClip.lastSyncDate = Date()
            }

            // Find videos that exist remotely but not locally
            let localVideoIds = Set(localClips.map { $0.id })
            let newRemoteVideos = remoteVideos.filter { !localVideoIds.contains($0.id) }

            guard !newRemoteVideos.isEmpty else {
                continue
            }

            print("📥 Found \(newRemoteVideos.count) new videos from Firestore for \(athlete.name)")

            for remoteVideo in newRemoteVideos {
                // Create local VideoClip from remote metadata
                let newClip = VideoClip(
                    fileName: remoteVideo.fileName,
                    filePath: "" // Will be set when downloaded
                )
                newClip.id = remoteVideo.id
                newClip.cloudURL = remoteVideo.downloadURL
                newClip.isUploaded = true // It's already in the cloud
                newClip.createdAt = remoteVideo.createdAt
                newClip.isHighlight = remoteVideo.isHighlight
                newClip.note = remoteVideo.note
                newClip.firestoreId = remoteVideo.id.uuidString
                newClip.needsSync = false
                newClip.athlete = athlete

                // Reconstruct PlayResult from the stored raw value
                if let rawValue = remoteVideo.playResultRawValue,
                   let playResultType = PlayResultType(rawValue: rawValue) {
                    let playResult = PlayResult(type: playResultType)
                    newClip.playResult = playResult
                    context.insert(playResult)
                }

                // Link to game by stable ID first; fall back to opponent name for older records
                // that were uploaded before gameId was stored.
                let games = athlete.games ?? []
                if let gameId = remoteVideo.gameId {
                    newClip.game = games.first {
                        $0.id.uuidString == gameId || $0.firestoreId == gameId
                    }
                } else if let gameOpponent = remoteVideo.gameOpponent {
                    newClip.game = games.first { $0.opponent == gameOpponent }
                }

                context.insert(newClip)
                print("✅ Created local VideoClip from remote: \(remoteVideo.fileName)")

                // Queue video for background download; task self-removes on completion.
                let taskID = UUID()
                pendingDownloadTasks[taskID] = Task { [weak self] in
                    guard let self else { return }
                    await downloadVideoFile(clip: newClip, context: context)
                    pendingDownloadTasks.removeValue(forKey: taskID)
                }
            }

            athletesWithNewClips.append(athlete)
        }

        try context.save()

        // Rebuild derived statistics for athletes that received new clips.
        // GameStatistics and AthleteStatistics are not stored in Firestore — they are
        // computed from VideoClip.playResult relationships. After downloading clips we
        // must reconstruct them so stats are correct on a new device or after reinstall.
        for athlete in athletesWithNewClips {
            for game in athlete.games ?? [] {
                try? StatisticsService.shared.recalculateGameStatistics(for: game, context: context)
            }
            try? StatisticsService.shared.recalculateAthleteStatistics(for: athlete, context: context)
        }
    }

    /// Downloads the actual video file from Firebase Storage
    private func downloadVideoFile(clip: VideoClip, context: ModelContext) async {
        guard let cloudURL = clip.cloudURL else {
            print("⚠️ Cannot download video - no cloud URL")
            return
        }

        // Generate local file path
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let clipsDirectory = documentsURL.appendingPathComponent("Clips", isDirectory: true)

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: clipsDirectory, withIntermediateDirectories: true)

        let localPath = clipsDirectory.appendingPathComponent(clip.fileName).path

        // Skip if already downloaded
        if FileManager.default.fileExists(atPath: localPath) {
            clip.filePath = localPath
            try? context.save()
            print("✅ Video already exists locally: \(clip.fileName)")
            return
        }

        do {
            try await VideoCloudManager.shared.downloadVideo(
                from: cloudURL,
                to: localPath,
                clipId: clip.id
            )

            // Generate thumbnail from the now-local video file if one doesn't exist.
            let videoURL = URL(fileURLWithPath: localPath)
            let thumbnailPath = try? await ClipPersistenceService().generateThumbnail(for: videoURL)

            await MainActor.run {
                clip.filePath = localPath
                if let thumbnailPath {
                    clip.thumbnailPath = thumbnailPath
                }
                try? context.save()
            }

            print("✅ Downloaded video: \(clip.fileName)")

        } catch {
            print("❌ Failed to download video \(clip.fileName): \(error)")
        }
    }

    // MARK: - Practice Notes Sync

    func syncPracticeNotes(for user: User) async throws {
        guard let context = modelContext else { return }
        guard let userId = Auth.auth().currentUser?.uid else { return }

        let athletes = user.athletes ?? []
        let allPractices = athletes.flatMap { $0.practices ?? [] }

        for practice in allPractices {
            guard let practiceFirestoreId = practice.firestoreId else { continue }

            // Upload dirty notes
            let dirtyNotes = (practice.notes ?? []).filter { $0.needsSync }
            for note in dirtyNotes {
                do {
                    if let noteFirestoreId = note.firestoreId {
                        try await FirestoreManager.shared.updatePracticeNote(
                            userId: userId,
                            practiceFirestoreId: practiceFirestoreId,
                            noteId: noteFirestoreId,
                            data: note.toFirestoreData(practiceFirestoreId: practiceFirestoreId)
                        )
                    } else {
                        let docId = try await FirestoreManager.shared.createPracticeNote(
                            userId: userId,
                            practiceFirestoreId: practiceFirestoreId,
                            data: note.toFirestoreData(practiceFirestoreId: practiceFirestoreId)
                        )
                        note.firestoreId = docId
                    }
                    note.needsSync = false
                } catch {
                    print("❌ Failed to sync practice note: \(error)")
                }
            }

            // Download notes that exist remotely but not locally
            let remoteNotes = try await FirestoreManager.shared.fetchPracticeNotes(
                userId: userId,
                practiceFirestoreId: practiceFirestoreId
            )
            let localNoteIds = Set((practice.notes ?? []).compactMap { $0.firestoreId })
            for remoteNote in remoteNotes where !localNoteIds.contains(remoteNote.id ?? "") {
                let newNote = PracticeNote(content: remoteNote.content)
                newNote.createdAt = remoteNote.createdAt
                newNote.firestoreId = remoteNote.id
                newNote.needsSync = false
                newNote.practice = practice
                context.insert(newNote)
            }
        }

        try context.save()
        print("✅ Practice notes sync completed")
    }

    // MARK: - Photos Sync

    func syncPhotos(for user: User) async throws {
        guard let context = modelContext else { return }
        guard let ownerUID = Auth.auth().currentUser?.uid else { return }

        let athletes = user.athletes ?? []

        for athlete in athletes {
            let photos = athlete.photos ?? []

            // Upload new photos that haven't been synced
            for photo in photos where photo.cloudURL == nil && photo.needsSync {
                guard FileManager.default.fileExists(atPath: photo.filePath) else { continue }
                do {
                    let cloudURL = try await VideoCloudManager.shared.uploadPhoto(
                        at: URL(fileURLWithPath: photo.filePath),
                        ownerUID: ownerUID
                    )
                    photo.cloudURL = cloudURL
                    let firestoreId = try await FirestoreManager.shared.createPhoto(
                        data: photo.toFirestoreData(ownerUID: ownerUID)
                    )
                    photo.firestoreId = firestoreId
                    photo.needsSync = false
                    print("✅ Uploaded photo: \(photo.fileName)")
                } catch {
                    print("❌ Failed to upload photo \(photo.fileName): \(error)")
                }
            }

            // Download photos that exist remotely but not locally
            let athleteStableId = athlete.firestoreId ?? athlete.id.uuidString
            let remotePhotos = try await FirestoreManager.shared.fetchPhotos(
                uploadedBy: ownerUID,
                athleteId: athleteStableId
            )
            let localPhotoIds = Set(photos.compactMap { $0.firestoreId })

            for remotePhoto in remotePhotos where !localPhotoIds.contains(remotePhoto.id ?? "") {
                guard let downloadURL = remotePhoto.downloadURL else { continue }

                // Build local path
                let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                let photosDir = documentsURL.appendingPathComponent("Photos", isDirectory: true)
                try? FileManager.default.createDirectory(at: photosDir, withIntermediateDirectories: true)
                let localPath = photosDir.appendingPathComponent(remotePhoto.fileName).path

                let newPhoto = Photo(fileName: remotePhoto.fileName, filePath: localPath)
                newPhoto.id = UUID(uuidString: remotePhoto.swiftDataId) ?? UUID()
                newPhoto.cloudURL = downloadURL
                newPhoto.caption = remotePhoto.caption
                newPhoto.createdAt = remotePhoto.createdAt
                newPhoto.firestoreId = remotePhoto.id
                newPhoto.needsSync = false
                newPhoto.athlete = athlete

                // Link to game/practice/season by ID if available
                if let gameId = remotePhoto.gameId {
                    newPhoto.game = (athlete.games ?? []).first { $0.id.uuidString == gameId }
                }
                if let practiceId = remotePhoto.practiceId {
                    newPhoto.practice = (athlete.practices ?? []).first { $0.id.uuidString == practiceId }
                }
                if let seasonId = remotePhoto.seasonId {
                    newPhoto.season = (athlete.seasons ?? []).first { $0.id.uuidString == seasonId }
                }

                context.insert(newPhoto)

                // Download the image file in the background if not already present.
                // Task self-removes on completion.
                let taskID = UUID()
                pendingDownloadTasks[taskID] = Task { [weak self] in
                    do {
                        try await VideoCloudManager.shared.downloadPhoto(from: downloadURL, to: localPath)
                    } catch {
                        print("❌ Failed to download photo \(remotePhoto.fileName): \(error)")
                    }
                    self?.pendingDownloadTasks.removeValue(forKey: taskID)
                }
            }
        }

        try context.save()
        print("✅ Photos sync completed")
    }

    // MARK: - Coaches Sync

    func syncCoaches(for user: User) async throws {
        guard let context = modelContext else { return }
        guard let userId = Auth.auth().currentUser?.uid else { return }

        let athletes = user.athletes ?? []

        for athlete in athletes {
            guard let athleteFirestoreId = athlete.firestoreId else { continue }

            let coaches = athlete.coaches ?? []

            // Upload dirty coaches
            for coach in coaches where coach.needsSync {
                do {
                    if let coachFirestoreId = coach.firestoreId {
                        try await FirestoreManager.shared.updateCoach(
                            userId: userId,
                            athleteFirestoreId: athleteFirestoreId,
                            coachId: coachFirestoreId,
                            data: coach.toFirestoreData(athleteFirestoreId: athleteFirestoreId)
                        )
                    } else {
                        let docId = try await FirestoreManager.shared.createCoach(
                            userId: userId,
                            athleteFirestoreId: athleteFirestoreId,
                            data: coach.toFirestoreData(athleteFirestoreId: athleteFirestoreId)
                        )
                        coach.firestoreId = docId
                    }
                    coach.needsSync = false
                } catch {
                    print("❌ Failed to sync coach \(coach.name): \(error)")
                }
            }

            // Download coaches that exist remotely but not locally
            let remoteCoaches = try await FirestoreManager.shared.fetchCoaches(
                userId: userId,
                athleteFirestoreId: athleteFirestoreId
            )
            let localCoachIds = Set(coaches.compactMap { $0.firestoreId })
            for remoteCoach in remoteCoaches where !localCoachIds.contains(remoteCoach.id ?? "") {
                let newCoach = Coach(
                    name: remoteCoach.name,
                    role: remoteCoach.role,
                    phone: remoteCoach.phone ?? "",
                    email: remoteCoach.email,
                    notes: remoteCoach.notes ?? ""
                )
                newCoach.createdAt = remoteCoach.createdAt
                newCoach.firestoreId = remoteCoach.id
                newCoach.needsSync = false
                newCoach.firebaseCoachID = remoteCoach.firebaseCoachID
                newCoach.lastInvitationStatus = remoteCoach.invitationStatus
                newCoach.athlete = athlete
                context.insert(newCoach)
                print("✅ Restored coach from Firestore: \(remoteCoach.name)")
            }
        }

        try context.save()
        print("✅ Coaches sync completed")
    }

    // MARK: - Comprehensive Sync (All Entities)

    /// Syncs all entities for a user in dependency order.
    /// Each step is isolated — a failure in one entity type does not abort the rest.
    /// Order: Athletes → Seasons → Games → Practices → Videos → PracticeNotes → Photos → Coaches
    func syncAll(for user: User) async throws {
        guard !isSyncing else {
            print("⚠️ Sync already in progress, skipping")
            return
        }
        isSyncing = true
        defer { isSyncing = false }

        print("🔄 Starting comprehensive sync (Athletes → Seasons → Games → Practices → Videos → Notes → Photos → Coaches)")

        await isolatedSync("Athletes")  { try await syncAthletes(for: user) }
        await isolatedSync("Seasons")   { try await syncSeasons(for: user) }
        await isolatedSync("Games")     { try await syncGames(for: user) }
        await isolatedSync("Practices") { try await syncPractices(for: user) }
        await isolatedSync("Videos")    { try await syncVideos(for: user) }
        await isolatedSync("Notes")     { try await syncPracticeNotes(for: user) }
        await isolatedSync("Photos")    { try await syncPhotos(for: user) }
        await isolatedSync("Coaches")   { try await syncCoaches(for: user) }

        lastSyncDate = Date()
        print("✅ Comprehensive sync completed")
    }

    /// Runs a sync step, recording any error without propagating it so sibling steps still run.
    private func isolatedSync(_ name: String, operation: () async throws -> Void) async {
        do {
            try await operation()
        } catch {
            print("⚠️ \(name) sync failed (non-blocking): \(error)")
            appendSyncError(SyncError(type: .syncFailed, entityId: name, message: error.localizedDescription))
        }
    }

    /// Appends a sync error, capping the list at 100 entries to prevent unbounded growth.
    private func appendSyncError(_ error: SyncError) {
        syncErrors.append(error)
        if syncErrors.count > 100 {
            syncErrors.removeFirst(syncErrors.count - 100)
        }
    }

    // MARK: - Background Sync

    private func startPeriodicSync() {
        timer?.invalidate() // Prevent multiple timers if configure() is called again
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
        guard let firebaseEmail = Auth.auth().currentUser?.email else {
            return nil
        }

        // Predicate fetch — avoids loading all User rows into memory.
        var descriptor = FetchDescriptor<User>(
            predicate: #Predicate<User> { user in
                user.email == firebaseEmail
            }
        )
        descriptor.fetchLimit = 1

        do {
            return try context.fetch(descriptor).first
        } catch {
            print("❌ Failed to fetch current user: \(error)")
            return nil
        }
    }

    /// Clears all sync errors
    func clearErrors() {
        syncErrors.removeAll()
    }

    /// Stops the periodic sync timer and cancels any in-flight background downloads
    func stopPeriodicSync() {
        timer?.invalidate()
        timer = nil
        pendingDownloadTasks.values.forEach { $0.cancel() }
        pendingDownloadTasks.removeAll()
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
