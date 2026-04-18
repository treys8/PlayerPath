import Foundation
import SwiftData
import FirebaseAuth
import os

private let syncLog = Logger(subsystem: "com.playerpath.app", category: "Sync")

extension SyncCoordinator {
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

    func uploadLocalAthletes(_ user: User, context: ModelContext) async throws {
        let athletes = user.athletes ?? []
        let dirtyAthletes = athletes.filter { $0.needsSync && !$0.isDeletedRemotely }

        guard !dirtyAthletes.isEmpty else {
            return
        }


        var syncedAthletes: [Athlete] = []

        for athlete in dirtyAthletes {
            do {
                if let firestoreId = athlete.firestoreId {
                    try await FirestoreManager.shared.updateAthlete(
                        userId: (user.firebaseAuthUid ?? user.id.uuidString),
                        athleteId: firestoreId,
                        data: athlete.toFirestoreData()
                    )
                } else {
                    let docId = try await FirestoreManager.shared.createAthlete(
                        userId: (user.firebaseAuthUid ?? user.id.uuidString),
                        data: athlete.toFirestoreData()
                    )
                    athlete.firestoreId = docId
                    // Save firestoreId immediately to prevent duplicate creation on crash
                    ErrorHandlerService.shared.saveContext(context, caller: "SyncCoordinator.syncAthletes.firestoreId")
                }

                athlete.needsSync = false
                athlete.lastSyncDate = Date()
                athlete.version += 1
                syncedAthletes.append(athlete)

            } catch {
                appendSyncError(SyncError(
                    type: .uploadFailed,
                    entityId: athlete.id.uuidString,
                    message: "Failed to upload '\(athlete.name)': \(error.localizedDescription)"
                ))
            }
        }

        // Save all changes to SwiftData — re-dirty on failure so next sync retries
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                for athlete in syncedAthletes { athlete.needsSync = true }
                throw error
            }
        }
    }

    // MARK: - Download (Firestore → Local)

    func downloadRemoteAthletes(_ user: User, context: ModelContext) async throws {

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

                if remoteUpdatedAt > localUpdatedAt && local.needsSync {
                    syncLog.warning("Sync conflict on athlete '\(local.name)': local has pending changes, skipping remote update")
                    appendSyncError(SyncError(
                        type: .conflictResolution,
                        entityId: local.id.uuidString,
                        message: "Athlete '\(local.name)' modified on both devices — local changes kept"
                    ))
                } else if remoteUpdatedAt > localUpdatedAt && !local.needsSync {
                    // Only write properties that actually changed to avoid
                    // dirtying the object and triggering unnecessary @Query updates.
                    var changed = false
                    if local.name != remoteData.name { local.name = remoteData.name; changed = true }
                    if let roleRaw = remoteData.primaryRole,
                       let role = AthleteRole(rawValue: roleRaw),
                       local.primaryRole != role {
                        local.primaryRole = role; changed = true
                    }
                    if let remoteTrackStats = remoteData.trackStatsEnabled,
                       local.trackStatsEnabled != remoteTrackStats {
                        local.trackStatsEnabled = remoteTrackStats; changed = true
                    }
                    if local.version != remoteData.version { local.version = remoteData.version; changed = true }
                    if changed {
                        local.lastSyncDate = Date()
                    }
                }

            } else {
                // Genuinely new athlete from another device - create locally

                let newAthlete = Athlete(name: remoteData.name)
                newAthlete.firestoreId = remoteId
                newAthlete.createdAt = remoteData.createdAt
                newAthlete.lastSyncDate = Date()
                newAthlete.needsSync = false
                newAthlete.version = remoteData.version
                newAthlete.trackStatsEnabled = remoteData.trackStatsEnabled ?? true
                // Mirror the update-branch decode so primaryRole also propagates
                // on first sync to a new device (without this, role silently
                // defaults to .batter here while the update branch writes it).
                if let roleRaw = remoteData.primaryRole,
                   let role = AthleteRole(rawValue: roleRaw) {
                    newAthlete.primaryRole = role
                }
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

    func resolveConflicts(user: User, context: ModelContext) async throws {
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
}
