import SwiftUI
import SwiftData
import AVFoundation
import Foundation

/// A service responsible for persisting a recorded or selected video clip into SwiftData,
/// generating a thumbnail, linking it to an athlete, game, and/or practice,
/// updating related statistics, and cleaning up temporary files.
/// 
/// Usage:
/// Call `saveClip(from:playResult:context:athlete:game:practice:)` asynchronously to save a video clip,
/// which handles copying the file, creating the model objects, generating a thumbnail,
/// linking the entities, updating statistics, and cleaning up.
/// The API returns the persisted `VideoClip` object.
public struct ClipPersistenceService {
    
    /// Saves a video clip from a given source URL into the persistent store,
    /// linking it to the provided athlete, game, and practice, and updating statistics.
    /// This function also generates a thumbnail asynchronously and cleans up temporary files if needed.
    ///
    /// - Parameters:
    ///   - sourceURL: The URL of the original video clip file.
    ///   - playResult: An optional play result type describing the clip's outcome.
    ///   - context: The SwiftData model context for persistence operations.
    ///   - athlete: The athlete associated with the clip.
    ///   - game: An optional game associated with the clip.
    ///   - practice: An optional practice associated with the clip.
    /// - Returns: The persisted `VideoClip` object.
    /// - Throws: Rethrows errors from file operations or context saving.
    public func saveClip(
        from sourceURL: URL,
        playResult: PlayResultType?,
        context: ModelContext,
        athlete: Athlete,
        game: Game?,
        practice: Practice?
    ) async throws -> VideoClip {
        
        let permanentURL = try VideoFileManager.copyToDocuments(from: sourceURL)
        
        let clip = VideoClip(fileName: permanentURL.lastPathComponent, filePath: permanentURL.path)
        
        if let playResult = playResult {
            let result = PlayResult(type: playResult)
            clip.playResult = result
            clip.isHighlight = playResult.isHighlight
            context.insert(result)
            
            athlete.statistics?.addPlayResult(playResult)
            if let gameStats = game?.gameStats {
                gameStats.addPlayResult(playResult)
            }
        }
        
        if let game = game {
            clip.game = game
            game.videoClips.append(clip)
        } else if let practice = practice {
            clip.practice = practice
            practice.videoClips.append(clip)
        }
        
        clip.athlete = athlete
        athlete.videoClips.append(clip)
        
        context.insert(clip)
        try context.save()
        
        Task.detached(priority: .background) {
            if let thumbnailPath = await VideoFileManager.generateThumbnail(from: permanentURL) {
                await MainActor.run {
                    clip.thumbnailPath = thumbnailPath
                    try? context.save()
                }
            }
        }
        
        if sourceURL != permanentURL {
            VideoFileManager.cleanup(url: sourceURL)
        }
        
        return clip
    }
}
