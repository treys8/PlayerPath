//
//  FirestoreManager+CoachPrivateFolders.swift
//  PlayerPath
//
//  Coach private folder operations for FirestoreManager.
//  Coaches record practice videos into a private staging folder,
//  then move selected clips to the shared folder.
//
//  STORAGE DESIGN: Private videos are stored at the same Storage path as
//  shared videos (shared_folders/{sharedFolderID}/{fileName}). The "private"
//  concept is purely a Firestore metadata layer — the video file lives in
//  shared Storage from the start so that when it's "moved" to the shared
//  folder, only the Firestore metadata changes. This avoids needing
//  separate Storage rules or file copies.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import os

private let privateFolderLog = Logger(subsystem: "com.playerpath.app", category: "CoachPrivateFolders")

extension FirestoreManager {

    // MARK: - Private Folder CRUD

    /// Creates or returns a coach's private folder for a given shared folder.
    /// Uses a deterministic document ID (coachID_sharedFolderID) to prevent
    /// duplicate creation across multiple devices.
    func getOrCreatePrivateFolder(
        coachID: String,
        athleteID: String,
        sharedFolderID: String
    ) async throws -> CoachPrivateFolder {
        // Deterministic ID prevents multi-device race condition
        let docID = "\(coachID)_\(sharedFolderID)"
        let docRef = db.collection("coachPrivateFolders").document(docID)

        let doc = try await docRef.getDocument()
        if doc.exists {
            var folder = try doc.data(as: CoachPrivateFolder.self)
            folder.id = doc.documentID
            return folder
        }

        // Create new private folder with deterministic ID
        let folderData: [String: Any] = [
            "coachID": coachID,
            "athleteID": athleteID,
            "sharedFolderID": sharedFolderID,
            "videoCount": 0,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]

        try await docRef.setData(folderData)
        privateFolderLog.info("Created private folder \(docID) for coach \(coachID)")

        var folder = CoachPrivateFolder(
            coachID: coachID,
            athleteID: athleteID,
            sharedFolderID: sharedFolderID,
            videoCount: 0,
            createdAt: Date(),
            updatedAt: Date()
        )
        folder.id = docID
        return folder
    }

    /// Fetches all private videos in a coach's private folder, ordered by creation date.
    /// The `uploadedBy` filter is required to satisfy the Firestore security rule
    /// which gates reads on `resource.data.uploadedBy == request.auth.uid`.
    func fetchPrivateVideos(privateFolderID: String, coachID: String? = nil) async throws -> [CoachPrivateVideo] {
        var query = db.collection("coachPrivateVideos")
            .whereField("privateFolderID", isEqualTo: privateFolderID)
        // Add uploadedBy filter to satisfy security rules (required for queries)
        if let coachID {
            query = query.whereField("uploadedBy", isEqualTo: coachID)
        } else if let uid = Auth.auth().currentUser?.uid {
            query = query.whereField("uploadedBy", isEqualTo: uid)
        }
        let snapshot = try await query
            .order(by: "createdAt", descending: true)
            .limit(to: 100)
            .getDocuments()

        return snapshot.documents.compactMap { doc -> CoachPrivateVideo? in
            do {
                var video = try doc.data(as: CoachPrivateVideo.self)
                video.id = doc.documentID
                return video
            } catch {
                privateFolderLog.warning("Failed to decode CoachPrivateVideo from doc \(doc.documentID): \(error.localizedDescription)")
                return nil
            }
        }
    }

    /// Saves a newly recorded video's metadata to the coach's private folder.
    /// The video file is already in Firebase Storage at shared_folders/{sharedFolderID}/{fileName}.
    func createPrivateVideo(
        privateFolderID: String,
        fileName: String,
        storageURL: String,
        uploadedBy: String,
        uploadedByName: String,
        fileSize: Int64,
        duration: Double?,
        thumbnailURL: String?,
        notes: String?
    ) async throws -> String {
        var videoData: [String: Any] = [
            "privateFolderID": privateFolderID,
            "fileName": fileName,
            "firebaseStorageURL": storageURL,
            "uploadedBy": uploadedBy,
            "uploadedByName": uploadedByName,
            "createdAt": FieldValue.serverTimestamp(),
            "fileSize": fileSize
        ]
        if let duration { videoData["duration"] = duration }
        if let thumbnailURL { videoData["thumbnailURL"] = thumbnailURL }
        if let notes, !notes.isEmpty { videoData["notes"] = notes }

        // Batch: create video doc + increment private folder count
        let batch = db.batch()
        let videoRef = db.collection("coachPrivateVideos").document()
        batch.setData(videoData, forDocument: videoRef)
        batch.updateData([
            "videoCount": FieldValue.increment(Int64(1)),
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: db.collection("coachPrivateFolders").document(privateFolderID))
        try await batch.commit()

        privateFolderLog.info("Created private video \(videoRef.documentID) in folder \(privateFolderID)")
        return videoRef.documentID
    }

    /// Moves a video from the coach's private folder to the shared folder.
    /// The Storage file stays at the same URL — only Firestore metadata changes.
    func moveVideoToSharedFolder(
        privateVideoID: String,
        privateFolderID: String,
        sharedFolderID: String,
        coachID: String,
        coachName: String,
        tags: [String] = [],
        drillType: String? = nil
    ) async throws {
        // 1. Read the private video metadata
        let privateDoc = try await db.collection("coachPrivateVideos").document(privateVideoID).getDocument()
        guard let privateData = privateDoc.data() else {
            throw NSError(domain: "FirestoreManager", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Private video not found."])
        }

        let fileName = privateData["fileName"] as? String ?? ""
        let storageURL = privateData["firebaseStorageURL"] as? String ?? ""
        let fileSize = privateData["fileSize"] as? Int64 ?? 0
        let duration = privateData["duration"] as? Double
        let notes = privateData["notes"] as? String
        let thumbnailURL = privateData["thumbnailURL"] as? String

        // 2. Batch: create shared video + increment shared folder count
        //         + delete private video + decrement private folder count
        let batch = db.batch()

        // Create in shared videos collection
        let sharedVideoRef = db.collection("videos").document()
        var sharedVideoData: [String: Any] = [
            "fileName": fileName,
            "firebaseStorageURL": storageURL,
            "uploadedBy": coachID,
            "uploadedByName": coachName,
            "uploadedByType": "coach",
            "sharedFolderID": sharedFolderID,
            "createdAt": FieldValue.serverTimestamp(),
            "fileSize": fileSize,
            "videoType": "practice"
        ]
        if let duration { sharedVideoData["duration"] = duration }
        if let notes { sharedVideoData["notes"] = notes }
        if !tags.isEmpty { sharedVideoData["tags"] = tags }
        if let drillType { sharedVideoData["drillType"] = drillType }
        if let thumbnailURL {
            sharedVideoData["thumbnailURL"] = thumbnailURL
            sharedVideoData["thumbnail"] = ["standardURL": thumbnailURL]
        }
        batch.setData(sharedVideoData, forDocument: sharedVideoRef)

        // Increment shared folder videoCount
        batch.updateData([
            "videoCount": FieldValue.increment(Int64(1)),
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: db.collection("sharedFolders").document(sharedFolderID))

        // Delete from private videos
        batch.deleteDocument(db.collection("coachPrivateVideos").document(privateVideoID))

        // Decrement private folder videoCount
        batch.updateData([
            "videoCount": FieldValue.increment(Int64(-1)),
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: db.collection("coachPrivateFolders").document(privateFolderID))

        try await batch.commit()
        privateFolderLog.info("Moved video \(privateVideoID) from private folder \(privateFolderID) to shared folder \(sharedFolderID)")
    }

    /// Deletes a video from the coach's private folder (both Storage file and Firestore metadata).
    /// The Storage file is at shared_folders/{sharedFolderID}/{fileName}.
    func deletePrivateVideo(videoID: String, privateFolderID: String, sharedFolderID: String, fileName: String) async throws {
        // Delete from Storage (stored under shared_folders path)
        do {
            try await VideoCloudManager.shared.deleteVideo(fileName: fileName, folderID: sharedFolderID)
        } catch {
            privateFolderLog.warning("Failed to delete private video storage file \(fileName): \(error.localizedDescription)")
            // Continue with metadata cleanup — file may not exist if upload failed
        }

        // Batch: delete metadata + decrement count
        let batch = db.batch()
        batch.deleteDocument(db.collection("coachPrivateVideos").document(videoID))
        batch.updateData([
            "videoCount": FieldValue.increment(Int64(-1)),
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: db.collection("coachPrivateFolders").document(privateFolderID))
        try await batch.commit()

        privateFolderLog.info("Deleted private video \(videoID)")
    }
}
