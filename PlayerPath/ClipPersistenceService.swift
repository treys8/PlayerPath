import SwiftUI
import SwiftData
import Foundation
import AVFoundation

enum ClipPersistenceError: Error {
    case fileNotFound
    case failedToCopy
    case failedToCreateAsset
}

final class ClipPersistenceService {
    public init() {}
    
    func saveClip(
        from url: URL,
        playResult: PlayResultType?,
        context: ModelContext,
        athlete: Athlete,
        game: Game?,
        practice: Practice?
    ) async throws -> Clip {
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: url.path) else {
            throw ClipPersistenceError.fileNotFound
        }
        
        // Prepare destination URL in Caches/Clips preserving lastPathComponent
        let cachesURL = try fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let clipsDirectoryURL = cachesURL.appendingPathComponent("Clips", isDirectory: true)
        
        if !fileManager.fileExists(atPath: clipsDirectoryURL.path) {
            try fileManager.createDirectory(at: clipsDirectoryURL, withIntermediateDirectories: true)
        }
        
        let destinationURL = clipsDirectoryURL.appendingPathComponent(url.lastPathComponent)
        
        // Copy file to destinationURL to decouple from temp URL
        // Remove existing if needed
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        do {
            try fileManager.copyItem(at: url, to: destinationURL)
        } catch {
            throw ClipPersistenceError.failedToCopy
        }
        
        let asset = AVAsset(url: destinationURL)
        
        // Validate asset has tracks and valid duration
        guard !asset.tracks.isEmpty else {
            throw ClipPersistenceError.failedToCreateAsset
        }
        let durationSeconds = CMTimeGetSeconds(asset.duration)
        guard durationSeconds >= 0 && durationSeconds.isFinite else {
            throw ClipPersistenceError.failedToCreateAsset
        }
        
        // Create new Clip instance
        // TODO: Adjust property names if different in your Clip model
        let clip = Clip(
            id: UUID(), // TODO: Replace with your Clip's id init if needed
            createdAt: Date(), // TODO: Replace with your Clip's createdAt property if named differently
            videoURL: destinationURL, // TODO: Replace with your Clip's URL property if named differently
            duration: durationSeconds, // TODO: Replace with your Clip's duration property if named differently
            playResult: playResult // TODO: Replace with your Clip's playResult property if named differently
        )
        
        // Associate relationships
        // TODO: Adjust property names if different or if Clip uses different relationship setup
        clip.athlete = athlete
        
        if let game = game {
            clip.game = game
        }
        
        if let practice = practice {
            clip.practice = practice
        }
        
        context.insert(clip)
        try context.save()
        
        return clip
    }
}
