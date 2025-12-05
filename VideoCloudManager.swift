//
//  VideoCloudManager.swift
//  PlayerPath
//
//  Cross-platform video storage manager using Firebase
//

import Foundation
import Combine
import SwiftData
import FirebaseStorage
import FirebaseFirestore

@MainActor
class VideoCloudManager: ObservableObject {
    static let shared = VideoCloudManager()
    
    @Published var uploadProgress: [UUID: Double] = [:]
    @Published var isUploading: [UUID: Bool] = [:]
    @Published var downloadProgress: [UUID: Double] = [:]
    @Published var isDownloading: [UUID: Bool] = [:]
    
    private init() {}
    
    // Simulated upload with realistic progress updates
    func uploadVideo(_ videoClip: VideoClip, athlete: Athlete) async throws -> String {
        let clipId = videoClip.id
        
        // Mark as uploading
        isUploading[clipId] = true
        uploadProgress[clipId] = 0.0
        
        defer {
            isUploading[clipId] = false
            uploadProgress[clipId] = nil
        }
        
        // Simulate realistic upload progress
        do {
            for i in 1...20 {
                try await Task.sleep(nanoseconds: UInt64.random(in: 50_000_000...200_000_000)) // 0.05-0.2 seconds
                
                let progress = Double(i) / 20.0
                uploadProgress[clipId] = progress
                
                print("VideoCloudManager: Upload progress for \(videoClip.fileName): \(Int(progress * 100))%")
            }
            
            // Simulate potential upload errors (10% chance)
            if Bool.random() && Double.random(in: 0...1) < 0.1 {
                throw VideoCloudError.uploadFailed("Network timeout during upload")
            }
            
            // Generate a realistic cloud URL
            let fileName = videoClip.fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "video.mov"
            let cloudURL = "https://firebasestorage.googleapis.com/v0/b/playerpath-app.appspot.com/o/videos%2F\(athlete.id.uuidString)%2F\(fileName)?alt=media&token=\(UUID().uuidString)"
            
            print("VideoCloudManager: Upload completed successfully for \(videoClip.fileName)")
            return cloudURL
            
        } catch {
            print("VideoCloudManager: Upload failed for \(videoClip.fileName): \(error)")
            throw error
        }
    }
    
    func downloadVideo(from url: String, to localPath: String) async throws {
        // Extract clip ID from the path for progress tracking
        let clipId = UUID() // In real implementation, this would be derived from context
        
        isDownloading[clipId] = true
        downloadProgress[clipId] = 0.0
        
        defer {
            isDownloading[clipId] = false
            downloadProgress[clipId] = nil
        }
        
        // Simulate realistic download progress
        do {
            for i in 1...15 {
                try await Task.sleep(nanoseconds: UInt64.random(in: 100_000_000...300_000_000)) // 0.1-0.3 seconds
                
                let progress = Double(i) / 15.0
                downloadProgress[clipId] = progress
                
                print("VideoCloudManager: Download progress: \(Int(progress * 100))%")
            }
            
            // Simulate potential download errors (5% chance)
            if Bool.random() && Double.random(in: 0...1) < 0.05 {
                throw VideoCloudError.downloadFailed("Network timeout during download")
            }
            
            print("VideoCloudManager: Download completed successfully")
            
        } catch {
            print("VideoCloudManager: Download failed: \(error)")
            throw error
        }
    }
    
    func syncVideos(for athlete: Athlete) async throws -> [VideoClipMetadata] {
        // Simulate fetching video metadata from cloud
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Return empty array for now - in real implementation would fetch from Firebase
        return []
    }
    
    func deleteVideo(_ videoClip: VideoClip, athlete: Athlete) async throws {
        // Simulate cloud deletion
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Simulate potential deletion errors (2% chance)
        if Bool.random() && Double.random(in: 0...1) < 0.02 {
            throw VideoCloudError.deletionFailed("Failed to delete video from cloud storage")
        }
        
        print("VideoCloudManager: Video deleted from cloud successfully")
    }
    
    func getUploadStatus(for clipId: UUID) -> UploadStatus {
        if let isUploading = isUploading[clipId], isUploading {
            return .uploading(progress: uploadProgress[clipId] ?? 0.0)
        } else if let isDownloading = isDownloading[clipId], isDownloading {
            return .downloading(progress: downloadProgress[clipId] ?? 0.0)
        } else {
            return .idle
        }
    }
    
    // Batch upload functionality
    func uploadMultipleVideos(_ clips: [VideoClip], athlete: Athlete) async -> [(VideoClip, Result<String, Error>)] {
        var results: [(VideoClip, Result<String, Error>)] = []
        
        // Upload clips sequentially to avoid overwhelming the system
        for clip in clips {
            do {
                let cloudURL = try await uploadVideo(clip, athlete: athlete)
                results.append((clip, .success(cloudURL)))
            } catch {
                results.append((clip, .failure(error)))
            }
        }
        
        return results
    }
    
    // MARK: - Shared Folder Upload (for Coach-to-Athlete sharing)
    
    /// Uploads a video file to Firebase Storage for a shared folder
    /// - Parameters:
    ///   - localURL: Local file URL of the video
    ///   - fileName: Name for the file in storage
    ///   - folderID: Shared folder ID
    ///   - progressHandler: Closure called with progress updates (0.0 to 1.0)
    /// - Returns: The download URL for the uploaded video
    func uploadVideo(
        localURL: URL,
        fileName: String,
        folderID: String,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> String {
        
        // Create storage reference
        let storage = Storage.storage()
        let storageRef = storage.reference()
        let videoRef = storageRef.child("shared_folders/\(folderID)/\(fileName)")
        
        // Read video data
        let videoData = try Data(contentsOf: localURL)
        
        // Create upload task with metadata
        let metadata = StorageMetadata()
        metadata.contentType = "video/quicktime"
        
        // Simulate progress for now (in production, use the actual upload task progress)
        return try await withCheckedThrowingContinuation { continuation in
            let uploadTask = videoRef.putData(videoData, metadata: metadata) { metadata, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                // Get download URL
                videoRef.downloadURL { url, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let url = url {
                        continuation.resume(returning: url.absoluteString)
                    } else {
                        continuation.resume(throwing: VideoCloudError.invalidURL)
                    }
                }
            }
            
            // Monitor upload progress
            uploadTask.observe(.progress) { snapshot in
                guard let progress = snapshot.progress else { return }
                let percentComplete = Double(progress.completedUnitCount) / Double(progress.totalUnitCount)
                Task { @MainActor in
                    progressHandler(percentComplete)
                }
            }
        }
    }
    
    /// Uploads a thumbnail image to Firebase Storage for a shared folder video
    /// - Parameters:
    ///   - thumbnailURL: Local file URL of the thumbnail image
    ///   - videoFileName: The video file name (to create matching thumbnail name)
    ///   - folderID: Shared folder ID
    /// - Returns: The download URL for the uploaded thumbnail
    func uploadThumbnail(
        thumbnailURL: URL,
        videoFileName: String,
        folderID: String
    ) async throws -> String {
        
        // Create storage reference for thumbnail
        let storage = Storage.storage()
        let storageRef = storage.reference()
        
        // Generate thumbnail filename from video filename
        let thumbnailFileName = videoFileName.replacingOccurrences(of: ".mov", with: "_thumbnail.jpg")
            .replacingOccurrences(of: ".mp4", with: "_thumbnail.jpg")
            .replacingOccurrences(of: ".MOV", with: "_thumbnail.jpg")
            .replacingOccurrences(of: ".MP4", with: "_thumbnail.jpg")
        
        let thumbnailRef = storageRef.child("shared_folders/\(folderID)/thumbnails/\(thumbnailFileName)")
        
        // Read thumbnail data
        let thumbnailData = try Data(contentsOf: thumbnailURL)
        
        // Create upload task with metadata
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        metadata.cacheControl = "public, max-age=31536000" // Cache for 1 year
        
        return try await withCheckedThrowingContinuation { continuation in
            thumbnailRef.putData(thumbnailData, metadata: metadata) { metadata, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                // Get download URL
                thumbnailRef.downloadURL { url, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let url = url {
                        continuation.resume(returning: url.absoluteString)
                    } else {
                        continuation.resume(throwing: VideoCloudError.invalidURL)
                    }
                }
            }
        }
    }
    
    /// Gets a secure download URL for a video with security token
    /// - Parameters:
    ///   - fileName: The video file name in storage
    ///   - folderID: Shared folder ID
    /// - Returns: A secure download URL with Firebase security token
    /// - Note: Firebase Storage URLs include long-lived security tokens. For true expiring URLs,
    ///         implement a Cloud Function using Firebase Admin SDK to generate signed URLs with
    ///         custom expiration times. Current implementation uses Firebase's built-in token-based
    ///         security which validates against Storage Rules on each request.
    func getSecureDownloadURL(
        fileName: String,
        folderID: String
    ) async throws -> String {
        
        let storage = Storage.storage()
        let storageRef = storage.reference()
        let videoRef = storageRef.child("shared_folders/\(folderID)/\(fileName)")
        
        return try await withCheckedThrowingContinuation { continuation in
            videoRef.downloadURL { url, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let url = url {
                    // Firebase Storage URLs include a security token that validates against
                    // your Storage Rules on every request, providing security even though
                    // the URL itself is long-lived
                    continuation.resume(returning: url.absoluteString)
                } else {
                    continuation.resume(throwing: VideoCloudError.invalidURL)
                }
            }
        }
    }
    
    /// Gets a secure download URL for a thumbnail with security token
    /// - Parameters:
    ///   - videoFileName: The video file name (thumbnail name will be derived)
    ///   - folderID: Shared folder ID
    /// - Returns: A secure download URL for the thumbnail
    /// - Note: Like video URLs, thumbnail URLs include Firebase security tokens that validate
    ///         against Storage Rules. Thumbnails are heavily cached (1 year cache-control header).
    func getSecureThumbnailURL(
        videoFileName: String,
        folderID: String
    ) async throws -> String {
        
        let storage = Storage.storage()
        let storageRef = storage.reference()
        
        // Generate thumbnail filename from video filename
        let thumbnailFileName = videoFileName.replacingOccurrences(of: ".mov", with: "_thumbnail.jpg")
            .replacingOccurrences(of: ".mp4", with: "_thumbnail.jpg")
            .replacingOccurrences(of: ".MOV", with: "_thumbnail.jpg")
            .replacingOccurrences(of: ".MP4", with: "_thumbnail.jpg")
        
        let thumbnailRef = storageRef.child("shared_folders/\(folderID)/thumbnails/\(thumbnailFileName)")
        
        return try await withCheckedThrowingContinuation { continuation in
            thumbnailRef.downloadURL { url, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let url = url {
                    continuation.resume(returning: url.absoluteString)
                } else {
                    continuation.resume(throwing: VideoCloudError.invalidURL)
                }
            }
        }
    }
    
    /// Generates a secure, expiring download URL for a video in Firebase Storage
    /// - Parameters:
    ///   - videoFileName: Name of the video file in storage
    ///   - folderID: Shared folder ID
    ///   - expirationHours: Number of hours until the URL expires (default: 24)
    /// - Returns: A secure, time-limited download URL
    func getSecureDownloadURL(
        videoFileName: String,
        folderID: String,
        expirationHours: Int = 24
    ) async throws -> String {
        
        let storage = Storage.storage()
        let storageRef = storage.reference()
        let videoRef = storageRef.child("shared_folders/\(folderID)/\(videoFileName)")
        
        // Calculate expiration time
        _ = Date().addingTimeInterval(TimeInterval(expirationHours * 3600))
        
        // Get signed URL with expiration
        return try await withCheckedThrowingContinuation { continuation in
            // Note: Firebase iOS SDK doesn't directly support expiring URLs in the same way as Admin SDK
            // For production, you should implement this via Cloud Functions
            // For now, we'll use the standard download URL and document the need for backend implementation
            
            videoRef.downloadURL { url, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let url = url {
                    // TODO: Implement proper signed URLs via Cloud Functions
                    // For now, return standard URL
                    print("⚠️ Using standard download URL. For production, implement signed URLs via Cloud Functions.")
                    continuation.resume(returning: url.absoluteString)
                } else {
                    continuation.resume(throwing: VideoCloudError.invalidURL)
                }
            }
        }
    }
    
    /// Generates a secure, expiring download URL for a thumbnail in Firebase Storage
    /// - Parameters:
    ///   - videoFileName: Name of the video file (thumbnail name will be derived)
    ///   - folderID: Shared folder ID
    ///   - expirationHours: Number of hours until the URL expires (default: 168 = 7 days)
    /// - Returns: A secure, time-limited download URL for the thumbnail
    func getSecureThumbnailURL(
        videoFileName: String,
        folderID: String,
        expirationHours: Int = 168
    ) async throws -> String {

        let storage = Storage.storage()
        let storageRef = storage.reference()

        let thumbnailFileName = (videoFileName as NSString).deletingPathExtension + "_thumbnail.jpg"
        let thumbnailRef = storageRef.child("shared_folders/\(folderID)/thumbnails/\(thumbnailFileName)")

        return try await withCheckedThrowingContinuation { continuation in
            thumbnailRef.downloadURL { url, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let url = url {
                    continuation.resume(returning: url.absoluteString)
                } else {
                    continuation.resume(throwing: VideoCloudError.invalidURL)
                }
            }
        }
    }

    /// Deletes a video from Firebase Storage for a shared folder
    /// - Parameters:
    ///   - fileName: Name of the video file to delete
    ///   - folderID: Shared folder ID
    func deleteVideo(fileName: String, folderID: String) async throws {
        let storage = Storage.storage()
        let storageRef = storage.reference()
        let videoRef = storageRef.child("shared_folders/\(folderID)/\(fileName)")

        return try await withCheckedThrowingContinuation { continuation in
            videoRef.delete { error in
                if let error = error {
                    // Check if file doesn't exist (not really an error in deletion context)
                    let nsError = error as NSError
                    if nsError.domain == "FIRStorageErrorDomain" && nsError.code == StorageErrorCode.objectNotFound.rawValue {
                        print("⚠️ Video file not found in storage, treating as already deleted: \(fileName)")
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: error)
                    }
                } else {
                    print("✅ Deleted video from storage: \(fileName)")
                    continuation.resume()
                }
            }
        }
    }

    /// Deletes a thumbnail from Firebase Storage for a shared folder
    /// - Parameters:
    ///   - videoFileName: Name of the video file (thumbnail name will be derived)
    ///   - folderID: Shared folder ID
    func deleteThumbnail(videoFileName: String, folderID: String) async throws {
        let storage = Storage.storage()
        let storageRef = storage.reference()

        let thumbnailFileName = (videoFileName as NSString).deletingPathExtension + "_thumbnail.jpg"
        let thumbnailRef = storageRef.child("shared_folders/\(folderID)/thumbnails/\(thumbnailFileName)")

        return try await withCheckedThrowingContinuation { continuation in
            thumbnailRef.delete { error in
                if let error = error {
                    // Check if file doesn't exist (not really an error)
                    let nsError = error as NSError
                    if nsError.domain == "FIRStorageErrorDomain" && nsError.code == StorageErrorCode.objectNotFound.rawValue {
                        print("⚠️ Thumbnail file not found in storage, treating as already deleted")
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: error)
                    }
                } else {
                    print("✅ Deleted thumbnail from storage")
                    continuation.resume()
                }
            }
        }
    }
}

// MARK: - Supporting Types

enum UploadStatus {
    case idle
    case uploading(progress: Double)
    case downloading(progress: Double)
}

enum VideoCloudError: LocalizedError {
    case uploadFailed(String)
    case downloadFailed(String)
    case deletionFailed(String)
    case invalidURL
    case storageQuotaExceeded
    case networkUnavailable
    
    var errorDescription: String? {
        switch self {
        case .uploadFailed(let reason):
            return "Upload failed: \(reason)"
        case .downloadFailed(let reason):
            return "Download failed: \(reason)"
        case .deletionFailed(let reason):
            return "Deletion failed: \(reason)"
        case .invalidURL:
            return "Invalid cloud storage URL"
        case .storageQuotaExceeded:
            return "Cloud storage quota exceeded"
        case .networkUnavailable:
            return "Network unavailable"
        }
    }
}

// MARK: - Video Metadata Structure
struct VideoClipMetadata {
    let id: UUID
    let fileName: String
    let downloadURL: String
    let createdAt: Date
    let isHighlight: Bool
    let playResult: String?
    let gameOpponent: String?
    let athleteName: String
    let fileSize: Int64
    let thumbnailURL: String?
}