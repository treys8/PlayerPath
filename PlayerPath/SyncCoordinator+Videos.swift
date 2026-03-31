import Foundation
import SwiftData
import FirebaseAuth
import FirebaseFirestore
import UIKit
import os

private let syncLog = Logger(subsystem: "com.playerpath.app", category: "Sync")

extension SyncCoordinator {
    // MARK: - Videos Sync (Cross-Device)

    /// Syncs video metadata for athletes. Video files are uploaded to Storage
    /// via UploadQueueManager; this syncs the Firestore metadata for cross-device discovery.
    /// - Parameters:
    ///   - user: The SwiftData User to sync videos for
    ///   - activeOnly: When true, only downloads videos for the active athlete
    ///     (set via `SyncCoordinator.activeAthleteID`). Uploads always cover all
    ///     athletes since only dirty clips are processed.
    func syncVideos(for user: User, activeOnly: Bool = false) async throws {
        guard let context = modelContext else {
            return
        }


        do {
            // Step 1: Upload local video metadata that isn't synced yet (all athletes — cheap)
            try await uploadLocalVideoMetadata(user, context: context)

            // Step 2: Download remote videos from Firestore
            try await downloadRemoteVideos(user, context: context, activeOnly: activeOnly)


        } catch {
            appendSyncError(SyncError(
                type: .syncFailed,
                entityId: (user.firebaseAuthUid ?? user.id.uuidString),
                message: "Video sync failed: \(error.localizedDescription)"
            ))
            throw error
        }
    }

    func uploadLocalVideoMetadata(_ user: User, context: ModelContext) async throws {
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

        var syncedClips: [VideoClip] = []

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
                syncedClips.append(clip)
            } catch {
                syncLog.error("Failed to save video metadata to Firestore: \(error.localizedDescription)")
            }
        }

        for clip in updatedVideos {
            guard let firestoreId = clip.firestoreId else { continue }
            do {
                // Read-before-write: skip if Firestore doc already matches local state.
                // 1 read costs ~0.3x a write, so this saves money when data is unchanged
                // (e.g., after crash/restart where needsSync wasn't cleared).
                let existingDoc = try? await Firestore.firestore()
                    .collection(FC.videos).document(firestoreId).getDocument()
                if let data = existingDoc?.data(),
                   videoMetadataMatches(data, clip: clip) {
                    clip.needsSync = false
                    syncedClips.append(clip)
                    continue
                }

                try await VideoCloudManager.shared.updateVideoMetadata(
                    clipId: firestoreId,
                    isHighlight: clip.isHighlight,
                    note: clip.note,
                    playResultType: clip.playResult?.type,
                    pitchSpeed: clip.pitchSpeed,
                    pitchType: clip.pitchType,
                    gameId: clip.game.map { $0.firestoreId ?? $0.id.uuidString },
                    gameOpponent: clip.gameOpponent ?? clip.game?.opponent,
                    gameDate: clip.gameDate ?? clip.game?.date,
                    seasonId: clip.season.map { $0.firestoreId ?? $0.id.uuidString },
                    seasonName: clip.seasonName ?? clip.season?.displayName,
                    practiceId: clip.practice?.id.uuidString,
                    practiceDate: clip.practiceDate ?? clip.practice?.date
                )
                clip.needsSync = false
                syncedClips.append(clip)
            } catch {
                syncLog.error("Failed to update video metadata in Firestore: \(error.localizedDescription)")
            }
        }

        // Save all changes to SwiftData — re-dirty on failure so next sync retries
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                for clip in syncedClips { clip.needsSync = true }
                throw error
            }
        }
    }

    func downloadRemoteVideos(_ user: User, context: ModelContext, activeOnly: Bool = false) async throws {
        var athletes = user.athletes ?? []

        // When doing an active-athlete-only sync, restrict the download to just
        // that athlete. Non-active athletes are covered by the periodic full sync.
        if activeOnly, let activeID = activeAthleteID {
            athletes = athletes.filter { $0.id.uuidString == activeID }
        }

        var athletesWithNewClips: [Athlete] = []
        /// Game IDs that received new or updated clips — only these need stats recalculation.
        var gamesWithNewClips: Set<UUID> = []

        for athlete in athletes {
            // Get video metadata from Firestore
            let remoteVideos = try await VideoCloudManager.shared.syncVideos(for: athlete)

            let localClips = athlete.videoClips ?? []
            let localClipsByID = Dictionary(uniqueKeysWithValues: localClips.map { ($0.id, $0) })

            // Detect clips deleted on another device — remote set no longer contains them.
            // Safety: skip deletion pass if the remote count is suspiciously low compared
            // to local, which can happen on transient Firestore failures, network timeouts,
            // or partial query results (e.g., query returned 50 of 150 clips).
            let remoteVideoIds = Set(remoteVideos.map { $0.id })
            let syncedLocalClips = localClips.filter { $0.firestoreId != nil }
            let remoteReturnedTooFew = !syncedLocalClips.isEmpty
                && remoteVideoIds.count < syncedLocalClips.count / 2
            if remoteReturnedTooFew {
                syncLog.warning("Remote returned \(remoteVideoIds.count) videos but \(syncedLocalClips.count) synced clips exist locally — skipping deletion pass to prevent data loss from partial fetch")
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
                guard let localClip = localClipsByID[remoteVideo.id] else { continue }
                let remoteIsNewer = remoteVideo.updatedAt > (localClip.lastSyncDate ?? .distantPast)
                guard remoteIsNewer else { continue }

                if localClip.needsSync {
                    syncLog.warning("Sync conflict on video '\(localClip.fileName)': local has pending changes, skipping remote update")
                    appendSyncError(SyncError(
                        type: .conflictResolution,
                        entityId: localClip.id.uuidString,
                        message: "Video '\(localClip.fileName)' modified on both devices — local changes kept"
                    ))
                    continue
                }

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
                if let pitchType = remoteVideo.pitchType {
                    localClip.pitchType = pitchType
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
                newClip.pitchType = remoteVideo.pitchType
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
                if let game = newClip.game { gamesWithNewClips.insert(game.id) }
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
                    await MainActor.run { _ = self.pendingDownloadTasks.removeValue(forKey: taskID) }
                }
            }

            athletesWithNewClips.append(athlete)
        }

        if context.hasChanges { try context.save() }

        // Rebuild derived statistics only for games that actually received new clips.
        // GameStatistics and AthleteStatistics are not stored in Firestore — they are
        // computed from VideoClip.playResult relationships. After downloading clips we
        // must reconstruct them so stats are correct on a new device or after reinstall.
        for athlete in athletesWithNewClips {
            let affectedGames = (athlete.games ?? []).filter { gamesWithNewClips.contains($0.id) }
            for game in affectedGames {
                do {
                    try StatisticsService.shared.recalculateGameStatistics(for: game, context: context)
                } catch {
                    syncLog.error("Failed to recalculate game stats for '\(game.opponent)': \(error.localizedDescription)")
                }
            }
            // Athlete-level stats aggregate across all games — one call per athlete is acceptable.
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
    func downloadVideoFile(clip: VideoClip, context: ModelContext) async {
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

            // Clean up any partial file left on disk to prevent orphaned storage
            if FileManager.default.fileExists(atPath: localPath) {
                do {
                    try FileManager.default.removeItem(atPath: localPath)
                } catch {
                    syncLog.error("Failed to clean up partial download at \(localPath): \(error.localizedDescription)")
                }
            }

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

    // MARK: - Read-Before-Write Helper

    /// Compares Firestore document data against local VideoClip fields.
    /// Returns true if all mutable metadata fields match (no write needed).
    private func videoMetadataMatches(_ data: [String: Any], clip: VideoClip) -> Bool {
        guard data["isHighlight"] as? Bool == clip.isHighlight else { return false }

        let remoteNote = data["note"] as? String
        if remoteNote != clip.note { return false }

        let remotePlayResult = data["playResult"] as? Int
        let localPlayResult = clip.playResult?.type.rawValue
        if remotePlayResult != localPlayResult { return false }

        let remotePitchSpeed = data["pitchSpeed"] as? Double
        if remotePitchSpeed != clip.pitchSpeed { return false }

        let remotePitchType = data["pitchType"] as? String
        if remotePitchType != clip.pitchType { return false }

        let remoteGameId = data["gameId"] as? String
        let localGameId = clip.game.map { $0.firestoreId ?? $0.id.uuidString }
        if remoteGameId != localGameId { return false }

        let remoteGameOpponent = data["gameOpponent"] as? String
        let localGameOpponent = clip.gameOpponent ?? clip.game?.opponent
        if remoteGameOpponent != localGameOpponent { return false }

        let remoteSeasonId = data["seasonId"] as? String
        let localSeasonId = clip.season.map { $0.firestoreId ?? $0.id.uuidString }
        if remoteSeasonId != localSeasonId { return false }

        let remoteSeasonName = data["seasonName"] as? String
        let localSeasonName = clip.seasonName ?? clip.season?.displayName
        if remoteSeasonName != localSeasonName { return false }

        let remotePracticeId = data["practiceId"] as? String
        let localPracticeId = clip.practice?.id.uuidString
        if remotePracticeId != localPracticeId { return false }

        return true
    }
}
