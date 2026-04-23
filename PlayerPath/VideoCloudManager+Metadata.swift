//
//  VideoCloudManager+Metadata.swift
//  PlayerPath
//
//  Firestore video metadata: save, update, sync, mark deleted, real-time listener.
//

import Foundation
import FirebaseStorage
import FirebaseFirestore
import FirebaseAuth
import os

private let videoCloudLog = Logger(subsystem: "com.playerpath.app", category: "VideoCloud")

extension VideoCloudManager {

    /// Saves video metadata to Firestore for cross-device sync
    func saveVideoMetadataToFirestore(_ videoClip: VideoClip, athlete: Athlete, downloadURL: String) async throws {
        // Capture values before async boundary (Sendable compliance)
        let clipId = videoClip.id
        let clipFileName = videoClip.fileName
        let clipIsHighlight = videoClip.isHighlight
        let clipCreatedAt = videoClip.createdAt ?? Date()
        let clipDuration = videoClip.duration
        // Resolve in case the path was stored relative to Documents — downstream
        // file I/O (fileExists + URL(fileURLWithPath:) for upload) requires absolute.
        let clipThumbnailPath = videoClip.resolvedThumbnailPath
        let clipNote = videoClip.note
        let clipPitchSpeed = videoClip.pitchSpeed
        let clipPitchType = videoClip.pitchType
        let playResultType = videoClip.playResult?.type
        let gameId = videoClip.game.map { $0.firestoreId ?? $0.id.uuidString }
        let gameOpponent = videoClip.gameOpponent ?? videoClip.game?.opponent
        let gameDate = videoClip.gameDate ?? videoClip.game?.date
        let practiceDate = videoClip.practiceDate ?? videoClip.practice?.date
        let practiceId = videoClip.practice?.id
        let seasonId = videoClip.season.map { $0.firestoreId ?? $0.id.uuidString }
        let seasonName = videoClip.seasonName ?? videoClip.season?.displayName
        let sourceCoachVideoID = videoClip.sourceCoachVideoID
        let athleteStableId = athlete.firestoreId ?? athlete.id.uuidString
        let athleteName = athlete.name

        // Get file size
        let fileSize = FileManager.default.fileSize(atPath: videoClip.resolvedFilePath)

        let db = Firestore.firestore()

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
            "uploadedBy": ownerUID,
            "uploadStatus": "completed"
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
        if let pitchType = clipPitchType {
            data["pitchType"] = pitchType
        }
        if let sourceCoachVideoID {
            data["sourceCoachVideoID"] = sourceCoachVideoID
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
        try await db.collection(FC.videos).document(clipId.uuidString).setData(data)
    }

    /// Creates a pending Firestore video metadata doc for an athlete personal
    /// upload, BEFORE the Storage upload begins. The doc serves as a tombstone:
    /// if the Storage upload or `markAthleteVideoCompleted` fails, the daily
    /// maintenance Cloud Function sweeps both the doc and any partial Storage
    /// file after 24 hours. Read paths already filter out non-completed docs.
    ///
    /// Uses `clipId.uuidString` as the doc ID so the existing crash-recovery
    /// branch in `UploadQueueManager.processUpload` can detect a pending doc
    /// from a previous app session and resume the upload.
    func createPendingAthleteVideoMetadata(_ videoClip: VideoClip, athlete: Athlete) async throws {
        let clipId = videoClip.id
        let clipFileName = videoClip.fileName
        let clipIsHighlight = videoClip.isHighlight
        let clipCreatedAt = videoClip.createdAt ?? Date()
        let clipDuration = videoClip.duration
        let clipNote = videoClip.note
        let clipPitchSpeed = videoClip.pitchSpeed
        let clipPitchType = videoClip.pitchType
        let playResultType = videoClip.playResult?.type
        let gameId = videoClip.game.map { $0.firestoreId ?? $0.id.uuidString }
        let gameOpponent = videoClip.gameOpponent ?? videoClip.game?.opponent
        let gameDate = videoClip.gameDate ?? videoClip.game?.date
        let practiceDate = videoClip.practiceDate ?? videoClip.practice?.date
        let practiceId = videoClip.practice?.id
        let seasonId = videoClip.season.map { $0.firestoreId ?? $0.id.uuidString }
        let seasonName = videoClip.seasonName ?? videoClip.season?.displayName
        let sourceCoachVideoID = videoClip.sourceCoachVideoID
        let athleteStableId = athlete.firestoreId ?? athlete.id.uuidString
        let athleteName = athlete.name

        let fileSize = FileManager.default.fileSize(atPath: videoClip.resolvedFilePath)

        let db = Firestore.firestore()

        guard let ownerUID = Auth.auth().currentUser?.uid else {
            throw VideoCloudError.uploadFailed("User session expired — please sign in again to upload")
        }

        var data: [String: Any] = [
            "id": clipId.uuidString,
            "athleteId": athleteStableId,
            "athleteName": athleteName,
            "fileName": clipFileName,
            // Empty downloadURL is allowed by firestore.rules:274 for pending docs.
            "downloadURL": "",
            "isHighlight": clipIsHighlight,
            "createdAt": Timestamp(date: clipCreatedAt),
            "updatedAt": Timestamp(date: Date()),
            "fileSize": fileSize,
            "isDeleted": false,
            "uploadedBy": ownerUID,
            "uploadStatus": "pending"
        ]

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
        if let pitchType = clipPitchType {
            data["pitchType"] = pitchType
        }
        if let sourceCoachVideoID {
            data["sourceCoachVideoID"] = sourceCoachVideoID
        }

        try await db.collection(FC.videos).document(clipId.uuidString).setData(data)
    }

    /// Marks a pending athlete video as completed after a successful Storage
    /// upload. Uploads the thumbnail (if a local one exists) and writes the
    /// downloadURL + thumbnailURL onto the existing pending doc.
    func markAthleteVideoCompleted(_ videoClip: VideoClip, athlete: Athlete, downloadURL: String) async throws {
        let clipId = videoClip.id
        let clipFileName = videoClip.fileName
        let clipThumbnailPath = videoClip.resolvedThumbnailPath
        let athleteStableId = athlete.firestoreId ?? athlete.id.uuidString

        // Refresh fileSize in case the local file changed (e.g., re-trim).
        let fileSize = FileManager.default.fileSize(atPath: videoClip.resolvedFilePath)

        var partial: [String: Any] = [
            "downloadURL": downloadURL,
            "uploadStatus": "completed",
            "fileSize": fileSize,
            "updatedAt": Timestamp(date: Date())
        ]

        // Upload thumbnail to Storage if a local one exists, then merge URL.
        if let thumbnailPath = clipThumbnailPath,
           FileManager.default.fileExists(atPath: thumbnailPath) {
            do {
                let thumbnailURL = URL(fileURLWithPath: thumbnailPath)
                let cloudThumbnailURL = try await uploadAthleteVideoThumbnail(
                    thumbnailURL: thumbnailURL,
                    videoFileName: clipFileName,
                    athleteStableId: athleteStableId
                )
                partial["thumbnailURL"] = cloudThumbnailURL
            } catch {
                videoCloudLog.warning("Failed to upload thumbnail for \(clipFileName): \(error.localizedDescription)")
            }
        }

        let db = Firestore.firestore()
        try await db.collection(FC.videos).document(clipId.uuidString).updateData(partial)
    }

    /// Marks a pending athlete video as failed so the daily maintenance sweep
    /// can clean it up promptly. Never throws.
    func markAthleteVideoFailed(clipId: UUID, reason: String?) async {
        let db = Firestore.firestore()
        do {
            try await db.collection(FC.videos).document(clipId.uuidString).updateData([
                "uploadStatus": "failed",
                "failureReason": reason ?? NSNull(),
                "updatedAt": Timestamp(date: Date())
            ])
        } catch {
            videoCloudLog.error("Failed to mark athlete video failed (\(clipId)): \(error.localizedDescription)")
        }
    }

    /// Updates only the note field on an existing video document in Firestore.
    func updateVideoNote(clipId: String, note: String?) async throws {
        let db = Firestore.firestore()
        let value: Any = note ?? NSNull()
        try await db.collection(FC.videos).document(clipId).updateData(["note": value, "updatedAt": Timestamp(date: Date())])
    }

    /// Updates mutable video metadata fields in Firestore (isHighlight, note).
    func updateVideoMetadata(clipId: String, isHighlight: Bool, note: String?, playResultType: PlayResultType?, pitchSpeed: Double?, pitchType: String? = nil, gameId: String?, gameOpponent: String?, gameDate: Date?, seasonId: String?, seasonName: String?, practiceId: String?, practiceDate: Date? = nil) async throws {
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
        data["pitchType"] = pitchType ?? NSNull()
        data["gameId"] = gameId ?? NSNull()
        data["gameOpponent"] = gameOpponent ?? NSNull()
        data["gameDate"] = gameDate.map { Timestamp(date: $0) } ?? NSNull()
        data["seasonId"] = seasonId ?? NSNull()
        data["seasonName"] = seasonName ?? NSNull()
        data["practiceId"] = practiceId ?? NSNull()
        data["practiceDate"] = practiceDate.map { Timestamp(date: $0) } ?? NSNull()
        try await db.collection(FC.videos).document(clipId).updateData(data)
    }

    /// Merges file-level fields (downloadURL, fileSize, duration, thumbnail)
    /// into an existing video Firestore document. Used by the re-trim flow
    /// in `ClipTrimService` — unlike `saveVideoMetadataToFirestore` this uses
    /// `updateData` (merge) so it does NOT clobber annotationCount,
    /// sharedFolderID, notes, tags, or any other fields set elsewhere.
    func updateVideoFileFields(
        clip: VideoClip,
        downloadURL: String,
        fileSize: Int64,
        duration: Double
    ) async throws {
        let clipId = clip.id.uuidString
        let clipFileName = clip.fileName
        let clipThumbnailPath = clip.thumbnailPath
        let athleteStableId = clip.athlete?.firestoreId ?? clip.athlete?.id.uuidString ?? ""
        let clipVersion = clip.version

        // Re-upload the thumbnail first so Firestore points at the new frame.
        var thumbnailURL: String? = nil
        if let thumbnailPath = clipThumbnailPath,
           FileManager.default.fileExists(atPath: thumbnailPath) {
            do {
                thumbnailURL = try await uploadAthleteVideoThumbnail(
                    thumbnailURL: URL(fileURLWithPath: thumbnailPath),
                    videoFileName: clipFileName,
                    athleteStableId: athleteStableId
                )
            } catch {
                // Non-fatal — Firestore keeps the old thumbnail URL.
                videoCloudLog.warning("Re-trim thumbnail upload failed: \(error.localizedDescription)")
            }
        }

        let db = Firestore.firestore()
        var data: [String: Any] = [
            "downloadURL": downloadURL,
            "fileSize": fileSize,
            "duration": duration,
            "version": clipVersion,
            "updatedAt": Timestamp(date: Date())
        ]
        if let thumbnailURL {
            data["thumbnailURL"] = thumbnailURL
            data["thumbnail"] = ["standardURL": thumbnailURL]
        }
        try await db.collection(FC.videos).document(clipId).updateData(data)
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
            let hasResumed = OSAllocatedUnfairLock(initialState: false)
            thumbnailRef.putFile(from: thumbnailURL, metadata: metadata) { _, error in
                if let error = error {
                    let alreadyResumed = hasResumed.withLock { val -> Bool in
                        if val { return true }; val = true; return false
                    }
                    if !alreadyResumed { continuation.resume(throwing: error) }
                    return
                }

                thumbnailRef.downloadURL { url, error in
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
        }
    }

    /// Fetches video metadata from Firestore for cross-device sync
    func syncVideos(for athlete: Athlete) async throws -> [VideoClipMetadata] {
        guard let ownerUID = Auth.auth().currentUser?.uid else {
            throw VideoCloudError.uploadFailed("User session expired — please sign in again to upload")
        }
        let athleteStableId = athlete.firestoreId ?? athlete.id.uuidString
        let db = Firestore.firestore()

        let snapshot = try await db.collection(FC.videos)
            .whereField("uploadedBy", isEqualTo: ownerUID)
            .whereField("athleteId", isEqualTo: athleteStableId)
            .whereField("isDeleted", isEqualTo: false)
            .order(by: "createdAt", descending: true)
            .limit(to: 200)
            .getDocuments()

        let videos = snapshot.documents.compactMap { VideoClipMetadata(from: $0.data()) }

        if snapshot.documents.count == 200 {
            videoCloudLog.warning("syncVideos hit 200-document limit for athlete \(athleteStableId) — older videos may be missing")
        }

        return videos
    }

}
