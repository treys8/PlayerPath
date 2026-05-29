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


        // Pre-upload sync-state snapshot per athlete so a failed BATCH save can roll
        // back ALL mutated sync fields, not just needsSync. Without this the inflated
        // version + advanced lastSyncDate ship on the retry, and the advanced
        // lastSyncDate makes downloadRemoteAthletes skip genuinely-newer remote
        // updates. firestoreId is intentionally NOT rolled back: for new athletes it
        // is already persisted by the immediate saveContext below, and undoing it
        // would orphan the freshly-created Firestore doc.
        var rollback: [(athlete: Athlete, needsSync: Bool, version: Int, lastSyncDate: Date?)] = []

        for athlete in dirtyAthletes {
            let priorNeedsSync = athlete.needsSync
            let priorVersion = athlete.version
            let priorLastSync = athlete.lastSyncDate
            do {
                // Bump version BEFORE serialization so the written doc carries the
                // incremented version (not the stale pre-bump value).
                athlete.version += 1
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
                rollback.append((athlete, priorNeedsSync, priorVersion, priorLastSync))

            } catch {
                // Upload failed — undo this athlete's optimistic version bump.
                athlete.version = priorVersion
                appendSyncError(SyncError(
                    type: .uploadFailed,
                    entityId: athlete.id.uuidString,
                    message: "Failed to upload '\(athlete.name)': \(error.localizedDescription)"
                ))
            }
        }

        // Save all changes to SwiftData — on failure restore every mutated sync
        // field so the next sync retries from a consistent state.
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                for entry in rollback {
                    entry.athlete.needsSync = true
                    entry.athlete.version = entry.version
                    entry.athlete.lastSyncDate = entry.lastSyncDate
                }
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
                    // Same drift recovery as the firestoreId-match branch — the
                    // name fallback implies a reinstall that lost firestoreId,
                    // so local.id almost certainly drifted too.
                    if let remoteUUID = UUID(uuidString: remoteData.swiftDataId), matched.id != remoteUUID {
                        matched.id = remoteUUID
                    }
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

                // UUID drift recovery. Firestore's `id` field is the canonical
                // per-athlete UUID — once set on first upload, it follows the athlete
                // forever. Reinstalls used to overwrite local.id with a fresh UUID(),
                // drifting it away from Firestore. Reconcile here. Safe because
                // SwiftData relationships are object refs, not UUID-keyed.
                if let remoteUUID = UUID(uuidString: remoteData.swiftDataId), local.id != remoteUUID {
                    local.id = remoteUUID
                }

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
                    if let sportRaw = remoteData.sport,
                       let sport = Sport(rawValue: sportRaw),
                       local.sport != sport {
                        local.sport = sport; changed = true
                    }
                    if let remoteTrackStats = remoteData.trackStatsEnabled,
                       local.trackStatsEnabled != remoteTrackStats {
                        local.trackStatsEnabled = remoteTrackStats; changed = true
                    }
                    let remoteGroupID = remoteData.personGroupID.flatMap(UUID.init(uuidString:))
                    if local.personGroupID != remoteGroupID {
                        local.personGroupID = remoteGroupID; changed = true
                    }
                    if local.version != remoteData.version { local.version = remoteData.version; changed = true }
                    if changed {
                        // Anchor lastSyncDate to the remote write time, NOT Date(). Using
                        // "now" makes a later third-device write with a slightly older
                        // updatedAt look stale and get skipped. Fall back to now only when
                        // the remote doc has no updatedAt (legacy docs).
                        local.lastSyncDate = remoteData.updatedAt ?? Date()
                    }
                }

            } else {
                // Genuinely new athlete from another device - create locally

                let newAthlete = Athlete(name: remoteData.name)
                // Preserve the athlete's original UUID across devices. Without this,
                // a second device would assign a fresh UUID(), which silently breaks
                // any data keyed by athlete UUID (e.g. sharedFolders.athleteUUID).
                if let remoteUUID = UUID(uuidString: remoteData.swiftDataId) {
                    newAthlete.id = remoteUUID
                }
                newAthlete.firestoreId = remoteId
                newAthlete.createdAt = remoteData.createdAt
                newAthlete.lastSyncDate = Date()
                newAthlete.needsSync = false
                newAthlete.version = remoteData.version
                newAthlete.trackStatsEnabled = remoteData.trackStatsEnabled ?? true
                newAthlete.personGroupID = remoteData.personGroupID.flatMap(UUID.init(uuidString:))
                // Mirror the update-branch decode so primaryRole also propagates
                // on first sync to a new device (without this, role silently
                // defaults to .batter here while the update branch writes it).
                if let roleRaw = remoteData.primaryRole,
                   let role = AthleteRole(rawValue: roleRaw) {
                    newAthlete.primaryRole = role
                }
                if let sportRaw = remoteData.sport,
                   let sport = Sport(rawValue: sportRaw) {
                    newAthlete.sport = sport
                }
                newAthlete.user = user

                context.insert(newAthlete)
                claimedFirestoreIds.insert(remoteId)
            }
        }

        // Mark locally-present athletes that vanished from the remote set as
        // deleted-on-another-device. Gated on connectivity: Firestore's persistent
        // cache can return a stale/empty set OFFLINE without throwing, and a blip
        // must never flip an entire multi-athlete account (Plus=3, Pro=5) to
        // deleted. Matches the destructive-reconciliation gate in +HoleScores /
        // +HighlightReels.
        if ConnectivityMonitor.shared.isConnected {
            let remoteAthleteIds = Set(remoteAthletes.compactMap { $0.id })
            for localAthlete in user.athletes ?? [] {
                if let firestoreId = localAthlete.firestoreId,
                   !remoteAthleteIds.contains(firestoreId) {
                    localAthlete.isDeletedRemotely = true
                }
            }
        } else {
            syncLog.warning("Skipping athlete deletion pass — offline (would risk wiping synced athletes)")
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
