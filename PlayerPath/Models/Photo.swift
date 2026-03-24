//
//  Photo.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import Foundation
import SwiftData
import os

// MARK: - Photo Model
@Model
final class Photo {
    var id: UUID = UUID()
    var fileName: String = ""
    var filePath: String = ""
    var thumbnailPath: String?
    var caption: String?
    var createdAt: Date?
    var athlete: Athlete?
    var game: Game?
    var practice: Practice?
    var season: Season?

    // MARK: - Firestore / Storage Sync Metadata
    var cloudURL: String?
    var firestoreId: String?
    var needsSync: Bool = false

    init(fileName: String, filePath: String) {
        self.id = UUID()
        self.fileName = fileName
        self.filePath = filePath
        self.createdAt = Date()
    }

    func toFirestoreData(ownerUID: String) -> [String: Any] {
        var data: [String: Any] = [
            "id": id.uuidString,
            "fileName": fileName,
            "athleteId": athlete?.id.uuidString ?? "",
            "uploadedBy": ownerUID,
            "createdAt": createdAt ?? Date(),
            "updatedAt": Date(),
            "isDeleted": false
        ]
        if let caption = caption { data["caption"] = caption }
        if let gameId = game?.id.uuidString { data["gameId"] = gameId }
        if let practiceId = practice?.id.uuidString { data["practiceId"] = practiceId }
        if let seasonId = season?.id.uuidString { data["seasonId"] = seasonId }
        if let cloudURL = cloudURL { data["downloadURL"] = cloudURL }
        return data
    }

    /// Full-size image URL derived from filePath
    var fileURL: URL? {
        URL(fileURLWithPath: filePath)
    }

    /// Thumbnail image URL derived from thumbnailPath
    var thumbnailURL: URL? {
        guard let thumbnailPath else { return nil }
        return URL(fileURLWithPath: thumbnailPath)
    }

    /// Delete photo with all associated files
    @MainActor func delete(in context: ModelContext) {
        // Capture paths before context.delete to avoid accessing deleted SwiftData object
        let capturedFilePath = filePath
        let capturedThumbPath = thumbnailPath

        // Dispatch file I/O to background
        DispatchQueue.global(qos: .utility).async {
            do {
                try FileManager.default.removeItem(atPath: capturedFilePath)
            } catch {
                modelsLog.error("Failed to delete photo file at '\(capturedFilePath)': \(error.localizedDescription)")
            }
            if let thumbPath = capturedThumbPath {
                do {
                    try FileManager.default.removeItem(atPath: thumbPath)
                } catch {
                    modelsLog.error("Failed to delete photo thumbnail at '\(thumbPath)': \(error.localizedDescription)")
                }
            }
        }
        // Delete from cloud storage if uploaded.
        // Capture values before context.delete(self) to avoid accessing a deleted SwiftData object.
        if cloudURL != nil {
            let capturedFileName = self.fileName
            let capturedPhotoId = self.id
            let capturedUser = athlete?.user
            let fileSize: Int64
            do {
                let attrs = try FileManager.default.attributesOfItem(atPath: capturedFilePath)
                fileSize = (attrs[.size] as? Int64) ?? 0
            } catch {
                modelsLog.error("Failed to read photo file size for cloud quota update: \(error.localizedDescription)")
                fileSize = 0
            }
            Task { @MainActor in
                let cloudManager = VideoCloudManager.shared
                do {
                    try await withRetry {
                        try await cloudManager.deleteAthletePhoto(fileName: capturedFileName)
                    }
                    // Only decrement quota after the Storage file is actually deleted
                    if let user = capturedUser {
                        user.cloudStorageUsedBytes = max(0, user.cloudStorageUsedBytes - fileSize)
                    }
                } catch {
                    // All retries exhausted — record as pending deletion so server-side
                    // cleanup can remove the orphaned Storage file later.
                    // Quota is NOT freed — the cleanup function will handle it.
                    do {
                        try await cloudManager.recordPendingPhotoDeletion(photoId: capturedPhotoId, fileName: capturedFileName)
                    } catch {
                        modelsLog.error("Failed to record pending photo deletion for \(capturedPhotoId): \(error.localizedDescription)")
                    }
                }
            }
        }
        // Soft-delete Firestore metadata if previously synced
        if let capturedFirestoreId = firestoreId {
            Task {
                await retryAsync {
                    try await FirestoreManager.shared.deletePhoto(photoId: capturedFirestoreId)
                }
            }
        }
        context.delete(self)
    }
}
