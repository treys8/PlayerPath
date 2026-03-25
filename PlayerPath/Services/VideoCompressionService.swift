//
//  VideoCompressionService.swift
//  PlayerPath
//
//  Compresses videos before upload to reduce bandwidth and storage costs.
//

import AVFoundation
import os

private let compressionLog = Logger(subsystem: "com.playerpath.app", category: "Compression")

final class VideoCompressionService {
    static let shared = VideoCompressionService()
    private init() {}

    /// Compresses the video at `sourceURL` in-place, replacing the original file.
    /// If compression fails or produces a larger file, the original is kept unchanged.
    func compressForUpload(at sourceURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality) else {
            compressionLog.warning("Could not create export session — uploading original")
            return sourceURL
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        session.outputURL = tempURL
        session.outputFileType = .mov
        session.shouldOptimizeForNetworkUse = true

        let originalSize = fileSize(at: sourceURL)
        compressionLog.info("Compressing video: \(self.formatBytes(originalSize)) at \(sourceURL.lastPathComponent)")

        await session.export()

        guard session.status == .completed else {
            compressionLog.error("Compression failed: \(session.error?.localizedDescription ?? "unknown")")
            try? FileManager.default.removeItem(at: tempURL)
            return sourceURL
        }

        let compressedSize = fileSize(at: tempURL)

        // Only use compressed version if it's actually smaller
        guard compressedSize < originalSize else {
            compressionLog.info("Compressed file not smaller (\(self.formatBytes(compressedSize)) vs \(self.formatBytes(originalSize))) — keeping original")
            try? FileManager.default.removeItem(at: tempURL)
            return sourceURL
        }

        // Replace original with compressed version
        do {
            try FileManager.default.removeItem(at: sourceURL)
            try FileManager.default.moveItem(at: tempURL, to: sourceURL)
            let savings = Int((1.0 - Double(compressedSize) / Double(originalSize)) * 100)
            compressionLog.info("Compressed: \(self.formatBytes(originalSize)) → \(self.formatBytes(compressedSize)) (\(savings)% smaller)")
        } catch {
            compressionLog.error("Failed to replace original with compressed file: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: tempURL)
        }

        return sourceURL
    }

    private func fileSize(at url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_048_576.0
        return String(format: "%.1f MB", mb)
    }
}
