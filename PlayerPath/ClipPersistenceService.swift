import SwiftUI
import SwiftData
import Foundation
import AVFoundation
import Photos
import os

enum ClipPersistenceError: LocalizedError {
    case fileNotFound(URL)
    case invalidURL(URL)
    case failedToCopy(from: URL, to: URL, underlying: Error)
    case failedToCreateAsset(URL, underlying: Error?)
    case corruptedVideo(URL, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "File not found at \(url.path)"
        case .invalidURL(let url):
            return "Invalid non-file URL: \(url.absoluteString)"
        case .failedToCopy(let from, let to, let underlying):
            return "Failed to copy from \(from.lastPathComponent) to \(to.lastPathComponent): \(underlying.localizedDescription)"
        case .failedToCreateAsset(let url, let underlying):
            return "Failed to create AVAsset for \(url.lastPathComponent): \(underlying?.localizedDescription ?? "Unknown error")"
        case .corruptedVideo(let url, let underlying):
            return "Video file appears to be corrupted: \(url.lastPathComponent) - \(underlying.localizedDescription)"
        }
    }
}

@MainActor
final class ClipPersistenceService {
    private enum Constants {
        static let clipsFolderName = "Clips"
    }

    private let fileManager: FileManager
    private let now: () -> Date
    private let clipLog = Logger(subsystem: "com.playerpath.app", category: "ClipPersistence")

    public init(fileManager: FileManager = .default, now: @escaping () -> Date = Date.init) {
        self.fileManager = fileManager
        self.now = now
    }

    private func ensureClipsDirectory() throws -> URL {
        let documentsURL = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let clipsDirectoryURL = documentsURL.appendingPathComponent(Constants.clipsFolderName, isDirectory: true)
        if !fileManager.fileExists(atPath: clipsDirectoryURL.path) {
            try fileManager.createDirectory(at: clipsDirectoryURL, withIntermediateDirectories: true)
        }
        return clipsDirectoryURL
    }

    /// Migrates video files from Caches to Documents directory
    /// This is a one-time migration to prevent iOS from deleting videos
    func migrateVideosToDocuments(context: ModelContext) async throws {
        let migrationKey = "hasCompletedVideoStorageMigration"

        // Check if migration already completed
        if UserDefaults.standard.bool(forKey: migrationKey) {
            return
        }


        // Get old Caches directory
        let cachesURL = try fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        let oldClipsDirectory = cachesURL.appendingPathComponent(Constants.clipsFolderName, isDirectory: true)

        // Get new Documents directory
        let newClipsDirectory = try ensureClipsDirectory()

        // Check if old directory exists
        guard fileManager.fileExists(atPath: oldClipsDirectory.path) else {
            UserDefaults.standard.set(true, forKey: migrationKey)
            return
        }

        // Get all video files from old directory
        let oldVideoFiles = try fileManager.contentsOfDirectory(
            at: oldClipsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: .skipsHiddenFiles
        ).filter { $0.pathExtension.lowercased() == "mov" || $0.pathExtension.lowercased() == "mp4" }


        // Per-file failure counts persisted across launches. A file that can never
        // migrate (corrupt asset, unresolvable name collision) must not pin the
        // whole migration in a permanent re-run loop — after `maxMigrationAttempts`
        // tries it is permanently skipped so the migration can mark itself done.
        let failureCountsKey = "videoStorageMigrationFailureCounts"
        let maxMigrationAttempts = 3
        var failureCounts = (UserDefaults.standard.dictionary(forKey: failureCountsKey) as? [String: Int]) ?? [:]

        var migratedCount = 0
        var failedCount = 0

        for oldVideoURL in oldVideoFiles {
            let fileName = oldVideoURL.lastPathComponent

            // Skip files that have already exhausted their retry budget on prior
            // launches. Leaves the file in place but stops it from blocking completion.
            if (failureCounts[fileName] ?? 0) >= maxMigrationAttempts {
                continue
            }

            let newVideoURL = newClipsDirectory.appendingPathComponent(fileName)

            do {
                // Move file to new location
                if fileManager.fileExists(atPath: newVideoURL.path) {
                    // File already exists in new location, just delete old one
                    try fileManager.removeItem(at: oldVideoURL)
                } else {
                    try fileManager.moveItem(at: oldVideoURL, to: newVideoURL)
                }

                // Update VideoClip path in SwiftData (store as relative)
                let predicate = #Predicate<VideoClip> { clip in
                    clip.fileName == fileName
                }
                let descriptor = FetchDescriptor(predicate: predicate)
                let clips = try context.fetch(descriptor)

                for clip in clips {
                    clip.updateFilePath(VideoClip.toRelativePath(newVideoURL.path))
                }

                // Save after each file so paths stay in sync with moved files
                try context.save()

                migratedCount += 1
                failureCounts[fileName] = nil   // clear any prior failures on success

            } catch {
                clipLog.error("Video migration failed for \(fileName): \(error.localizedDescription)")
                failedCount += 1
                failureCounts[fileName, default: 0] += 1
            }
        }

        // Clean up old directory if empty
        do {
            let remainingFiles = try fileManager.contentsOfDirectory(atPath: oldClipsDirectory.path)
            if remainingFiles.isEmpty {
                do {
                    try fileManager.removeItem(at: oldClipsDirectory)
                } catch {
                    ErrorHandlerService.shared.handle(error, context: "ClipPersistence.removeMigrationDir", showAlert: false)
                }
            }
        } catch {
            ErrorHandlerService.shared.handle(error, context: "ClipPersistence.readMigrationDir", showAlert: false)
        }

        clipLog.info("Video storage migration pass: \(migratedCount) migrated, \(failedCount) failed this run, \(failureCounts.count) file(s) with unresolved failures")

        // Persist updated per-file failure counts so attempts accumulate across launches.
        if failureCounts.isEmpty {
            UserDefaults.standard.removeObject(forKey: failureCountsKey)
        } else {
            UserDefaults.standard.set(failureCounts, forKey: failureCountsKey)
        }

        // Mark migration complete when nothing retriable remains: either every file
        // migrated, or every remaining failure has exhausted its retry budget and is
        // now permanently skipped. This stops a single un-migratable file from
        // re-running the whole migration on every launch (the old `failedCount == 0`
        // check would never pass while that file lingered).
        let hasRetriableFailure = failureCounts.values.contains { $0 < maxMigrationAttempts }
        if !hasRetriableFailure {
            UserDefaults.standard.set(true, forKey: migrationKey)
            UserDefaults.standard.removeObject(forKey: failureCountsKey)
        }

    }

    private func uniqueDestinationURL(basedOn destinationURL: URL) -> URL {
        let ext = destinationURL.pathExtension
        let baseName = destinationURL.deletingPathExtension().lastPathComponent
        var candidate = destinationURL
        var counter = 1
        while fileManager.fileExists(atPath: candidate.path) {
            let newName = "\(baseName)-\(counter)"
            candidate = destinationURL.deletingLastPathComponent().appendingPathComponent(newName).appendingPathExtension(ext)
            counter += 1
        }
        return candidate
    }

    /// Generates a thumbnail image from a video file
    /// - Parameters:
    ///   - videoURL: The URL of the video file
    ///   - time: The time in the video to capture (defaults to 1 second)
    /// - Returns: The file path where the thumbnail was saved
    /// Verifies that a video file is playable and not corrupted
    /// - Parameters:
    ///   - asset: The AVAsset to verify
    ///   - url: The URL of the video file
    /// Validates a freshly-copied clip for corruption. Takes the asset properties
    /// `saveClip` already batch-loaded (tracks, duration, isPlayable) so it does not
    /// re-issue the same AVAsset loads — only the per-track naturalSize/transform,
    /// which are loaded together in one call.
    private func verifyVideoPlayability(url: URL, tracks: [AVAssetTrack], duration: CMTime, isPlayable: Bool) async throws {
        // Check 1: Verify file size is reasonable (not suspiciously small)
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        guard let fileSize = attributes[.size] as? Int64, fileSize > 10000 else { // At least 10KB
            throw NSError(domain: "ClipPersistence", code: -1, userInfo: [NSLocalizedDescriptionKey: "Video file size is suspiciously small (\(attributes[.size] ?? 0) bytes)"])
        }

        // Check 2: Verify the asset has video tracks (reuses the already-loaded tracks)
        let videoTracks = tracks.filter { $0.mediaType == .video }
        guard !videoTracks.isEmpty else {
            throw NSError(domain: "ClipPersistence", code: -2, userInfo: [NSLocalizedDescriptionKey: "No video tracks found in file"])
        }

        // Check 3: Verify first video track has valid dimensions. naturalSize and
        // preferredTransform are batched into one load (concurrent, not serial).
        if let firstVideoTrack = videoTracks.first {
            let (naturalSize, transform) = try await firstVideoTrack.load(.naturalSize, .preferredTransform)
            guard naturalSize.width > 0 && naturalSize.height > 0 else {
                throw NSError(domain: "ClipPersistence", code: -3, userInfo: [NSLocalizedDescriptionKey: "Video track has invalid dimensions"])
            }

            // Diagnostic: log preferredTransform so silent orientation loss is
            // detectable in field logs. Does NOT throw — unusual transforms
            // shouldn't reject an otherwise-valid clip.
            clipLog.info("verifyVideoPlayability: url=\(url.lastPathComponent) natural=\(Int(naturalSize.width))x\(Int(naturalSize.height)) transform=[a:\(transform.a) b:\(transform.b) c:\(transform.c) d:\(transform.d) tx:\(transform.tx) ty:\(transform.ty)] identity=\(transform.isIdentity)")
        }

        // Check 4: Verify asset is playable (reuses the already-loaded value)
        guard isPlayable else {
            throw NSError(domain: "ClipPersistence", code: -4, userInfo: [NSLocalizedDescriptionKey: "Video is marked as not playable"])
        }

        // Check 5: Verify duration matches expected format (reuses the already-loaded value)
        let durationSeconds = CMTimeGetSeconds(duration)
        guard durationSeconds > 0 && durationSeconds.isFinite && durationSeconds < 14400 else { // Max 4 hours
            throw NSError(domain: "ClipPersistence", code: -5, userInfo: [NSLocalizedDescriptionKey: "Video duration is invalid (\(durationSeconds) seconds)"])
        }

    }

    /// Delegates to `VideoFileManager.generateThumbnail` so every clip in the app
    /// — recorded, imported, trimmed, sync-regenerated — gets the same native-aspect
    /// bounded output. Previously this path produced full-resolution native-aspect
    /// thumbs while `VideoFileManager` produced letterboxed 480×270; the two
    /// diverged visually (black bars on imported portrait clips) and on disk
    /// (multi-MB thumbnails for recorded 4K video).
    func generateThumbnail(for videoURL: URL, at time: CMTime = CMTime(seconds: 1.0, preferredTimescale: 600), knownDuration: CMTime? = nil) async throws -> String {
        let result = await VideoFileManager.generateThumbnail(from: videoURL, at: time, knownDuration: knownDuration)
        switch result {
        case .success(let path):
            return path
        case .failure(let error):
            throw error
        }
    }

    func saveClip(
        from url: URL,
        playResult: PlayResultType?,
        pitchSpeed: Double? = nil,
        pitchType: String? = nil,
        club: Club? = nil,
        role: AthleteRole = .batter,
        note: String? = nil,
        markAsHighlight: Bool = false,
        context: ModelContext,
        athlete: Athlete,
        game: Game?,
        practice: Practice?
    ) async throws -> VideoClip {
        // v6.1 S4: enforce the playResult/club XOR at the single clip-creation
        // choke point. A clip carries either a play result (baseball/softball)
        // or a club (golf), never both — see VideoClip.isTagged /
        // VideoClip+DisplayTag. Both set would corrupt stats (addPlayResult
        // below runs) and mis-display (displayTagName prefers club). No current
        // caller passes both; this assert is a debug tripwire for a future one.
        assert(playResult == nil || club == nil,
               "VideoClip XOR violated: a clip cannot carry both a playResult and a club")

        // Capture the live golf hole NOW, before any awaits. The remaining
        // work (file copy, asset load, verifyVideoPlayability, thumbnail) can
        // take seconds, during which a score tap landing between MainActor
        // yields would shift LiveHoleTracker's next-unscored hole by one and
        // attribute this clip to the *next* hole instead of the recording hole.
        //
        // For an orphan golf capture (no live round) the current-hole stepper
        // (GolfCaptureContext) supplies the hole — nil means "Range", which
        // leaves holeNumber unset and routes the clip to a range session below;
        // a set hole stamps the clip and routes it to today's practice round.
        let manualGolfHole: Int? = (game == nil && practice == nil && athlete.sportType == .golf)
            ? GolfCaptureContext.shared.currentHole
            : nil
        let capturedHoleNumber = manualGolfHole
            ?? LiveHoleTracker.shared.currentHole(for: game)
            ?? LiveHoleTracker.shared.currentHole(for: practice)

        // Validate source URL
        guard url.isFileURL else { throw ClipPersistenceError.invalidURL(url) }
        guard fileManager.fileExists(atPath: url.path) else { throw ClipPersistenceError.fileNotFound(url) }

        // Prepare destination directory
        let clipsDirectoryURL = try ensureClipsDirectory()

        // Build destination URL and avoid copying onto itself
        let proposedDestination = clipsDirectoryURL.appendingPathComponent(url.lastPathComponent)
        let destinationURL: URL
        // Track whether we made a copy so we can delete the source after a successful save.
        // This prevents orphaned imported_*.mov files from accumulating in Documents.
        let sourceNeedsDeletion: Bool
        if url.standardizedFileURL.deletingLastPathComponent() == clipsDirectoryURL.standardizedFileURL {
            destinationURL = url // already in place
            sourceNeedsDeletion = false
        } else {
            destinationURL = uniqueDestinationURL(basedOn: proposedDestination)
            do {
                // Copy on a background thread to avoid blocking the main actor for large videos
                let source = url
                let dest = destinationURL
                try await Task.detached(priority: .userInitiated) {
                    try FileManager.default.copyItem(at: source, to: dest)
                }.value
            } catch {
                throw ClipPersistenceError.failedToCopy(from: url, to: destinationURL, underlying: error)
            }
            sourceNeedsDeletion = true
        }

        let asset: AVAsset = AVURLAsset(url: destinationURL)

        // Validate asset has tracks and valid duration using async property loading.
        // Batch the three asset-level properties into ONE load() so AVFoundation
        // resolves them concurrently (not three serial round-trips) and so
        // verifyVideoPlayability below can reuse them instead of re-loading.
        let tracks: [AVAssetTrack]
        let duration: CMTime
        let isPlayable: Bool
        do {
            (tracks, duration, isPlayable) = try await asset.load(.tracks, .duration, .isPlayable)
        } catch {
            if sourceNeedsDeletion { try? fileManager.removeItem(at: destinationURL) }
            throw ClipPersistenceError.failedToCreateAsset(destinationURL, underlying: error)
        }
        guard !tracks.isEmpty else {
            if sourceNeedsDeletion { try? fileManager.removeItem(at: destinationURL) }
            throw ClipPersistenceError.failedToCreateAsset(destinationURL, underlying: nil)
        }
        let durationSeconds = CMTimeGetSeconds(duration)
        guard durationSeconds >= 0 && durationSeconds.isFinite else {
            if sourceNeedsDeletion { try? fileManager.removeItem(at: destinationURL) }
            throw ClipPersistenceError.failedToCreateAsset(destinationURL, underlying: nil)
        }

        // Verify video is actually playable (corruption detection)
        do {
            try await verifyVideoPlayability(url: destinationURL, tracks: tracks, duration: duration, isPlayable: isPlayable)
        } catch {
            // Only remove the file we just copied in. If destinationURL was an
            // existing file already inside Documents/Clips (sourceNeedsDeletion == false),
            // do NOT delete it — that would destroy the user's original video.
            if sourceNeedsDeletion { try? fileManager.removeItem(at: destinationURL) }
            throw ClipPersistenceError.corruptedVideo(destinationURL, underlying: error)
        }

        // Generate thumbnail for the video
        let thumbnailPath: String?
        do {
            thumbnailPath = try await generateThumbnail(for: destinationURL, knownDuration: duration)
        } catch {
            thumbnailPath = nil
            // Continue without thumbnail - not critical
        }

        // Create new VideoClip instance using app's model
        let videoClip = VideoClip(
            fileName: destinationURL.lastPathComponent,
            filePath: VideoClip.toRelativePath(destinationURL.path)
        )
        videoClip.createdAt = now()
        videoClip.thumbnailPath = thumbnailPath
        videoClip.duration = durationSeconds
        videoClip.pitchSpeed = pitchSpeed
        videoClip.pitchType = pitchType
        videoClip.club = club
        videoClip.note = note
        videoClip.isHighlight = markAsHighlight
        // Use the hole captured at saveClip entry (see top of function).
        // Nil for baseball/softball or for golf clips recorded outside a live round.
        videoClip.holeNumber = capturedHoleNumber

        // Create and link PlayResult model if provided
        if let playResultType = playResult {
            let result = PlayResult(type: playResultType)
            videoClip.playResult = result
            context.insert(result)
            // Auto-tag as highlight based on user-configured rules (Plus feature).
            // OR with the manual flag so an explicit highlight intent can't be
            // demoted by a play type the rules don't cover.
            videoClip.isHighlight = videoClip.isHighlight
                || AutoHighlightSettings.shared.shouldAutoHighlight(
                    playType: playResultType,
                    role: role
                )

            if let game = game {
                // For game videos: Only update game statistics
                // Athlete stats will be aggregated when the game ends
                if game.gameStats == nil {
                    let gameStats = GameStatistics()
                    gameStats.game = game
                    game.gameStats = gameStats
                    context.insert(gameStats)
                }
                if let gameStats = game.gameStats {
                    // Manual-entry games are the stats source of truth — video tags
                    // don't fold into counters. The playResult still lives on the
                    // VideoClip itself, so a future mode switch can rebuild from it.
                    if !gameStats.hasManualEntry {
                        gameStats.addPlayResult(playResultType, pitchType: pitchType, pitchSpeed: pitchSpeed)
                    }
                }
            } else {
                // For practice/standalone videos: Update athlete statistics directly
                if athlete.statistics == nil {
                    let stats = AthleteStatistics()
                    stats.athlete = athlete
                    athlete.statistics = stats
                    context.insert(stats)
                }
                if let statistics = athlete.statistics {
                    statistics.addPlayResult(playResultType, pitchType: pitchType, pitchSpeed: pitchSpeed)
                }
            }
        }

        // Inherit the event's own season so a clip recorded into a past-season
        // game/practice stays on that season — parity with PhotoPersistenceService
        // ("Inherit the game's actual season, not just activeSeason"). Only true
        // orphans (no game, no practice) fall back to the active season, creating
        // a default one if missing so clips are never seasonless. Resolving the
        // event season first also avoids spawning a phantom current season via
        // ensureActiveSeason when recording into a game whose season has ended.
        let resolvedSeason = game?.season ?? practice?.season
            ?? athlete.activeSeason ?? SeasonManager.ensureActiveSeason(for: athlete, in: context)

        // Orphan golf clips (no game, no practice) would each surface as their
        // own journal entry — a 100-swing range session = 100 cards. Group them
        // into today's range-session Practice so the feed shows one card (the
        // journal collapses a practice's clips into a single entry). Only the
        // standalone golf record path lands here; baseball orphans keep updating
        // athlete stats above and stay practice-less.
        var resolvedPractice = practice
        if game == nil, practice == nil, athlete.sportType == .golf {
            // Stepper engaged (a hole is set) = on a course → group into today's
            // practice ROUND and keep the stamped hole. Otherwise it's range
            // work → today's range SESSION (grouped by club, no holes).
            let sessionType: PracticeType = (manualGolfHole != nil) ? .practiceRound : .rangeSession
            resolvedPractice = GolfCaptureSession.todaysSession(
                type: sessionType,
                for: athlete,
                season: resolvedSeason,
                in: context
            )
        }

        // Associate relationships (set one side; rely on Swift Data inverses)
        videoClip.athlete = athlete
        if let game = game { videoClip.game = game }
        if let resolvedPractice { videoClip.practice = resolvedPractice }
        if let season = resolvedSeason {
            videoClip.season = season
        }

        // Denormalize game/season display data directly onto the clip so it survives
        // cross-device sync even if game/season relationships cannot be re-linked.
        videoClip.gameOpponent = game?.opponent
        videoClip.gameDate = game?.date
        videoClip.practiceDate = resolvedPractice?.date
        videoClip.seasonName = resolvedSeason?.displayName

        // Insert and save — clean up copied file if save fails to prevent orphans
        context.insert(videoClip)
        do {
            try context.save()
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            if let absoluteThumbnailPath = videoClip.resolvedThumbnailPath {
                try? fileManager.removeItem(atPath: absoluteThumbnailPath)
            }
            throw error
        }

        // Save to Photos Library if enabled in user preferences
        let preferences: UserPreferences?
        do {
            preferences = try context.fetch(FetchDescriptor<UserPreferences>()).first
        } catch {
            ErrorHandlerService.shared.handle(error, context: "ClipPersistence.fetchPreferences", showAlert: false)
            preferences = nil
        }
        if let preferences, preferences.saveToPhotosLibrary {
            let savedURL = destinationURL
            Task { @MainActor in
                let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
                guard status == .authorized || status == .limited else {
                    ErrorHandlerService.shared.handle(
                        AppError.unknown(nil),
                        context: "ClipPersistence.saveToPhotosLibrary.permissionDenied",
                        showAlert: false
                    )
                    return
                }
                do {
                    try await PHPhotoLibrary.shared().performChanges {
                        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: savedURL)
                    }
                } catch {
                    // Non-fatal: video is already saved to app storage
                    ErrorHandlerService.shared.handle(error, context: "ClipPersistence.saveToPhotosLibrary", showAlert: false)
                }
            }
        }

        // Delete the source file now that the clip is safely persisted in Documents/Clips/.
        // This cleans up the temporary file the recorder or trimmer wrote to a scratch location.
        if sourceNeedsDeletion {
            try? fileManager.removeItem(at: url)
        }

        // Track video recorded analytics
        AnalyticsService.shared.trackVideoRecorded(
            duration: durationSeconds,
            quality: "high", // TODO: Pass actual quality from recorder
            isQuickRecord: false // TODO: Pass actual quick record flag
        )

        // Track video tagging analytics
        if let playResultType = playResult {
            AnalyticsService.shared.trackVideoTagged(
                playResult: playResultType.displayName,
                videoID: videoClip.id.uuidString
            )
        }

        // Notify dashboard to refresh
        NotificationCenter.default.post(name: .videoRecorded, object: videoClip)

        // Automatically queue for cloud upload if the user's preferences allow it. Centralized
        // in UploadQueueManager so the same gate also runs when a clip is starred post-hoc.
        UploadQueueManager.shared.enqueueForAutoUploadIfEligible(videoClip, athlete: athlete, context: context)

        return videoClip
    }
}
