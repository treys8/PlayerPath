//
//  CoachVideoProcessingService.swift
//  PlayerPath
//
//  Post-recording processing for coach videos: extracts duration
//  and generates/uploads thumbnails. Reuses VideoFileManager for
//  AVAsset thumbnail generation and VideoCloudManager for Storage uploads.
//

import Foundation
import AVFoundation
import os

private let processingLog = Logger(subsystem: "com.playerpath.app", category: "CoachVideoProcessing")

@MainActor
final class CoachVideoProcessingService {
    static let shared = CoachVideoProcessingService()

    struct ProcessedVideo {
        let duration: Double
        let thumbnailURL: String?
    }

    /// Processes a recorded video: extracts duration and generates/uploads a thumbnail.
    /// Never throws — thumbnail failure is non-fatal; duration defaults to 0.
    func process(videoURL: URL, fileName: String, folderID: String) async -> ProcessedVideo {
        // 1. Extract duration
        let duration = await extractDuration(from: videoURL)

        // 2. Generate thumbnail locally
        let localThumbPath = await generateThumbnail(from: videoURL)

        // 3. Upload thumbnail to Storage
        var thumbnailDownloadURL: String?
        if let thumbPath = localThumbPath {
            thumbnailDownloadURL = await uploadThumbnail(
                localPath: thumbPath,
                videoFileName: fileName,
                folderID: folderID
            )
            // Clean up local thumbnail file
            try? FileManager.default.removeItem(atPath: thumbPath)
        }

        processingLog.info("Processed video \(fileName): duration=\(duration)s, thumbnail=\(thumbnailDownloadURL != nil ? "yes" : "no")")
        return ProcessedVideo(duration: duration, thumbnailURL: thumbnailDownloadURL)
    }

    // MARK: - Private

    private func extractDuration(from videoURL: URL) async -> Double {
        do {
            let asset = AVURLAsset(url: videoURL)
            let duration = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(duration)
            return seconds.isFinite ? seconds : 0
        } catch {
            processingLog.warning("Failed to extract duration: \(error.localizedDescription)")
            return 0
        }
    }

    private func generateThumbnail(from videoURL: URL) async -> String? {
        let result = await VideoFileManager.generateThumbnail(from: videoURL)
        switch result {
        case .success(let path):
            return path
        case .failure(let error):
            processingLog.warning("Failed to generate thumbnail: \(error.localizedDescription)")
            return nil
        }
    }

    private func uploadThumbnail(localPath: String, videoFileName: String, folderID: String) async -> String? {
        let localURL = URL(fileURLWithPath: localPath)
        do {
            let downloadURL = try await VideoCloudManager.shared.uploadThumbnail(
                thumbnailURL: localURL,
                videoFileName: videoFileName,
                folderID: folderID
            )
            return downloadURL
        } catch {
            processingLog.warning("Failed to upload thumbnail: \(error.localizedDescription)")
            return nil
        }
    }
}
