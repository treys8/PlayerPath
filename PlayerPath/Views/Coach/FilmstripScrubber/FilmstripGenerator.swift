//
//  FilmstripGenerator.swift
//  PlayerPath
//
//  Generates frame thumbnails from a video asset at regular intervals.
//  Used by CoachVideoPlayerViewModel to populate the filmstrip scrubber.
//

import AVFoundation
import UIKit

final class FilmstripGenerator {

    /// Generates evenly-spaced thumbnails across the video duration.
    /// Updates the returned array progressively as each frame is generated.
    /// Call from a background-friendly context — image generation is CPU work.
    ///
    /// - Parameters:
    ///   - asset: The video asset to extract frames from.
    ///   - duration: Pre-loaded duration in seconds (avoids redundant async load).
    ///   - onProgress: Called on the main actor each time a new thumbnail is ready.
    ///                 Receives the full array (partially populated with images).
    func generateThumbnails(
        for asset: AVAsset,
        duration: Double,
        onProgress: @MainActor @Sendable ([FilmstripThumbnail]) -> Void
    ) async {
        guard duration > 0 else { return }

        let frameCount = min(30, max(1, Int(duration / 0.5)))
        let interval = duration / Double(frameCount)

        // Pre-populate with nil images
        var thumbnails = (0..<frameCount).map { index in
            FilmstripThumbnail(
                id: index,
                timestamp: Double(index) * interval,
                image: nil
            )
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 160, height: 90)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)

        for index in 0..<frameCount {
            guard !Task.isCancelled else { return }

            let time = CMTime(seconds: thumbnails[index].timestamp, preferredTimescale: 600)
            do {
                let (cgImage, _) = try await generator.image(at: time)
                thumbnails[index].image = UIImage(cgImage: cgImage)
            } catch {
                // Skip frames that fail — leave image as nil
            }

            let snapshot = thumbnails
            await MainActor.run { onProgress(snapshot) }
        }
    }
}
