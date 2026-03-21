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
import UIKit
import os

private let syncLog = Logger(subsystem: "com.playerpath.app", category: "Sync")

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
    private var timer: Timer?
    /// Active background video/photo download tasks keyed by a local UUID so they
    /// can self-remove on completion and be bulk-cancelled on sign-out.
    private var pendingDownloadTasks: [UUID: Task<Void, Never>] = [:]
    /// Tokens for background/foreground NotificationCenter observers so they
    /// can be removed before re-adding (avoids duplicates when configure() is
    /// called more than once).
    private var backgroundObservers: [Any] = []

    private init() {
    }

    // Note: As a @MainActor singleton, deinit cannot access isolated properties.
    // Timer and task cleanup is handled by stopPeriodicSync() called on sign-out.

    // MARK: - Configuration

    /// Configure the sync coordinator with a ModelContext.
    /// Safe to call multiple times — updates the context and restarts the timer
    /// without leaking additional timers.
    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext

        // Remove any previous background/foreground observers to avoid duplicates
        // when configure() is called more than once.
        for observer in backgroundObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        backgroundObservers.removeAll()

        // Pause the timer when the app enters background
        let bgObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.timer?.invalidate()
                self?.timer = nil
            }
        }
        backgroundObservers.append(bgObserver)

        // Resume the timer when the app returns to foreground
        let fgObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.startPeriodicSync()
            }
        }
        backgroundObservers.append(fgObserver)

        startPeriodicSync()
    }

    // MARK: - Public Sync Methods

    /// Syncs all athletes for a user bidirectionally (upload + download + resolve)
    /// - Parameter user: The SwiftData User to sync athletes for
    func syncAthletes(for user: User) async throws {
        guard let context = modelContext else {
            return
        }


        do {
            try await uploadLocalAthletes(user, context: context)
            try await downloadRemoteAthletes(user, context: context)
            try await resolveConflicts(user: user, context: context)
        } catch {
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
            return
        }


        for athlete in dirtyAthletes {
            do {
                if let firestoreId = athlete.firestoreId {
                    // Update existing athlete in Firestore
                    try await FirestoreManager.shared.updateAthlete(
                        userId: (user.firebaseAuthUid ?? user.id.uuidString),
                        athleteId: firestoreId,
                        data: athlete.toFirestoreData()
                    )

                } else {
                    // Create new athlete in Firestore
                    let docId = try await FirestoreManager.shared.createAthlete(
                        userId: (user.firebaseAuthUid ?? user.id.uuidString),
                        data: athlete.toFirestoreData()
                    )
                    athlete.firestoreId = docId
                }

                // Mark as synced
                athlete.needsSync = false
                athlete.lastSyncDate = Date()
                athlete.version += 1

            } catch {
                appendSyncError(SyncError(
                    type: .uploadFailed,
                    entityId: athlete.id.uuidString,
                    message: "Failed to upload '\(athlete.name)': \(error.localizedDescription)"
                ))
            }
        }

        // Save all changes to SwiftData
        if context.hasChanges { try context.save() }
    }

    // MARK: - Download (Firestore → Local)

    private func downloadRemoteAthletes(_ user: User, context: ModelContext) async throws {

        let remoteAthletes = try await FirestoreManager.shared.fetchAthletes(
            userId: (user.firebaseAuthUid ?? user.id.uuidString)
        )

        guard !remoteAthletes.isEmpty else {
            return
        }


        // Track which Firestore IDs we've already linked to a local athlete
        // to prevent multiple remote duplicates from each creating a new local record.
        var claimedFirestoreIds = Set<String>()

        for remoteData in remoteAthletes {
            guard let remoteId = remoteData.id else { continue }

            // Skip if another remote record with the same name already claimed a local athlete
            // (handles duplicate Firestore documents for the same athlete)
            if claimedFirestoreIds.contains(remoteId) { continue }

            // 1. Match by firestoreId (exact link)
            var localAthlete = (user.athletes ?? []).first {
                $0.firestoreId == remoteId
            }

            // 2. Fallback: match by name for athletes that lost their firestoreId (reinstall/migration)
            if localAthlete == nil {
                localAthlete = (user.athletes ?? []).first {
                    $0.firestoreId == nil && $0.name == remoteData.name
                }
                if let matched = localAthlete {
                    // Re-link the local athlete to this Firestore document
                    matched.firestoreId = remoteId
                }
            }

            // 3. Fallback: match by name even if firestoreId is set to a different value
            //    (handles the case where duplicates were created and the first one already claimed a different ID)
            if localAthlete == nil {
                let nameMatch = (user.athletes ?? []).first {
                    $0.name == remoteData.name && !claimedFirestoreIds.contains($0.firestoreId ?? "")
                }
                if nameMatch != nil {
                    // This remote doc is a duplicate — skip creating a new athlete.
                    // The local athlete is already linked to a different Firestore doc.
                    claimedFirestoreIds.insert(remoteId)
                    continue
                }
            }

            if let local = localAthlete {
                claimedFirestoreIds.insert(remoteId)

                // Athlete exists locally - check if remote is newer
                let remoteUpdatedAt = remoteData.updatedAt ?? Date.distantPast
                let localUpdatedAt = local.lastSyncDate ?? Date.distantPast

                if remoteUpdatedAt > localUpdatedAt && !local.needsSync {
                    // Only write properties that actually changed to avoid
                    // dirtying the object and triggering unnecessary @Query updates.
                    var changed = false
                    if local.name != remoteData.name { local.name = remoteData.name; changed = true }
                    if let roleRaw = remoteData.primaryRole,
                       let role = AthleteRole(rawValue: roleRaw),
                       local.primaryRole != role {
                        local.primaryRole = role; changed = true
                    }
                    if local.version != remoteData.version { local.version = remoteData.version; changed = true }
                    if changed {
                        local.lastSyncDate = Date()
                    }

                } else if local.needsSync {
                    // Will be resolved in resolveConflicts()
                }

            } else {
                // Genuinely new athlete from another device - create locally

                let newAthlete = Athlete(name: remoteData.name)
                newAthlete.firestoreId = remoteId
                newAthlete.createdAt = remoteData.createdAt
                newAthlete.lastSyncDate = Date()
                newAthlete.needsSync = false
                newAthlete.version = remoteData.version
                newAthlete.user = user

                context.insert(newAthlete)
                claimedFirestoreIds.insert(remoteId)
            }
        }

        // Check for locally deleted athletes that still exist remotely
        let remoteAthleteIds = Set(remoteAthletes.compactMap { $0.id })
        for localAthlete in user.athletes ?? [] {
            if let firestoreId = localAthlete.firestoreId,
               !remoteAthleteIds.contains(firestoreId) {
                // Athlete was deleted on another device
                localAthlete.isDeletedRemotely = true
            }
        }

        // Save all changes
        if context.hasChanges { try context.save() }
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
            return
        }


        for _ in conflictedAthletes {
            // For now, local changes win (already marked needsSync)
            // Upload will overwrite remote version
        }

        if context.hasChanges { try context.save() }
    }

    // MARK: - Seasons Sync

    /// Syncs all seasons for a user bidirectionally (upload + download + resolve)
    /// - Parameter user: The SwiftData User to sync seasons for
    func syncSeasons(for user: User) async throws {
        guard let context = modelContext else {
            return
        }


        do {
            // Step 1: Upload local changes to Firestore
            try await uploadLocalSeasons(user, context: context)

            // Step 2: Download remote changes from Firestore
            try await downloadRemoteSeasons(user, context: context)

            // Step 3: Resolve conflicts (if any)
            try await resolveSeasonConflicts(user: user, context: context)


        } catch {
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
            return
        }


        for season in dirtySeasons {
            do {
                if let firestoreId = season.firestoreId {
                    // Update existing season in Firestore
                    try await FirestoreManager.shared.updateSeason(
                        userId: (user.firebaseAuthUid ?? user.id.uuidString),
                        seasonId: firestoreId,
                        data: season.toFirestoreData()
                    )

                } else {
                    // Create new season in Firestore
                    let docId = try await FirestoreManager.shared.createSeason(
                        userId: (user.firebaseAuthUid ?? user.id.uuidString),
                        data: season.toFirestoreData()
                    )
                    season.firestoreId = docId
                }

                // Mark as synced
                season.needsSync = false
                season.lastSyncDate = Date()
                season.version += 1

            } catch {
                appendSyncError(SyncError(
                    type: .uploadFailed,
                    entityId: season.id.uuidString,
                    message: "Failed to upload '\(season.name)': \(error.localizedDescription)"
                ))
            }
        }

        // Save all changes to SwiftData
        if context.hasChanges { try context.save() }
    }

    private func downloadRemoteSeasons(_ user: User, context: ModelContext) async throws {
        let remoteSeasons = try await FirestoreManager.shared.fetchSeasons(userId: (user.firebaseAuthUid ?? user.id.uuidString))

        guard !remoteSeasons.isEmpty else {
            return
        }


        // Get all local seasons
        let athletes = user.athletes ?? []
        let allLocalSeasons = athletes.flatMap { $0.seasons ?? [] }

        for remoteSeason in remoteSeasons {
            // Find local season by firestoreId
            let localSeason = allLocalSeasons.first {
                $0.firestoreId == remoteSeason.id
            }

            // Find parent athlete by athleteId (matches firestoreId or local UUID).
            // Falls back to the sole athlete if there's only one — handles legacy data
            // where athleteId references a stale local UUID from a previous install.
            let parentAthlete: Athlete? = athletes.first {
                $0.id.uuidString == remoteSeason.athleteId || $0.firestoreId == remoteSeason.athleteId
            } ?? (athletes.count == 1 ? athletes.first : nil)

            if let local = localSeason {
                // Only merge if remote is newer AND local has no pending changes.
                // If needsSync is true, local edits haven't uploaded yet — don't overwrite them.
                if (remoteSeason.updatedAt ?? Date.distantPast) > (local.lastSyncDate ?? Date.distantPast)
                    && !local.needsSync {
                    // Only write properties that actually changed to avoid
                    // dirtying the object and triggering unnecessary @Query updates.
                    var changed = false
                    if local.name != remoteSeason.name { local.name = remoteSeason.name; changed = true }
                    if local.startDate != remoteSeason.startDate { local.startDate = remoteSeason.startDate; changed = true }
                    if local.endDate != remoteSeason.endDate { local.endDate = remoteSeason.endDate; changed = true }
                    if local.isActive != remoteSeason.isActive { local.isActive = remoteSeason.isActive; changed = true }
                    if local.notes != remoteSeason.notes { local.notes = remoteSeason.notes; changed = true }
                    if local.version != remoteSeason.version { local.version = remoteSeason.version; changed = true }
                    if changed {
                        local.lastSyncDate = Date()
                    }
                }
            } else if let athlete = parentAthlete {
                // Create new local season from remote
                let newSeason = Season(
                    name: remoteSeason.name,
                    startDate: remoteSeason.startDate ?? Date.distantPast,
                    sport: remoteSeason.sport == "Softball" ? .softball : .baseball
                )
                newSeason.id = UUID(uuidString: remoteSeason.swiftDataId) ?? UUID()
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
            } else {
                syncLog.warning("Dropped remote season '\(remoteSeason.name)' (id: \(remoteSeason.id ?? "nil")) — no matching athlete found for athleteId '\(remoteSeason.athleteId)'")
            }
        }

        if context.hasChanges { try context.save() }
    }

    private func resolveSeasonConflicts(user: User, context: ModelContext) async throws {
        // For now, local changes win (already marked needsSync)
    }

    // MARK: - Games Sync

    /// Syncs all games for a user bidirectionally (upload + download + resolve)
    /// - Parameter user: The SwiftData User to sync games for
    func syncGames(for user: User) async throws {
        guard let context = modelContext else {
            return
        }


        do {
            try await uploadLocalGames(user, context: context)
            try await downloadRemoteGames(user, context: context)
            try await resolveGameConflicts(user: user, context: context)
        } catch {
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
            return
        }


        for game in dirtyGames {
            do {
                if let firestoreId = game.firestoreId {
                    // Update existing game in Firestore
                    try await FirestoreManager.shared.updateGame(
                        userId: (user.firebaseAuthUid ?? user.id.uuidString),
                        gameId: firestoreId,
                        data: game.toFirestoreData()
                    )

                } else {
                    // Create new game in Firestore
                    let docId = try await FirestoreManager.shared.createGame(
                        userId: (user.firebaseAuthUid ?? user.id.uuidString),
                        data: game.toFirestoreData()
                    )
                    game.firestoreId = docId
                }

                // Mark as synced
                game.needsSync = false
                game.lastSyncDate = Date()
                game.version += 1

            } catch {
                appendSyncError(SyncError(
                    type: .uploadFailed,
                    entityId: game.id.uuidString,
                    message: "Failed to upload game: \(error.localizedDescription)"
                ))
            }
        }

        // Save all changes to SwiftData
        if context.hasChanges { try context.save() }
    }

    private func downloadRemoteGames(_ user: User, context: ModelContext) async throws {
        let remoteGames = try await FirestoreManager.shared.fetchGames(userId: (user.firebaseAuthUid ?? user.id.uuidString))

        guard !remoteGames.isEmpty else {
            return
        }


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

            // Find parent athlete by athleteId (matches local UUID or firestoreId).
            // Falls back to sole athlete for legacy data with stale local UUIDs.
            let parentAthlete: Athlete? = athletes.first {
                $0.id.uuidString == remoteGame.athleteId || $0.firestoreId == remoteGame.athleteId
            } ?? (athletes.count == 1 ? athletes.first : nil)

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
                    // Only write properties that actually changed to avoid
                    // dirtying the object and triggering unnecessary @Query updates.
                    var changed = false
                    if local.opponent != remoteGame.opponent { local.opponent = remoteGame.opponent; changed = true }
                    if local.date != remoteGame.date { local.date = remoteGame.date; changed = true }
                    if local.isLive != remoteGame.isLive { local.isLive = remoteGame.isLive; changed = true }
                    if local.isComplete != remoteGame.isComplete { local.isComplete = remoteGame.isComplete; changed = true }
                    if local.year != remoteGame.year { local.year = remoteGame.year; changed = true }
                    if local.location != remoteGame.location { local.location = remoteGame.location; changed = true }
                    if local.notes != remoteGame.notes { local.notes = remoteGame.notes; changed = true }
                    if local.version != remoteGame.version { local.version = remoteGame.version; changed = true }
                    if changed {
                        local.lastSyncDate = Date()
                    }
                }
            } else if let athlete = parentAthlete {
                // Create new local game from remote
                let newGame = Game(
                    date: remoteGame.date ?? Date.distantPast,
                    opponent: remoteGame.opponent
                )
                newGame.id = UUID(uuidString: remoteGame.swiftDataId) ?? UUID()
                newGame.firestoreId = remoteGame.id
                newGame.isLive = remoteGame.isLive
                newGame.isComplete = remoteGame.isComplete
                newGame.year = remoteGame.year
                newGame.location = remoteGame.location
                newGame.notes = remoteGame.notes
                newGame.createdAt = remoteGame.createdAt
                newGame.lastSyncDate = Date()
                newGame.needsSync = false
                newGame.version = remoteGame.version
                newGame.athlete = athlete
                newGame.season = parentSeason
                context.insert(newGame)
            } else {
                syncLog.warning("Dropped remote game '\(remoteGame.opponent)' (id: \(remoteGame.id ?? "nil")) — no matching athlete found for athleteId '\(remoteGame.athleteId)'")
            }
        }

        if context.hasChanges { try context.save() }
    }

    private func resolveGameConflicts(user: User, context: ModelContext) async throws {
        // For now, local changes win (already marked needsSync)
    }

    // MARK: - Practices Sync (Phase 3)

    func syncPractices(for user: User) async throws {
        guard let context = modelContext else {
            return
        }


        do {
            // Step 1: Upload local changes to Firestore
            try await uploadLocalPractices(user, context: context)

            // Step 2: Download remote changes from Firestore
            try await downloadRemotePractices(user, context: context)

            // Step 3: Resolve conflicts (if any)
            try await resolvePracticeConflicts(user: user, context: context)


        } catch {
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
            return
        }


        for practice in dirtyPractices {
            if practice.isDeletedRemotely {
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
                } else {
                    // Create new
                    let docId = try await FirestoreManager.shared.createPractice(
                        userId: (user.firebaseAuthUid ?? user.id.uuidString),
                        data: practice.toFirestoreData()
                    )
                    practice.firestoreId = docId
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
            }
        }

        if context.hasChanges { try context.save() }
    }

    private func downloadRemotePractices(_ user: User, context: ModelContext) async throws {

        let remotePractices = try await FirestoreManager.shared.fetchPractices(
            userId: (user.firebaseAuthUid ?? user.id.uuidString)
        )

        let athletes = user.athletes ?? []
        let remotePracticeIds = Set(remotePractices.compactMap { $0.id })

        // Detect practices deleted on another device — remote set no longer contains them.
        // Safety: skip bulk deletion if remote returned empty but local has synced practices,
        // which can happen on transient Firestore failures or network timeouts.
        for athlete in athletes {
            let syncedLocalPractices = (athlete.practices ?? []).filter { $0.firestoreId != nil }
            if !syncedLocalPractices.isEmpty && remotePracticeIds.isEmpty {
                syncLog.warning("Remote returned 0 practices but \(syncedLocalPractices.count) synced practices exist locally — skipping deletion pass to prevent data loss")
            } else {
                for localPractice in syncedLocalPractices {
                    if let firestoreId = localPractice.firestoreId, !remotePracticeIds.contains(firestoreId) {
                        localPractice.delete(in: context)
                    }
                }
            }
        }

        guard !remotePractices.isEmpty else {
            if context.hasChanges { try context.save() }
            return
        }

        for remoteData in remotePractices {
            // Find athlete by athleteId (matches local UUID or firestoreId).
            // Falls back to sole athlete for legacy data with stale local UUIDs.
            guard let athlete = athletes.first(where: {
                $0.id.uuidString == remoteData.athleteId || $0.firestoreId == remoteData.athleteId
            }) ?? (athletes.count == 1 ? athletes.first : nil) else {
                continue
            }

            // Find local practice by firestoreId
            let localPractice = (athlete.practices ?? []).first {
                $0.firestoreId == remoteData.id
            }

            if let local = localPractice {
                // Practice exists locally - check if remote is newer AND no pending local changes
                let remoteUpdatedAt = remoteData.updatedAt ?? Date.distantPast
                let localSyncDate = local.lastSyncDate ?? Date.distantPast

                if remoteUpdatedAt > localSyncDate && !local.needsSync {
                    local.date = remoteData.date
                    local.practiceType = remoteData.practiceType ?? local.practiceType
                    local.lastSyncDate = Date()
                    local.version = remoteData.version
                    local.needsSync = false
                }
            } else {
                // New practice from remote - create locally
                let newPractice = Practice(date: remoteData.date ?? Date.distantPast)
                newPractice.id = UUID(uuidString: remoteData.swiftDataId) ?? UUID()
                newPractice.firestoreId = remoteData.id
                newPractice.createdAt = remoteData.createdAt
                newPractice.lastSyncDate = Date()
                newPractice.needsSync = false
                newPractice.version = remoteData.version
                newPractice.practiceType = remoteData.practiceType ?? "general"
                newPractice.athlete = athlete

                // Link to season if seasonId provided
                if let seasonId = remoteData.seasonId {
                    if let season = athlete.seasons?.first(where: { $0.id.uuidString == seasonId || $0.firestoreId == seasonId }) {
                        newPractice.season = season
                    }
                }

                context.insert(newPractice)
            }
        }

        if context.hasChanges { try context.save() }
    }

    private func resolvePracticeConflicts(user: User, context: ModelContext) async throws {
        // For now, local changes win (already marked needsSync)
    }

    // MARK: - Videos Sync (Cross-Device)

    /// Syncs video metadata for all athletes
    /// Note: Video files are uploaded to Storage via UploadQueueManager
    /// This syncs the Firestore metadata for cross-device discovery
    /// - Parameter user: The SwiftData User to sync videos for
    func syncVideos(for user: User) async throws {
        guard let context = modelContext else {
            return
        }


        do {
            // Step 1: Upload local video metadata that isn't synced yet
            try await uploadLocalVideoMetadata(user, context: context)

            // Step 2: Download remote videos from Firestore
            try await downloadRemoteVideos(user, context: context)


        } catch {
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
                if clip.isDeletedRemotely { continue }
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
            return
        }


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
            } catch {
                syncLog.error("Failed to save video metadata to Firestore: \(error.localizedDescription)")
            }
        }

        for clip in updatedVideos {
            guard let firestoreId = clip.firestoreId else { continue }
            do {
                try await VideoCloudManager.shared.updateVideoMetadata(
                    clipId: firestoreId,
                    isHighlight: clip.isHighlight,
                    note: clip.note,
                    playResultType: clip.playResult?.type,
                    pitchSpeed: clip.pitchSpeed,
                    gameId: clip.game.map { $0.firestoreId ?? $0.id.uuidString },
                    gameOpponent: clip.gameOpponent ?? clip.game?.opponent,
                    gameDate: clip.gameDate ?? clip.game?.date,
                    seasonId: clip.season.map { $0.firestoreId ?? $0.id.uuidString },
                    seasonName: clip.seasonName ?? clip.season?.displayName,
                    practiceId: clip.practice?.id.uuidString,
                    practiceDate: clip.practiceDate ?? clip.practice?.date
                )
                clip.needsSync = false
            } catch {
                syncLog.error("Failed to update video metadata in Firestore: \(error.localizedDescription)")
            }
        }

        if context.hasChanges { try context.save() }
    }

    private func downloadRemoteVideos(_ user: User, context: ModelContext) async throws {
        let athletes = user.athletes ?? []
        var athletesWithNewClips: [Athlete] = []

        for athlete in athletes {
            // Get video metadata from Firestore
            let remoteVideos = try await VideoCloudManager.shared.syncVideos(for: athlete)

            let localClips = athlete.videoClips ?? []
            let localClipsByID = Dictionary(uniqueKeysWithValues: localClips.map { ($0.id, $0) })

            // Detect clips deleted on another device — remote set no longer contains them.
            // Safety: skip bulk deletion if remote returned empty but local has clips,
            // which can happen on transient Firestore failures or network timeouts.
            let remoteVideoIds = Set(remoteVideos.map { $0.id })
            let syncedLocalClips = localClips.filter { $0.firestoreId != nil }
            if !syncedLocalClips.isEmpty && remoteVideoIds.isEmpty {
                syncLog.warning("Remote returned 0 videos but \(syncedLocalClips.count) synced clips exist locally — skipping deletion pass to prevent data loss")
            } else {
                for localClip in syncedLocalClips {
                    if !remoteVideoIds.contains(localClip.id) {
                        localClip.delete(in: context)
                    }
                }
            }

            let allLocalSeasons = athlete.seasons ?? []
            let allLocalPractices = athlete.practices ?? []
            // Mirror uploadLocalGames: collect from both athlete.games and season.games
            // so season-linked games are found during association lookup.
            let directGames = athlete.games ?? []
            let seasonGames = athlete.seasons?.flatMap { $0.games ?? [] } ?? []
            var seenGameIDs = Set<UUID>()
            let allLocalGames = (directGames + seasonGames).filter { seenGameIDs.insert($0.id).inserted }

            // Merge updates into existing clips where remote is newer and local has no pending changes
            for remoteVideo in remoteVideos {
                if remoteVideo.isDeleted { continue }
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
                if let gameId = remoteVideo.gameId {
                    localClip.game = allLocalGames.first { $0.id.uuidString == gameId || $0.firestoreId == gameId }
                }
                if let seasonId = remoteVideo.seasonId {
                    localClip.season = allLocalSeasons.first { $0.id.uuidString == seasonId || $0.firestoreId == seasonId }
                }
                if let practiceId = remoteVideo.practiceId {
                    localClip.practice = allLocalPractices.first { $0.id.uuidString == practiceId }
                }
                // Restore denormalized display fields — prefer remote values, then fall back
                // to resolved relationship so existing clips get backfilled automatically.
                localClip.gameOpponent = remoteVideo.gameOpponent ?? localClip.game?.opponent
                localClip.gameDate = remoteVideo.gameDate ?? localClip.game?.date
                localClip.practiceDate = remoteVideo.practiceDate ?? localClip.practice?.date
                localClip.seasonName = remoteVideo.seasonName ?? localClip.season?.displayName
                if let pitchSpeed = remoteVideo.pitchSpeed {
                    localClip.pitchSpeed = pitchSpeed
                }
                if let duration = remoteVideo.duration {
                    localClip.duration = duration
                }
                localClip.cloudURL = remoteVideo.downloadURL
                localClip.lastSyncDate = Date()
            }

            // Find videos that exist remotely but not locally — skip deleted ones
            let localVideoIds = Set(localClips.map { $0.id })
            let newRemoteVideos = remoteVideos.filter { !localVideoIds.contains($0.id) && !$0.isDeleted }

            guard !newRemoteVideos.isEmpty else {
                continue
            }


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
                newClip.pitchSpeed = remoteVideo.pitchSpeed
                newClip.duration = remoteVideo.duration
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
                if let gameId = remoteVideo.gameId {
                    newClip.game = allLocalGames.first { $0.id.uuidString == gameId || $0.firestoreId == gameId }
                } else if let gameOpponent = remoteVideo.gameOpponent {
                    newClip.game = allLocalGames.first { $0.opponent == gameOpponent }
                }
                if let seasonId = remoteVideo.seasonId {
                    newClip.season = allLocalSeasons.first { $0.id.uuidString == seasonId || $0.firestoreId == seasonId }
                }
                if let practiceId = remoteVideo.practiceId {
                    newClip.practice = allLocalPractices.first { $0.id.uuidString == practiceId }
                }
                // Restore denormalized display fields — prefer remote values, then fall back
                // to resolved relationship so data is always present even if Firestore fields
                // are missing (older records) or relationship linking fails.
                newClip.gameOpponent = remoteVideo.gameOpponent ?? newClip.game?.opponent
                newClip.gameDate = remoteVideo.gameDate ?? newClip.game?.date
                newClip.practiceDate = remoteVideo.practiceDate ?? newClip.practice?.date
                newClip.seasonName = remoteVideo.seasonName ?? newClip.season?.displayName

                context.insert(newClip)

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

        if context.hasChanges { try context.save() }

        // Rebuild derived statistics for athletes that received new clips.
        // GameStatistics and AthleteStatistics are not stored in Firestore — they are
        // computed from VideoClip.playResult relationships. After downloading clips we
        // must reconstruct them so stats are correct on a new device or after reinstall.
        for athlete in athletesWithNewClips {
            for game in athlete.games ?? [] {
                do {
                    try StatisticsService.shared.recalculateGameStatistics(for: game, context: context)
                } catch {
                    syncLog.error("Failed to recalculate game stats for '\(game.opponent)': \(error.localizedDescription)")
                }
            }
            do {
                try StatisticsService.shared.recalculateAthleteStatistics(for: athlete, context: context)
            } catch {
                syncLog.error("Failed to recalculate athlete stats for '\(athlete.name)': \(error.localizedDescription)")
            }
        }

        // Persist the recalculated statistics
        if !athletesWithNewClips.isEmpty {
            if context.hasChanges { try context.save() }
        }
    }

    /// Downloads the actual video file from Firebase Storage
    private func downloadVideoFile(clip: VideoClip, context: ModelContext) async {
        guard let cloudURL = clip.cloudURL else {
            return
        }

        // Generate local file path
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let clipsDirectory = documentsURL.appendingPathComponent("Clips", isDirectory: true)

        // Ensure directory exists
        do {
            try FileManager.default.createDirectory(at: clipsDirectory, withIntermediateDirectories: true)
        } catch {
            syncLog.error("Failed to create Clips directory: \(error.localizedDescription)")
        }

        let localPath = clipsDirectory.appendingPathComponent(clip.fileName).path

        // Skip if already downloaded
        if FileManager.default.fileExists(atPath: localPath) {
            clip.filePath = VideoClip.toRelativePath(localPath)
            ErrorHandlerService.shared.saveContext(context, caller: "SyncCoordinator.downloadVideo.alreadyExists")
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
            let thumbnailPath: String?
            do {
                thumbnailPath = try await ClipPersistenceService().generateThumbnail(for: videoURL)
            } catch {
                syncLog.warning("Failed to generate thumbnail for synced clip '\(clip.fileName)': \(error.localizedDescription)")
                thumbnailPath = nil
            }

            clip.filePath = VideoClip.toRelativePath(localPath)
            if let thumbnailPath {
                clip.thumbnailPath = thumbnailPath
            }
            ErrorHandlerService.shared.saveContext(context, caller: "SyncCoordinator.downloadVideo.success")


        } catch {
            syncLog.error("Video download failed for clip \(clip.id): \(error.localizedDescription)")
            // Delete the ghost record (and its PlayResult) so it gets re-created and
            // re-downloaded on the next sync cycle. Without this, the clip persists
            // with an empty filePath and no retry path.
            if let playResult = clip.playResult {
                context.delete(playResult)
            }
            context.delete(clip)
            ErrorHandlerService.shared.saveContext(context, caller: "SyncCoordinator.downloadVideo.cleanup")
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
                    syncLog.error("Failed to sync practice note to Firestore: \(error.localizedDescription)")
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

        if context.hasChanges { try context.save() }
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
                // Enforce storage limit before uploading (use live StoreKit tier)
                let fileSize: Int64
                do {
                    let attrs = try FileManager.default.attributesOfItem(atPath: photo.filePath)
                    fileSize = (attrs[.size] as? Int64) ?? 0
                } catch {
                    syncLog.error("Failed to read photo file size at '\(photo.filePath)': \(error.localizedDescription)")
                    continue
                }
                let tier = StoreKitManager.shared.currentTier
                let limitBytes = Int64(tier.storageLimitGB) * StorageConstants.bytesPerGB
                guard user.cloudStorageUsedBytes + fileSize <= limitBytes else {
                    continue
                }
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
                    // Update storage counter
                    if let uploadedSize = (try? FileManager.default.attributesOfItem(atPath: photo.filePath)[.size] as? Int64) {
                        user.cloudStorageUsedBytes += uploadedSize
                    } else {
                        syncLog.warning("Could not read uploaded photo file size for storage tracking")
                    }
                } catch {
                    syncLog.error("Failed to sync photo to Firestore: \(error.localizedDescription)")
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
                guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { continue }
                let photosDir = documentsURL.appendingPathComponent("Photos", isDirectory: true)
                do {
                    try FileManager.default.createDirectory(at: photosDir, withIntermediateDirectories: true)
                } catch {
                    syncLog.error("Failed to create Photos directory: \(error.localizedDescription)")
                    continue
                }
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
                    newPhoto.game = (athlete.games ?? []).first { $0.id.uuidString == gameId || $0.firestoreId == gameId }
                }
                if let practiceId = remotePhoto.practiceId {
                    newPhoto.practice = (athlete.practices ?? []).first { $0.id.uuidString == practiceId || $0.firestoreId == practiceId }
                }
                if let seasonId = remotePhoto.seasonId {
                    newPhoto.season = (athlete.seasons ?? []).first { $0.id.uuidString == seasonId || $0.firestoreId == seasonId }
                }

                context.insert(newPhoto)

                // Download the image file in the background if not already present.
                // Task self-removes on completion.
                let taskID = UUID()
                let photoRef = newPhoto
                pendingDownloadTasks[taskID] = Task { [weak self] in
                    do {
                        try await VideoCloudManager.shared.downloadPhoto(from: downloadURL, to: localPath)
                    } catch {
                        // Mark for re-download on next sync so the photo doesn't remain as a ghost record
                        photoRef.needsSync = true
                    }
                    self?.pendingDownloadTasks.removeValue(forKey: taskID)
                }
            }
        }

        if context.hasChanges { try context.save() }
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
                    syncLog.error("Failed to sync coach to Firestore: \(error.localizedDescription)")
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
            }
        }

        if context.hasChanges { try context.save() }
    }

    // MARK: - Comprehensive Sync (All Entities)

    /// Syncs all entities for a user in dependency order.
    /// Each step is isolated — a failure in one entity type does not abort the rest.
    /// Order: Athletes → Seasons → Games → Practices → Videos → PracticeNotes → Photos → Coaches
    func syncAll(for user: User) async throws {
        guard !isSyncing else {
            return
        }
        isSyncing = true
        defer { isSyncing = false }


        await isolatedSync("Athletes")  { try await syncAthletes(for: user) }
        await isolatedSync("Seasons")   { try await syncSeasons(for: user) }
        await isolatedSync("Games")     { try await syncGames(for: user) }
        await isolatedSync("Practices") { try await syncPractices(for: user) }
        await isolatedSync("Videos")    { try await syncVideos(for: user) }
        await isolatedSync("Notes")     { try await syncPracticeNotes(for: user) }
        await isolatedSync("Photos")    { try await syncPhotos(for: user) }
        await isolatedSync("Coaches")   { try await syncCoaches(for: user) }

        lastSyncDate = Date()
    }

    /// Runs a sync step, recording any error without propagating it so sibling steps still run.
    private func isolatedSync(_ name: String, operation: () async throws -> Void) async {
        do {
            try await operation()
        } catch {
            appendSyncError(SyncError(type: .syncFailed, entityId: name, message: error.localizedDescription))
        }
    }

    /// Appends a sync error, capping the list at 100 entries to prevent unbounded growth.
    private func appendSyncError(_ error: SyncError) {
        syncErrors.append(error)
        if syncErrors.count > 100 {
            syncErrors.removeFirst(syncErrors.count - 100)
        }
        // Bridge to centralized error tracking for analytics
        ErrorHandlerService.shared.handle(
            AppError.syncFailed(error.message),
            context: "SyncCoordinator.\(error.type)",
            showAlert: false
        )
    }

    // MARK: - Background Sync

    private func startPeriodicSync() {
        timer?.invalidate() // Prevent multiple timers if configure() is called again
        timer = Timer.scheduledTimer(withTimeInterval: 300.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.syncInBackground()
            }
        }
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
            return nil
        }
    }

    /// Clears all sync errors
    func clearErrors() {
        syncErrors.removeAll()
    }

    /// Stops the periodic sync timer, removes background/foreground observers,
    /// and cancels any in-flight background downloads.
    func stopPeriodicSync() {
        timer?.invalidate()
        timer = nil
        for observer in backgroundObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        backgroundObservers.removeAll()
        pendingDownloadTasks.values.forEach { $0.cancel() }
        pendingDownloadTasks.removeAll()
    }
}

// MARK: - Supporting Types

/// Represents a queued sync operation (for future enhancement)
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
