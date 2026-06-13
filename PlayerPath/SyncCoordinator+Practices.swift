import Foundation
import SwiftData
import FirebaseAuth
import os

private let syncLog = Logger(subsystem: "com.playerpath.app", category: "Sync")

extension SyncCoordinator {
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

    func uploadLocalPractices(_ user: User, context: ModelContext) async throws {
        let athletes = user.athletes ?? []
        var allPractices: [Practice] = []

        // Collect all practices from all athletes
        for athlete in athletes {
            let practices = athlete.practices ?? []
            allPractices.append(contentsOf: practices)
        }

        // Only upload practices whose parent athlete has already synced (has a firestoreId).
        let dirtyPractices = allPractices.filter { $0.needsSync && $0.athlete?.firestoreId != nil }

        guard !dirtyPractices.isEmpty else {
            return
        }

        // See uploadLocalAthletes for the rollback rationale.
        var rollback: [(practice: Practice, needsSync: Bool, version: Int, lastSyncDate: Date?)] = []

        for practice in dirtyPractices {
            // A tombstoned practice still needs its remote delete propagated — see
            // the dedicated handling below rather than silently skipping.
            if practice.isDeletedRemotely {
                await propagatePracticeTombstone(practice, user: user, context: context)
                continue
            }

            let priorNeedsSync = practice.needsSync
            let priorVersion = practice.version
            let priorLastSync = practice.lastSyncDate
            do {
                // Bump version BEFORE serialization so the written doc carries it.
                practice.version += 1
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
                    ErrorHandlerService.shared.saveContext(context, caller: "SyncCoordinator.syncPractices.firestoreId")
                }

                practice.needsSync = false
                practice.lastSyncDate = Date()
                rollback.append((practice, priorNeedsSync, priorVersion, priorLastSync))

            } catch {
                practice.version = priorVersion
                appendSyncError(SyncError(
                    type: .uploadFailed,
                    entityId: practice.id.uuidString,
                    message: "Practice upload failed: \(error.localizedDescription)"
                ))
            }
        }

        // Save all changes to SwiftData — on failure restore every mutated sync field.
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                for entry in rollback {
                    entry.practice.needsSync = true
                    entry.practice.version = entry.version
                    entry.practice.lastSyncDate = entry.lastSyncDate
                }
                throw error
            }
        }
    }

    func downloadRemotePractices(_ user: User, context: ModelContext) async throws {

        let remotePractices = try await FirestoreManager.shared.fetchPractices(
            userId: (user.firebaseAuthUid ?? user.id.uuidString)
        )

        let athletes = user.athletes ?? []
        let remotePracticeIds = Set(remotePractices.compactMap { $0.id })

        /// Athletes whose stats need recalculation because practices were deleted
        /// remotely. The practice cascade removes attached clips + their play
        /// results, so athlete totals shift. Practices don't have game-level
        /// stats, so only athlete recalc is needed.
        var athletesAffectedByPracticeDeletion: Set<PersistentIdentifier> = []

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
                        athletesAffectedByPracticeDeletion.insert(athlete.persistentModelID)
                        localPractice.delete(in: context)
                    }
                }
            }
        }

        // Recalculate athlete stats before the early return so deletions still
        // flush when the remote set is empty (or contained only already-known practices).
        func recalcAffectedAthletes() {
            for athleteID in athletesAffectedByPracticeDeletion {
                guard let athlete = athletes.first(where: { $0.persistentModelID == athleteID }) else { continue }
                do {
                    try StatisticsService.shared.recalculateAthleteStatistics(for: athlete, context: context)
                } catch {
                    syncLog.error("Failed to recalculate athlete stats after remote practice deletion for '\(athlete.name)': \(error.localizedDescription)")
                }
            }
        }

        guard !remotePractices.isEmpty else {
            if context.hasChanges { try context.save() }
            recalcAffectedAthletes()
            if context.hasChanges { try context.save() }
            return
        }

        // Practices created from remote docs within this loop. Included in the
        // multi-device dedup search so a fresh device downloading two duplicate
        // Firestore docs doesn't create both locally.
        var newPracticesThisPass: [Practice] = []

        // Roster-wide local index so a practice re-homed to another profile (legacy
        // split) is found under its OLD owner by firestoreId and repointed below,
        // not duplicate-inserted. The Seasons/Games/Tournaments syncs already search
        // their local rows across all athletes; practices was the lone exception.
        let allLocalPractices = athletes.flatMap { $0.practices ?? [] }

        for remoteData in remotePractices {
            // Find athlete by athleteId (matches local UUID or firestoreId).
            // Falls back to sole athlete for legacy data with stale local UUIDs.
            guard let athlete = athletes.first(where: {
                $0.id.uuidString == remoteData.athleteId || $0.firestoreId == remoteData.athleteId
            }) ?? (athletes.count == 1 ? athletes.first : nil) else {
                if athletes.count > 1 {
                    syncLog.error("Orphaned remote practice (athleteId=\(remoteData.athleteId)) — no matching local athlete among \(athletes.count) profiles.")
                }
                continue
            }

            // Find local practice by firestoreId — roster-wide, so a re-homed practice
            // is matched under its old owner and repointed (not duplicate-inserted).
            var localPractice = (allLocalPractices + newPracticesThisPass).first {
                $0.firestoreId == remoteData.id
            }

            // Multi-device dedup: mirror downloadRemoteGames. Two devices on the same
            // account creating a practice on the same day with the same type should
            // converge to one local row instead of two after sync.
            //
            // Golf practice rounds / range sessions are EXEMPT (mirrors the golf
            // exemption in downloadRemoteGames): a golfer can legitimately log two
            // rounds — or two range sessions — at the same course on one day, and
            // collapsing them would drop one row (orphaning its clips) and skew the
            // GolfStatsSection averages. They still dedup reliably by firestoreId above.
            let practiceType = remoteData.practiceType ?? "general"
            let isGolfPractice = practiceType == PracticeType.practiceRound.rawValue
                || practiceType == PracticeType.rangeSession.rawValue
            if localPractice == nil, !isGolfPractice, let remoteDate = remoteData.date {
                let calendar = Calendar.current
                let matchesNaturalKey: (Practice) -> Bool = { practice in
                    practice.practiceType == practiceType
                        && (practice.date.map { calendar.isDate($0, inSameDayAs: remoteDate) } ?? false)
                }
                let candidates = (athlete.practices ?? []) + newPracticesThisPass.filter { $0.athlete?.id == athlete.id }
                if let unsynced = candidates.first(where: { $0.firestoreId == nil && matchesNaturalKey($0) }) {
                    // Link by firestoreId only — don't rewrite local UUID. Any video clip
                    // already uploaded with this practice's local UUID as practiceId would
                    // orphan if we changed it (see SyncCoordinator+Videos.swift:113,223).
                    unsynced.firestoreId = remoteData.id
                    localPractice = unsynced
                    syncLog.info("Multi-device dedup: linked local practice (\(practiceType)) to remote \(remoteData.id ?? "nil")")
                } else if candidates.contains(where: { $0.firestoreId != nil && $0.firestoreId != remoteData.id && matchesNaturalKey($0) }) {
                    syncLog.info("Multi-device dedup: skipped duplicate remote practice (id: \(remoteData.id ?? "nil"))")
                    continue
                }
            }

            if let local = localPractice {
                let remoteUpdatedAt = remoteData.updatedAt ?? Date.distantPast
                let localSyncDate = local.lastSyncDate ?? Date.distantPast
                let remoteIsNewer = remoteUpdatedAt > localSyncDate

                if remoteIsNewer && local.needsSync {
                    syncLog.warning("Sync conflict on practice (\(local.date?.formatted(.dateTime.month().day()) ?? "undated")): local has pending changes, skipping remote update")
                    appendSyncError(SyncError(
                        type: .conflictResolution,
                        entityId: local.id.uuidString,
                        message: "Practice modified on both devices — local changes kept"
                    ))
                } else if remoteIsNewer {
                    local.date = remoteData.date
                    local.practiceType = remoteData.practiceType ?? local.practiceType
                    // Holes is optional and only populated for golf practice
                    // rounds; preserve nil semantics on baseball/range docs.
                    if let h = remoteData.holes { local.holes = h }
                    // Live-activity state (SchemaV26). A round/session started
                    // on another device surfaces as live here; End on either
                    // device clears it. Only overwrite when the remote doc
                    // explicitly carries the field — an older/partial doc that
                    // omits isLive must NOT flip an active local session to false.
                    if let isLive = remoteData.isLive {
                        local.isLive = isLive
                        local.liveStartDate = remoteData.liveStartDate
                        // Round ended on another device — drop this device's
                        // pending stale-session reminder too.
                        if !isLive {
                            GameAlertService.shared.cancelEndPracticeReminder(forID: local.id)
                        }
                    }
                    local.course = remoteData.course
                    // Re-home (legacy-split migration): re-bind the parent athlete when a
                    // remote athleteId change moved this practice to another profile. The
                    // season id is invariant across a split, so local.season stays valid.
                    // Only repoint when the parent resolves locally — never null it out.
                    if local.athlete?.id != athlete.id {
                        local.athlete = athlete
                    }
                    // Anchor to remote write time, not Date() — see uploadLocalAthletes.
                    local.lastSyncDate = remoteData.updatedAt ?? Date()
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
                newPractice.holes = remoteData.holes
                newPractice.isLive = remoteData.isLive ?? false
                newPractice.liveStartDate = remoteData.liveStartDate
                newPractice.course = remoteData.course
                newPractice.athlete = athlete

                // Link to season if seasonId provided
                if let seasonId = remoteData.seasonId {
                    if let season = athlete.seasons?.first(where: { $0.id.uuidString == seasonId || $0.firestoreId == seasonId }) {
                        newPractice.season = season
                    }
                }

                context.insert(newPractice)
                newPracticesThisPass.append(newPractice)
            }
        }

        if context.hasChanges { try context.save() }
        recalcAffectedAthletes()
        if context.hasChanges { try context.save() }
    }

    func resolvePracticeConflicts(user: User, context: ModelContext) async throws {
        // For now, local changes win (already marked needsSync)
    }

    /// Propagates a locally-tombstoned practice's deletion to Firestore, then
    /// clears its dirty flag so it doesn't re-enter the upload loop on every sync.
    /// Mirrors the soft-delete-then-clear branch in +HighlightReels. Best-effort:
    /// a failed remote delete leaves `needsSync` set so the next pass retries.
    /// (`Practice.isDeletedRemotely` is currently only ever false in shipping code;
    /// this keeps the latent tombstone path correct rather than silently looping.)
    private func propagatePracticeTombstone(_ practice: Practice, user: User, context: ModelContext) async {
        guard let firestoreId = practice.firestoreId else {
            // Never synced remotely — nothing to delete; just clear the flag.
            practice.needsSync = false
            return
        }
        do {
            try await FirestoreManager.shared.deletePractice(
                userId: (user.firebaseAuthUid ?? user.id.uuidString),
                practiceId: firestoreId
            )
            practice.needsSync = false
        } catch {
            syncLog.error("Failed to propagate practice tombstone \(firestoreId): \(error.localizedDescription)")
            // Leave needsSync set so the next sync retries the remote delete.
        }
    }
}
