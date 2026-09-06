//
//  ProjectedCloudStorage.swift
//  PlayerPath
//
//  Cloud-quota arithmetic that counts bytes already committed locally but not yet
//  uploaded. `User.cloudStorageUsedBytes` tracks only what has reached Firebase
//  Storage, so it under-reports by the whole upload backlog, and any "you need N
//  more GB" copy built on it alone would be wrong.
//
//  IMPORTANT: "pending" means *destined for the cloud under current settings*,
//  not merely "not uploaded yet". A clip the app will never enqueue — auto-upload
//  off, highlights-only sync on, or over the user's per-file cap — consumes no
//  cloud storage and must not be charged against a cloud cap. Counting it would
//  paywall a user for space they are not using, on a projection that can never
//  drain: with `syncHighlightsOnly` on, EVERY imported clip is permanently
//  ineligible, so the pile only ever grows and no action in the upgrade sheet
//  resolves it. Photos have no such gate — `SyncCoordinator+Photos` uploads every
//  photo with `cloudURL == nil && needsSync` — so all pending photo bytes count.
//

import Foundation
import SwiftData
import os

private let storageLog = Logger(subsystem: "com.playerpath.app", category: "ProjectedStorage")

enum ProjectedCloudStorage {

    struct Snapshot: Sendable, Equatable {
        /// Bytes already in Firebase Storage, per the server-reconciled counter.
        ///
        /// `UploadQueueManager` reserves into this counter BEFORE an upload
        /// finishes, while `isUploaded` is still false, so a clip in flight is
        /// briefly counted here AND in `pendingLocalBytes`. That double-count is
        /// transient and errs toward blocking, which is the safe direction.
        let cloudUsedBytes: Int64
        /// Bytes on disk in rows that have not uploaded yet — destined for the
        /// cloud, invisible to `cloudUsedBytes` until they get there.
        let pendingLocalBytes: Int64
        /// The athlete tier's cap.
        let limitBytes: Int64

        var projectedUsedBytes: Int64 { cloudUsedBytes + pendingLocalBytes }
        var remainingBytes: Int64 { max(0, limitBytes - projectedUsedBytes) }

        /// Whether one more item fits, accounting for what this import batch has
        /// already committed but not yet uploaded (`alreadyReserved`).
        func fits(_ additionalBytes: Int64, alreadyReserved: Int64) -> Bool {
            projectedUsedBytes + alreadyReserved + additionalBytes <= limitBytes
        }

        /// Placeholder for the unreachable case where a quota stop is reported
        /// without a snapshot. Renders as "0 left of 0", which reads as broken —
        /// deliberately, since reaching it means the gate ran without a snapshot.
        static let empty = Snapshot(cloudUsedBytes: 0, pendingLocalBytes: 0, limitBytes: 0)
    }

    /// Takes one snapshot for a whole import batch. Do NOT call per item — it
    /// stats every un-uploaded file in the library.
    ///
    /// Two phases, deliberately: everything that touches a `@Model` happens
    /// synchronously on the main actor and is reduced to plain `String` paths
    /// first, because `@Model` is not `Sendable` and must never be captured into
    /// a detached task or read after an await.
    @MainActor
    static func snapshot(for user: User) async -> Snapshot {
        // Phase 1 — main actor, synchronous, models → Strings.

        // Mirrors the enqueue gate in BulkVideoImportViewModel / ClipPersistenceService.
        // Nil preferences means "don't enqueue" there, so it means "not pending" here.
        var prefs: UserPreferences?
        if let context = user.modelContext {
            prefs = (try? context.fetch(FetchDescriptor<UserPreferences>()))?.first
        }
        let clipsAreUploadEligible = prefs?.autoUploadToCloud ?? false
        let highlightsOnly = prefs?.syncHighlightsOnly ?? false
        // Per-file cap, in bytes. Clips above it are never enqueued, so they are
        // filtered in phase 2 where the sizes are known.
        let perFileCap = Int64(prefs?.maxVideoFileSize ?? 0) * StorageConstants.bytesPerMB

        var clipPaths: [String] = []
        var photoPaths: [String] = []
        // Skip tombstoned profiles: their files are still on disk, but charging
        // them against the cap would paywall an import over a deleted athlete.
        for athlete in user.athletes ?? [] where !athlete.isDeletedRemotely {
            if clipsAreUploadEligible {
                for clip in athlete.videoClips ?? [] where !clip.isUploaded && !clip.isDeletedRemotely {
                    if highlightsOnly && !clip.isHighlight { continue }
                    clipPaths.append(clip.resolvedFilePath)
                }
            }
            for photo in athlete.photos ?? [] where photo.cloudURL == nil && !photo.isDeletedRemotely {
                photoPaths.append(photo.resolvedFilePath)
            }
        }
        let cloudUsed = user.cloudStorageUsedBytes
        let tier = SubscriptionGate.effectiveAthleteTier
        let limit = Int64(tier.storageLimitGB) * StorageConstants.bytesPerGB

        // Phase 2 — off-main: N stat() calls, zero model references captured.
        let pending = await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let clipBytes = clipPaths.reduce(Int64(0)) { total, path in
                let size = fm.fileSize(atPath: path)
                // Over the user's per-file cap → never enqueued → not pending.
                return size > perFileCap ? total : total + size
            }
            return clipBytes + photoPaths.reduce(Int64(0)) { $0 + fm.fileSize(atPath: $1) }
        }.value

        storageLog.debug("Projected storage: cloud=\(cloudUsed) pending=\(pending) limit=\(limit) over \(clipPaths.count) clip(s) + \(photoPaths.count) photo(s)")
        return Snapshot(cloudUsedBytes: cloudUsed, pendingLocalBytes: pending, limitBytes: limit)
    }
}
