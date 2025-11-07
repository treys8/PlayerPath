//
//  VideoThumbnailGenerator.swift
//  PlayerPath
//
//  Created by Assistant on 10/27/25.
//

import AVFoundation
import UIKit
import CoreImage

class VideoThumbnailGenerator {
    static let shared = VideoThumbnailGenerator()
    
    private init() {}
    
    /// Generate a thumbnail image from a video URL
    /// - Parameters:
    ///   - videoURL: The URL of the video file
    ///   - time: The time in the video to capture (defaults to 1 second)
    ///   - size: The desired thumbnail size (defaults to 160x120)
    /// - Returns: The thumbnail image path or nil if generation failed
    func generateThumbnail(from videoURL: URL, at time: CMTime = CMTime(seconds: 1, preferredTimescale: 1), size: CGSize = CGSize(width: 160, height: 120)) async -> String? {
        
        print("VideoThumbnailGenerator: Generating thumbnail for video: \(videoURL)")
        
        do {
            let asset = AVURLAsset(url: videoURL)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            imageGenerator.maximumSize = size
            
            // Try to get a thumbnail at the specified time, or fallback to a safe time
            var thumbnailTime = time
            let duration = try await asset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(duration)
            
            // If the requested time is beyond the video duration, use 10% of duration or 0.5 seconds
            if CMTimeGetSeconds(time) >= durationSeconds {
                let fallbackSeconds = min(durationSeconds * 0.1, 0.5)
                thumbnailTime = CMTime(seconds: fallbackSeconds, preferredTimescale: 1)
            }
            
            print("VideoThumbnailGenerator: Using time: \(CMTimeGetSeconds(thumbnailTime)) seconds")
            
            let cgImage = try imageGenerator.copyCGImage(at: thumbnailTime, actualTime: nil)
            let image = UIImage(cgImage: cgImage)
            
            // Save thumbnail to documents directory
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let thumbnailFileName = "thumb_\(UUID().uuidString).jpg"
            let thumbnailURL = documentsPath.appendingPathComponent(thumbnailFileName)
            
            guard let imageData = image.jpegData(compressionQuality: 0.8) else {
                print("VideoThumbnailGenerator: Failed to create JPEG data")
                return nil
            }
            
            try imageData.write(to: thumbnailURL)
            print("VideoThumbnailGenerator: Successfully saved thumbnail to: \(thumbnailURL.path)")
            
            return thumbnailURL.path
            
        } catch {
            print("VideoThumbnailGenerator: Error generating thumbnail: \(error)")
            return nil
        }
    }
    
    /// Load thumbnail image from path
    /// - Parameter path: The file path to the thumbnail image
    /// - Returns: UIImage or nil if loading failed
    func loadThumbnail(from path: String) -> UIImage? {
        guard FileManager.default.fileExists(atPath: path) else {
            print("VideoThumbnailGenerator: Thumbnail file not found at path: \(path)")
            return nil
        }
        
        return UIImage(contentsOfFile: path)
    }
    
    /// Delete thumbnail file
    /// - Parameter path: The file path to the thumbnail image
    func deleteThumbnail(at path: String) {
        try? FileManager.default.removeItem(atPath: path)
        print("VideoThumbnailGenerator: Deleted thumbnail at path: \(path)")
    }
    
    /// Generate thumbnail from video file path
    /// - Parameter filePath: The file path of the video
    /// - Returns: The thumbnail image path or nil if generation failed
    func generateThumbnail(from filePath: String) async -> String? {
        let videoURL = URL(fileURLWithPath: filePath)
        return await generateThumbnail(from: videoURL)
    }
}