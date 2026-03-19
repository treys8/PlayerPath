//
//  VideoCloudManager.swift
//  PlayerPath
//
//  Cross-platform video storage manager using Firebase
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
            let limitBytes = Int64(tier.storageLimitGB) * 1_073_741_824
            let fileAttrs = try? FileManager.default.attributesOfItem(atPath: localURL.path)
            let fileSize = (fileAttrs?[.size] as? Int64) ?? 0
            if user.cloudStorageUsedBytes + fileSize > limitBytes {
                let usedGB = Double(user.cloudStorageUsedBytes) / 1_073_741_824.0
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
                    let percentComplete = Double(progress.completedUnitCount) / Double(progress.totalUnitCount)

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
        try? FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)

        // Create storage reference from URL
        let storage = Storage.storage()
        let storageRef = try storage.reference(for: storageURL)

        // Download file with progress monitoring.
        // withTaskCancellationHandler cancels the Firebase task if the Swift Task is cancelled.
        let downloadBox = DownloadTaskBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let downloadTask = storageRef.write(toFile: localURL) { [weak downloadBox] url, error in
                    // Remove progress observer to prevent memory leaks
                    downloadBox?.task?.removeAllObservers()

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
                    let percentComplete = Double(progress.completedUnitCount) / Double(progress.totalUnitCount)

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
    
    // MARK: - Firestore Video Metadata Sync

    /// Saves video metadata to Firestore for cross-device sync
    /// - Parameters:
    ///   - videoClip: The video clip to save metadata for
    ///   - athlete: The athlete who owns the video
    ///   - downloadURL: The Firebase Storage download URL
    func saveVideoMetadataToFirestore(_ videoClip: VideoClip, athlete: Athlete, downloadURL: String) async throws {
        // Capture values before async boundary (Sendable compliance)
        let clipId = videoClip.id
        let clipFileName = videoClip.fileName
        let clipIsHighlight = videoClip.isHighlight
        let clipCreatedAt = videoClip.createdAt ?? Date()
        let clipDuration = videoClip.duration
        let clipThumbnailPath = videoClip.thumbnailPath
        let clipNote = videoClip.note
        let clipPitchSpeed = videoClip.pitchSpeed
        let playResultType = videoClip.playResult?.type
        // Use stable firestoreId for cross-device linking; fall back to SwiftData UUID
        let gameId = videoClip.game.map { $0.firestoreId ?? $0.id.uuidString }
        let gameOpponent = videoClip.gameOpponent ?? videoClip.game?.opponent
        let gameDate = videoClip.gameDate ?? videoClip.game?.date
        let practiceDate = videoClip.practiceDate ?? videoClip.practice?.date
        let practiceId = videoClip.practice?.id
        let seasonId = videoClip.season.map { $0.firestoreId ?? $0.id.uuidString }
        let seasonName = videoClip.seasonName ?? videoClip.season?.displayName
        // Use firestoreId as stable cross-device key; fall back to SwiftData UUID if not yet synced
        let athleteStableId = athlete.firestoreId ?? athlete.id.uuidString
        let athleteName = athlete.name

        // Get file size
        let fileSize = FileManager.default.fileSize(atPath: videoClip.resolvedFilePath)

        let db = Firestore.firestore()

        // Owner UID used for Firestore security rules and Storage path
        guard let ownerUID = Auth.auth().currentUser?.uid else {
            throw VideoCloudError.uploadFailed("User session expired — please sign in again to upload")
        }

        // Build document data
        var data: [String: Any] = [
            "id": clipId.uuidString,
            "athleteId": athleteStableId,
            "athleteName": athleteName,
            "fileName": clipFileName,
            "downloadURL": downloadURL,
            "isHighlight": clipIsHighlight,
            "createdAt": Timestamp(date: clipCreatedAt),
            "updatedAt": Timestamp(date: Date()),
            "fileSize": fileSize,
            "isDeleted": false,
            "uploadedBy": ownerUID
        ]

        // Optional fields
        if let duration = clipDuration {
            data["duration"] = duration
        }
        if let playResult = playResultType {
            data["playResult"] = playResult.rawValue
            data["playResultName"] = playResult.displayName
        }
        if let opponent = gameOpponent {
            data["gameOpponent"] = opponent
        }
        if let gameDate = gameDate {
            data["gameDate"] = Timestamp(date: gameDate)
        }
        if let gameId = gameId {
            data["gameId"] = gameId
        }
        if let practiceId = practiceId {
            data["practiceId"] = practiceId.uuidString
        }
        if let practiceDate = practiceDate {
            data["practiceDate"] = Timestamp(date: practiceDate)
        }
        if let seasonId = seasonId {
            data["seasonId"] = seasonId
        }
        if let seasonName = seasonName {
            data["seasonName"] = seasonName
        }
        if let note = clipNote {
            data["note"] = note
        }
        if let pitchSpeed = clipPitchSpeed {
            data["pitchSpeed"] = pitchSpeed
        }

        // Upload thumbnail to Storage if exists, then add URL to metadata
        if let thumbnailPath = clipThumbnailPath,
           FileManager.default.fileExists(atPath: thumbnailPath) {
            do {
                let thumbnailURL = URL(fileURLWithPath: thumbnailPath)
                let cloudThumbnailURL = try await uploadAthleteVideoThumbnail(
                    thumbnailURL: thumbnailURL,
                    videoFileName: clipFileName,
                    athleteStableId: athleteStableId
                )
                data["thumbnailURL"] = cloudThumbnailURL
            } catch {
                videoCloudLog.warning("Failed to upload thumbnail for \(clipFileName): \(error.localizedDescription)")
            }
        }

        // Save to Firestore - use clipId as document ID for easy lookup
        try await db.collection("videos").document(clipId.uuidString).setData(data)

    }

    /// Updates only the note field on an existing video document in Firestore.
    func updateVideoNote(clipId: String, note: String?) async throws {
        let db = Firestore.firestore()
        let value: Any = note ?? NSNull()
        try await db.collection("videos").document(clipId).updateData(["note": value, "updatedAt": Timestamp(date: Date())])
    }

    /// Updates mutable video metadata fields in Firestore (isHighlight, note).
    func updateVideoMetadata(clipId: String, isHighlight: Bool, note: String?, playResultType: PlayResultType?, pitchSpeed: Double?, gameId: String?, gameOpponent: String?, gameDate: Date?, seasonId: String?, seasonName: String?, practiceId: String?, practiceDate: Date? = nil) async throws {
        let db = Firestore.firestore()
        var data: [String: Any] = [
            "isHighlight": isHighlight,
            "note": note ?? NSNull(),
            "updatedAt": Timestamp(date: Date())
        ]
        if let playResultType {
            data["playResult"] = playResultType.rawValue
            data["playResultName"] = playResultType.displayName
        } else {
            data["playResult"] = NSNull()
            data["playResultName"] = NSNull()
        }
        data["pitchSpeed"] = pitchSpeed ?? NSNull()
        data["gameId"] = gameId ?? NSNull()
        data["gameOpponent"] = gameOpponent ?? NSNull()
        data["gameDate"] = gameDate.map { Timestamp(date: $0) } ?? NSNull()
        data["seasonId"] = seasonId ?? NSNull()
        data["seasonName"] = seasonName ?? NSNull()
        data["practiceId"] = practiceId ?? NSNull()
        data["practiceDate"] = practiceDate.map { Timestamp(date: $0) } ?? NSNull()
        try await db.collection("videos").document(clipId).updateData(data)
    }

    // MARK: - Photo Storage

    /// Uploads a photo file to Firebase Storage and returns its download URL.
    func uploadPhoto(at localURL: URL, ownerUID: String) async throws -> String {
        let storage = Storage.storage()
        let fileName = localURL.lastPathComponent
        let photoRef = storage.reference().child("athlete_photos/\(ownerUID)/\(fileName)")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        return try await withCheckedThrowingContinuation { continuation in
            photoRef.putFile(from: localURL, metadata: metadata) { _, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                photoRef.downloadURL { url, error in
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

    /// Deletes an athlete's photo from Firebase Storage.
    func deleteAthletePhoto(fileName: String) async throws {
        guard let ownerUID = Auth.auth().currentUser?.uid else {
            throw VideoCloudError.uploadFailed("User session expired — please sign in again")
        }
        let photoRef = Storage.storage().reference().child("athlete_photos/\(ownerUID)/\(fileName)")
        return try await withCheckedThrowingContinuation { continuation in
            photoRef.delete { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// Downloads a photo file from Firebase Storage to a local path.
    func downloadPhoto(from cloudURL: String, to localPath: String) async throws {
        guard ConnectivityMonitor.shared.isConnected else {
            throw VideoCloudError.networkUnavailable
        }
        guard let storageURL = URL(string: cloudURL) else { throw VideoCloudError.invalidURL }
        let localURL = URL(fileURLWithPath: localPath)
        try? FileManager.default.createDirectory(
            at: localURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: localPath) { return }

        let storage = Storage.storage()
        let photoRef = storage.reference(forURL: storageURL.absoluteString)

        return try await withCheckedThrowingContinuation { continuation in
            photoRef.write(toFile: localURL) { _, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// Uploads a thumbnail image for an athlete's video
    private func uploadAthleteVideoThumbnail(
        thumbnailURL: URL,
        videoFileName: String,
        athleteStableId: String
    ) async throws -> String {
        let storage = Storage.storage()
        let storageRef = storage.reference()

        let thumbnailFileName = (videoFileName as NSString).deletingPathExtension + "_thumbnail.jpg"
        guard let ownerUID = Auth.auth().currentUser?.uid else {
            throw VideoCloudError.uploadFailed("User session expired — please sign in again to upload")
        }
        let thumbnailRef = storageRef.child("athlete_videos/\(ownerUID)/thumbnails/\(thumbnailFileName)")

        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        metadata.cacheControl = "public, max-age=31536000"

        return try await withCheckedThrowingContinuation { continuation in
            thumbnailRef.putFile(from: thumbnailURL, metadata: metadata) { _, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

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

    /// Fetches video metadata from Firestore for cross-device sync
    /// - Parameter athlete: The athlete whose videos to fetch
    /// - Returns: Array of video metadata from Firestore
    func syncVideos(for athlete: Athlete) async throws -> [VideoClipMetadata] {
        guard let ownerUID = Auth.auth().currentUser?.uid else {
            throw VideoCloudError.uploadFailed("User session expired — please sign in again to upload")
        }
        let athleteStableId = athlete.firestoreId ?? athlete.id.uuidString
        let db = Firestore.firestore()

        // Query videos for this specific athlete that aren't deleted.
        // uploadedBy filter is required for Firestore security rule evaluation.
        let snapshot = try await db.collection("videos")
            .whereField("uploadedBy", isEqualTo: ownerUID)
            .whereField("athleteId", isEqualTo: athleteStableId)
            .whereField("isDeleted", isEqualTo: false)
            .order(by: "createdAt", descending: true)
            .limit(to: 200)
            .getDocuments()

        var videos: [VideoClipMetadata] = []

        for document in snapshot.documents {
            let data = document.data()

            guard let idString = data["id"] as? String,
                  let id = UUID(uuidString: idString),
                  let fileName = data["fileName"] as? String,
                  let downloadURL = data["downloadURL"] as? String,
                  let athleteName = data["athleteName"] as? String else {
                continue
            }

            // Parse optional fields
            let createdAt: Date
            if let timestamp = data["createdAt"] as? Timestamp {
                createdAt = timestamp.dateValue()
            } else {
                createdAt = Date()
            }

            let updatedAt: Date
            if let updatedTimestamp = data["updatedAt"] as? Timestamp {
                updatedAt = updatedTimestamp.dateValue()
            } else {
                updatedAt = createdAt
            }
            let isHighlight = data["isHighlight"] as? Bool ?? false
            let playResultName = data["playResultName"] as? String
            let playResultRawValue = data["playResult"] as? Int
            let note = data["note"] as? String
            let gameId = data["gameId"] as? String
            let gameOpponent = data["gameOpponent"] as? String
            let gameDate = (data["gameDate"] as? Timestamp)?.dateValue()
            let seasonId = data["seasonId"] as? String
            let seasonName = data["seasonName"] as? String
            let practiceId = data["practiceId"] as? String
            let practiceDate = (data["practiceDate"] as? Timestamp)?.dateValue()
            let pitchSpeed = data["pitchSpeed"] as? Double
            let duration = data["duration"] as? Double
            let fileSize = data["fileSize"] as? Int64 ?? 0
            let thumbnailURL = data["thumbnailURL"] as? String
            let isDeleted = data["isDeleted"] as? Bool ?? false

            let metadata = VideoClipMetadata(
                id: id,
                fileName: fileName,
                downloadURL: downloadURL,
                createdAt: createdAt,
                updatedAt: updatedAt,
                isHighlight: isHighlight,
                playResult: playResultName,
                playResultRawValue: playResultRawValue,
                note: note,
                gameId: gameId,
                gameOpponent: gameOpponent,
                gameDate: gameDate,
                seasonId: seasonId,
                seasonName: seasonName,
                practiceId: practiceId,
                practiceDate: practiceDate,
                pitchSpeed: pitchSpeed,
                duration: duration,
                athleteName: athleteName,
                fileSize: fileSize,
                thumbnailURL: thumbnailURL,
                isDeleted: isDeleted
            )

            videos.append(metadata)
        }

        return videos
    }

    /// Marks a video as deleted in Firestore (soft delete for sync)
    /// - Parameter clipId: The ID of the video clip to mark as deleted
    func markVideoDeletedInFirestore(_ clipId: UUID) async throws {
        let db = Firestore.firestore()

        try await db.collection("videos").document(clipId.uuidString).updateData([
            "isDeleted": true,
            "deletedAt": Timestamp(date: Date())
        ])

    }

    /// Sets up a real-time listener for new videos from other devices
    /// - Parameters:
    ///   - athlete: The athlete to listen for
    ///   - onNewVideo: Callback when a new video is discovered
    /// - Returns: A listener registration that can be used to remove the listener
    func listenForNewVideos(
        for athlete: Athlete,
        onNewVideo: @escaping (VideoClipMetadata) -> Void
    ) -> ListenerRegistration {
        // Use firestoreId as stable cross-device key; fall back to SwiftData UUID if not yet synced
        let athleteStableId = athlete.firestoreId ?? athlete.id.uuidString
        let db = Firestore.firestore()
        guard let ownerUID = Auth.auth().currentUser?.uid else {
            return db.collection("videos").limit(to: 0).addSnapshotListener { _, _ in }
        }

        let listener = db.collection("videos")
            .whereField("uploadedBy", isEqualTo: ownerUID)
            .whereField("athleteId", isEqualTo: athleteStableId)
            .whereField("isDeleted", isEqualTo: false)
            .limit(to: 200)
            .addSnapshotListener { snapshot, error in
                guard let snapshot = snapshot else {
                    return
                }

                // Process only added documents (new videos)
                for change in snapshot.documentChanges where change.type == .added {
                    let data = change.document.data()

                    guard let idString = data["id"] as? String,
                          let id = UUID(uuidString: idString),
                          let fileName = data["fileName"] as? String,
                          let downloadURL = data["downloadURL"] as? String,
                          let athleteName = data["athleteName"] as? String else {
                        continue
                    }

                    let createdAt: Date
                    if let timestamp = data["createdAt"] as? Timestamp {
                        createdAt = timestamp.dateValue()
                    } else {
                        createdAt = Date()
                    }

                    let metadata = VideoClipMetadata(
                        id: id,
                        fileName: fileName,
                        downloadURL: downloadURL,
                        createdAt: createdAt,
                        updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? createdAt,
                        isHighlight: data["isHighlight"] as? Bool ?? false,
                        playResult: data["playResultName"] as? String,
                        playResultRawValue: data["playResult"] as? Int,
                        note: data["note"] as? String,
                        gameId: data["gameId"] as? String,
                        gameOpponent: data["gameOpponent"] as? String,
                        gameDate: (data["gameDate"] as? Timestamp)?.dateValue(),
                        seasonId: data["seasonId"] as? String,
                        seasonName: data["seasonName"] as? String,
                        practiceId: data["practiceId"] as? String,
                        practiceDate: (data["practiceDate"] as? Timestamp)?.dateValue(),
                        pitchSpeed: data["pitchSpeed"] as? Double,
                        duration: data["duration"] as? Double,
                        athleteName: athleteName,
                        fileSize: data["fileSize"] as? Int64 ?? 0,
                        thumbnailURL: data["thumbnailURL"] as? String,
                        isDeleted: data["isDeleted"] as? Bool ?? false
                    )

                    onNewVideo(metadata)
                }
            }

        return listener
    }
    
    /// Deletes a video clip from Firebase Storage for an athlete
    /// - Parameters:
    ///   - videoClip: The video clip to delete
    ///   - athlete: The athlete who owns the video
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
        try await db.collection("pendingDeletions").document(clipId.uuidString).setData([
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
    
    // MARK: - Batch Upload Functionality

    /// Uploads multiple videos with controlled concurrency (max 3 concurrent uploads)
    /// - Parameters:
    ///   - clips: Array of video clips to upload
    ///   - athlete: The athlete who owns the videos
    ///   - maxConcurrentUploads: Maximum number of simultaneous uploads (default: 3)
    /// - Returns: Array of tuples containing each clip ID and its upload result
    func uploadMultipleVideos(
        _ clips: [VideoClip],
        athlete: Athlete,
        maxConcurrentUploads: Int = 3
    ) async -> [(UUID, Result<String, Error>)] {
        // Capture clip data before async boundary (Sendable compliance)
        // VideoClip is a SwiftData model and not Sendable
        struct ClipData: Sendable {
            let id: UUID
            let filePath: String
            let fileName: String
        }

        let clipDataArray = clips.map { ClipData(id: $0.id, filePath: $0.resolvedFilePath, fileName: $0.fileName) }
        // Use firestoreId as stable cross-device key; fall back to SwiftData UUID if not yet synced
        let athleteStableId = athlete.firestoreId ?? athlete.id.uuidString
        let athleteName = athlete.name

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

        // Create storage reference for athlete videos
        // Use Firebase Auth UID as the path segment so storage rules can enforce ownership
        guard let ownerUID = Auth.auth().currentUser?.uid else {
            throw VideoCloudError.uploadFailed("User session expired — please sign in again to upload")
        }
        let storage = Storage.storage()
        let storageRef = storage.reference()
        let videoRef = storageRef.child("athlete_videos/\(ownerUID)/\(fileName)")

        // Create upload task with metadata
        let metadata = StorageMetadata()
        metadata.contentType = "video/quicktime"
        metadata.customMetadata = [
            "athleteId": athleteStableId,
            "athleteName": athleteName,
            "videoClipId": clipId.uuidString
        ]

        // Use file-based upload for streaming (prevents OOM on large files).
        // withTaskCancellationHandler cancels the Firebase task if the Swift Task is cancelled.
        let uploadBox = UploadTaskBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
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
                uploadBox.task = uploadTask

                // Monitor upload progress with throttling
                uploadTask.observe(.progress) { [weak self] snapshot in
                    guard let progress = snapshot.progress else { return }
                    let percentComplete = Double(progress.completedUnitCount) / Double(progress.totalUnitCount)

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
        let thumbnailFileName = (videoFileName as NSString).deletingPathExtension + "_thumbnail.jpg"
        
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
        isThumbnail: Bool = false
    ) async throws -> String {
        guard ConnectivityMonitor.shared.isConnected else {
            throw VideoCloudError.networkUnavailable
        }

        let storage = Storage.storage()
        let storageRef = storage.reference()

        // Build the correct storage path
        let filePath: String
        if isThumbnail {
            let thumbnailFileName = (fileName as NSString).deletingPathExtension + "_thumbnail.jpg"
            filePath = "shared_folders/\(folderID)/thumbnails/\(thumbnailFileName)"
        } else {
            filePath = "shared_folders/\(folderID)/\(fileName)"
        }

        let fileRef = storageRef.child(filePath)

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
            guard let url = uploadedURL else {
                throw VideoCloudError.uploadFailed("Upload completed but URL was not set")
            }
            try await metadataWriter(url)

            // Success - return URL
            return url

        } catch {
            // Metadata write failed - rollback the upload
            if uploadedURL != nil {
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

    /// Deletes all videos and thumbnails for a specific user (GDPR compliance)
    /// This deletes all files in the user's athlete_videos folder in Firebase Storage
    /// Deletes all photo files from Firebase Storage for a user
    /// - Parameter userID: The user ID whose photos should be deleted
    func deleteAllUserPhotos(userID: String) async throws {
        guard ConnectivityMonitor.shared.isConnected else {
            throw VideoCloudError.networkUnavailable
        }

        let storage = Storage.storage()
        let userPhotoRef = storage.reference().child("athlete_photos/\(userID)")

        do {
            let result = try await userPhotoRef.listAll()
            for fileRef in result.items {
                do {
                    try await fileRef.delete()
                } catch {
                    // Continue deleting other files even if one fails
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

    /// Deletes all video files from Firebase Storage for a user
    /// - Parameter userID: The user ID whose videos should be deleted
    func deleteAllUserVideos(userID: String) async throws {
        guard ConnectivityMonitor.shared.isConnected else {
            throw VideoCloudError.networkUnavailable
        }

        let storage = Storage.storage()
        let storageRef = storage.reference()


        // Path to user's video folder
        let userFolderRef = storageRef.child("athlete_videos/\(userID)")

        do {
            // List all files in the user's folder
            let result = try await userFolderRef.listAll()


            // Delete all files
            for fileRef in result.items {
                do {
                    try await fileRef.delete()
                } catch {
                    // Continue deleting other files even if one fails
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
                    // Continue with other directories
                }
            }


        } catch {
            // If folder doesn't exist, that's fine - no videos to delete
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
private final class UploadTaskBox: @unchecked Sendable {
    nonisolated(unsafe) var task: StorageUploadTask?
}

/// Bridges a Firebase StorageDownloadTask across Swift concurrency for cooperative cancellation.
private final class DownloadTaskBox: @unchecked Sendable {
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
    let duration: Double?
    let athleteName: String
    let fileSize: Int64
    let thumbnailURL: String?
    let isDeleted: Bool
}