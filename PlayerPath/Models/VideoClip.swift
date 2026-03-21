//
//  VideoClip.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import Foundation
import SwiftData
import os

@Model
final class VideoClip {
    var id: UUID = UUID()
    var fileName: String = ""
    var filePath: String = ""
    var thumbnailPath: String?     // Path to thumbnail image
    var cloudURL: String?          // Firebase Storage URL
    var isUploaded: Bool = false           // Sync status
    var lastSyncDate: Date?        // Last successful sync
    var createdAt: Date?
    var duration: Double?          // Video duration in seconds
    var pitchSpeed: Double?        // Pitch speed in MPH (optional, radar gun input)
    @Relationship(inverse: \PlayResult.videoClip) var playResult: PlayResult?
    var isHighlight: Bool = false
    var note: String? = nil
    // Denormalized display fields — copied at save time so data survives cross-device sync
    // even if the game/season relationship cannot be re-linked on a new device.
    var gameOpponent: String?
    var gameDate: Date?
    var practiceDate: Date?
    var seasonName: String?
    var game: Game?
    var practice: Practice?
    var athlete: Athlete?
    var season: Season?

    // MARK: - Firestore Sync Metadata (Phase 3)

    /// Firestore document ID for video metadata (not the video file itself)
    var firestoreId: String?

    /// Dirty flag - true when metadata needs uploading to Firestore
    var needsSync: Bool = false

    /// Soft delete flag - true when deleted on another device
    var isDeletedRemotely: Bool = false

    /// Version number for conflict resolution
    var version: Int = 0

    /// Computed sync status for metadata
    var isSynced: Bool {
        needsSync == false && firestoreId != nil
    }

    init(fileName: String, filePath: String) {
        self.id = UUID()
        self.fileName = fileName
        self.filePath = filePath
        self.createdAt = Date()
    }

    /// Converts an absolute path to a path relative to the Documents directory.
    /// If the path is already relative or not under Documents, returns it unchanged.
    static func toRelativePath(_ absolutePath: String) -> String {
        guard absolutePath.hasPrefix("/"),
              let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return absolutePath
        }
        let docsPath = docs.path
        if absolutePath.hasPrefix(docsPath) {
            let relative = String(absolutePath.dropFirst(docsPath.count))
            return relative.hasPrefix("/") ? String(relative.dropFirst()) : relative
        }
        return absolutePath
    }

    // Computed properties for sync status
    var needsUpload: Bool {
        return !isUploaded && cloudURL == nil
    }

    /// Cached result of path resolution. Stable within a single app launch since the
    /// Documents directory URL doesn't change. Eliminates repeated `fileExists` syscalls
    /// that otherwise fire on every cell render in video lists.
    @Transient private var _cachedResolvedPath: String?

    /// Resolves `filePath` to an absolute path, handling both legacy absolute paths
    /// and relative paths (relative to Documents directory). Absolute paths break
    /// when iOS relocates the app sandbox (reinstall, backup restore), so new clips
    /// store relative paths and this property resolves them at read time.
    var resolvedFilePath: String {
        if let cached = _cachedResolvedPath { return cached }
        let resolved = _resolveFilePath()
        _cachedResolvedPath = resolved
        return resolved
    }

    private func _resolveFilePath() -> String {
        // Relative path — resolve against Documents
        if !filePath.hasPrefix("/") {
            guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                return filePath
            }
            return docs.appendingPathComponent(filePath).path
        }
        // Legacy absolute path — use as-is if file exists
        if FileManager.default.fileExists(atPath: filePath) {
            return filePath
        }
        // Absolute path but file missing (sandbox moved) — try resolving from fileName
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return filePath
        }
        let recovered = docs.appendingPathComponent("Clips").appendingPathComponent(fileName).path
        if FileManager.default.fileExists(atPath: recovered) {
            return recovered
        }
        // Return original — caller will handle the missing-file case
        return filePath
    }

    var resolvedFileURL: URL {
        URL(fileURLWithPath: resolvedFilePath)
    }

    var isAvailableOffline: Bool {
        return FileManager.default.fileExists(atPath: resolvedFilePath)
    }

    // MARK: - Firestore Conversion

    /// Converts video metadata to Firestore document
    /// Note: This syncs metadata only - actual video files are in Firebase Storage
    func toFirestoreData() -> [String: Any] {
        var data: [String: Any] = [
            "id": id.uuidString,
            "athleteId": athlete?.id.uuidString ?? "",
            "fileName": fileName,
            "isHighlight": isHighlight,
            "isUploaded": isUploaded,
            "createdAt": createdAt ?? Date(),
            "updatedAt": Date(),
            "version": version,
            "isDeleted": false
        ]

        // Optional fields
        if let gameId = game?.id.uuidString {
            data["gameId"] = gameId
        }
        if let practiceId = practice?.id.uuidString {
            data["practiceId"] = practiceId
        }
        if let practiceDate = practiceDate ?? practice?.date {
            data["practiceDate"] = practiceDate
        }
        if let seasonId = season?.id.uuidString {
            data["seasonId"] = seasonId
        }
        if let cloudURL = cloudURL {
            data["cloudURL"] = cloudURL
        }
        if let playResult = playResult {
            data["playResultType"] = playResult.type.rawValue
        }

        return data
    }

    /// Properly delete video clip with all associated files and data
    func delete(in context: ModelContext) {
        // Capture paths before context.delete to avoid accessing deleted SwiftData object
        let absolutePath = resolvedFilePath
        let capturedThumbPath = thumbnailPath

        // Dispatch file I/O to background — removeItem can take 10-50ms for large videos
        DispatchQueue.global(qos: .utility).async {
            do {
                try FileManager.default.removeItem(atPath: absolutePath)
            } catch {
                modelsLog.error("Failed to delete video file at '\(absolutePath)': \(error.localizedDescription)")
            }
            if let thumbPath = capturedThumbPath {
                do {
                    try FileManager.default.removeItem(atPath: thumbPath)
                } catch {
                    modelsLog.error("Failed to delete thumbnail at '\(thumbPath)': \(error.localizedDescription)")
                }
            }
        }

        // Remove thumbnail from in-memory cache on main actor
        if let thumbPath = capturedThumbPath {
            Task { @MainActor in
                ThumbnailCache.shared.removeThumbnail(at: thumbPath)
            }
        }

        // Delete from cloud storage if uploaded.
        // Capture values before context.delete(self) to avoid accessing a deleted SwiftData object.
        if isUploaded {
            let capturedFileName = self.fileName
            let capturedClipId = self.id
            let capturedUser = athlete?.user
            let fileSize: Int64
            do {
                let attrs = try FileManager.default.attributesOfItem(atPath: resolvedFilePath)
                fileSize = (attrs[.size] as? Int64) ?? 0
            } catch {
                modelsLog.error("Failed to read file size for cloud quota update: \(error.localizedDescription)")
                fileSize = 0
            }
            Task { @MainActor in
                let cloudManager = VideoCloudManager.shared
                do {
                    try await withRetry {
                        try await cloudManager.deleteAthleteVideo(fileName: capturedFileName)
                    }
                    // Only decrement quota after the Storage file is actually deleted
                    if let user = capturedUser {
                        user.cloudStorageUsedBytes = max(0, user.cloudStorageUsedBytes - fileSize)
                    }
                } catch {
                    // All retries exhausted — record as pending deletion so the server-side
                    // cleanup function can remove the orphaned Storage file later.
                    // Quota is NOT freed — the dailyStorageCleanup function will handle it.
                    do {
                        try await cloudManager.recordPendingDeletion(clipId: capturedClipId, fileName: capturedFileName)
                    } catch {
                        modelsLog.error("Failed to record pending deletion for clip \(capturedClipId): \(error.localizedDescription)")
                    }
                }
            }
        }

        // Soft-delete Firestore metadata if previously synced
        if let capturedFirestoreId = firestoreId {
            Task {
                await retryAsync {
                    try await FirestoreManager.shared.deleteVideoClip(videoClipId: capturedFirestoreId)
                }
            }
        }

        // Delete associated play result
        if let playResult = playResult {
            context.delete(playResult)
        }

        // Delete video clip database record
        context.delete(self)
    }
}
