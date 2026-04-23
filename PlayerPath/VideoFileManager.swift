//
//  VideoFileManager.swift
//  PlayerPath
//
//  Created by Assistant on 10/27/25.
//

import Foundation
import AVFoundation
import CoreMedia
import UIKit
import os

class VideoFileManager {
    
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "RZR.DT3", category: "VideoFileManager")
    
    enum ValidationError: LocalizedError {
        case fileNotFound
        case fileTooLarge(Int64)
        case fileTooSmall
        case durationTooLong(TimeInterval)
        case durationTooShort(TimeInterval)
        case invalidFormat
        case corruptedFile
        case cancelled

        var errorDescription: String? {
            switch self {
            case .fileNotFound:
                return "Video file not found."
            case .fileTooLarge(let size):
                return "Video file is too large (\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))). Please select a video under 500MB."
            case .fileTooSmall:
                return "Video file appears to be invalid or corrupted."
            case .durationTooLong(let duration):
                return "Video is too long (\(Int(duration/60)) minutes). Please select a video under 10 minutes."
            case .durationTooShort(let duration):
                return "Video is too short (\(String(format: "%.1f", duration)) seconds). Please select a video at least 1 second long."
            case .invalidFormat:
                return "Video format is not supported."
            case .corruptedFile:
                return "Video file appears to be corrupted."
            case .cancelled:
                return "Video validation was cancelled."
            }
        }
    }
    
    enum FileManagerError: LocalizedError {
        case documentsDirectoryNotFound
        case fileAlreadyExists
        case copyFailed(Error)
        case deleteFailed(Error)
        
        var errorDescription: String? {
            switch self {
            case .documentsDirectoryNotFound:
                return "Could not access app documents directory."
            case .fileAlreadyExists:
                return "A file with this name already exists."
            case .copyFailed(let error):
                return "Failed to copy file: \(error.localizedDescription)"
            case .deleteFailed(let error):
                return "Failed to delete file: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Constants
    private enum Constants {
        static let maxFileSizeBytes: Int64 = StorageConstants.maxVideoFileSizeBytes
        static let minFileSizeBytes: Int64 = 1024 // 1KB
        static let maxDurationSeconds: TimeInterval = 600 // 10 minutes
        static let minDurationSeconds: TimeInterval = 1 // 1 second
        /// Cloud thumbnails generated at 3x base size (480x270) so they look crisp on all
        /// Retina displays. Matches the effective quality of athlete local thumbnails, which
        /// are stored at full resolution and downsampled at display time by ThumbnailCache.
        static let thumbnailSize: CGSize = CGSize(width: 480, height: 270)
        static let thumbnailCompressionQuality: CGFloat = 0.8
    }
    
    private static func documentsDirectory() throws -> URL {
        guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            logger.error("Documents directory not found")
            throw FileManagerError.documentsDirectoryNotFound
        }
        return url
    }
    
    // MARK: - File Operations
    
    static func createPermanentVideoURL(extension ext: String = "mov") throws -> URL {
        let documentsPath = try documentsDirectory()
        let clipsDir = documentsPath.appendingPathComponent("Clips", isDirectory: true)
        try FileManager.default.createDirectory(at: clipsDir, withIntermediateDirectories: true)
        return clipsDir.appendingPathComponent("\(UUID().uuidString).\(ext)")
    }
    
    static func createThumbnailURL() throws -> URL {
        let documentsPath = try documentsDirectory()
        let thumbnailsDir = documentsPath.appendingPathComponent("Thumbnails", isDirectory: true)
        try FileManager.default.createDirectory(at: thumbnailsDir, withIntermediateDirectories: true)
        return thumbnailsDir.appendingPathComponent("thumb_\(UUID().uuidString).jpg")
    }
    
    static func cleanup(url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            logger.error("Failed to cleanup file at \(url.path, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }
    
    // MARK: - Validation
    
    static func validateVideo(at url: URL) async -> Result<Void, ValidationError> {
        guard !Task.isCancelled else { return .failure(.cancelled) }

        // File size check — treat read errors as non-fatal and skip size gate
        if let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init) {
            if fileSize > Constants.maxFileSizeBytes {
                return .failure(.fileTooLarge(fileSize))
            }
            // Very small files are invalid; skip if fileSize is unavailable
            if fileSize < Constants.minFileSizeBytes {
                return .failure(.fileTooSmall)
            }
        } else {
            // Fallback: check existence via FileManager (handles iCloud symlinks, etc.)
            guard FileManager.default.fileExists(atPath: url.path) else {
                return .failure(.fileNotFound)
            }
        }

        // Duration + playability
        return await validatePlayability(at: url)
    }
    
    private static func validatePlayability(at url: URL) async -> Result<Void, ValidationError> {
        let asset = AVURLAsset(url: url)
        
        do {
            let (duration, isPlayable) = try await asset.load(.duration, .isPlayable)
            guard isPlayable else { return .failure(.invalidFormat) }

            let durationSeconds = CMTimeGetSeconds(duration)
            if durationSeconds > Constants.maxDurationSeconds {
                return .failure(.durationTooLong(durationSeconds))
            }
            if durationSeconds < Constants.minDurationSeconds {
                return .failure(.durationTooShort(durationSeconds))
            }

            let durationText = String(format: "%.1f", durationSeconds)
            logger.info("Video validation successful - Duration: \(durationText, privacy: .public)s")
            return .success(())

        } catch is CancellationError {
            logger.info("Video validation cancelled")
            return .failure(.cancelled)
        } catch {
            logger.error("Failed to validate video: \(String(describing: error), privacy: .public)")
            return .failure(.invalidFormat)
        }
    }
    
    // MARK: - Thumbnail Generation
    
    /// Generates a thumbnail image, preserving aspect ratio by default, and saves it to the app's documents directory.
    static func generateThumbnail(
        from videoURL: URL,
        at time: CMTime = CMTime(seconds: 1, preferredTimescale: 1),
        size: CGSize? = nil
    ) async -> Result<String, Error> {
        
        // Check for cancellation early
        guard !Task.isCancelled else {
            logger.info("Thumbnail generation cancelled")
            return .failure(CancellationError())
        }
        
        logger.info("Generating thumbnail for video: \(videoURL.path, privacy: .public)")

        do {
            let asset = AVURLAsset(url: videoURL)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true

            // Ensure thumbnail size is valid (prevent zero-dimension errors)
            let requestedSize = size ?? Constants.thumbnailSize
            let safeSize = CGSize(
                width: max(requestedSize.width, 1),
                height: max(requestedSize.height, 1)
            )
            imageGenerator.maximumSize = safeSize
            
            // Check for cancellation before expensive operation
            guard !Task.isCancelled else {
                logger.info("Thumbnail generation cancelled before image generation")
                return .failure(CancellationError())
            }
            
            // Calculate safe thumbnail time
            let thumbnailTime = try await calculateSafeThumbnailTime(for: asset, requestedTime: time)
            logger.info("Using thumbnail time: \(String(format: "%.3f", CMTimeGetSeconds(thumbnailTime)), privacy: .public) seconds")
            
            // Check for cancellation again
            guard !Task.isCancelled else {
                logger.info("Thumbnail generation cancelled before CGImage generation")
                return .failure(CancellationError())
            }
            
            // Generate thumbnail image
            let cgImage: CGImage
            if #available(iOS 18.0, *) {
                cgImage = try await imageGenerator.image(at: thumbnailTime).image
            } else {
                // copyCGImage is synchronous — run off main thread to avoid blocking UI
                let gen = imageGenerator
                let time = thumbnailTime
                cgImage = try await Task.detached(priority: .userInitiated) {
                    try gen.copyCGImage(at: time, actualTime: nil)
                }.value
            }
            
            // The image generator's `maximumSize` already bounds the output while
            // preserving native aspect. Keep the native-aspect UIImage so the grid's
            // `.aspectRatio(.fill) + .clipped()` renders consistently across recorded
            // and imported clips (no letterbox bars on portrait content).
            let image = UIImage(cgImage: cgImage)

            // Check for cancellation before saving
            guard !Task.isCancelled else {
                logger.info("Thumbnail generation cancelled before saving")
                return .failure(CancellationError())
            }

            // Save to documents directory
            let thumbnailURL = try createThumbnailURL()
            guard let imageData = image.jpegData(compressionQuality: Constants.thumbnailCompressionQuality) else {
                throw NSError(domain: "VideoFileManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create JPEG data"])
            }

            try imageData.write(to: thumbnailURL)
            logger.info("Successfully saved thumbnail to: \(thumbnailURL.path, privacy: .public)")

            // Return a path relative to Documents so callers that persist the result
            // on a VideoClip survive sandbox relocation on update/reinstall.
            // Absolute-path consumers (cloud upload) resolve via ThumbnailCache / VideoClip.resolvedThumbnailPath.
            return .success(VideoClip.toRelativePath(thumbnailURL.path))
            
        } catch is CancellationError {
            logger.info("Thumbnail generation was cancelled")
            return .failure(CancellationError())
        } catch {
            logger.error("Error generating thumbnail: \(String(describing: error), privacy: .public)")
            return .failure(error)
        }
    }
    
    private static func normalizedThumbnail(_ image: UIImage, size: CGSize, preserveAspect: Bool = true) -> UIImage {
        let safeSize = CGSize(width: max(size.width, 1), height: max(size.height, 1))
        let format = UIGraphicsImageRendererFormat.default()
        // Keep this trait-agnostic; a scale of 1 reduces disk size and is fine for small thumbs
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: safeSize, format: format)
        return renderer.image { _ in
            if preserveAspect, image.size.width > 0, image.size.height > 0 {
                let aspect = min(safeSize.width / image.size.width, safeSize.height / image.size.height)
                let drawSize = CGSize(width: image.size.width * aspect, height: image.size.height * aspect)
                let origin = CGPoint(x: (safeSize.width - drawSize.width) / 2, y: (safeSize.height - drawSize.height) / 2)
                image.draw(in: CGRect(origin: origin, size: drawSize))
            } else {
                image.draw(in: CGRect(origin: .zero, size: safeSize))
            }
        }
    }
    
    private static func calculateSafeThumbnailTime(for asset: AVURLAsset, requestedTime: CMTime) async throws -> CMTime {
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        let requestedSeconds = CMTimeGetSeconds(requestedTime)

        let epsilon = 0.01
        let timescale: CMTimeScale = 600
        let safeRequested = max(epsilon, requestedSeconds)

        if safeRequested >= durationSeconds {
            let fallbackSeconds = max(epsilon, min(durationSeconds * 0.1, 0.5))
            return CMTime(seconds: fallbackSeconds, preferredTimescale: timescale)
        }

        return CMTime(seconds: safeRequested, preferredTimescale: timescale)
    }
}

