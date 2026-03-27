//
//  VideoCloudManager.swift
//  PlayerPath
//
//  Core: singleton, progress state, throttling, athlete video upload/download/delete.
//  Photo operations → VideoCloudManager+Photos.swift
//  Shared folder operations → VideoCloudManager+SharedFolders.swift
//  Firestore metadata sync → VideoCloudManager+Metadata.swift
//

import Foundation
import Combine
import os
@preconcurrency import SwiftData
import FirebaseStorage
import FirebaseFirestore
import FirebaseAuth

private let videoCloudLog = Logger(subsystem: "com.playerpath.app", category: "VideoCloud")

@MainActor
class VideoCloudManager: ObservableObject {
    static let shared = VideoCloudManager()

    @Published var uploadProgress: [UUID: Double] = [:]
    @Published var isUploading: [UUID: Bool] = [:]
    @Published var downloadProgress: [UUID: Double] = [:]
    @Published var isDownloading: [UUID: Bool] = [:]

    // Progress throttling to prevent excessive UI updates
    var lastProgressUpdate: [String: Date] = [:]
    let progressThrottleInterval: TimeInterval = 0.05 // 50ms

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
    func throttledProgressUpdate(
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

    // MARK: - Athlete Video Upload

    /// Uploads a video file to Firebase Storage for an athlete
    /// - Parameters:
    ///   - videoClip: The video clip to upload
    ///   - athlete: The athlete who owns the video
    /// - Returns: The download URL for the uploaded video
    func uploadVideo(_ videoClip: VideoClip, athlete: Athlete) async throws -> String {
        // Capture values from SwiftData model before async boundary (Sendable compliance)
        let clipId = videoClip.id
        let clipFilePath = videoClip.resolvedFilePath
        let clipFileName = videoClip.fileName
        // Use firestoreId as stable cross-device key; fall back to SwiftData UUID if not yet synced
        let athleteStableId = athlete.firestoreId ?? athlete.id.uuidString
        let athleteName = athlete.name

        // Mark as uploading
        isUploading[clipId] = true
        uploadProgress[clipId] = 0.0

        defer {
            isUploading[clipId] = false
            uploadProgress[clipId] = nil
            lastProgressUpdate.removeValue(forKey: "upload_\(clipId.uuidString)")
        }

        // Verify local file exists
        let localURL = URL(fileURLWithPath: clipFilePath)
        guard FileManager.default.fileExists(atPath: localURL.path) else {
            throw VideoCloudError.uploadFailed("Local file not found at \(clipFilePath)")
        }

        // Enforce per-tier cloud storage limit using live StoreKit tier
        if let user = athlete.user {
            let tier = StoreKitManager.shared.currentTier
            let limitBytes = Int64(tier.storageLimitGB) * StorageConstants.bytesPerGB
            let fileSize: Int64
            do {
                let fileAttrs = try FileManager.default.attributesOfItem(atPath: localURL.path)
                fileSize = (fileAttrs[.size] as? Int64) ?? 0
            } catch {
                videoCloudLog.error("Failed to read file size for quota check: \(error.localizedDescription)")
                fileSize = 0
            }
            if user.cloudStorageUsedBytes + fileSize > limitBytes {
                let usedGB = Double(user.cloudStorageUsedBytes) / StorageConstants.bytesPerGBDouble
                throw VideoCloudError.uploadFailed(
                    String(format: "Storage limit reached (%.1f GB of %d GB used). Upgrade your plan for more storage.", usedGB, tier.storageLimitGB)
                )
            }
        }

        // Create storage reference for athlete videos
        // Use Firebase Auth UID as the path segment so storage rules can enforce ownership
        guard let ownerUID = Auth.auth().currentUser?.uid else {
            throw VideoCloudError.uploadFailed("User session expired — please sign in again to upload")
        }
        let storage = Storage.storage()
        let storageRef = storage.reference()
        let videoRef = storageRef.child("athlete_videos/\(ownerUID)/\(clipFileName)")

        // Create upload task with metadata
        let metadata = StorageMetadata()
        metadata.contentType = "video/quicktime"
        metadata.customMetadata = [
            "athleteId": athleteStableId,
            "athleteName": athleteName,
            "videoClipId": clipId.uuidString
        ]

        // Use file-based upload for streaming (prevents OOM on large files).
        // withTaskCancellationHandler cancels the Firebase task if the Swift Task is cancelled,
        // preventing uploads from running in the background after the user navigates away.
        let uploadBox = UploadTaskBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                // Flag to ensure continuation is resumed exactly once
                let hasResumed = OSAllocatedUnfairLock(initialState: false)
                let uploadTask = videoRef.putFile(from: localURL, metadata: metadata) { [weak uploadBox] metadata, error in
                    // Remove progress observer to prevent memory leaks
                    uploadBox?.task?.removeAllObservers()

                    if let error = error {
                        let alreadyResumed = hasResumed.withLock { val -> Bool in
                            if val { return true }
                            val = true
                            return false
                        }
                        if !alreadyResumed {
                            continuation.resume(throwing: error)
                        }
                        return
                    }

                    // Get download URL
                    videoRef.downloadURL { url, error in
                        let alreadyResumed = hasResumed.withLock { val -> Bool in
                            if val { return true }
                            val = true
                            return false
                        }
                        guard !alreadyResumed else { return }

                        if let error = error {
                            continuation.resume(throwing: error)
                        } else if let url = url {
                            continuation.resume(returning: url.absoluteString)
                        } else {
                            continuation.resume(throwing: VideoCloudError.invalidURL)
                        }
                    }
                }
                uploadBox.task = uploadTask

                // Monitor upload progress with throttling
                uploadTask.observe(.progress) { [weak self] snapshot in
                    guard let progress = snapshot.progress else { return }
                    let percentComplete = progress.totalUnitCount > 0 ? Double(progress.completedUnitCount) / Double(progress.totalUnitCount) : 0.0

                    Task { @MainActor in
                        guard let self = self else { return }

                        _ = self.throttledProgressUpdate(
                            key: "upload_\(clipId.uuidString)",
                            progress: percentComplete
                        ) { progress in
                            self.uploadProgress[clipId] = progress
                        }
                    }
                }
            }
        } onCancel: {
            uploadBox.task?.cancel()
        }
    }

    // MARK: - Athlete Video Download

    /// Downloads a video file from Firebase Storage to local storage
    /// - Parameters:
    ///   - url: The cloud storage URL (from videoClip.cloudURL)
    ///   - localPath: Local file path where the video should be saved
    ///   - clipId: Optional UUID for progress tracking (defaults to new UUID)
    func downloadVideo(from url: String, to localPath: String, clipId: UUID = UUID()) async throws {
        guard ConnectivityMonitor.shared.isConnected else {
            throw VideoCloudError.networkUnavailable
        }

        isDownloading[clipId] = true
        downloadProgress[clipId] = 0.0

        defer {
            isDownloading[clipId] = false
            downloadProgress[clipId] = nil
            lastProgressUpdate.removeValue(forKey: "download_\(clipId.uuidString)")
        }

        // Parse the Firebase Storage URL to get the storage path
        guard let storageURL = URL(string: url) else {
            throw VideoCloudError.invalidURL
        }

        // Create local file URL
        let localURL = URL(fileURLWithPath: localPath)

        // Ensure parent directory exists
        let parentDirectory = localURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
        } catch {
            videoCloudLog.error("Failed to create download directory: \(error.localizedDescription)")
        }

        // Create storage reference from URL
        let storage = Storage.storage()
        let storageRef = try storage.reference(for: storageURL)

        // Download file with progress monitoring.
        // withTaskCancellationHandler cancels the Firebase task if the Swift Task is cancelled.
        let downloadBox = DownloadTaskBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let hasResumed = OSAllocatedUnfairLock(initialState: false)
                let downloadTask = storageRef.write(toFile: localURL) { [weak downloadBox] url, error in
                    // Remove progress observer to prevent memory leaks
                    downloadBox?.task?.removeAllObservers()

                    let alreadyResumed = hasResumed.withLock { val -> Bool in
                        if val { return true }
                        val = true
                        return false
                    }
                    guard !alreadyResumed else { return }

                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        #if DEBUG
                        print("VideoCloudManager: Download completed successfully to \(localPath)")
                        #endif
                        continuation.resume()
                    }
                }
                downloadBox.task = downloadTask

                // Monitor download progress with throttling
                downloadTask.observe(.progress) { [weak self] snapshot in
                    guard let progress = snapshot.progress else { return }
                    let percentComplete = progress.totalUnitCount > 0 ? Double(progress.completedUnitCount) / Double(progress.totalUnitCount) : 0.0

                    Task { @MainActor in
                        guard let self = self else { return }

                        _ = self.throttledProgressUpdate(
                            key: "download_\(clipId.uuidString)",
                            progress: percentComplete
                        ) { progress in
                            self.downloadProgress[clipId] = progress
                        }
                    }
                }
            }
        } onCancel: {
            downloadBox.task?.cancel()
        }
    }

    // MARK: - Athlete Video Delete

    /// Deletes a video clip from Firebase Storage for an athlete
    func deleteVideo(_ videoClip: VideoClip, athlete: Athlete) async throws {
        // Capture values from SwiftData model before async boundary (Sendable compliance)
        let clipFileName = videoClip.fileName

        guard let ownerUID = Auth.auth().currentUser?.uid else {
            throw VideoCloudError.uploadFailed("User session expired — please sign in again to upload")
        }
        let storage = Storage.storage()
        let storageRef = storage.reference()
        let videoRef = storageRef.child("athlete_videos/\(ownerUID)/\(clipFileName)")

        return try await withCheckedThrowingContinuation { continuation in
            videoRef.delete { error in
                if let error = error {
                    // Check if file doesn't exist (not really an error in deletion context)
                    let nsError = error as NSError
                    if nsError.domain == "FIRStorageErrorDomain" && nsError.code == StorageErrorCode.objectNotFound.rawValue {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: error)
                    }
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// Deletes an athlete's video from Firebase Storage by filename.
    /// Use this instead of deleteVideo(_:athlete:) when the VideoClip SwiftData object
    /// may already be deleted (avoids use-after-free on the model object).
    func deleteAthleteVideo(fileName: String) async throws {
        guard let ownerUID = Auth.auth().currentUser?.uid else {
            throw VideoCloudError.uploadFailed("User session expired — please sign in again to upload")
        }
        let videoRef = Storage.storage().reference().child("athlete_videos/\(ownerUID)/\(fileName)")
        return try await withCheckedThrowingContinuation { continuation in
            videoRef.delete { error in
                if let error = error {
                    let nsError = error as NSError
                    if nsError.domain == "FIRStorageErrorDomain" && nsError.code == StorageErrorCode.objectNotFound.rawValue {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: error)
                    }
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// Records a failed Storage deletion in Firestore so the server-side cleanup
    /// function can garbage-collect the orphaned file later.
    func recordPendingDeletion(clipId: UUID, fileName: String) async throws {
        guard let ownerUID = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        try await db.collection(FC.pendingDeletions).document(clipId.uuidString).setData([
            "ownerUID": ownerUID,
            "fileName": fileName,
            "storagePath": "athlete_videos/\(ownerUID)/\(fileName)",
            "createdAt": Timestamp(date: Date())
        ])
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

    // MARK: - Batch Upload

    /// Uploads multiple videos with controlled concurrency (max 3 concurrent uploads)
    func uploadMultipleVideos(
        _ clips: [VideoClip],
        athlete: Athlete,
        maxConcurrentUploads: Int = 3
    ) async -> [(UUID, Result<String, Error>)] {
        // Capture clip data before async boundary (Sendable compliance)
        struct ClipData: Sendable {
            let id: UUID
            let filePath: String
            let fileName: String
        }

        let clipDataArray = clips.map { ClipData(id: $0.id, filePath: $0.resolvedFilePath, fileName: $0.fileName) }
        let athleteStableId = athlete.firestoreId ?? athlete.id.uuidString
        let athleteName = athlete.name

        // Enforce per-tier cloud storage limit before starting batch
        if let user = athlete.user {
            let tier = StoreKitManager.shared.currentTier
            let limitBytes = Int64(tier.storageLimitGB) * StorageConstants.bytesPerGB
            let totalBatchSize = clipDataArray.reduce(Int64(0)) { sum, clip in
                let attrs = try? FileManager.default.attributesOfItem(atPath: clip.filePath)
                return sum + ((attrs?[.size] as? Int64) ?? 0)
            }
            if user.cloudStorageUsedBytes + totalBatchSize > limitBytes {
                let usedGB = Double(user.cloudStorageUsedBytes) / StorageConstants.bytesPerGBDouble
                return clips.map { ($0.id, .failure(VideoCloudError.uploadFailed(
                    String(format: "Storage limit reached (%.1f GB of %d GB used). Upgrade your plan for more storage.", usedGB, tier.storageLimitGB)
                ))) }
            }
        }

        return await withTaskGroup(of: (UUID, Result<String, Error>).self) { group in
            var results: [(UUID, Result<String, Error>)] = []
            var activeUploads = 0
            var clipIndex = 0

            // Start initial batch of uploads
            while clipIndex < clipDataArray.count && activeUploads < maxConcurrentUploads {
                let clipData = clipDataArray[clipIndex]
                group.addTask {
                    do {
                        let cloudURL = try await self.uploadVideoData(
                            clipId: clipData.id,
                            filePath: clipData.filePath,
                            fileName: clipData.fileName,
                            athleteStableId: athleteStableId,
                            athleteName: athleteName
                        )
                        return (clipData.id, .success(cloudURL))
                    } catch {
                        return (clipData.id, .failure(error))
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
                if clipIndex < clipDataArray.count {
                    let clipData = clipDataArray[clipIndex]
                    group.addTask {
                        do {
                            let cloudURL = try await self.uploadVideoData(
                                clipId: clipData.id,
                                filePath: clipData.filePath,
                                fileName: clipData.fileName,
                                athleteStableId: athleteStableId,
                                athleteName: athleteName
                            )
                            return (clipData.id, .success(cloudURL))
                        } catch {
                            return (clipData.id, .failure(error))
                        }
                    }
                    activeUploads += 1
                    clipIndex += 1
                }
            }

            return results
        }
    }

    /// Internal upload method that works with primitive/Sendable types
    private func uploadVideoData(
        clipId: UUID,
        filePath: String,
        fileName: String,
        athleteStableId: String,
        athleteName: String
    ) async throws -> String {
        // Mark as uploading
        isUploading[clipId] = true
        uploadProgress[clipId] = 0.0

        defer {
            isUploading[clipId] = false
            uploadProgress[clipId] = nil
            lastProgressUpdate.removeValue(forKey: "upload_\(clipId.uuidString)")
        }

        // Verify local file exists
        let localURL = URL(fileURLWithPath: filePath)
        guard FileManager.default.fileExists(atPath: localURL.path) else {
            throw VideoCloudError.uploadFailed("Local file not found at \(filePath)")
        }

        guard let ownerUID = Auth.auth().currentUser?.uid else {
            throw VideoCloudError.uploadFailed("User session expired — please sign in again to upload")
        }
        let storage = Storage.storage()
        let storageRef = storage.reference()
        let videoRef = storageRef.child("athlete_videos/\(ownerUID)/\(fileName)")

        let metadata = StorageMetadata()
        metadata.contentType = "video/quicktime"
        metadata.customMetadata = [
            "athleteId": athleteStableId,
            "athleteName": athleteName,
            "videoClipId": clipId.uuidString
        ]

        let uploadBox = UploadTaskBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let hasResumed = OSAllocatedUnfairLock(initialState: false)
                let uploadTask = videoRef.putFile(from: localURL, metadata: metadata) { metadata, error in
                    if let error = error {
                        let alreadyResumed = hasResumed.withLock { val -> Bool in
                            if val { return true }; val = true; return false
                        }
                        if !alreadyResumed { continuation.resume(throwing: error) }
                        return
                    }

                    videoRef.downloadURL { url, error in
                        let alreadyResumed = hasResumed.withLock { val -> Bool in
                            if val { return true }; val = true; return false
                        }
                        guard !alreadyResumed else { return }
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else if let url = url {
                            continuation.resume(returning: url.absoluteString)
                        } else {
                            continuation.resume(throwing: VideoCloudError.invalidURL)
                        }
                    }
                }
                uploadBox.task = uploadTask

                uploadTask.observe(.progress) { [weak self] snapshot in
                    guard let progress = snapshot.progress else { return }
                    let percentComplete = progress.totalUnitCount > 0 ? Double(progress.completedUnitCount) / Double(progress.totalUnitCount) : 0.0

                    Task { @MainActor in
                        guard let self = self else { return }

                        _ = self.throttledProgressUpdate(
                            key: "upload_\(clipId.uuidString)",
                            progress: percentComplete
                        ) { progress in
                            self.uploadProgress[clipId] = progress
                        }
                    }
                }
            }
        } onCancel: {
            uploadBox.task?.cancel()
        }
    }

    // MARK: - GDPR Bulk Delete

    /// Deletes all video files from Firebase Storage for a user
    func deleteAllUserVideos(userID: String) async throws {
        guard ConnectivityMonitor.shared.isConnected else {
            throw VideoCloudError.networkUnavailable
        }

        let storage = Storage.storage()
        let storageRef = storage.reference()
        let userFolderRef = storageRef.child("athlete_videos/\(userID)")

        do {
            let result = try await userFolderRef.listAll()

            for fileRef in result.items {
                do {
                    try await fileRef.delete()
                } catch {
                    videoCloudLog.warning("Failed to delete storage file: \(error.localizedDescription)")
                }
            }

            // Recursively delete subdirectories (thumbnails, etc.)
            for prefixRef in result.prefixes {
                do {
                    let subResult = try await prefixRef.listAll()
                    for subFileRef in subResult.items {
                        try await subFileRef.delete()
                    }
                } catch {
                    videoCloudLog.warning("Failed to delete storage subdirectory: \(error.localizedDescription)")
                }
            }
        } catch {
            let nsError = error as NSError
            if nsError.domain == "FIRStorageErrorDomain" && nsError.code == StorageErrorCode.objectNotFound.rawValue {
                return
            }
            throw error
        }
    }
}

// MARK: - Supporting Types

/// Bridges a Firebase StorageUploadTask across Swift concurrency for cooperative cancellation.
/// @unchecked Sendable is safe here because the task reference is written once before the
/// onCancel handler can fire, and StorageUploadTask.cancel() is thread-safe.
final class UploadTaskBox: @unchecked Sendable {
    nonisolated(unsafe) var task: StorageUploadTask?
}

/// Bridges a Firebase StorageDownloadTask across Swift concurrency for cooperative cancellation.
final class DownloadTaskBox: @unchecked Sendable {
    nonisolated(unsafe) var task: StorageDownloadTask?
}

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
            return "No internet connection. Please check your network and try again."
        }
    }
}

// MARK: - Video Metadata Structure
struct VideoClipMetadata {
    let id: UUID
    let fileName: String
    let downloadURL: String
    let createdAt: Date
    let updatedAt: Date
    let isHighlight: Bool
    let playResult: String?
    let playResultRawValue: Int?
    let note: String?
    let gameId: String?
    let gameOpponent: String?
    let gameDate: Date?
    let seasonId: String?
    let seasonName: String?
    let practiceId: String?
    let practiceDate: Date?
    let pitchSpeed: Double?
    let pitchType: String?
    let duration: Double?
    let athleteName: String
    let fileSize: Int64
    let thumbnailURL: String?
    let isDeleted: Bool

    /// Parses a Firestore document into VideoClipMetadata, returning nil if required fields are missing.
    init?(from data: [String: Any]) {
        guard let idString = data["id"] as? String,
              let id = UUID(uuidString: idString),
              let fileName = data["fileName"] as? String,
              let downloadURL = data["downloadURL"] as? String,
              let athleteName = data["athleteName"] as? String else {
            return nil
        }

        let createdAt: Date
        if let timestamp = data["createdAt"] as? Timestamp {
            createdAt = timestamp.dateValue()
        } else {
            createdAt = Date()
        }

        self.id = id
        self.fileName = fileName
        self.downloadURL = downloadURL
        self.createdAt = createdAt
        self.updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? createdAt
        self.isHighlight = data["isHighlight"] as? Bool ?? false
        self.playResult = data["playResultName"] as? String
        self.playResultRawValue = data["playResult"] as? Int
        self.note = data["note"] as? String
        self.gameId = data["gameId"] as? String
        self.gameOpponent = data["gameOpponent"] as? String
        self.gameDate = (data["gameDate"] as? Timestamp)?.dateValue()
        self.seasonId = data["seasonId"] as? String
        self.seasonName = data["seasonName"] as? String
        self.practiceId = data["practiceId"] as? String
        self.practiceDate = (data["practiceDate"] as? Timestamp)?.dateValue()
        self.pitchSpeed = data["pitchSpeed"] as? Double
        self.pitchType = data["pitchType"] as? String
        self.duration = data["duration"] as? Double
        self.athleteName = athleteName
        self.fileSize = data["fileSize"] as? Int64 ?? 0
        self.thumbnailURL = data["thumbnailURL"] as? String
        self.isDeleted = data["isDeleted"] as? Bool ?? false
    }
}
