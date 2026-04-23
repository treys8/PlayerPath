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


        var migratedCount = 0
        var failedCount = 0

        for oldVideoURL in oldVideoFiles {
            let newVideoURL = newClipsDirectory.appendingPathComponent(oldVideoURL.lastPathComponent)

            do {
                // Move file to new location
                if fileManager.fileExists(atPath: newVideoURL.path) {
                    // File already exists in new location, just delete old one
                    try fileManager.removeItem(at: oldVideoURL)
                } else {
                    try fileManager.moveItem(at: oldVideoURL, to: newVideoURL)
                }

                // Update VideoClip path in SwiftData (store as relative)
                let fileName = oldVideoURL.lastPathComponent
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

            } catch {
                clipLog.error("Video migration failed for \(oldVideoURL.lastPathComponent): \(error.localizedDescription)")
                failedCount += 1
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

        // Only mark migration complete if all files succeeded
        if failedCount == 0 {
            UserDefaults.standard.set(true, forKey: migrationKey)
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
    private func verifyVideoPlayability(asset: AVAsset, url: URL) async throws {
        // Check 1: Verify file size is reasonable (not suspiciously small)
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        guard let fileSize = attributes[.size] as? Int64, fileSize > 10000 else { // At least 10KB
            throw NSError(domain: "ClipPersistence", code: -1, userInfo: [NSLocalizedDescriptionKey: "Video file size is suspiciously small (\(attributes[.size] ?? 0) bytes)"])
        }

        // Check 2: Verify the asset has video tracks
        let allTracks = try await asset.load(.tracks)
        let videoTracks = allTracks.filter { $0.mediaType == .video }
        guard !videoTracks.isEmpty else {
            throw NSError(domain: "ClipPersistence", code: -2, userInfo: [NSLocalizedDescriptionKey: "No video tracks found in file"])
        }

        // Check 3: Verify first video track has valid dimensions
        if let firstVideoTrack = videoTracks.first {
            let naturalSize = try await firstVideoTrack.load(.naturalSize)
            guard naturalSize.width > 0 && naturalSize.height > 0 else {
                throw NSError(domain: "ClipPersistence", code: -3, userInfo: [NSLocalizedDescriptionKey: "Video track has invalid dimensions"])
            }

            // Diagnostic: log preferredTransform so silent orientation loss is
            // detectable in field logs. Does NOT throw — unusual transforms
            // shouldn't reject an otherwise-valid clip.
            let transform = try await firstVideoTrack.load(.preferredTransform)
            clipLog.info("verifyVideoPlayability: url=\(url.lastPathComponent) natural=\(Int(naturalSize.width))x\(Int(naturalSize.height)) transform=[a:\(transform.a) b:\(transform.b) c:\(transform.c) d:\(transform.d) tx:\(transform.tx) ty:\(transform.ty)] identity=\(transform.isIdentity)")
        }

        // Check 4: Verify asset is playable
        let isPlayable = try await asset.load(.isPlayable)
        guard isPlayable else {
            throw NSError(domain: "ClipPersistence", code: -4, userInfo: [NSLocalizedDescriptionKey: "Video is marked as not playable"])
        }

        // Check 5: Verify duration matches expected format
        let duration = try await asset.load(.duration)
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
    func generateThumbnail(for videoURL: URL, at time: CMTime = CMTime(seconds: 1.0, preferredTimescale: 600)) async throws -> String {
        let result = await VideoFileManager.generateThumbnail(from: videoURL, at: time)
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
        role: AthleteRole = .batter,
        note: String? = nil,
        context: ModelContext,
        athlete: Athlete,
        game: Game?,
        practice: Practice?
    ) async throws -> VideoClip {
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

        // Validate asset has tracks and valid duration using async property loading
        let tracks: [AVAssetTrack]
        let duration: CMTime
        do {
            tracks = try await asset.load(.tracks)
            duration = try await asset.load(.duration)
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
            try await verifyVideoPlayability(asset: asset, url: destinationURL)
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
            thumbnailPath = try await generateThumbnail(for: destinationURL)
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
        videoClip.note = note

        // Create and link PlayResult model if provided
        if let playResultType = playResult {
            let result = PlayResult(type: playResultType)
            videoClip.playResult = result
            context.insert(result)
            // Auto-tag as highlight based on user-configured rules (Plus feature)
            videoClip.isHighlight = AutoHighlightSettings.shared.shouldAutoHighlight(
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
                    gameStats.addPlayResult(playResultType, pitchType: pitchType, pitchSpeed: pitchSpeed)
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

        // Associate relationships (set one side; rely on Swift Data inverses)
        videoClip.athlete = athlete
        if let game = game { videoClip.game = game }
        if let practice = practice { videoClip.practice = practice }

        // Ensure athlete has an active season (creates default if missing),
        // then link the video to it so clips are never orphaned without a season.
        let activeSeason = athlete.activeSeason ?? SeasonManager.ensureActiveSeason(for: athlete, in: context)
        if let season = activeSeason {
            videoClip.season = season
        }

        // Denormalize game/season display data directly onto the clip so it survives
        // cross-device sync even if game/season relationships cannot be re-linked.
        videoClip.gameOpponent = game?.opponent
        videoClip.gameDate = game?.date
        videoClip.practiceDate = practice?.date
        videoClip.seasonName = activeSeason?.displayName

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

        // Automatically queue for cloud upload if enabled in preferences
        Task { @MainActor in
            // Check user preferences for auto-upload setting
            let descriptor = FetchDescriptor<UserPreferences>()
            let autoUploadPrefs: UserPreferences?
            do {
                autoUploadPrefs = try context.fetch(descriptor).first
            } catch {
                ErrorHandlerService.shared.handle(error, context: "ClipPersistence.fetchAutoUploadPrefs", showAlert: false)
                autoUploadPrefs = nil
            }
            guard let preferences = autoUploadPrefs, preferences.autoUploadToCloud else { return }

            let fileSize = self.fileManager.fileSize(atPath: videoClip.resolvedFilePath)
            let fileSizeMB = fileSize / StorageConstants.bytesPerMB
            guard fileSizeMB <= preferences.maxVideoFileSize else { return }
            guard !preferences.syncHighlightsOnly || videoClip.isHighlight else { return }

            UploadQueueManager.shared.enqueue(videoClip, athlete: athlete, priority: .normal)
        }

        return videoClip
    }
}
