import SwiftUI
import SwiftData
import Foundation
import AVFoundation

enum ClipPersistenceError: LocalizedError {
    case fileNotFound(URL)
    case invalidURL(URL)
    case failedToCopy(from: URL, to: URL, underlying: Error)
    case failedToCreateAsset(URL, underlying: Error?)

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
        let cachesURL = try fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let clipsDirectoryURL = cachesURL.appendingPathComponent(Constants.clipsFolderName, isDirectory: true)
        if !fileManager.fileExists(atPath: clipsDirectoryURL.path) {
            try fileManager.createDirectory(at: clipsDirectoryURL, withIntermediateDirectories: true)
        }
        return clipsDirectoryURL
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

    func saveClip(
        from url: URL,
        playResult: PlayResultType?,
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

        // Create new VideoClip instance using app's model
        let videoClip = VideoClip(
            fileName: destinationURL.lastPathComponent,
            filePath: destinationURL.path
        )
        videoClip.createdAt = now()

        // Create and link PlayResult model if provided
        if let playResultType = playResult {
            let result = PlayResult(type: playResultType)
            videoClip.playResult = result
            context.insert(result)
            // Mark as highlight for hit outcomes
            videoClip.isHighlight = playResultType.isHighlight
        }

        // Associate relationships (set one side; rely on Swift Data inverses)
        videoClip.athlete = athlete
        if let game = game { videoClip.game = game }
        if let practice = practice { videoClip.practice = practice }

        // Insert and save
        context.insert(videoClip)
        try context.save()

        return videoClip
    }
}
