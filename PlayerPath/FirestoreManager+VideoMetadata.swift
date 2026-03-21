//
//  FirestoreManager+VideoMetadata.swift
//  PlayerPath
//
//  Video metadata operations for FirestoreManager
//

import Foundation
import FirebaseFirestore
import os

extension FirestoreManager {

    // MARK: - Video Metadata

    /// Uploads video metadata to Firestore after file upload to Storage
    /// - Parameters:
    ///   - fileName: Name of the video file
    ///   - storageURL: Firebase Storage URL for the video
    ///   - thumbnail: Structured thumbnail metadata (supports multiple qualities)
    ///   - folderID: Shared folder ID
    ///   - uploadedBy: User ID of uploader
    ///   - uploadedByName: Display name of uploader
    ///   - fileSize: File size in bytes
    ///   - duration: Video duration in seconds
    ///   - videoType: Type of video ("game", "practice", "highlight")
    ///   - gameContext: Optional game-specific metadata
    ///   - practiceContext: Optional practice-specific metadata
    /// - Returns: Document ID of created video metadata
    func uploadVideoMetadata(
        fileName: String,
        storageURL: String,
        thumbnail: ThumbnailMetadata?,
        folderID: String,
        uploadedBy: String,
        uploadedByName: String,
        fileSize: Int64,
        duration: Double?,
        videoType: String = "game",
        gameContext: GameContext? = nil,
        practiceContext: PracticeContext? = nil
    ) async throws -> String {
        var videoData: [String: Any] = [
            "fileName": fileName,
            "firebaseStorageURL": storageURL,
            "uploadedBy": uploadedBy,
            "uploadedByName": uploadedByName,
            "sharedFolderID": folderID,
            "createdAt": FieldValue.serverTimestamp(),
            "fileSize": fileSize,
            "duration": duration as Any,
            "videoType": videoType,
            "isHighlight": videoType == "highlight"
        ]

        // Add structured thumbnail data
        if let thumbnail = thumbnail {
            var thumbnailDict: [String: Any] = [
                "standardURL": thumbnail.standardURL
            ]
            if let highQualityURL = thumbnail.highQualityURL {
                thumbnailDict["highQualityURL"] = highQualityURL
            }
            if let timestamp = thumbnail.timestamp {
                thumbnailDict["timestamp"] = timestamp
            }
            if let width = thumbnail.width {
                thumbnailDict["width"] = width
            }
            if let height = thumbnail.height {
                thumbnailDict["height"] = height
            }
            videoData["thumbnail"] = thumbnailDict

            // Keep legacy field for backward compatibility
            videoData["thumbnailURL"] = thumbnail.standardURL
        }

        // Add game-specific context
        if let game = gameContext {
            videoData["gameOpponent"] = game.opponent
            videoData["gameDate"] = game.date
            if let notes = game.notes {
                videoData["notes"] = notes
            }
        }

        // Add practice-specific context
        if let practice = practiceContext {
            videoData["practiceDate"] = practice.date
            if let notes = practice.notes {
                videoData["notes"] = notes
            }
        }

        do {
            // Batch: create video doc + increment folder count atomically
            let batch = db.batch()
            let videoRef = db.collection("videos").document()
            batch.setData(videoData, forDocument: videoRef)
            batch.updateData([
                "videoCount": FieldValue.increment(Int64(1)),
                "updatedAt": FieldValue.serverTimestamp()
            ], forDocument: db.collection("sharedFolders").document(folderID))
            try await batch.commit()

            return videoRef.documentID
        } catch {
            errorMessage = "Failed to save video."
            throw error
        }
    }

    /// Legacy method for backward compatibility - use uploadVideoMetadata with ThumbnailMetadata instead
    @available(*, deprecated, message: "Use uploadVideoMetadata with ThumbnailMetadata parameter")
    func uploadVideoMetadata(
        fileName: String,
        storageURL: String,
        thumbnailURL: String?,
        folderID: String,
        uploadedBy: String,
        uploadedByName: String,
        fileSize: Int64,
        duration: Double?
    ) async throws -> String {
        let thumbnail = thumbnailURL.map { ThumbnailMetadata(standardURL: $0) }
        return try await uploadVideoMetadata(
            fileName: fileName,
            storageURL: storageURL,
            thumbnail: thumbnail,
            folderID: folderID,
            uploadedBy: uploadedBy,
            uploadedByName: uploadedByName,
            fileSize: fileSize,
            duration: duration
        )
    }

    /// Fetches all videos in a shared folder
    func fetchVideos(forFolder folderID: String) async throws -> [FirestoreVideoMetadata] {
        do {
            let snapshot = try await db.collection("videos")
                .whereField("sharedFolderID", isEqualTo: folderID)
                .order(by: "createdAt", descending: true)
                .limit(to: 100)
                .getDocuments()

            let videos = snapshot.documents.compactMap { doc -> FirestoreVideoMetadata? in
                do {
                    var video = try doc.data(as: FirestoreVideoMetadata.self)
                    video.id = doc.documentID
                    return video
                } catch {
                    firestoreLog.warning("Failed to decode FirestoreVideoMetadata from doc \(doc.documentID): \(error.localizedDescription)")
                    return nil
                }
            }

            return videos
        } catch {
            errorMessage = "Failed to load videos."
            throw error
        }
    }

    /// Fetches a single video's metadata by document ID (point-read — 1 read regardless of folder size)
    func fetchVideo(videoID: String) async throws -> FirestoreVideoMetadata? {
        do {
            let doc = try await db.collection("videos").document(videoID).getDocument()
            guard doc.exists else { return nil }
            do {
                var video = try doc.data(as: FirestoreVideoMetadata.self)
                video.id = doc.documentID
                return video
            } catch {
                firestoreLog.warning("Failed to decode FirestoreVideoMetadata from doc \(doc.documentID): \(error.localizedDescription)")
                return nil
            }
        } catch {
            throw error
        }
    }

    /// Deletes a video and its metadata
    func deleteVideo(videoID: String, folderID: String) async throws {
        do {
            // Delete all annotations first (paginated — delete until none remain)
            let annotationsQuery = db.collection("videos")
                .document(videoID)
                .collection("annotations")
            while true {
                let annotationsSnapshot = try await annotationsQuery.limit(to: 400).getDocuments()
                guard !annotationsSnapshot.documents.isEmpty else { break }
                let batch = db.batch()
                annotationsSnapshot.documents.forEach { batch.deleteDocument($0.reference) }
                try await batch.commit()
            }

            // Batch: delete video metadata + decrement folder count atomically
            let batch = db.batch()
            batch.deleteDocument(db.collection("videos").document(videoID))
            batch.updateData([
                "videoCount": FieldValue.increment(Int64(-1)),
                "updatedAt": FieldValue.serverTimestamp()
            ], forDocument: db.collection("sharedFolders").document(folderID))
            try await batch.commit()

        } catch {
            errorMessage = "Failed to delete video."
            throw error
        }
    }

    // MARK: - Helper Methods for Coach Views

    /// Fetches videos for a shared folder (convenience method)
    func fetchVideos(forSharedFolder folderID: String) async throws -> [FirestoreVideoMetadata] {
        return try await fetchVideos(forFolder: folderID)
    }

    // MARK: - Thumbnail Management

    /// Uploads a single thumbnail to Firebase Storage
    /// - Parameters:
    ///   - localURL: Local file URL of the thumbnail image
    ///   - videoFileName: The video file name (to create matching thumbnail name)
    ///   - folderID: Shared folder ID
    ///   - quality: Quality level ("standard" or "high")
    /// - Returns: The download URL for the uploaded thumbnail
    func uploadThumbnail(
        localURL: URL,
        videoFileName: String,
        folderID: String,
        quality: ThumbnailQuality = .standard
    ) async throws -> String {
        // Use VideoCloudManager for actual upload
        let cloudManager = VideoCloudManager.shared

        // Generate appropriate filename based on quality
        let baseFileName = (videoFileName as NSString).deletingPathExtension
        let suffix = quality == .high ? "_thumbnail_hq.jpg" : "_thumbnail.jpg"
        let thumbnailFileName = baseFileName + suffix

        do {
            // Create a temporary reference using the quality-specific filename
            let thumbnailURL = try await cloudManager.uploadThumbnail(
                thumbnailURL: localURL,
                videoFileName: thumbnailFileName,
                folderID: folderID
            )

            return thumbnailURL
        } catch {
            errorMessage = "Failed to upload thumbnail."
            throw error
        }
    }

    /// Uploads multiple thumbnails (standard and high quality) for highlights
    /// - Parameters:
    ///   - standardURL: Local file URL of standard quality thumbnail
    ///   - highQualityURL: Local file URL of high quality thumbnail (optional)
    ///   - videoFileName: The video file name
    ///   - folderID: Shared folder ID
    ///   - timestamp: Time in video where thumbnail was captured
    /// - Returns: Complete ThumbnailMetadata object with all URLs
    func uploadThumbnails(
        standardURL: URL,
        highQualityURL: URL?,
        videoFileName: String,
        folderID: String,
        timestamp: Double? = nil
    ) async throws -> ThumbnailMetadata {
        // Upload standard quality thumbnail
        let standardDownloadURL = try await uploadThumbnail(
            localURL: standardURL,
            videoFileName: videoFileName,
            folderID: folderID,
            quality: .standard
        )

        // Upload high quality thumbnail if provided
        var highQualityDownloadURL: String?
        if let highQualityURL = highQualityURL {
            highQualityDownloadURL = try await uploadThumbnail(
                localURL: highQualityURL,
                videoFileName: videoFileName,
                folderID: folderID,
                quality: .high
            )
        }

        return ThumbnailMetadata(
            standardURL: standardDownloadURL,
            highQualityURL: highQualityDownloadURL,
            timestamp: timestamp
        )
    }

    enum ThumbnailQuality: String {
        case standard = "standard"
        case high = "high"
    }

    /// Creates video metadata with additional context (convenience method)
    func createVideoMetadata(
        folderID: String,
        metadata: [String: Any]
    ) async throws -> String {

        // Allowlist prevents arbitrary fields from being written to Firestore
        let allowedFields: Set<String> = [
            "fileName", "firebaseStorageURL", "uploadedBy", "uploadedByName",
            "sharedFolderID", "fileSize", "duration", "videoType", "isHighlight",
            "thumbnail", "thumbnailURL", "gameOpponent", "gameDate", "practiceDate",
            "notes", "playResult", "athleteName", "seasonID"
        ]
        var safeMetadata = metadata.filter { allowedFields.contains($0.key) }
        safeMetadata["sharedFolderID"] = folderID
        safeMetadata["createdAt"] = FieldValue.serverTimestamp()

        do {
            // Batch: create video doc + increment folder count atomically
            let batch = db.batch()
            let videoRef = db.collection("videos").document()
            batch.setData(safeMetadata, forDocument: videoRef)
            batch.updateData([
                "videoCount": FieldValue.increment(Int64(1)),
                "updatedAt": FieldValue.serverTimestamp()
            ], forDocument: db.collection("sharedFolders").document(folderID))
            try await batch.commit()

            return videoRef.documentID
        } catch {
            errorMessage = "Failed to save video."
            throw error
        }
    }
}
