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

    // Progress throttling to prevent excessive UI updates
    private var lastProgressUpdate: [String: Date] = [:]
    private let progressThrottleInterval: TimeInterval = 0.05 // 50ms

    private init() {}

    /// Cleans up completed uploads/downloads from progress tracking dictionaries
    /// Call this periodically or when memory pressure is detected
    func cleanupCompletedOperations() {
        // Remove entries where operation is marked as not in progress
        uploadProgress = uploadProgress.filter { clipId, _ in
            isUploading[clipId] == true
        }

        downloadProgress = downloadProgress.filter { clipId, _ in
            isDownloading[clipId] == true
        }

        // Remove false entries from status dictionaries
        isUploading = isUploading.filter { _, isActive in isActive }
        isDownloading = isDownloading.filter { _, isActive in isActive }

        // Clean up throttle tracking
        lastProgressUpdate.removeAll()

        #if DEBUG
        print("🧹 VideoCloudManager: Cleaned up completed operations")
        #endif
    }

    /// Throttles progress updates to prevent excessive MainActor dispatches
    /// - Parameters:
    ///   - key: Unique identifier for the operation
    ///   - progress: Progress value (0.0 to 1.0)
    ///   - handler: Progress handler to call if throttle allows
    /// - Returns: true if update was sent, false if throttled
    private func throttledProgressUpdate(
        key: String,
        progress: Double,
        handler: @escaping (Double) -> Void
    ) -> Bool {
        let now = Date()

        // Always allow 0% and 100% updates
        if progress == 0.0 || progress == 1.0 {
            lastProgressUpdate[key] = now
            handler(progress)
            return true
        }

        // Check if enough time has elapsed since last update
        if let lastUpdate = lastProgressUpdate[key] {
            let elapsed = now.timeIntervalSince(lastUpdate)
            if elapsed < progressThrottleInterval {
                return false // Throttled
            }
        }

        // Send update
        lastProgressUpdate[key] = now
        handler(progress)
        return true
    }
    
    /// Uploads a video file to Firebase Storage for an athlete
    /// - Parameters:
    ///   - videoClip: The video clip to upload
    ///   - athlete: The athlete who owns the video
    /// - Returns: The download URL for the uploaded video
    func uploadVideo(_ videoClip: VideoClip, athlete: Athlete) async throws -> String {
        let clipId = videoClip.id

        // Mark as uploading
        isUploading[clipId] = true
        uploadProgress[clipId] = 0.0

        defer {
            isUploading[clipId] = false
            uploadProgress[clipId] = nil
        }

        // Verify local file exists
        let localURL = URL(fileURLWithPath: videoClip.filePath)
        guard FileManager.default.fileExists(atPath: localURL.path) else {
            throw VideoCloudError.uploadFailed("Local file not found at \(videoClip.filePath)")
        }

        // Create storage reference for athlete videos
        let storage = Storage.storage()
        let storageRef = storage.reference()
        let videoRef = storageRef.child("athlete_videos/\(athlete.id.uuidString)/\(videoClip.fileName)")

        // Create upload task with metadata
        let metadata = StorageMetadata()
        metadata.contentType = "video/quicktime"
        metadata.customMetadata = [
            "athleteId": athlete.id.uuidString,
            "athleteName": athlete.name,
            "videoClipId": clipId.uuidString
        ]

        // Use file-based upload for streaming (prevents OOM on large files)
        return try await withCheckedThrowingContinuation { continuation in
            let uploadTask = videoRef.putFile(from: localURL, metadata: metadata) { metadata, error in
                if let error = error {
                    print("VideoCloudManager: Upload failed for \(videoClip.fileName): \(error)")
                    continuation.resume(throwing: error)
                    return
                }

                // Get download URL
                videoRef.downloadURL { url, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let url = url {
                        print("VideoCloudManager: Upload completed successfully for \(videoClip.fileName)")
                        continuation.resume(returning: url.absoluteString)
                    } else {
                        continuation.resume(throwing: VideoCloudError.invalidURL)
                    }
                }
            }

            // Monitor upload progress with throttling
            uploadTask.observe(.progress) { [weak self] snapshot in
                guard let progress = snapshot.progress else { return }
                let percentComplete = Double(progress.completedUnitCount) / Double(progress.totalUnitCount)

                Task { @MainActor in
                    guard let self = self else { return }

                    // Update progress with throttling
                    _ = self.throttledProgressUpdate(
                        key: "upload_\(clipId.uuidString)",
                        progress: percentComplete
                    ) { progress in
                        self.uploadProgress[clipId] = progress
                        print("VideoCloudManager: Upload progress for \(videoClip.fileName): \(Int(progress * 100))%")
                    }
                }
            }
        }
    }
    
    /// Downloads a video file from Firebase Storage to local storage
    /// - Parameters:
    ///   - url: The cloud storage URL (from videoClip.cloudURL)
    ///   - localPath: Local file path where the video should be saved
    ///   - clipId: Optional UUID for progress tracking (defaults to new UUID)
    func downloadVideo(from url: String, to localPath: String, clipId: UUID = UUID()) async throws {
        isDownloading[clipId] = true
        downloadProgress[clipId] = 0.0

        defer {
            isDownloading[clipId] = false
            downloadProgress[clipId] = nil
        }

        // Parse the Firebase Storage URL to get the storage path
        guard let storageURL = URL(string: url) else {
            throw VideoCloudError.invalidURL
        }

        // Create local file URL
        let localURL = URL(fileURLWithPath: localPath)

        // Ensure parent directory exists
        let parentDirectory = localURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)

        // Create storage reference from URL
        let storage = Storage.storage()
        let storageRef = try storage.reference(for: storageURL)

        // Download file with progress monitoring
        return try await withCheckedThrowingContinuation { continuation in
            let downloadTask = storageRef.write(toFile: localURL) { url, error in
                if let error = error {
                    print("VideoCloudManager: Download failed: \(error)")
                    continuation.resume(throwing: error)
                } else {
                    print("VideoCloudManager: Download completed successfully to \(localPath)")
                    continuation.resume()
                }
            }

            // Monitor download progress with throttling
            downloadTask.observe(.progress) { [weak self] snapshot in
                guard let progress = snapshot.progress else { return }
                let percentComplete = Double(progress.completedUnitCount) / Double(progress.totalUnitCount)

                Task { @MainActor in
                    guard let self = self else { return }

                    // Update progress with throttling
                    _ = self.throttledProgressUpdate(
                        key: "download_\(clipId.uuidString)",
                        progress: percentComplete
                    ) { progress in
                        self.downloadProgress[clipId] = progress
                        print("VideoCloudManager: Download progress: \(Int(progress * 100))%")
                    }
                }
            }
        }
    }
    
    func syncVideos(for athlete: Athlete) async throws -> [VideoClipMetadata] {
        // Simulate fetching video metadata from cloud
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Return empty array for now - in real implementation would fetch from Firebase
        return []
    }
    
    /// Deletes a video clip from Firebase Storage for an athlete
    /// - Parameters:
    ///   - videoClip: The video clip to delete
    ///   - athlete: The athlete who owns the video
    func deleteVideo(_ videoClip: VideoClip, athlete: Athlete) async throws {
        let storage = Storage.storage()
        let storageRef = storage.reference()
        let videoRef = storageRef.child("athlete_videos/\(athlete.id.uuidString)/\(videoClip.fileName)")

        return try await withCheckedThrowingContinuation { continuation in
            videoRef.delete { error in
                if let error = error {
                    // Check if file doesn't exist (not really an error in deletion context)
                    let nsError = error as NSError
                    if nsError.domain == "FIRStorageErrorDomain" && nsError.code == StorageErrorCode.objectNotFound.rawValue {
                        print("⚠️ Video file not found in storage, treating as already deleted: \(videoClip.fileName)")
                        continuation.resume()
                    } else {
                        print("VideoCloudManager: Failed to delete video \(videoClip.fileName): \(error)")
                        continuation.resume(throwing: error)
                    }
                } else {
                    print("VideoCloudManager: Video deleted from cloud successfully: \(videoClip.fileName)")
                    continuation.resume()
                }
            }
        }
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
    
    // MARK: - Batch Upload Functionality

    /// Uploads multiple videos with controlled concurrency (max 3 concurrent uploads)
    /// - Parameters:
    ///   - clips: Array of video clips to upload
    ///   - athlete: The athlete who owns the videos
    ///   - maxConcurrentUploads: Maximum number of simultaneous uploads (default: 3)
    /// - Returns: Array of tuples containing each clip and its upload result
    func uploadMultipleVideos(
        _ clips: [VideoClip],
        athlete: Athlete,
        maxConcurrentUploads: Int = 3
    ) async -> [(VideoClip, Result<String, Error>)] {

        return await withTaskGroup(of: (VideoClip, Result<String, Error>).self) { group in
            var results: [(VideoClip, Result<String, Error>)] = []
            var activeUploads = 0
            var clipIndex = 0

            // Start initial batch of uploads
            while clipIndex < clips.count && activeUploads < maxConcurrentUploads {
                let clip = clips[clipIndex]
                group.addTask {
                    do {
                        let cloudURL = try await self.uploadVideo(clip, athlete: athlete)
                        return (clip, .success(cloudURL))
                    } catch {
                        return (clip, .failure(error))
                    }
                }
                activeUploads += 1
                clipIndex += 1
            }

            // Process results and start new uploads as slots become available
            for await result in group {
                results.append(result)
                activeUploads -= 1

                // Start next upload if available
                if clipIndex < clips.count {
                    let clip = clips[clipIndex]
                    group.addTask {
                        do {
                            let cloudURL = try await self.uploadVideo(clip, athlete: athlete)
                            return (clip, .success(cloudURL))
                        } catch {
                            return (clip, .failure(error))
                        }
                    }
                    activeUploads += 1
                    clipIndex += 1
                }
            }

            return results
        }
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

        // Create upload task with metadata
        let metadata = StorageMetadata()
        metadata.contentType = "video/quicktime"

        // Use file-based upload for streaming (prevents OOM on large files)
        return try await withCheckedThrowingContinuation { continuation in
            let uploadTask = videoRef.putFile(from: localURL, metadata: metadata) { metadata, error in
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

            // Monitor upload progress with throttling
            // Note: Observer is automatically cleaned up when uploadTask completes or is deallocated
            uploadTask.observe(.progress) { [weak self] snapshot in
                guard let progress = snapshot.progress else { return }
                let percentComplete = Double(progress.completedUnitCount) / Double(progress.totalUnitCount)

                Task { @MainActor in
                    // Apply throttling to prevent excessive UI updates (max 50ms interval)
                    guard let self = self else {
                        progressHandler(percentComplete)
                        return
                    }

                    _ = self.throttledProgressUpdate(
                        key: "upload_\(fileName)",
                        progress: percentComplete,
                        handler: progressHandler
                    )
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

        // Create upload task with metadata
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        metadata.cacheControl = "public, max-age=31536000" // Cache for 1 year

        // Use file-based upload for streaming (consistent with video uploads)
        return try await withCheckedThrowingContinuation { continuation in
            thumbnailRef.putFile(from: thumbnailURL, metadata: metadata) { metadata, error in
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
    
    // MARK: - Consolidated URL Methods

    /// Gets a secure download URL for a file in Firebase Storage
    /// - Parameters:
    ///   - fileName: Name of the file in storage
    ///   - folderID: Shared folder ID
    ///   - isThumbnail: Whether this is a thumbnail (stored in thumbnails/ subfolder)
    ///   - expirationHours: Optional. Hours until URL expires (currently not implemented - see note)
    /// - Returns: A secure download URL with Firebase security token
    /// - Note: Firebase Storage URLs include long-lived security tokens. For true expiring URLs,
    ///         implement a Cloud Function using Firebase Admin SDK to generate signed URLs with
    ///         custom expiration times. Current implementation uses Firebase's built-in token-based
    ///         security which validates against Storage Rules on each request.
    func getSecureDownloadURL(
        fileName: String,
        folderID: String,
        isThumbnail: Bool = false,
        expirationHours: Int? = nil
    ) async throws -> String {

        let storage = Storage.storage()
        let storageRef = storage.reference()

        // Build the correct storage path
        let filePath: String
        if isThumbnail {
            // Convert video filename to thumbnail filename
            let thumbnailFileName = (fileName as NSString).deletingPathExtension + "_thumbnail.jpg"
            filePath = "shared_folders/\(folderID)/thumbnails/\(thumbnailFileName)"
        } else {
            filePath = "shared_folders/\(folderID)/\(fileName)"
        }

        let fileRef = storageRef.child(filePath)

        // Note expiration warning if requested
        if let hours = expirationHours {
            #if DEBUG
            print("⚠️ Expiring URLs requested (\(hours)h) but not implemented. Using standard URL.")
            print("   TODO: Implement signed URLs via Cloud Functions for true expiration.")
            #endif
        }

        return try await withCheckedThrowingContinuation { continuation in
            fileRef.downloadURL { url, error in
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

    // MARK: - Convenience Methods (use consolidated method internally)

    /// Convenience: Gets download URL for a video file
    func getVideoDownloadURL(fileName: String, folderID: String) async throws -> String {
        return try await getSecureDownloadURL(fileName: fileName, folderID: folderID, isThumbnail: false)
    }

    /// Convenience: Gets download URL for a thumbnail file
    func getThumbnailDownloadURL(videoFileName: String, folderID: String) async throws -> String {
        return try await getSecureDownloadURL(fileName: videoFileName, folderID: folderID, isThumbnail: true)
    }

    // MARK: - Orphaned File Cleanup

    /// Uploads video with automatic rollback on metadata failure
    /// - Parameters:
    ///   - localURL: Local file URL of the video
    ///   - fileName: Name for the file in storage
    ///   - folderID: Shared folder ID
    ///   - progressHandler: Closure called with progress updates
    ///   - metadataWriter: Async closure that writes metadata to Firestore
    /// - Returns: The download URL for the uploaded video
    /// - Note: If metadata write fails, automatically deletes the uploaded file to prevent orphans
    func uploadVideoWithRollback(
        localURL: URL,
        fileName: String,
        folderID: String,
        progressHandler: @escaping (Double) -> Void,
        metadataWriter: @escaping (String) async throws -> Void
    ) async throws -> String {

        var uploadedURL: String?

        do {
            // Step 1: Upload video to Storage
            uploadedURL = try await uploadVideo(
                localURL: localURL,
                fileName: fileName,
                folderID: folderID,
                progressHandler: progressHandler
            )

            // Step 2: Write metadata to Firestore
            try await metadataWriter(uploadedURL!)

            // Success - return URL
            return uploadedURL!

        } catch {
            // Metadata write failed - rollback the upload
            if let url = uploadedURL {
                #if DEBUG
                print("⚠️ Metadata write failed, rolling back Storage upload: \(fileName)")
                #endif

                do {
                    try await deleteVideo(fileName: fileName, folderID: folderID)
                    #if DEBUG
                    print("✅ Successfully rolled back orphaned file: \(fileName)")
                    #endif
                } catch {
                    #if DEBUG
                    print("❌ Failed to rollback orphaned file: \(fileName) - \(error)")
                    print("   Manual cleanup required for: shared_folders/\(folderID)/\(fileName)")
                    #endif
                }
            }

            throw error
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

    /// Deletes all videos and thumbnails for a specific user (GDPR compliance)
    /// This deletes all files in the user's athlete_videos folder in Firebase Storage
    /// - Parameter userID: The user ID whose videos should be deleted
    func deleteAllUserVideos(userID: String) async throws {
        let storage = Storage.storage()
        let storageRef = storage.reference()

        print("🗑️ Deleting all videos for user: \(userID)")

        // Path to user's video folder
        let userFolderRef = storageRef.child("athlete_videos/\(userID)")

        do {
            // List all files in the user's folder
            let result = try await userFolderRef.listAll()

            print("🗑️ Found \(result.items.count) files and \(result.prefixes.count) subdirectories to delete")

            // Delete all files
            for fileRef in result.items {
                do {
                    try await fileRef.delete()
                    print("✅ Deleted file: \(fileRef.name)")
                } catch {
                    print("⚠️ Failed to delete file \(fileRef.name): \(error)")
                    // Continue deleting other files even if one fails
                }
            }

            // Recursively delete subdirectories (thumbnails, etc.)
            for prefixRef in result.prefixes {
                do {
                    let subResult = try await prefixRef.listAll()
                    for subFileRef in subResult.items {
                        try await subFileRef.delete()
                        print("✅ Deleted subfolder file: \(subFileRef.name)")
                    }
                } catch {
                    print("⚠️ Failed to delete subdirectory \(prefixRef.name): \(error)")
                    // Continue with other directories
                }
            }

            print("✅ Deleted all videos for user \(userID)")

        } catch {
            // If folder doesn't exist, that's fine - no videos to delete
            let nsError = error as NSError
            if nsError.domain == "FIRStorageErrorDomain" && nsError.code == StorageErrorCode.objectNotFound.rawValue {
                print("⚠️ No videos folder found for user \(userID), treating as already deleted")
                return
            }
            throw error
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