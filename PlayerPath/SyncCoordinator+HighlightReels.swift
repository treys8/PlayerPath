//
//  SyncCoordinator+HighlightReels.swift
//  PlayerPath
//
//  Sync for virtual highlight reels (SchemaV25 / v6.1 PR2). Uploads dirty
//  rows, propagates soft-deletes, and downloads remote-only rows per athlete.
//  Doc id is the reel UUID string, so re-saving the same reel upserts cleanly.
//
//  Mirrors the SyncCoordinator+HoleScores pattern — runs after Videos in
//  syncAll so clipID lookups resolve on first cross-device download.
//

import Foundation
import SwiftData
import FirebaseAuth
import os

private let reelSyncLog = Logger(subsystem: "com.playerpath.app", category: "Sync")

extension SyncCoordinator {

    func syncHighlightReels(for user: User) async throws {
        guard let context = modelContext else { return }
        guard let userId = Auth.auth().currentUser?.uid else { return }

        let athletes = user.athletes ?? []

        // Single descriptor for all reels — filter per athlete in memory.
        // SwiftData @Relationship between HighlightReel and Athlete isn't
        // declared (the reel carries athleteID denormalized), so we fetch
        // flat and partition.
        let allReels: [HighlightReel]
        do {
            allReels = try context.fetch(FetchDescriptor<HighlightReel>())
        } catch {
            reelSyncLog.error("Failed to fetch local HighlightReels: \(error.localizedDescription)")
            return
        }

        var syncedReels: [HighlightReel] = []

        // Re-home support (legacy-split migration): `fetchHighlightReels` is per-athlete,
        // so accumulate the FULL remote id set across every athlete for ONE global delete
        // pass after the loop, and map every local reel by firestoreId so a reel moved to
        // another profile is repointed to its new owner instead of being mistaken for a
        // remote delete. Mirrors SyncCoordinator+Photos.
        var globalRemoteReelIds = Set<String>()
        var allFetchesSucceeded = true
        let globalLocalReelsByFirestoreId = Dictionary(
            allReels.compactMap { reel in reel.firestoreId.map { ($0, reel) } },
            uniquingKeysWith: { existing, _ in existing }
        )

        for athlete in athletes {
            let athleteID = athlete.id
            let athleteReels = allReels.filter { $0.athleteID == athleteID }

            // Upload dirty rows. Three branches: create, soft-delete, update.
            for reel in athleteReels where reel.needsSync {
                let reelDocId = reel.firestoreId ?? reel.id.uuidString
                do {
                    if reel.firestoreId == nil {
                        // First-time create — always pushes a fresh doc with
                        // the reel's UUID as the doc id.
                        try await FirestoreManager.shared.createHighlightReel(
                            userId: userId,
                            reelId: reelDocId,
                            data: reel.toFirestoreData()
                        )
                        reel.firestoreId = reelDocId
                    } else if reel.isDeletedRemotely {
                        // Local soft-delete propagates as a Firestore soft-delete.
                        try await FirestoreManager.shared.deleteHighlightReel(
                            userId: userId,
                            reelId: reelDocId
                        )
                    } else {
                        try await FirestoreManager.shared.updateHighlightReel(
                            userId: userId,
                            reelId: reelDocId,
                            data: reel.toFirestoreData()
                        )
                    }
                    reel.needsSync = false
                    reel.lastSyncDate = Date()
                    syncedReels.append(reel)
                } catch {
                    reelSyncLog.error("Failed to sync HighlightReel \(reelDocId): \(error.localizedDescription)")
                }
            }

            // Download remote rows that don't yet exist locally. The fetch
            // already filters out remote-soft-deleted rows, so cross-device
            // demotion shows up as the reel simply not appearing.
            do {
                let remoteReels = try await FirestoreManager.shared.fetchHighlightReels(
                    userId: userId,
                    athleteId: athleteID.uuidString
                )
                for remote in remoteReels { if let id = remote.id { globalRemoteReelIds.insert(id) } }
                // Map firestoreId → local reel for both the exists-check and
                // the S1 reconcile branch below.
                let localByFirestoreId = Dictionary(
                    athleteReels.compactMap { reel in reel.firestoreId.map { ($0, reel) } },
                    uniquingKeysWith: { first, _ in first }
                )
                for remote in remoteReels {
                    guard let remoteId = remote.id else { continue }

                    // Re-home (legacy-split migration): this reel exists locally under a
                    // DIFFERENT profile. Repoint its denormalized athleteID to the new
                    // owner — a scalar assignment (no @Relationship) — instead of the old
                    // delete-under-old + reinsert-under-new churn. If the local row has
                    // pending edits, leave it (its own upload wins); either way `continue`
                    // so a re-homed reel can NEVER fall through to a duplicate insert under
                    // the new owner. No needsSync / lastSyncDate bump on repoint: the remote
                    // already holds the new owner. (Same-athlete reels fail the `!=` guard
                    // and fall through to the S1 merge below.) Mirrors the unconditional
                    // `continue` in SyncCoordinator+Photos' re-home branch.
                    if let existing = globalLocalReelsByFirestoreId[remoteId],
                       existing.athleteID != athleteID {
                        if !existing.needsSync { existing.athleteID = athleteID }
                        continue
                    }

                    if let local = localByFirestoreId[remoteId] {
                        // S1: absorb remote field edits onto an existing local
                        // reel. A clean local row (!needsSync) has already
                        // pushed everything it holds, so it can never be newer
                        // than the server — taking the remote is always correct
                        // and converges the equal-version case a strict `>`
                        // would leave diverged. HighlightReel stores no
                        // `updatedAt`, so this replaces the reconcileHoles
                        // version/updatedAt tiebreak. The fetch already excludes
                        // remote-soft-deleted reels, so every `remote` here is
                        // alive — tombstones are handled below. Content-diff
                        // before assigning to avoid churning SwiftData
                        // observation on no-op sync passes.
                        guard !local.needsSync else { continue }
                        guard (remote.version ?? 0) >= local.version else { continue }
                        let differs = local.clipIDs != remote.clipIDs
                            || local.score != remote.score
                            || local.par != remote.par
                            || local.displayName != remote.displayName
                            || local.courseOrOpponent != remote.courseOrOpponent
                        if differs {
                            local.clipIDs = remote.clipIDs
                            local.score = remote.score
                            local.par = remote.par
                            local.displayName = remote.displayName
                            local.courseOrOpponent = remote.courseOrOpponent
                            local.date = remote.date
                            local.version = remote.version ?? 0
                            local.lastSyncDate = Date()
                        }
                        continue
                    }

                    let local = HighlightReel(
                        clipIDs: remote.clipIDs,
                        athleteID: athleteID,
                        gameID: remote.gameID.flatMap(UUID.init(uuidString:)),
                        practiceID: remote.practiceID.flatMap(UUID.init(uuidString:)),
                        holeNumber: remote.holeNumber,
                        score: remote.score,
                        par: remote.par,
                        displayName: remote.displayName,
                        courseOrOpponent: remote.courseOrOpponent
                    )
                    // Restore the remote-side UUID so subsequent edits keep
                    // upserting the same doc instead of creating a duplicate.
                    if let remoteUUID = UUID(uuidString: remoteId) {
                        local.id = remoteUUID
                    }
                    local.date = remote.date
                    local.createdAt = remote.createdAt
                    local.firestoreId = remoteId
                    local.version = remote.version ?? 0
                    local.needsSync = false
                    local.lastSyncDate = Date()
                    context.insert(local)
                }

            } catch {
                // Swallow-and-continue keeps one athlete's fetch failure from aborting the
                // whole sync — but globalRemoteReelIds is now incomplete, so the global
                // delete pass below must be skipped (see allFetchesSucceeded) or it would
                // mistake that athlete's live reels for deletions.
                allFetchesSucceeded = false
                reelSyncLog.error("Failed to fetch remote HighlightReels for athlete \(athleteID.uuidString): \(error.localizedDescription)")
            }
        }

        // Global tombstone reconciliation — a previously-synced local reel absent from the
        // FULL remote set (across every athlete) was deleted on another device. A re-homed
        // reel survives because its firestoreId is still present under its new owner. Skip
        // if any per-athlete fetch failed (the set would be partial) or when offline (a
        // stale cached getDocuments must not drive destructive deletes). The local @Query
        // already hides deleted reels and there's no undo, so we hard-delete. Mirrors
        // SyncCoordinator+Photos' global delete pass.
        if allFetchesSucceeded && ConnectivityMonitor.shared.isConnected {
            for reel in allReels {
                guard let fid = reel.firestoreId, !reel.needsSync else { continue }
                if !globalRemoteReelIds.contains(fid) {
                    context.delete(reel)
                }
            }
        }

        if context.hasChanges {
            do {
                try context.save()
            } catch {
                // Re-dirty so the next pass retries.
                for reel in syncedReels { reel.needsSync = true }
                throw error
            }
        }
    }
}
