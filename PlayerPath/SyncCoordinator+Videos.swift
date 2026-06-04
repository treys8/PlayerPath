import Foundation
import SwiftData
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
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
        var orphanedClips: [(VideoClip, Athlete)] = []

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
                } else if clip.isUploaded && clip.cloudURL == nil && clip.firestoreId == nil {
                    // Orphan: the process was killed between the Storage upload
                    // succeeding and the SwiftData save, so isUploaded stuck true
                    // but neither cloudURL nor firestoreId was persisted. Such a
                    // clip is invisible to both branches above — a leaked blob.
                    orphanedClips.append((clip, athlete))
                }
            }
        }

        // Recover orphaned clips by re-driving them through the normal upload
        // pipeline when the local file survives (a fresh Storage object + metadata
        // doc; the original leaked blob is left for server-side GC). If the local
        // file is gone too, the footage is unrecoverable from here — log it.
        for (clip, athlete) in orphanedClips {
            if FileManager.default.fileExists(atPath: clip.resolvedFilePath) {
                clip.isUploaded = false  // reflect reality so enqueue() accepts it
                UploadQueueManager.shared.enqueue(clip, athlete: athlete, priority: .normal)
                syncLog.info("Recovered orphaned clip \(clip.id) — re-enqueued for upload")
            } else {
                syncLog.error("Orphaned clip \(clip.id) has no local file and no cloudURL — cannot recover")
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
                    club: clip.club?.rawValue,
                    gameId: clip.game.map { $0.firestoreId ?? $0.id.uuidString },
                    gameOpponent: clip.gameOpponent ?? clip.game?.opponent,
                    gameDate: clip.gameDate ?? clip.game?.date,
                    seasonId: clip.season.map { $0.firestoreId ?? $0.id.uuidString },
                    seasonName: clip.seasonName ?? clip.season?.displayName,
                    practiceId: clip.practice?.id.uuidString,
                    practiceDate: clip.practiceDate ?? clip.practice?.date,
                    athleteId: clip.athlete.map { $0.firestoreId ?? $0.id.uuidString },
                    athleteName: clip.athlete?.name
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
        let allAthletes = user.athletes ?? []
        var athletes = allAthletes

        // When doing an active-athlete-only sync, restrict the download to just
        // that athlete. Non-active athletes are covered by the periodic full sync.
        if activeOnly, let activeID = activeAthleteID {
            athletes = athletes.filter { $0.id.uuidString == activeID }
        }

        // Pre-fetch every in-scope athlete's remote videos up front. The deletion
        // pass and the re-home repoint must reason about the FULL remote set, not
        // one athlete at a time — otherwise a clip moved to another profile (the
        // legacy-split migration) reads as "deleted here / new there" and its local
        // file gets destroyed and re-downloaded.
        var remoteByAthlete: [(Athlete, [VideoClipMetadata])] = []
        var globalRemoteIds = Set<UUID>()
        for athlete in athletes {
            let remote = try await VideoCloudManager.shared.syncVideos(for: athlete)
            remoteByAthlete.append((athlete, remote))
            for r in remote where !r.isDeleted { globalRemoteIds.insert(r.id) }
        }
        // Every local clip across the WHOLE roster (not just in-scope athletes) keyed
        // by its UUID, so a re-homed clip is repointed to its new owner rather than
        // duplicate-inserted. Collapse the known multi-device duplicate-id case.
        let globalLocalClipsById = Dictionary(
            allAthletes.flatMap { $0.videoClips ?? [] }.map { ($0.id, $0) },
            uniquingKeysWith: { existing, _ in existing }
        )

        var athletesWithNewClips: [Athlete] = []
        /// Game IDs that received new or updated clips — only these need stats recalculation.
        var gamesWithNewClips: Set<UUID> = []
        /// Athletes whose stats need recalculation because clips were deleted remotely.
        var athletesWithDeletedClips: Set<PersistentIdentifier> = []
        /// Game IDs whose stats need recalculation because clips were deleted remotely.
        var gamesWithDeletedClips: Set<UUID> = []

        for (athlete, remoteVideos) in remoteByAthlete {
            let localClips = athlete.videoClips ?? []
            // `id` is each clip's own UUID and should be unique, but the app's
            // known multi-device row duplication can leave two clips sharing one
            // id. Collapse rather than trap in Dictionary(uniqueKeysWithValues:)
            // — any winner is valid for lookup — and log if it ever fires so the
            // underlying corruption stays observable.
            let localClipsByID = Dictionary(
                localClips.map { ($0.id, $0) },
                uniquingKeysWith: { existing, _ in existing }
            )
            if localClipsByID.count != localClips.count {
                syncLog.warning("Collapsed \(localClips.count - localClipsByID.count) duplicate local VideoClip id(s) for athlete \(athlete.id)")
            }

            // Detect clips deleted on another device — remote set no longer contains
            // them. syncVideos now paginates the FULL set (no 200-doc truncation), and
            // a transient mid-page failure THROWS rather than returning a short set, so
            // globalRemoteIds is authoritative when we reach here.
            let syncedLocalClips = localClips.filter { $0.firestoreId != nil }
            // Gate destructive reconciliation on connectivity (see +HoleScores): an
            // offline/partial cached fetch must not drive clip deletions, which take
            // their PlayResults, coach annotations, and isHighlight flags with them.
            // Also skip in active-only mode — globalRemoteIds then covers only the
            // active athlete, so a clip re-homed to another profile would look
            // deleted; deletions reconcile on the next full sync. Check against the
            // GLOBAL remote set (all in-scope athletes) so a re-homed clip isn't
            // mistaken for a delete and have its file destroyed.
            if activeOnly || !ConnectivityMonitor.shared.isConnected {
                syncLog.warning("Skipping video deletion pass — \(activeOnly ? "active-only sync" : "offline") (would risk wiping synced/re-homed clips)")
            } else {
                for localClip in syncedLocalClips where !globalRemoteIds.contains(localClip.id) {
                    // Track affected game + athlete before the delete — accessing
                    // SwiftData properties after `context.delete` is undefined.
                    if let game = localClip.game { gamesWithDeletedClips.insert(game.id) }
                    athletesWithDeletedClips.insert(athlete.persistentModelID)
                    // cleanupReels: false — this clip was deleted on another
                    // device, whose clip-delete already stripped + synced the
                    // referencing reel; re-stripping here would double-dirty it
                    // and ping-pong the reel edit back cross-device.
                    localClip.delete(in: context, cleanupReels: false)
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
                // Either/or invariant: a clip is tagged with EITHER a PlayResult
                // (baseball/softball) OR a Club (golf), never both. If the
                // remote has a club, detach any local PlayResult to prevent
                // double-counting in stats recalc. Matches PlayResultEditorView
                // — orphaned PlayResults aren't queried independently anywhere,
                // so leaving them un-deleted is the safer pattern.
                if remoteVideo.club != nil {
                    localClip.playResult = nil
                } else if let rawValue = remoteVideo.playResultRawValue,
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
                if let clubRaw = remoteVideo.club, let club = Club(rawValue: clubRaw) {
                    localClip.club = club
                }
                // holeNumber is set once at clip creation on the recording
                // device and never mutated. Mirror unconditionally so a
                // second device can attribute the clip to its parent hole
                // for PR2's reel grouping. Nil-remote leaves local alone.
                if let holeNumber = remoteVideo.holeNumber {
                    localClip.holeNumber = holeNumber
                }
                if let duration = remoteVideo.duration {
                    localClip.duration = duration
                }
                // Coach-source link is immutable once set — don't clobber an existing
                // value with nil from a remote doc that predates the field.
                if let sourceCoachVideoID = remoteVideo.sourceCoachVideoID {
                    localClip.sourceCoachVideoID = sourceCoachVideoID
                }
                // Annotation counters are authoritative on the server side (coach
                // writes increment them). Mirror into SwiftData so the athlete's
                // local grid can render coach-feedback badges without querying.
                if let ac = remoteVideo.annotationCount {
                    localClip.annotationCount = ac
                }
                if let dc = remoteVideo.drawingCount {
                    localClip.drawingCount = dc
                }
                localClip.cloudURL = remoteVideo.downloadURL
                // Anchor to the remote write time, not Date() — using "now" makes a
                // later third-device write with a slightly older updatedAt look stale
                // and get skipped. See uploadLocalAthletes.
                localClip.lastSyncDate = remoteVideo.updatedAt
            }

            // Find videos that exist remotely but not locally — skip deleted ones
            let localVideoIds = Set(localClips.map { $0.id })
            let newRemoteVideos = remoteVideos.filter { !localVideoIds.contains($0.id) && !$0.isDeleted }

            guard !newRemoteVideos.isEmpty else {
                continue
            }


            for remoteVideo in newRemoteVideos {
                // Re-home: this clip already exists locally under a DIFFERENT profile
                // (legacy-split migration moved it). Repoint it to the new owner
                // instead of inserting a duplicate — preserves the downloaded file,
                // PlayResult, coach annotations, and the isHighlight flag. Skip if the
                // local row has pending edits (let the local upload win).
                if let existing = globalLocalClipsById[remoteVideo.id] {
                    if !existing.needsSync, existing.athlete?.id != athlete.id {
                        let oldOwner = existing.athlete
                        let oldGameId = existing.game?.id
                        existing.athlete = athlete
                        // Re-link parents within the new owner's subtree — ids are
                        // invariant across a split, so they resolve to the moved
                        // season/game/practice already re-pointed earlier in this sync.
                        if let seasonId = remoteVideo.seasonId {
                            existing.season = allLocalSeasons.first { $0.id.uuidString == seasonId || $0.firestoreId == seasonId }
                        }
                        if let gameId = remoteVideo.gameId {
                            existing.game = allLocalGames.first { $0.id.uuidString == gameId || $0.firestoreId == gameId }
                        }
                        if let practiceId = remoteVideo.practiceId {
                            existing.practice = allLocalPractices.first { $0.id.uuidString == practiceId }
                        }
                        existing.lastSyncDate = remoteVideo.updatedAt
                        // Stats: old owner sheds this clip's contribution; new owner gains it.
                        if let oldOwner { athletesWithDeletedClips.insert(oldOwner.persistentModelID) }
                        athletesWithNewClips.append(athlete)
                        if let oldGameId { gamesWithDeletedClips.insert(oldGameId) }
                        if let newGame = existing.game { gamesWithNewClips.insert(newGame.id) }
                    }
                    continue
                }

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
                newClip.club = remoteVideo.club.flatMap(Club.init(rawValue:))
                newClip.holeNumber = remoteVideo.holeNumber
                newClip.duration = remoteVideo.duration
                newClip.firestoreId = remoteVideo.id.uuidString
                newClip.sourceCoachVideoID = remoteVideo.sourceCoachVideoID
                newClip.annotationCount = remoteVideo.annotationCount ?? 0
                newClip.drawingCount = remoteVideo.drawingCount ?? 0
                newClip.needsSync = false
                newClip.athlete = athlete

                // Either/or invariant: skip PlayResult reconstruction when the
                // remote carries a club (golf tag) — see merge path above.
                if remoteVideo.club == nil,
                   let rawValue = remoteVideo.playResultRawValue,
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

        // Rebuild derived statistics for games whose clips changed (additions or
        // deletions). GameStatistics and AthleteStatistics are not stored in
        // Firestore — they are computed from VideoClip.playResult relationships.
        // After syncing clips we must reconstruct them so stats stay consistent
        // across devices (and after reinstall).
        let athleteIDsNeedingRecalc = Set(athletesWithNewClips.map(\.persistentModelID))
            .union(athletesWithDeletedClips)
        let gameIDsNeedingRecalc = gamesWithNewClips.union(gamesWithDeletedClips)
        for athleteID in athleteIDsNeedingRecalc {
            // Resolve against the FULL roster, not the in-scope `athletes`: a re-home
            // repoint queues its OLD owner for recalc, and that owner is out of scope
            // during an active-only sync. Skipping it would leave its stats over-counting.
            guard let athlete = allAthletes.first(where: { $0.persistentModelID == athleteID }) else { continue }
            let affectedGames = (athlete.games ?? []).filter { gameIDsNeedingRecalc.contains($0.id) }
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
        if !athleteIDsNeedingRecalc.isEmpty {
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
            clip.updateFilePath(VideoClip.toRelativePath(localPath))
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

            clip.updateFilePath(VideoClip.toRelativePath(localPath))
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

            if isObjectGoneRemotely(error) {
                // Permanent: Storage reports the object no longer exists. Delete the
                // ghost record (and its PlayResult) so it doesn't linger forever with
                // an empty filePath and no retry path.
                if let playResult = clip.playResult {
                    context.delete(playResult)
                }
                context.delete(clip)
                ErrorHandlerService.shared.saveContext(context, caller: "SyncCoordinator.downloadVideo.objectGone")
            } else {
                // Transient (offline, timeout, unknown): KEEP the clip. Its filePath
                // stays empty, so the next sync's `fileExists` check re-attempts the
                // download. Deleting here would discard coach annotations, the
                // isHighlight flag, and denormalized notes on a mere network blip.
                syncLog.info("Keeping clip \(clip.id) after transient download failure — will retry next sync")
            }
        }
    }

    /// True only when Firebase Storage reports the blob is genuinely gone
    /// (objectNotFound). Everything else — offline, timeout, URL-layer errors,
    /// unknown — is treated as transient so the clip (and its metadata) survives.
    /// Mirrors the objectNotFound check used throughout VideoCloudManager.
    private func isObjectGoneRemotely(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == "FIRStorageErrorDomain"
            && nsError.code == StorageErrorCode.objectNotFound.rawValue
    }

    // MARK: - Read-Before-Write Helper

    /// Compares Firestore document data against local VideoClip fields.
    /// Returns true if all mutable metadata fields match (no write needed).
    private func videoMetadataMatches(_ data: [String: Any], clip: VideoClip) -> Bool {
        guard data["isHighlight"] as? Bool == clip.isHighlight else { return false }

        // Re-home guard: if the clip moved to another profile, athleteId differs and
        // we must NOT skip the write (which would strand the clip on the old row).
        // Only force a write when the clip actually has an athlete.
        if let localAthleteId = clip.athlete.map({ $0.firestoreId ?? $0.id.uuidString }) {
            let remoteAthleteId = data["athleteId"] as? String
            if remoteAthleteId != localAthleteId { return false }
        }

        let remoteNote = data["note"] as? String
        if remoteNote != clip.note { return false }

        let remotePlayResult = data["playResult"] as? Int
        let localPlayResult = clip.playResult?.type.rawValue
        if remotePlayResult != localPlayResult { return false }

        let remotePitchSpeed = data["pitchSpeed"] as? Double
        if remotePitchSpeed != clip.pitchSpeed { return false }

        let remotePitchType = data["pitchType"] as? String
        if remotePitchType != clip.pitchType { return false }

        let remoteClub = data["club"] as? String
        if remoteClub != clip.club?.rawValue { return false }

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
