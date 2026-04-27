//
//  VideoTrimExporter.swift
//  PlayerPath
//
//  Shared async exporter for trimming video clips. Bakes preferredTransform
//  for rotated recordings and preserves native frame rate (60fps, 120fps,
//  slow-motion). Extracted from PreUploadTrimmerView.
//

import Foundation
import AVFoundation
import os

private let trimExportLog = Logger(subsystem: "com.playerpath.app", category: "VideoTrimExporter")

// AVAssetExportSession isn't Sendable, but `cancelExport()` is documented as
// thread-safe. Wrap it so the Task cancellation handler closure compiles
// cleanly under strict concurrency.
private final class SessionBox: @unchecked Sendable {
    nonisolated(unsafe) let session: AVAssetExportSession
    init(_ session: AVAssetExportSession) { self.session = session }
    nonisolated func cancel() { session.cancelExport() }
}

enum VideoTrimExporter {
    enum ExportError: LocalizedError {
        case sessionCreationFailed
        case exportFailed(String)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .sessionCreationFailed: return "Export session could not be created."
            case .exportFailed(let message): return message
            case .cancelled: return "Export was cancelled"
            }
        }
    }

    /// Trims a video file to the `[startTime, endTime]` range and writes the
    /// result to a new file in the temporary directory. Returns the output URL
    /// on success; throws `ExportError` on failure (caller is responsible for
    /// cleaning up the returned URL when it's no longer needed).
    ///
    /// - Bakes `preferredTransform` into an `AVVideoComposition` only when the
    ///   source track has a non-identity rotation transform (iPhone portrait
    ///   recordings). Identity-transform sources skip composition so
    ///   AVFoundation can preserve slow-motion time mappings.
    /// - Uses the source track's `nominalFrameRate` for the composition's
    ///   `frameDuration`, so 60fps and slow-motion (120/240fps) clips export
    ///   at their native rate instead of a hardcoded 30fps.
    static func export(
        sourceURL: URL,
        startTime: Double,
        endTime: Double
    ) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw ExportError.sessionCreationFailed
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("trimmed_\(UUID().uuidString).mp4")

        let start = CMTime(seconds: startTime, preferredTimescale: 600)
        let end = CMTime(seconds: endTime, preferredTimescale: 600)
        session.timeRange = CMTimeRangeFromTimeToTime(start: start, end: end)
        session.outputURL = outputURL
        session.outputFileType = .mp4

        // Bake the preferredTransform into the export when the video needs rotation
        // (e.g. iPhone portrait recordings stored with a 90° transform).
        // For already-correct-orientation videos (identity transform) we skip the
        // composition entirely so AVFoundation can preserve slow-motion time mappings
        // and other track-level metadata automatically.
        if let videoTrack = try? await asset.loadTracks(withMediaType: .video).first {
            var transform: CGAffineTransform?
            var naturalSize: CGSize?
            var nominalFrameRate: Float?
            var assetDuration: CMTime?
            do {
                transform = try await videoTrack.load(.preferredTransform)
                naturalSize = try await videoTrack.load(.naturalSize)
                nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
                assetDuration = try await asset.load(.duration)
            } catch {
                trimExportLog.warning("Failed to load video track properties for export: \(error.localizedDescription)")
            }

            if let transform, let naturalSize, let assetDuration {
                // Apply a video composition whenever the track has a non-identity
                // preferredTransform. The prior check (b != 0 || c != 0) only caught
                // pure rotation and silently dropped mirror/flip/scale transforms
                // (e.g. front-camera mirrored captures and some Photos imports).
                let needsComposition = !transform.isIdentity
                if needsComposition {
                    let size = naturalSize.applying(transform)
                    let renderSize = CGSize(width: abs(size.width), height: abs(size.height))
                    // Use the source track's actual frame rate instead of hardcoding 30 fps,
                    // so 60fps and slow-motion (120/240fps) videos export at their native rate.
                    let fps = Int32((nominalFrameRate ?? 30).rounded())
                    let frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(fps, 1)))
                    let timeRange = CMTimeRangeMake(start: .zero, duration: assetDuration)

                    if #available(iOS 26.0, *) {
                        var layerConfig = AVVideoCompositionLayerInstruction.Configuration(assetTrack: videoTrack)
                        layerConfig.setTransform(transform, at: .zero)
                        let layerInstruction = AVVideoCompositionLayerInstruction(configuration: layerConfig)
                        let instructionConfig = AVVideoCompositionInstruction.Configuration(
                            layerInstructions: [layerInstruction],
                            timeRange: timeRange
                        )
                        let instruction = AVVideoCompositionInstruction(configuration: instructionConfig)
                        let compConfig = AVVideoComposition.Configuration(
                            frameDuration: frameDuration,
                            instructions: [instruction],
                            renderSize: renderSize
                        )
                        session.videoComposition = AVVideoComposition(configuration: compConfig)
                    } else {
                        let composition = AVMutableVideoComposition()
                        composition.renderSize = renderSize
                        composition.frameDuration = frameDuration
                        let instruction = AVMutableVideoCompositionInstruction()
                        instruction.timeRange = timeRange
                        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
                        layerInstruction.setTransform(transform, at: .zero)
                        instruction.layerInstructions = [layerInstruction]
                        composition.instructions = [instruction]
                        session.videoComposition = composition
                    }
                }
            }
        }

        // Honor task cancellation: if the caller's Task is cancelled mid-export
        // (e.g. user backs out of the trim sheet), tell the session to stop so
        // CPU/battery don't keep churning until the export finishes on its own.
        let box = SessionBox(session)
        return try await withTaskCancellationHandler {
            if #available(iOS 18.0, *) {
                do {
                    try await session.export(to: outputURL, as: .mp4)
                    return outputURL
                } catch {
                    try? FileManager.default.removeItem(at: outputURL)
                    if Task.isCancelled {
                        throw ExportError.cancelled
                    }
                    throw ExportError.exportFailed(error.localizedDescription)
                }
            } else {
                await session.export()
                switch session.status {
                case .completed:
                    return outputURL
                case .cancelled:
                    try? FileManager.default.removeItem(at: outputURL)
                    throw ExportError.cancelled
                default:
                    try? FileManager.default.removeItem(at: outputURL)
                    throw ExportError.exportFailed(session.error?.localizedDescription ?? "Export failed")
                }
            }
        } onCancel: {
            box.cancel()
        }
    }
}
