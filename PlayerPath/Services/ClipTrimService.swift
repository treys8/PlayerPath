//
//  ClipTrimService.swift
//  PlayerPath
//
//  Persists a re-trim of an already-saved VideoClip: overwrites the local
//  file, regenerates the thumbnail, re-uploads to Firebase Storage, and
//  merges the new duration/fileSize/thumbnail into Firestore. Leaves
//  annotations, comments, and play-result metadata untouched.
//

import Foundation
import SwiftData
import AVFoundation
import os

private let clipTrimLog = Logger(subsystem: "com.playerpath.app", category: "ClipTrim")

@MainActor
enum ClipTrimService {

    enum TrimError: LocalizedError {
        case clipNotUploaded
        case uploadInProgress
        case missingAthlete
        case quotaExceeded(needed: Int64, available: Int64)
        case fileReplaceFailed(underlying: Error)
        case durationLoadFailed(underlying: Error)
        case thumbnailGenerationFailed(underlying: Error)
        case cloudUploadFailed(underlying: Error)
        case metadataUpdateFailed(underlying: Error)
        case saveFailed(underlying: Error)

        var errorDescription: String? {
            switch self {
            case .clipNotUploaded:
                return "This clip hasn't finished uploading yet. Please wait for the upload to complete before trimming."
            case .uploadInProgress:
                return "An upload is in progress for this clip. Please try again in a moment."
            case .missingAthlete:
                return "Unable to identify the athlete for this clip."
            case .quotaExceeded(let needed, let available):
                let neededMB = Double(needed) / 1_048_576
                let availableMB = Double(available) / 1_048_576
                return String(format: "Not enough cloud storage — needs %.1f MB more, %.1f MB available.", neededMB, availableMB)
            case .fileReplaceFailed(let underlying):
                return "Couldn't replace the clip file: \(underlying.localizedDescription)"
            case .durationLoadFailed(let underlying):
                return "Couldn't read the trimmed video: \(underlying.localizedDescription)"
            case .thumbnailGenerationFailed(let underlying):
                return "Couldn't update the thumbnail: \(underlying.localizedDescription)"
            case .cloudUploadFailed(let underlying):
                return "Cloud upload failed: \(underlying.localizedDescription)"
            case .metadataUpdateFailed(let underlying):
                return "Couldn't sync the changes: \(underlying.localizedDescription)"
            case .saveFailed(let underlying):
                return "Couldn't save the changes locally: \(underlying.localizedDescription)"
            }
        }
    }

    struct Progress {
        enum Stage: String {
            case replacingFile = "Replacing file"
            case regeneratingThumbnail = "Updating thumbnail"
            case uploadingVideo = "Uploading"
            case syncing = "Syncing"
            case done = "Done"
        }
        let stage: Stage
    }

    /// Applies a trimmed video to an existing, already-uploaded `VideoClip`.
    /// Moves `trimmedSourceURL` into place at the clip's existing local path,
    /// regenerates the thumbnail, re-uploads to Firebase Storage (overwriting
    /// at the stable `athlete_videos/{UID}/{fileName}` path), and merges the
    /// new duration/fileSize/thumbnail into Firestore. Adjusts the user's
    /// cloud storage quota by the file-size delta.
    ///
    /// - Parameters:
    ///   - clip: The saved clip to update. Must have `isUploaded == true`.
    ///   - trimmedSourceURL: URL of the trimmed temp file (from `VideoTrimExporter.export`).
    ///   - athlete: The owning athlete (needed for quota + upload attribution).
    ///   - context: SwiftData model context for saves.
    ///   - onProgress: Called on the main actor as the pipeline advances.
    static func applyTrim(
        to clip: VideoClip,
        trimmedSourceURL: URL,
        athlete: Athlete,
        context: ModelContext,
        onProgress: @MainActor @escaping (Progress) -> Void
    ) async throws {
        // === Preconditions ===
        guard clip.isUploaded, clip.cloudURL != nil else {
            throw TrimError.clipNotUploaded
        }
        if VideoCloudManager.shared.isUploading[clip.id] == true {
            throw TrimError.uploadInProgress
        }
        guard let user = athlete.user else {
            throw TrimError.missingAthlete
        }

        let oldLocalURL = URL(fileURLWithPath: clip.resolvedFilePath)
        let oldFileSize: Int64 = {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: oldLocalURL.path),
                  let size = attrs[.size] as? Int64 else { return 0 }
            return size
        }()

        // === Load new file metadata ===
        onProgress(Progress(stage: .replacingFile))
        let newFileSize: Int64 = {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: trimmedSourceURL.path),
                  let size = attrs[.size] as? Int64 else { return 0 }
            return size
        }()
        let newDuration: Double
        do {
            let newAsset = AVURLAsset(url: trimmedSourceURL)
            let cmDuration = try await newAsset.load(.duration)
            newDuration = CMTimeGetSeconds(cmDuration)
        } catch {
            throw TrimError.durationLoadFailed(underlying: error)
        }

        // === Quota pre-check (only if growing — trim usually shrinks) ===
        if newFileSize > oldFileSize {
            let delta = newFileSize - oldFileSize
            let tier = StoreKitManager.shared.currentTier
            let limitBytes = Int64(tier.storageLimitGB) * StorageConstants.bytesPerGB
            if user.cloudStorageUsedBytes + delta > limitBytes {
                let available = max(0, limitBytes - user.cloudStorageUsedBytes)
                throw TrimError.quotaExceeded(needed: delta, available: available)
            }
        }

        // === Replace local file atomically ===
        // replaceItemAt deletes the source after copying, consuming the
        // trimmed temp file in one call.
        do {
            _ = try FileManager.default.replaceItemAt(oldLocalURL, withItemAt: trimmedSourceURL)
        } catch {
            throw TrimError.fileReplaceFailed(underlying: error)
        }

        // Clear cached resolved path so late consumers re-verify the file.
        clip._invalidateResolvedPathCache()

        // === Regenerate thumbnail ===
        onProgress(Progress(stage: .regeneratingThumbnail))
        let persistence = ClipPersistenceService()
        let newThumbnailPath: String
        do {
            newThumbnailPath = try await persistence.generateThumbnail(for: oldLocalURL)
        } catch {
            clipTrimLog.warning("Thumbnail regeneration failed: \(error.localizedDescription)")
            throw TrimError.thumbnailGenerationFailed(underlying: error)
        }

        // `generateThumbnail` writes to a path derived from the video fileName,
        // so the path equals the existing `clip.thumbnailPath` when fileName is
        // stable (which it is during re-trim). Invalidate the in-memory cache
        // so existing views reload the new bitmap.
        ThumbnailCache.shared.removeThumbnail(at: newThumbnailPath)

        // === Update SwiftData (Phase 1 — local changes) ===
        clip.duration = newDuration
        clip.thumbnailPath = newThumbnailPath
        clip.version += 1
        clip.needsSync = true
        clip.lastSyncDate = nil
        do {
            try context.save()
        } catch {
            throw TrimError.saveFailed(underlying: error)
        }

        // === Re-upload video (overwrites at athlete_videos/{UID}/{fileName}) ===
        // Before calling uploadVideo, subtract the old file's bytes from the
        // user's quota. `VideoCloudManager.uploadVideo` does its own pre-check
        // (currentUsed + newSize > limit); leaving the old bytes in place
        // would double-count and could spuriously reject shrinking re-trims
        // for users near their quota cap. If upload fails we restore them.
        user.cloudStorageUsedBytes = max(0, user.cloudStorageUsedBytes - oldFileSize)

        onProgress(Progress(stage: .uploadingVideo))
        let downloadURL: String
        do {
            downloadURL = try await VideoCloudManager.shared.uploadVideo(clip, athlete: athlete)
        } catch {
            // Roll back the temporary decrement so quota is accurate again.
            user.cloudStorageUsedBytes += oldFileSize
            throw TrimError.cloudUploadFailed(underlying: error)
        }
        // Upload succeeded — add the new file's bytes to quota.
        user.cloudStorageUsedBytes += newFileSize
        clip.cloudURL = downloadURL

        // Persist `cloudURL` and quota now, before attempting the Firestore
        // metadata update. Firebase Storage regenerates the download token
        // on overwrite, so the old `cloudURL` points at an invalid URL now.
        // If we didn't save here and the Firestore step (or a crash) aborted
        // the flow, the clip would be left with a stale cloudURL in SwiftData,
        // rendering it unplayable from the cloud until another successful
        // re-trim. `needsSync` remains true so a later sync cycle will retry.
        do {
            try context.save()
        } catch {
            throw TrimError.saveFailed(underlying: error)
        }

        // === Update Firestore (merge duration/fileSize/thumbnail) ===
        onProgress(Progress(stage: .syncing))
        do {
            try await VideoCloudManager.shared.updateVideoFileFields(
                clip: clip,
                downloadURL: downloadURL,
                fileSize: newFileSize,
                duration: newDuration
            )
        } catch {
            throw TrimError.metadataUpdateFailed(underlying: error)
        }

        // === Final save ===
        clip.needsSync = false
        clip.lastSyncDate = Date()
        do {
            try context.save()
        } catch {
            throw TrimError.saveFailed(underlying: error)
        }

        onProgress(Progress(stage: .done))
    }
}
