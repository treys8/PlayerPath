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
    var version: Int = 0
    var isDeletedRemotely: Bool = false

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
            "athleteId": athlete?.firestoreId ?? athlete?.id.uuidString ?? "",
            "uploadedBy": ownerUID,
            "createdAt": createdAt ?? Date(),
            "updatedAt": Date(),
            "isDeleted": false
        ]
        if let caption = caption { data["caption"] = caption }
        if let gameId = game?.firestoreId ?? game?.id.uuidString { data["gameId"] = gameId }
        if let practiceId = practice?.firestoreId ?? practice?.id.uuidString { data["practiceId"] = practiceId }
        if let seasonId = season?.firestoreId ?? season?.id.uuidString { data["seasonId"] = seasonId }
        if let cloudURL = cloudURL { data["downloadURL"] = cloudURL }
        return data
    }

    /// Returns metadata fields that can change after initial upload.
    func updatableFirestoreData() -> [String: Any] {
        var data: [String: Any] = [
            "updatedAt": Date()
        ]
        data["caption"] = caption ?? NSNull()
        data["gameId"] = (game?.firestoreId ?? game?.id.uuidString) ?? NSNull()
        data["practiceId"] = (practice?.firestoreId ?? practice?.id.uuidString) ?? NSNull()
        data["seasonId"] = (season?.firestoreId ?? season?.id.uuidString) ?? NSNull()
        return data
    }

    // MARK: - Path Resolution

    @Transient private var _cachedResolvedPath: String?
    @Transient private var _cachedResolvedThumbPath: String?

    /// Resolves `filePath` to an absolute path, handling both legacy absolute paths
    /// and relative paths (relative to Documents directory).
    var resolvedFilePath: String {
        if let cached = _cachedResolvedPath { return cached }
        let resolved = _resolveFilePath()
        _cachedResolvedPath = resolved
        return resolved
    }

    private func _resolveFilePath() -> String {
        if !filePath.hasPrefix("/") {
            guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                return filePath
            }
            return docs.appendingPathComponent(filePath).path
        }
        if FileManager.default.fileExists(atPath: filePath) {
            return filePath
        }
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return filePath
        }
        let recovered = docs.appendingPathComponent("Photos").appendingPathComponent(fileName).path
        if FileManager.default.fileExists(atPath: recovered) {
            return recovered
        }
        return filePath
    }

    /// Resolves `thumbnailPath` to an absolute path. New photos store a path relative
    /// to Documents; legacy rows may hold a stale absolute path from a previous app
    /// container UUID and are recovered by filename under PhotoThumbnails/.
    var resolvedThumbnailPath: String? {
        guard let thumbnailPath else { return nil }
        if let cached = _cachedResolvedThumbPath { return cached }
        let resolved = _resolveThumbnailPath(thumbnailPath)
        _cachedResolvedThumbPath = resolved
        return resolved
    }

    private func _resolveThumbnailPath(_ thumbnailPath: String) -> String {
        if !thumbnailPath.hasPrefix("/") {
            guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                return thumbnailPath
            }
            return docs.appendingPathComponent(thumbnailPath).path
        }
        if FileManager.default.fileExists(atPath: thumbnailPath) {
            return thumbnailPath
        }
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return thumbnailPath
        }
        let fileName = (thumbnailPath as NSString).lastPathComponent
        let recovered = docs.appendingPathComponent("PhotoThumbnails").appendingPathComponent(fileName).path
        if FileManager.default.fileExists(atPath: recovered) {
            return recovered
        }
        return thumbnailPath
    }

    /// Full-size image URL derived from resolved filePath
    var fileURL: URL? {
        URL(fileURLWithPath: resolvedFilePath)
    }

    /// Thumbnail image URL derived from resolved thumbnailPath
    var thumbnailURL: URL? {
        guard let path = resolvedThumbnailPath else { return nil }
        return URL(fileURLWithPath: path)
    }

    var isAvailableOffline: Bool {
        FileManager.default.fileExists(atPath: resolvedFilePath)
    }

    /// Delete photo with all associated files
    @MainActor func delete(in context: ModelContext) {
        // Capture paths and file size before any deletion to avoid races
        let capturedFilePath = resolvedFilePath
        let capturedThumbPath = resolvedThumbnailPath
        let capturedFileSize: Int64
        if cloudURL != nil {
            do {
                let attrs = try FileManager.default.attributesOfItem(atPath: capturedFilePath)
                capturedFileSize = (attrs[.size] as? Int64) ?? 0
            } catch {
                modelsLog.error("Failed to read photo file size for cloud quota update: \(error.localizedDescription)")
                capturedFileSize = 0
            }
        } else {
            capturedFileSize = 0
        }

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
            let fileSize = capturedFileSize
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
