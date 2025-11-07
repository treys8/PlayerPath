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

class VideoFileManager {
    
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
    
    // MARK: - Constants
    private struct Constants {
        static let maxFileSizeBytes: Int64 = 500 * 1024 * 1024 // 500MB
        static let minFileSizeBytes: Int64 = 1024 // 1KB
        static let maxDurationSeconds: TimeInterval = 600 // 10 minutes
        static let minDurationSeconds: TimeInterval = 1 // 1 second
        static let thumbnailSize = CGSize(width: 160, height: 120)
    }
    
    // MARK: - File Operations
    
    static func createPermanentVideoURL() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsPath.appendingPathComponent("\(UUID().uuidString).mov")
    }
    
    static func createThumbnailURL() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsPath.appendingPathComponent("thumb_\(UUID().uuidString).jpg")
    }
    
    static func copyToDocuments(from sourceURL: URL) throws -> URL {
        let destinationURL = createPermanentVideoURL()
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        print("VideoFileManager: Successfully copied video to: \(destinationURL)")
        return destinationURL
    }
    
    static func cleanup(url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
            print("VideoFileManager: Cleaned up file at: \(url)")
        } catch {
            print("VideoFileManager: Failed to cleanup file at \(url): \(error)")
        }
    }
    
    // MARK: - Validation
    
    static func validateVideo(at url: URL) async -> Result<Void, ValidationError> {
        // Basic file existence check
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .failure(.fileNotFound)
        }
        
        // File size validation
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let fileSize = attributes[.size] as? Int64 {
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
        
        // Duration validation
        do {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(duration)
            
            if durationSeconds > Constants.maxDurationSeconds {
                return .failure(.durationTooLong(durationSeconds))
            }
            
            if durationSeconds < Constants.minDurationSeconds {
                return .failure(.durationTooShort(durationSeconds))
            }
            
            print("VideoFileManager: Video validation successful - Duration: \(String(format: "%.1f", durationSeconds))s")
            return .success(())
            
        } catch {
            print("VideoFileManager: Failed to validate video duration: \(error)")
            return .failure(.invalidFormat)
        }
    }
    
    // MARK: - Thumbnail Generation
    
    static func generateThumbnail(
        from videoURL: URL,
        at time: CMTime = CMTime(seconds: 1, preferredTimescale: 1),
        size: CGSize = Constants.thumbnailSize
    ) async -> Result<String, Error> {
        
        print("VideoFileManager: Generating thumbnail for video: \(videoURL)")
        
        do {
            let asset = AVURLAsset(url: videoURL)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            imageGenerator.maximumSize = size
            
            // Calculate safe thumbnail time
            let thumbnailTime = try await calculateSafeThumbnailTime(for: asset, requestedTime: time)
            print("VideoFileManager: Using thumbnail time: \(CMTimeGetSeconds(thumbnailTime)) seconds")
            
            // Generate thumbnail image
            let cgImage: CGImage
            if #available(iOS 18.0, *) {
                cgImage = try await imageGenerator.image(at: thumbnailTime).image
            } else {
                cgImage = try imageGenerator.copyCGImage(at: thumbnailTime, actualTime: nil)
            }
            
            let image = UIImage(cgImage: cgImage)
            
            // Save to documents directory
            let thumbnailURL = createThumbnailURL()
            guard let imageData = image.jpegData(compressionQuality: 0.8) else {
                throw NSError(domain: "VideoFileManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create JPEG data"])
            }
            
            try imageData.write(to: thumbnailURL)
            print("VideoFileManager: Successfully saved thumbnail to: \(thumbnailURL.path)")
            
            return .success(thumbnailURL.path)
            
        } catch {
            print("VideoFileManager: Error generating thumbnail: \(error)")
            return .failure(error)
        }
    }
    
    private static func calculateSafeThumbnailTime(for asset: AVURLAsset, requestedTime: CMTime) async throws -> CMTime {
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        let requestedSeconds = CMTimeGetSeconds(requestedTime)
        
        // If the requested time is beyond the video duration, use 10% of duration or 0.5 seconds, whichever is smaller
        if requestedSeconds >= durationSeconds {
            let fallbackSeconds = min(durationSeconds * 0.1, 0.5)
            return CMTime(seconds: fallbackSeconds, preferredTimescale: 1)
        }
        
        return requestedTime
    }
}