import Foundation
import SwiftData
import FirebaseAuth
import os

private let syncLog = Logger(subsystem: "com.playerpath.app", category: "Sync")

extension SyncCoordinator {
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

    func uploadLocalSeasons(_ user: User, context: ModelContext) async throws {
        // Get all seasons from all athletes for this user
        let athletes = user.athletes ?? []
        let allSeasons = athletes.flatMap { $0.seasons ?? [] }
        // Only upload seasons whose parent athlete has already synced (has a firestoreId).
        // Uploading before that would persist the local UUID as athleteId in Firestore,
        // causing orphaned records on other devices.
        let dirtySeasons = allSeasons.filter { $0.needsSync && !$0.isDeletedRemotely && $0.athlete?.firestoreId != nil }

        guard !dirtySeasons.isEmpty else {
            return
        }

        var syncedSeasons: [Season] = []

        for season in dirtySeasons {
            do {
                if let firestoreId = season.firestoreId {
                    try await FirestoreManager.shared.updateSeason(
                        userId: (user.firebaseAuthUid ?? user.id.uuidString),
                        seasonId: firestoreId,
                        data: season.toFirestoreData()
                    )
                } else {
                    let docId = try await FirestoreManager.shared.createSeason(
                        userId: (user.firebaseAuthUid ?? user.id.uuidString),
                        data: season.toFirestoreData()
                    )
                    season.firestoreId = docId
                    ErrorHandlerService.shared.saveContext(context, caller: "SyncCoordinator.syncSeasons.firestoreId")
                }

                season.needsSync = false
                season.lastSyncDate = Date()
                season.version += 1
                syncedSeasons.append(season)

            } catch {
                appendSyncError(SyncError(
                    type: .uploadFailed,
                    entityId: season.id.uuidString,
                    message: "Failed to upload '\(season.name)': \(error.localizedDescription)"
                ))
            }
        }

        if context.hasChanges {
            do {
                try context.save()
            } catch {
                for season in syncedSeasons { season.needsSync = true }
                throw error
            }
        }
    }

    func downloadRemoteSeasons(_ user: User, context: ModelContext) async throws {
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

            if parentAthlete == nil && athletes.count > 1 {
                syncLog.error("Orphaned remote season '\(remoteSeason.name)' (athleteId=\(remoteSeason.athleteId)) — no matching local athlete among \(athletes.count) profiles. Data will be re-synced when the matching athlete syncs.")
            }

            if let local = localSeason {
                let remoteIsNewer = (remoteSeason.updatedAt ?? Date.distantPast) > (local.lastSyncDate ?? Date.distantPast)

                if remoteIsNewer && local.needsSync {
                    syncLog.warning("Sync conflict on season '\(local.name)': local has pending changes, skipping remote update")
                    appendSyncError(SyncError(
                        type: .conflictResolution,
                        entityId: local.id.uuidString,
                        message: "Season '\(local.name)' modified on both devices — local changes kept"
                    ))
                } else if remoteIsNewer {
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

    func resolveSeasonConflicts(user: User, context: ModelContext) async throws {
        // For now, local changes win (already marked needsSync)
    }
}
