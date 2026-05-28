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
                let existingFirestoreIds = Set(athleteReels.compactMap(\.firestoreId))
                for remote in remoteReels {
                    guard let remoteId = remote.id else { continue }
                    if existingFirestoreIds.contains(remoteId) { continue }

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

                // Tombstone reconciliation — a previously-synced local reel
                // that's no longer in the remote alive set was deleted on
                // another device. The local @Query already hides deleted reels
                // and there's no undo, so we hard-delete. Gated on connectivity:
                // persistent cache means an offline getDocuments can return a
                // stale/empty set without throwing, which must not drive
                // destructive deletes (inserts above are harmless either way).
                if ConnectivityMonitor.shared.isConnected {
                    let remoteAliveIds = Set(remoteReels.compactMap(\.id))
                    for reel in athleteReels {
                        guard let fid = reel.firestoreId, !reel.needsSync else { continue }
                        if !remoteAliveIds.contains(fid) {
                            context.delete(reel)
                        }
                    }
                }
            } catch {
                reelSyncLog.error("Failed to fetch remote HighlightReels for athlete \(athleteID.uuidString): \(error.localizedDescription)")
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
