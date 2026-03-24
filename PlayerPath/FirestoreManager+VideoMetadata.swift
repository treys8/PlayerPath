//
//  FirestoreManager+VideoMetadata.swift
//  PlayerPath
//
//  Video metadata operations for FirestoreManager
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage
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
        practiceContext: PracticeContext? = nil,
        uploadedByType: UploadedByType? = nil,
        visibility: String = "shared",
        sessionID: String? = nil,
        playResult: String? = nil,
        pitchSpeed: Double? = nil,
        pitchType: String? = nil,
        seasonName: String? = nil,
        athleteName: String? = nil,
        isHighlight: Bool? = nil
    ) async throws -> String {
        var videoData: [String: Any] = [
            "fileName": fileName,
            "firebaseStorageURL": storageURL,
            "uploadedBy": uploadedBy,
            "uploadedByName": uploadedByName,
            "sharedFolderID": folderID,
            "createdAt": FieldValue.serverTimestamp(),
            "fileSize": fileSize,
            "videoType": videoType,
            "isHighlight": isHighlight ?? (videoType == "highlight")
        ]
        if let duration {
            videoData["duration"] = duration
        }
        if let uploadedByType {
            videoData["uploadedByType"] = uploadedByType.rawValue
        }
        videoData["visibility"] = visibility
        if let sessionID {
            videoData["sessionID"] = sessionID
        }
        if let playResult {
            videoData["playResult"] = playResult
        }
        if let pitchSpeed {
            videoData["pitchSpeed"] = pitchSpeed
        }
        if let pitchType {
            videoData["pitchType"] = pitchType
        }
        if let seasonName {
            videoData["seasonID"] = seasonName
        }
        if let athleteName {
            videoData["athleteName"] = athleteName
        }

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
            let videoRef = db.collection(FC.videos).document()

            if visibility == "private" {
                // Private video: create doc only, don't touch folder count
                try await videoRef.setData(videoData)
            } else {
                // Shared video: batch create doc + increment folder count
                let batch = db.batch()
                batch.setData(videoData, forDocument: videoRef)
                batch.updateData([
                    "videoCount": FieldValue.increment(Int64(1)),
                    "updatedAt": FieldValue.serverTimestamp()
                ], forDocument: db.collection(FC.sharedFolders).document(folderID))
                try await batch.commit()
            }

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

    /// Fetches all videos in a shared folder, filtering out private videos from other users
    func fetchVideos(forFolder folderID: String) async throws -> [FirestoreVideoMetadata] {
        do {
            let snapshot = try await db.collection(FC.videos)
                .whereField("sharedFolderID", isEqualTo: folderID)
                .order(by: "createdAt", descending: true)
                .limit(to: 100)
                .getDocuments()

            let currentUID = Auth.auth().currentUser?.uid
            let videos = snapshot.documents.compactMap { doc -> FirestoreVideoMetadata? in
                do {
                    var video = try doc.data(as: FirestoreVideoMetadata.self)
                    video.id = doc.documentID
                    // Hide private videos from other users
                    if video.visibility == "private" && video.uploadedBy != currentUID {
                        return nil
                    }
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
            let doc = try await db.collection(FC.videos).document(videoID).getDocument()
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

    /// Deletes all subcollections (annotations, comments, drillCards) for a video.
    /// Paginated to handle large subcollections.
    func deleteVideoSubcollections(videoID: String) async {
        let videoRef = db.collection(FC.videos).document(videoID)
        let subcollections = [FC.annotations, "comments", "drillCards"]

        for subcollection in subcollections {
            let query = videoRef.collection(subcollection)
            do {
                while true {
                    let snapshot = try await query.limit(to: 400).getDocuments()
                    guard !snapshot.documents.isEmpty else { break }
                    let batch = db.batch()
                    snapshot.documents.forEach { batch.deleteDocument($0.reference) }
                    try await batch.commit()
                }
            } catch {
                firestoreLog.warning("Failed to clean up \(subcollection) for video \(videoID): \(error.localizedDescription)")
            }
        }
    }

    /// Deletes a video and its metadata
    func deleteVideo(videoID: String, folderID: String) async throws {
        do {
            // Delete all subcollections (annotations, comments, drillCards)
            await deleteVideoSubcollections(videoID: videoID)

            // Batch: delete video metadata + decrement folder count atomically
            let batch = db.batch()
            batch.deleteDocument(db.collection(FC.videos).document(videoID))
            batch.updateData([
                "videoCount": FieldValue.increment(Int64(-1)),
                "updatedAt": FieldValue.serverTimestamp()
            ], forDocument: db.collection(FC.sharedFolders).document(folderID))
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

        // Pass the original video filename — VideoCloudManager adds the _thumbnail suffix
        // For high quality, we need a distinct name, so we modify the video filename
        let uploadFileName: String
        if quality == .high {
            let baseName = (videoFileName as NSString).deletingPathExtension
            let ext = (videoFileName as NSString).pathExtension
            uploadFileName = baseName + "_hq." + ext
        } else {
            uploadFileName = videoFileName
        }

        do {
            let thumbnailURL = try await cloudManager.uploadThumbnail(
                thumbnailURL: localURL,
                videoFileName: uploadFileName,
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
            "instructionDate", "notes", "playResult", "athleteName", "seasonID",
            "uploadedByType", "visibility"
        ]
        var safeMetadata = metadata.filter { allowedFields.contains($0.key) }
        safeMetadata["sharedFolderID"] = folderID
        safeMetadata["createdAt"] = FieldValue.serverTimestamp()

        do {
            // Batch: create video doc + increment folder count atomically
            let batch = db.batch()
            let videoRef = db.collection(FC.videos).document()
            batch.setData(safeMetadata, forDocument: videoRef)
            batch.updateData([
                "videoCount": FieldValue.increment(Int64(1)),
                "updatedAt": FieldValue.serverTimestamp()
            ], forDocument: db.collection(FC.sharedFolders).document(folderID))
            try await batch.commit()

            return videoRef.documentID
        } catch {
            errorMessage = "Failed to save video."
            throw error
        }
    }

    // MARK: - Session Videos

    /// Fetches all videos for a given session, ordered by creation time.
    /// Includes `uploadedBy` filter so the query satisfies Firestore security rules
    /// (which require `uploadedBy == auth.uid` for video reads).
    func fetchVideosBySession(sessionID: String) async throws -> [FirestoreVideoMetadata] {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "PlayerPath", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        let snapshot = try await db.collection(FC.videos)
            .whereField("sessionID", isEqualTo: sessionID)
            .whereField("uploadedBy", isEqualTo: uid)
            .order(by: "createdAt", descending: false)
            .limit(to: 200)
            .getDocuments()

        return snapshot.documents.compactMap { doc in
            do {
                var video = try doc.data(as: FirestoreVideoMetadata.self)
                video.id = doc.documentID
                return video
            } catch {
                firestoreLog.warning("Failed to decode video \(doc.documentID): \(error.localizedDescription)")
                return nil
            }
        }
    }

    // MARK: - Coach Private Videos

    /// Fetches private coach videos, optionally filtered by shared folder.
    func fetchCoachPrivateVideos(coachID: String, sharedFolderID: String? = nil) async throws -> [FirestoreVideoMetadata] {
        var query = db.collection(FC.videos)
            .whereField("uploadedBy", isEqualTo: coachID)
            .whereField("visibility", isEqualTo: "private")

        if let sharedFolderID {
            query = query.whereField("sharedFolderID", isEqualTo: sharedFolderID)
        }

        let snapshot = try await query
            .order(by: "createdAt", descending: true)
            .limit(to: 100)
            .getDocuments()

        return snapshot.documents.compactMap { doc in
            do {
                var video = try doc.data(as: FirestoreVideoMetadata.self)
                video.id = doc.documentID
                return video
            } catch {
                firestoreLog.warning("Failed to decode FirestoreVideoMetadata from doc \(doc.documentID): \(error.localizedDescription)")
                return nil
            }
        }
    }

    /// Publishes a private video to the shared folder (changes visibility + increments folder count).
    func publishPrivateVideo(
        videoID: String,
        sharedFolderID: String,
        notes: String? = nil,
        tags: [String]? = nil,
        drillType: String? = nil
    ) async throws {
        let batch = db.batch()

        var updateData: [String: Any] = [
            "visibility": "shared",
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let notes, !notes.isEmpty { updateData["notes"] = notes }
        if let tags, !tags.isEmpty { updateData["tags"] = tags }
        if let drillType { updateData["drillType"] = drillType }

        batch.updateData(updateData, forDocument: db.collection(FC.videos).document(videoID))
        batch.updateData([
            "videoCount": FieldValue.increment(Int64(1)),
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: db.collection(FC.sharedFolders).document(sharedFolderID))

        try await batch.commit()
    }

    /// Deletes a private coach video (Firestore doc + Storage file + thumbnail).
    func deleteCoachPrivateVideo(videoID: String, sharedFolderID: String, fileName: String) async throws {
        // Delete all subcollections (annotations, comments, drillCards)
        await deleteVideoSubcollections(videoID: videoID)

        // Delete Storage file
        do {
            try await VideoCloudManager.shared.deleteVideo(fileName: fileName, folderID: sharedFolderID)
        } catch {
            firestoreLog.warning("Failed to delete private video storage file \(fileName): \(error.localizedDescription)")
        }

        // Delete Storage thumbnail
        do {
            let thumbName = (fileName as NSString).deletingPathExtension + "_thumbnail.jpg"
            let thumbRef = Storage.storage().reference().child("shared_folders/\(sharedFolderID)/thumbnails/\(thumbName)")
            try await thumbRef.delete()
        } catch {
            firestoreLog.warning("Failed to delete private video thumbnail: \(error.localizedDescription)")
        }

        // Delete Firestore doc (no folder count decrement — private videos aren't counted)
        try await db.collection(FC.videos).document(videoID).delete()
    }

    // MARK: - Video Tags

    /// Updates tags and drill type on a video
    func updateVideoTags(videoID: String, tags: [String], drillType: String?) async throws {
        var data: [String: Any] = [
            "tags": tags
        ]
        if let drillType {
            data["drillType"] = drillType
        } else {
            data["drillType"] = FieldValue.delete()
        }

        try await db.collection(FC.videos).document(videoID).updateData(data)
    }
}
