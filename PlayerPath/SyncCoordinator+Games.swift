import Foundation
import SwiftData
import FirebaseAuth
import os

private let syncLog = Logger(subsystem: "com.playerpath.app", category: "Sync")

extension SyncCoordinator {
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

    func uploadLocalGames(_ user: User, context: ModelContext) async throws {
        // Collect games from both athlete.games and season.games, then deduplicate by ID.
        // A game can appear in both collections if it has both athlete + season relationships.
        let athletes = user.athletes ?? []
        let allGamesRaw = athletes.flatMap { athlete in
            (athlete.seasons?.flatMap { $0.games ?? [] } ?? []) + (athlete.games ?? [])
        }
        var seenGameIDs = Set<UUID>()
        let allGames = allGamesRaw.filter { seenGameIDs.insert($0.id).inserted }
        // Only upload games whose parent athlete has already synced (has a firestoreId).
        let dirtyGames = allGames.filter { $0.needsSync && !$0.isDeletedRemotely && $0.athlete?.firestoreId != nil }

        guard !dirtyGames.isEmpty else {
            return
        }

        var syncedGames: [Game] = []

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
                    ErrorHandlerService.shared.saveContext(context, caller: "SyncCoordinator.syncGames.firestoreId")
                }

                // Mark as synced
                game.needsSync = false
                game.lastSyncDate = Date()
                game.version += 1
                syncedGames.append(game)

            } catch {
                appendSyncError(SyncError(
                    type: .uploadFailed,
                    entityId: game.id.uuidString,
                    message: "Failed to upload game: \(error.localizedDescription)"
                ))
            }
        }

        // Save all changes to SwiftData — re-dirty on failure so next sync retries
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                for game in syncedGames { game.needsSync = true }
                throw error
            }
        }
    }

    func downloadRemoteGames(_ user: User, context: ModelContext) async throws {
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

            if parentAthlete == nil && athletes.count > 1 {
                syncLog.error("Orphaned remote game '\(remoteGame.opponent)' (athleteId=\(remoteGame.athleteId)) — no matching local athlete among \(athletes.count) profiles.")
            }

            // Find parent season by seasonId (optional)
            let parentSeason = allLocalSeasons.first {
                if let seasonId = remoteGame.seasonId {
                    return $0.id.uuidString == seasonId || $0.firestoreId == seasonId
                }
                return false
            }

            if let local = localGame {
                let remoteIsNewer = (remoteGame.updatedAt ?? Date.distantPast) > (local.lastSyncDate ?? Date.distantPast)

                if remoteIsNewer && local.needsSync {
                    syncLog.warning("Sync conflict on game vs '\(local.opponent)': local has pending changes, skipping remote update")
                    appendSyncError(SyncError(
                        type: .conflictResolution,
                        entityId: local.id.uuidString,
                        message: "Game vs '\(local.opponent)' modified on both devices — local changes kept"
                    ))
                } else if remoteIsNewer {
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

    func resolveGameConflicts(user: User, context: ModelContext) async throws {
        // For now, local changes win (already marked needsSync)
    }
}
