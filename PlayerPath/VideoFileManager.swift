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
    
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.example.PlayerPath", category: "VideoFileManager")
    
    enum ValidationError: LocalizedError {
        case fileNotFound
        case fileTooLarge(Int64)
        case fileTooSmall
        case durationTooLong(TimeInterval)
        case durationTooShort(TimeInterval)
        case invalidFormat
        case corruptedFile
        
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
        static let maxFileSizeBytes: Int64 = 500 * 1024 * 1024 // 500MB
        static let minFileSizeBytes: Int64 = 1024 // 1KB
        static let maxDurationSeconds: TimeInterval = 600 // 10 minutes
        static let minDurationSeconds: TimeInterval = 1 // 1 second
        static let thumbnailSize = CGSize(width: 160, height: 120)
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
    
    static func createPermanentVideoURL() throws -> URL {
        let documentsPath = try documentsDirectory()
        return documentsPath.appendingPathComponent("\(UUID().uuidString).mov")
    }
    
    static func createThumbnailURL() throws -> URL {
        let documentsPath = try documentsDirectory()
        return documentsPath.appendingPathComponent("thumb_\(UUID().uuidString).jpg")
    }
    
    static func copyToDocuments(from sourceURL: URL) throws -> URL {
        let documents = try documentsDirectory() // Don't fall back to temp!

        // If already in Documents, just return it
        if sourceURL.standardizedFileURL.deletingLastPathComponent() == documents.standardizedFileURL {
            return sourceURL
        }

        var destinationURL = try createPermanentVideoURL()
        var attempts = 0
        let maxAttempts = 10

        // Try to copy, handling file exists error with retry
        while attempts < maxAttempts {
            do {
                // This will throw if file already exists
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                logger.info("Successfully copied video to: \(destinationURL.path, privacy: .public)")
                return destinationURL
            } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError {
                // File exists, try again with new UUID
                logger.warning("File exists at \(destinationURL.path, privacy: .public), retrying with new name")
                destinationURL = try createPermanentVideoURL()
                attempts += 1
            } catch {
                logger.error("Failed to copy video: \(String(describing: error), privacy: .public)")
                throw FileManagerError.copyFailed(error)
            }
        }

        logger.error("Failed to find unique filename after \(maxAttempts) attempts")
        throw FileManagerError.fileAlreadyExists
    }
    
    static func cleanup(url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
            logger.info("Cleaned up file at: \(url.path, privacy: .public)")
        } catch {
            logger.error("Failed to cleanup file at \(url.path, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }
    
    // MARK: - Validation
    
    static func validateVideo(at url: URL) async -> Result<Void, ValidationError> {
        // Check for cancellation early
        guard !Task.isCancelled else {
            logger.info("Video validation cancelled")
            return .failure(.corruptedFile)
        }
        
        // Basic file existence and size via URL resource values
        do {
            let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
            let values = try url.resourceValues(forKeys: keys)
            guard values.isRegularFile == true else {
                return .failure(.fileNotFound)
            }
            if let fileSize = values.fileSize.map(Int64.init) {
                if fileSize > Constants.maxFileSizeBytes {
                    return .failure(.fileTooLarge(fileSize))
                }
                if fileSize < Constants.minFileSizeBytes {
                    return .failure(.fileTooSmall)
                }
            }
        } catch {
            return .failure(.corruptedFile)
        }

        // Check for cancellation before expensive operation
        guard !Task.isCancelled else {
            logger.info("Video validation cancelled before playability check")
            return .failure(.corruptedFile)
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
            imageGenerator.maximumSize = size ?? Constants.thumbnailSize
            
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
                cgImage = try imageGenerator.copyCGImage(at: thumbnailTime, actualTime: nil)
            }
            
            let baseImage = UIImage(cgImage: cgImage)
            let finalSize = size ?? Constants.thumbnailSize
            let image = normalizedThumbnail(baseImage, size: finalSize)

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

            return .success(thumbnailURL.path)
            
        } catch is CancellationError {
            logger.info("Thumbnail generation was cancelled")
            return .failure(CancellationError())
        } catch {
            logger.error("Error generating thumbnail: \(String(describing: error), privacy: .public)")
            return .failure(error)
        }
    }
    
    private static func normalizedThumbnail(_ image: UIImage, size: CGSize, preserveAspect: Bool = true) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        // Keep this trait-agnostic; a scale of 1 reduces disk size and is fine for small thumbs
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            if preserveAspect {
                let aspect = min(size.width / image.size.width, size.height / image.size.height)
                let drawSize = CGSize(width: image.size.width * aspect, height: image.size.height * aspect)
                let origin = CGPoint(x: (size.width - drawSize.width) / 2, y: (size.height - drawSize.height) / 2)
                image.draw(in: CGRect(origin: origin, size: drawSize))
            } else {
                image.draw(in: CGRect(origin: .zero, size: size))
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

