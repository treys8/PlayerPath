//
//  VideoStitchingService.swift
//  PlayerPath
//
//  Stitches multiple video files into a single MP4 via AVMutableComposition.
//  Bakes preferredTransform per source segment so portrait/mirrored clips
//  render correctly. Honors task cancellation.
//

import Foundation
import AVFoundation
import os

private let stitchLog = Logger(subsystem: "com.playerpath.app", category: "VideoStitchingService")

enum VideoStitchingService {
    enum StitchError: LocalizedError {
        case noClips
        case sessionCreationFailed
        case exportFailed(String)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .noClips: return "No clips available to stitch."
            case .sessionCreationFailed: return "Could not create export session."
            case .exportFailed(let msg): return msg
            case .cancelled: return "Stitch was cancelled."
            }
        }
    }

    /// Longest permitted reel dimension (1080p-class in either orientation).
    private static let maxReelLongSide: CGFloat = 1920

    /// Downscales `size` so its longer side is ≤ `maxReelLongSide`, preserving aspect
    /// and forcing even dimensions (H.264 rejects odd width/height). Returns `size`
    /// unchanged when already within the cap, so sub-4K reels stay byte-for-byte
    /// identical to today's output.
    private static func cappedRenderSize(_ size: CGSize) -> CGSize {
        let longSide = max(size.width, size.height)
        guard longSide > maxReelLongSide, longSide > 0 else { return size }
        let scale = maxReelLongSide / longSide
        func toEven(_ v: CGFloat) -> CGFloat { max(2, (v * scale / 2).rounded() * 2) }
        return CGSize(width: toEven(size.width), height: toEven(size.height))
    }

    /// Stitches the given source files end-to-end into one MP4 at `outputURL`.
    /// Skips files that don't exist (logs a warning); throws `noClips` if zero
    /// usable files remain. `progress` fires on the MainActor at ~10 Hz.
    static func stitch(
        sourceURLs: [URL],
        outputURL: URL,
        options: ReelExportOptions = .default,
        progress: @escaping @MainActor @Sendable (Float) -> Void
    ) async throws -> URL {
        let usable = sourceURLs.filter { url in
            let exists = FileManager.default.fileExists(atPath: url.path)
            if !exists { stitchLog.warning("Skipping missing source: \(url.lastPathComponent)") }
            return exists
        }
        guard !usable.isEmpty else { throw StitchError.noClips }

        let composition = AVMutableComposition()
        guard let compVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw StitchError.sessionCreationFailed
        }
        let compAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        var segments: [(timeRange: CMTimeRange, transform: CGAffineTransform, sourceSize: CGSize)] = []
        var cursor: CMTime = .zero
        var renderSize: CGSize = .zero
        var maxFrameRate: Float = 30

        for url in usable {
            let asset = AVURLAsset(url: url)
            do {
                let duration = try await asset.load(.duration)
                guard duration.isValid, duration.seconds > 0 else { continue }

                let videoTracks = try await asset.loadTracks(withMediaType: .video)
                guard let assetVideoTrack = videoTracks.first else {
                    stitchLog.warning("Skipping clip with no video track: \(url.lastPathComponent)")
                    continue
                }

                let segmentRange = CMTimeRange(start: .zero, duration: duration)
                try compVideoTrack.insertTimeRange(segmentRange, of: assetVideoTrack, at: cursor)

                if let assetAudioTrack = try? await asset.loadTracks(withMediaType: .audio).first,
                   let compAudioTrack {
                    do {
                        try compAudioTrack.insertTimeRange(segmentRange, of: assetAudioTrack, at: cursor)
                    } catch {
                        stitchLog.warning("Audio insert failed for \(url.lastPathComponent): \(error.localizedDescription)")
                    }
                }

                let transform = (try? await assetVideoTrack.load(.preferredTransform)) ?? .identity
                let naturalSize = (try? await assetVideoTrack.load(.naturalSize)) ?? .zero
                let nominalFrameRate = (try? await assetVideoTrack.load(.nominalFrameRate)) ?? 30

                if nominalFrameRate > maxFrameRate { maxFrameRate = nominalFrameRate }

                let transformed = naturalSize.applying(transform)
                let segmentRenderSize = CGSize(width: abs(transformed.width), height: abs(transformed.height))
                // Canvas = the largest-area clip's oriented size. Every segment is
                // then aspect-fit (letterboxed) into this single canvas, so a reel
                // mixing portrait and landscape clips renders each clip whole in a
                // consistent frame instead of padding all clips into a per-axis
                // union box (e.g. 1920x1920) with each anchored top-left. Same-
                // orientation + same-resolution segments (and single-clip reels,
                // the dominant case) stay byte-identical; a lower-res same-
                // orientation segment is now upscale-fit + centered instead of
                // top-left-anchored with black bars.
                let area = segmentRenderSize.width * segmentRenderSize.height
                if area > renderSize.width * renderSize.height { renderSize = segmentRenderSize }

                let placedRange = CMTimeRange(start: cursor, duration: duration)
                segments.append((placedRange, transform, segmentRenderSize))

                cursor = CMTimeAdd(cursor, duration)
            } catch {
                stitchLog.warning("Failed to insert clip \(url.lastPathComponent): \(error.localizedDescription)")
                continue
            }
        }

        guard cursor.seconds > 0 else { throw StitchError.noClips }
        if renderSize == .zero { renderSize = CGSize(width: 1920, height: 1080) }

        // Override the canvas for a forced aspect (e.g. 9:16 → 1080×1920). For
        // `.source` this returns the computed canvas unchanged, so default reels
        // render at exactly the same size as before.
        renderSize = options.renderSize(sourceCanvas: renderSize)

        // Cap the reel canvas to 1080p-class. A 4K-source reel is visually
        // indistinguishable from 1080p on a phone but ~4× the bytes — too large for
        // Messages/AirDrop/Photos when a season reel runs minutes long. Downscale
        // ONLY (never upscale); reels already ≤ 1920 on the long side (the common
        // iPhone-1080p case and the 9:16 export at 1080×1920) are returned unchanged,
        // so only oversized 4K+ reels change bytes. Codec stays H.264 (HighestQuality)
        // for universal playback on any recipient.
        renderSize = cappedRenderSize(renderSize)

        // Cap at 60fps: a single 120/240fps slow-mo highlight would otherwise force the
        // whole composition to that rate (much slower export, much larger file) for no
        // visual gain — the slow-motion effect rides on clip timing, not the frame rate.
        let fps = Int32(min(maxFrameRate, 60).rounded())
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(fps, 1)))

        // Prepend the intro title card (social variants only — needsCardSegment forces
        // !isVisuallyDefault, so the default dual codepath below never sees a card).
        // The card is generated at the FINAL renderSize (post-cap, post-9:16 override),
        // so its placement transform is identity and it fills the canvas exactly.
        var cardCleanupURL: URL?
        defer { if let cardCleanupURL { try? FileManager.default.removeItem(at: cardCleanupURL) } }

        if options.needsCardSegment {
            let cardDuration = CMTime(seconds: ReelCardStyle.durationSeconds, preferredTimescale: 600)
            let cardImage = ReelCardRenderer.makeCardImage(
                size: renderSize,
                title: options.resolvedCardTitle,
                subtitle: options.resolvedCardSubtitle
            )
            let cardURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("reelcard-\(UUID().uuidString).mp4")
            cardCleanupURL = cardURL
            _ = try await ReelCardRenderer.encodeStillMP4(
                image: cardImage, size: renderSize,
                duration: cardDuration, outputURL: cardURL
            )

            let cardAsset = AVURLAsset(url: cardURL)
            // Throw rather than silently skip: the output lands at the card-suffixed
            // cache path, so a card-less reel written there would be served as a
            // "cache hit" for this variant forever.
            guard let cardTrack = try await cardAsset.loadTracks(withMediaType: .video).first else {
                throw StitchError.exportFailed("Title card encode produced no video track.")
            }
            let cardRange = CMTimeRange(start: .zero, duration: cardDuration)
            try compVideoTrack.insertTimeRange(cardRange, of: cardTrack, at: .zero)
            // Keep A/V in sync: push the audio by the same amount with silence,
            // or the sound would play `cardDuration` ahead of its footage.
            compAudioTrack?.insertEmptyTimeRange(cardRange)
            // Shift every footage segment down the timeline, then lead with the card.
            segments = segments.map {
                (timeRange: CMTimeRange(start: CMTimeAdd($0.timeRange.start, cardDuration),
                                        duration: $0.timeRange.duration),
                 transform: $0.transform,
                 sourceSize: $0.sourceSize)
            }
            // sourceSize == renderSize ⇒ placedTransform is identity (fills the canvas).
            segments.insert((timeRange: cardRange, transform: .identity, sourceSize: renderSize), at: 0)
        }

        // Build the video composition. iOS 26 introduced a new Configuration-based API;
        // the older mutable types still work but emit deprecation warnings on iOS 26+.
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw StitchError.sessionCreationFailed
        }

        try? FileManager.default.removeItem(at: outputURL)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        session.outputURL = outputURL
        session.outputFileType = .mp4

        // Place each segment into `renderSize`: aspect-FIT (letterbox) by default, or
        // aspect-FILL (center-crop) when `options.fillCrop` — then center. Composed
        // AFTER the source's preferredTransform (orient first, then place). For the
        // default options this is `min`-scale + identity-when-matching, so
        // same-orientation/-resolution reels stay byte-for-byte unchanged.
        func placedTransform(_ transform: CGAffineTransform, sourceSize: CGSize) -> CGAffineTransform {
            guard sourceSize.width > 0, sourceSize.height > 0 else { return transform }
            let scaleX = renderSize.width / sourceSize.width
            let scaleY = renderSize.height / sourceSize.height
            let scale = options.fillCrop ? max(scaleX, scaleY) : min(scaleX, scaleY)
            let scaledW = sourceSize.width * scale
            let scaledH = sourceSize.height * scale
            let fit = CGAffineTransform(scaleX: scale, y: scale)
                .concatenating(CGAffineTransform(translationX: (renderSize.width - scaledW) / 2,
                                                 y: (renderSize.height - scaledH) / 2))
            return transform.concatenating(fit)
        }

        if !options.isVisuallyDefault {
            // Social-export variant (forced aspect and/or overlay). One mutable-API
            // path on all OS versions — confined here so the default reel keeps its
            // existing (deprecation-free) dual codepath below and stays identical.
            let videoComposition = AVMutableVideoComposition()
            videoComposition.renderSize = renderSize
            videoComposition.frameDuration = frameDuration
            let needsBlackBars = options.aspect == .vertical9x16
            videoComposition.instructions = segments.map { segment in
                let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideoTrack)
                layerInstruction.setTransform(placedTransform(segment.transform, sourceSize: segment.sourceSize), at: segment.timeRange.start)
                let instruction = AVMutableVideoCompositionInstruction()
                instruction.timeRange = segment.timeRange
                instruction.layerInstructions = [layerInstruction]
                // Opaque-black letterbox bars (the composition-instruction half of the
                // 9:16 background; the Core Animation parent layer is the other half).
                if needsBlackBars { instruction.backgroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1) }
                return instruction
            }
            // Bake the name/caption overlay and/or corner watermark into the frames.
            // Layers MUST be built on the main thread (this stitch is main-actor-
            // isolated by default), or the Core Animation tool renders black frames.
            if options.needsAnimationTool {
                videoComposition.animationTool = ReelOverlayRenderer.makeAnimationTool(renderSize: renderSize, options: options)
            }
            session.videoComposition = videoComposition
        } else if #available(iOS 26.0, *) {
            let instructions: [AVVideoCompositionInstruction] = segments.map { segment in
                var layerConfig = AVVideoCompositionLayerInstruction.Configuration(assetTrack: compVideoTrack)
                layerConfig.setTransform(placedTransform(segment.transform, sourceSize: segment.sourceSize), at: segment.timeRange.start)
                let layerInstruction = AVVideoCompositionLayerInstruction(configuration: layerConfig)
                let instructionConfig = AVVideoCompositionInstruction.Configuration(
                    layerInstructions: [layerInstruction],
                    timeRange: segment.timeRange
                )
                return AVVideoCompositionInstruction(configuration: instructionConfig)
            }
            let compConfig = AVVideoComposition.Configuration(
                frameDuration: frameDuration,
                instructions: instructions,
                renderSize: renderSize
            )
            session.videoComposition = AVVideoComposition(configuration: compConfig)
        } else {
            let videoComposition = AVMutableVideoComposition()
            videoComposition.renderSize = renderSize
            videoComposition.frameDuration = frameDuration
            videoComposition.instructions = segments.map { segment in
                let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideoTrack)
                layerInstruction.setTransform(placedTransform(segment.transform, sourceSize: segment.sourceSize), at: segment.timeRange.start)
                let instruction = AVMutableVideoCompositionInstruction()
                instruction.timeRange = segment.timeRange
                instruction.layerInstructions = [layerInstruction]
                return instruction
            }
            session.videoComposition = videoComposition
        }

        let box = AVExportSessionBox(session)

        return try await withTaskCancellationHandler {
            if #available(iOS 18.0, *) {
                // The modern `export(to:as:)` no longer drives the (deprecated)
                // `session.progress` KVO property — polling it leaves the UI stuck at
                // 0% until completion. Observe the `states(updateInterval:)` async
                // sequence concurrently instead; it terminates when the export ends.
                let progressTask = Task { @MainActor in
                    for await exportState in box.session.states(updateInterval: 0.1) {
                        if case .exporting(let p) = exportState {
                            progress(Float(p.fractionCompleted))
                        }
                    }
                }
                do {
                    try await session.export(to: outputURL, as: .mp4)
                    progressTask.cancel()
                    await MainActor.run { progress(1.0) }
                    return outputURL
                } catch {
                    progressTask.cancel()
                    try? FileManager.default.removeItem(at: outputURL)
                    if Task.isCancelled { throw StitchError.cancelled }
                    throw StitchError.exportFailed(error.localizedDescription)
                }
            } else {
                // iOS 17: the legacy `export()` still updates `session.progress`, so
                // poll it on the MainActor for the duration of the export.
                let progressTask = Task { @MainActor in
                    while !Task.isCancelled {
                        let p = box.session.progress
                        progress(p)
                        if p >= 1.0 { return }
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                }
                defer { progressTask.cancel() }
                await session.export()
                switch session.status {
                case .completed:
                    await MainActor.run { progress(1.0) }
                    return outputURL
                case .cancelled:
                    try? FileManager.default.removeItem(at: outputURL)
                    throw StitchError.cancelled
                default:
                    try? FileManager.default.removeItem(at: outputURL)
                    throw StitchError.exportFailed(session.error?.localizedDescription ?? "Export failed")
                }
            }
        } onCancel: {
            box.cancel()
        }
    }
}
