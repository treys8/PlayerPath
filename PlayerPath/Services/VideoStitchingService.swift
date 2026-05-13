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

private final class SessionBox: @unchecked Sendable {
    nonisolated(unsafe) let session: AVAssetExportSession
    init(_ session: AVAssetExportSession) { self.session = session }
    nonisolated func cancel() { session.cancelExport() }
}

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

    /// Stitches the given source files end-to-end into one MP4 at `outputURL`.
    /// Skips files that don't exist (logs a warning); throws `noClips` if zero
    /// usable files remain. `progress` fires on the MainActor at ~10 Hz.
    static func stitch(
        sourceURLs: [URL],
        outputURL: URL,
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

        var segments: [(timeRange: CMTimeRange, transform: CGAffineTransform)] = []
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
                if segmentRenderSize.width > renderSize.width { renderSize.width = segmentRenderSize.width }
                if segmentRenderSize.height > renderSize.height { renderSize.height = segmentRenderSize.height }

                let placedRange = CMTimeRange(start: cursor, duration: duration)
                segments.append((placedRange, transform))

                cursor = CMTimeAdd(cursor, duration)
            } catch {
                stitchLog.warning("Failed to insert clip \(url.lastPathComponent): \(error.localizedDescription)")
                continue
            }
        }

        guard cursor.seconds > 0 else { throw StitchError.noClips }
        if renderSize == .zero { renderSize = CGSize(width: 1920, height: 1080) }

        let fps = Int32(maxFrameRate.rounded())
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(fps, 1)))

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

        if #available(iOS 26.0, *) {
            let instructions: [AVVideoCompositionInstruction] = segments.map { segment in
                var layerConfig = AVVideoCompositionLayerInstruction.Configuration(assetTrack: compVideoTrack)
                layerConfig.setTransform(segment.transform, at: segment.timeRange.start)
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
                layerInstruction.setTransform(segment.transform, at: segment.timeRange.start)
                let instruction = AVMutableVideoCompositionInstruction()
                instruction.timeRange = segment.timeRange
                instruction.layerInstructions = [layerInstruction]
                return instruction
            }
            session.videoComposition = videoComposition
        }

        let box = SessionBox(session)

        // Drive periodic progress updates on the MainActor while the export runs.
        let progressTask = Task { @MainActor in
            while !Task.isCancelled {
                let p = box.session.progress
                progress(p)
                if p >= 1.0 { return }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        defer { progressTask.cancel() }

        return try await withTaskCancellationHandler {
            if #available(iOS 18.0, *) {
                do {
                    try await session.export(to: outputURL, as: .mp4)
                    await MainActor.run { progress(1.0) }
                    return outputURL
                } catch {
                    try? FileManager.default.removeItem(at: outputURL)
                    if Task.isCancelled { throw StitchError.cancelled }
                    throw StitchError.exportFailed(error.localizedDescription)
                }
            } else {
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
