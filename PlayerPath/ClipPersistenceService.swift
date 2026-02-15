import SwiftUI
import SwiftData
import Foundation
import AVFoundation

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
            print("ClipPersistenceService: Video storage migration already completed")
            return
        }

        print("ClipPersistenceService: Starting video storage migration from Caches to Documents...")

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
            print("ClipPersistenceService: No old Caches directory found, marking migration complete")
            UserDefaults.standard.set(true, forKey: migrationKey)
            return
        }

        // Get all video files from old directory
        let oldVideoFiles = try fileManager.contentsOfDirectory(
            at: oldClipsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: .skipsHiddenFiles
        ).filter { $0.pathExtension.lowercased() == "mov" || $0.pathExtension.lowercased() == "mp4" }

        print("ClipPersistenceService: Found \(oldVideoFiles.count) video files to migrate")

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

                // Update VideoClip path in SwiftData
                let fileName = oldVideoURL.lastPathComponent
                let predicate = #Predicate<VideoClip> { clip in
                    clip.fileName == fileName
                }
                let descriptor = FetchDescriptor(predicate: predicate)
                let clips = try context.fetch(descriptor)

                for clip in clips {
                    clip.filePath = newVideoURL.path
                }

                migratedCount += 1
                print("ClipPersistenceService: Migrated \(fileName)")

            } catch {
                print("ClipPersistenceService: Failed to migrate \(oldVideoURL.lastPathComponent): \(error.localizedDescription)")
                failedCount += 1
            }
        }

        // Save updated paths
        try context.save()

        // Clean up old directory if empty
        if let remainingFiles = try? fileManager.contentsOfDirectory(atPath: oldClipsDirectory.path),
           remainingFiles.isEmpty {
            try? fileManager.removeItem(at: oldClipsDirectory)
        }

        // Mark migration complete
        UserDefaults.standard.set(true, forKey: migrationKey)

        print("ClipPersistenceService: Migration complete - \(migratedCount) succeeded, \(failedCount) failed")
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
        }

        // Check 4: Verify asset is playable
        let isPlayable = try await asset.load(.isPlayable)
        guard isPlayable else {
            throw NSError(domain: "ClipPersistence", code: -4, userInfo: [NSLocalizedDescriptionKey: "Video is marked as not playable"])
        }

        // Check 5: Verify duration matches expected format
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        guard durationSeconds > 0 && durationSeconds.isFinite && durationSeconds < 3600 else { // Max 1 hour
            throw NSError(domain: "ClipPersistence", code: -5, userInfo: [NSLocalizedDescriptionKey: "Video duration is invalid (\(durationSeconds) seconds)"])
        }

        print("ClipPersistenceService: ✅ Video verified as playable - \(Int(durationSeconds))s, \(fileSize / 1024 / 1024)MB")
    }

    private func generateThumbnail(for videoURL: URL, at time: CMTime = CMTime(seconds: 1.0, preferredTimescale: 600)) async throws -> String {
        let asset = AVURLAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceAfter = .zero
        imageGenerator.requestedTimeToleranceBefore = .zero

        // Generate thumbnail image
        let cgImage = try await imageGenerator.image(at: time).image

        // Create thumbnails directory
        let documentsURL = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let thumbnailsDirectory = documentsURL.appendingPathComponent("Thumbnails", isDirectory: true)
        if !fileManager.fileExists(atPath: thumbnailsDirectory.path) {
            try fileManager.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
        }

        // Generate thumbnail filename based on video filename
        let videoFileName = videoURL.deletingPathExtension().lastPathComponent
        let thumbnailFileName = "\(videoFileName)_thumb.jpg"
        let thumbnailURL = thumbnailsDirectory.appendingPathComponent(thumbnailFileName)

        // Convert CGImage to JPEG and save
        #if os(iOS)
        let uiImage = UIImage(cgImage: cgImage)
        guard let jpegData = uiImage.jpegData(compressionQuality: 0.8) else {
            throw ClipPersistenceError.failedToCreateAsset(thumbnailURL, underlying: nil)
        }
        try jpegData.write(to: thumbnailURL)
        #endif

        print("ClipPersistenceService: Generated thumbnail at \(thumbnailURL.path)")
        return thumbnailURL.path
    }

    func saveClip(
        from url: URL,
        playResult: PlayResultType?,
        pitchSpeed: Double? = nil,
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
        if url.standardizedFileURL.deletingLastPathComponent() == clipsDirectoryURL.standardizedFileURL {
            destinationURL = url // already in place
        } else {
            destinationURL = uniqueDestinationURL(basedOn: proposedDestination)
            do {
                try fileManager.copyItem(at: url, to: destinationURL)
            } catch {
                throw ClipPersistenceError.failedToCopy(from: url, to: destinationURL, underlying: error)
            }
        }

        let asset: AVAsset = AVURLAsset(url: destinationURL)

        // Validate asset has tracks and valid duration using async property loading
        let tracks: [AVAssetTrack]
        let duration: CMTime
        do {
            tracks = try await asset.load(.tracks)
            duration = try await asset.load(.duration)
        } catch {
            throw ClipPersistenceError.failedToCreateAsset(destinationURL, underlying: error)
        }
        guard !tracks.isEmpty else {
            throw ClipPersistenceError.failedToCreateAsset(destinationURL, underlying: nil)
        }
        let durationSeconds = CMTimeGetSeconds(duration)
        guard durationSeconds >= 0 && durationSeconds.isFinite else {
            throw ClipPersistenceError.failedToCreateAsset(destinationURL, underlying: nil)
        }

        // Verify video is actually playable (corruption detection)
        do {
            try await verifyVideoPlayability(asset: asset, url: destinationURL)
        } catch {
            // Delete corrupted file
            try? fileManager.removeItem(at: destinationURL)
            throw ClipPersistenceError.corruptedVideo(destinationURL, underlying: error)
        }

        // Generate thumbnail for the video
        let thumbnailPath: String?
        do {
            thumbnailPath = try await generateThumbnail(for: destinationURL)
        } catch {
            print("⚠️ ClipPersistenceService: Failed to generate thumbnail: \(error.localizedDescription)")
            thumbnailPath = nil
            // Continue without thumbnail - not critical
        }

        // Create new VideoClip instance using app's model
        let videoClip = VideoClip(
            fileName: destinationURL.lastPathComponent,
            filePath: destinationURL.path
        )
        videoClip.createdAt = now()
        videoClip.thumbnailPath = thumbnailPath
        videoClip.duration = durationSeconds
        videoClip.pitchSpeed = pitchSpeed

        // Create and link PlayResult model if provided
        if let playResultType = playResult {
            let result = PlayResult(type: playResultType)
            videoClip.playResult = result
            context.insert(result)
            // Mark as highlight for hit outcomes
            videoClip.isHighlight = playResultType.isHighlight

            if let game = game {
                // For game videos: Only update game statistics
                // Athlete stats will be aggregated when the game ends
                if game.gameStats == nil {
                    let gameStats = GameStatistics()
                    gameStats.game = game
                    game.gameStats = gameStats
                    context.insert(gameStats)
                    print("ClipPersistenceService: Created new GameStatistics for game vs \(game.opponent)")
                }
                if let gameStats = game.gameStats {
                    gameStats.addPlayResult(playResultType)
                    print("ClipPersistenceService: Updated game statistics for play result: \(playResultType.rawValue)")
                }
            } else {
                // For practice/standalone videos: Update athlete statistics directly
                if athlete.statistics == nil {
                    let stats = AthleteStatistics()
                    stats.athlete = athlete
                    athlete.statistics = stats
                    context.insert(stats)
                    print("ClipPersistenceService: Created new Statistics for athlete \(athlete.name)")
                }
                if let statistics = athlete.statistics {
                    statistics.addPlayResult(playResultType)
                    print("ClipPersistenceService: Updated athlete statistics for play result: \(playResultType.rawValue)")
                }
            }
        }

        // Associate relationships (set one side; rely on Swift Data inverses)
        videoClip.athlete = athlete
        if let game = game { videoClip.game = game }
        if let practice = practice { videoClip.practice = practice }

        // Link video to active season BEFORE save
        if let activeSeason = athlete.activeSeason {
            videoClip.season = activeSeason
        }

        // Insert and save
        context.insert(videoClip)
        try context.save()

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
        NotificationCenter.default.post(name: Notification.Name("VideoRecorded"), object: videoClip)

        // Automatically queue for cloud upload if enabled in preferences
        Task { @MainActor in
            // Check user preferences for auto-upload setting
            let descriptor = FetchDescriptor<UserPreferences>()
            if let preferences = try? context.fetch(descriptor).first,
               preferences.autoUploadToCloud {
                // Check file size limit
                let fileSize = FileManager.default.fileSize(atPath: videoClip.filePath)
                let fileSizeMB = fileSize / 1024 / 1024

                if fileSizeMB <= preferences.maxVideoFileSize {
                    // Check if we should only upload highlights
                    if !preferences.syncHighlightsOnly || videoClip.isHighlight {
                        UploadQueueManager.shared.enqueue(videoClip, athlete: athlete, priority: .normal)
                        print("ClipPersistenceService: Queued video for automatic upload: \(videoClip.fileName)")
                    } else {
                        print("ClipPersistenceService: Skipping upload (not a highlight, highlights-only mode enabled)")
                    }
                } else {
                    print("ClipPersistenceService: Skipping upload (file size \(fileSizeMB)MB exceeds limit of \(preferences.maxVideoFileSize)MB)")
                }
            } else {
                print("ClipPersistenceService: Auto-upload disabled in preferences")
            }
        }

        return videoClip
    }
}
