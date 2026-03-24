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
        let clipThumbnailPath = videoClip.thumbnailPath
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
        if let pitchType = clipPitchType {
            data["pitchType"] = pitchType
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

            let metadata = VideoClipMetadata(
                id: id,
                fileName: fileName,
                downloadURL: downloadURL,
                createdAt: createdAt,
                updatedAt: updatedAt,
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
                pitchType: data["pitchType"] as? String,
                duration: data["duration"] as? Double,
                athleteName: athleteName,
                fileSize: data["fileSize"] as? Int64 ?? 0,
                thumbnailURL: data["thumbnailURL"] as? String,
                isDeleted: data["isDeleted"] as? Bool ?? false
            )

            videos.append(metadata)
        }

        return videos
    }

    /// Marks a video as deleted in Firestore (soft delete for sync)
    func markVideoDeletedInFirestore(_ clipId: UUID) async throws {
        let db = Firestore.firestore()

        try await db.collection(FC.videos).document(clipId.uuidString).updateData([
            "isDeleted": true,
            "deletedAt": Timestamp(date: Date())
        ])
    }

    /// Sets up a real-time listener for new videos from other devices
    func listenForNewVideos(
        for athlete: Athlete,
        onNewVideo: @escaping (VideoClipMetadata) -> Void
    ) -> ListenerRegistration {
        let athleteStableId = athlete.firestoreId ?? athlete.id.uuidString
        let db = Firestore.firestore()
        guard let ownerUID = Auth.auth().currentUser?.uid else {
            return db.collection(FC.videos).limit(to: 0).addSnapshotListener { _, _ in }
        }

        let listener = db.collection(FC.videos)
            .whereField("uploadedBy", isEqualTo: ownerUID)
            .whereField("athleteId", isEqualTo: athleteStableId)
            .whereField("isDeleted", isEqualTo: false)
            .limit(to: 200)
            .addSnapshotListener { snapshot, error in
                guard let snapshot = snapshot else {
                    return
                }

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
                        pitchType: data["pitchType"] as? String,
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
}
