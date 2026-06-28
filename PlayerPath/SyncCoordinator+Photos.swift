import Foundation
import SwiftData
import FirebaseAuth
import UIKit
import os

// `nonisolated` so the logger can be used from the `Task.detached` thumbnail-encoding
// closure below without tripping Swift 6 main-actor isolation. Logger is Sendable.
nonisolated private let syncLog = Logger(subsystem: "com.playerpath.app", category: "Sync")

extension SyncCoordinator {

    // MARK: - Photos Sync

    func syncPhotos(for user: User) async throws {
        guard let context = modelContext else { return }
        guard let ownerUID = Auth.auth().currentUser?.uid else { return }

        let athletes = user.athletes ?? []

        var syncedPhotos: [Photo] = []
        // Photo files to download, collected across all athletes and drained with
        // bounded concurrency after the save (see below). Only Sendable values.
        var pendingPhotoDownloads: [(photoID: UUID, url: String, path: String)] = []

        // Re-home support (legacy-split migration): a photo moved to another profile
        // must not be seen as deleted (its local file would be destroyed) when we
        // process its old owner. Accumulate the FULL remote id set across all athletes
        // for one global delete pass after the loop, and map every local photo by
        // firestoreId so a re-homed photo is repointed to its new owner, not duplicated.
        var globalRemotePhotoIds = Set<String>()
        let globalLocalPhotosByFirestoreId = Dictionary(
            athletes.flatMap { $0.photos ?? [] }.compactMap { p in p.firestoreId.map { ($0, p) } },
            uniquingKeysWith: { existing, _ in existing }
        )

        for athlete in athletes {
            // Skip athletes whose parent record hasn't synced yet. Keying photos on
            // the local UUID (the old `?? athlete.id.uuidString` fallback) silos them
            // per device and risks ghost-double-athletes when the same logical athlete
            // exists under a different firestoreId on the server. Respect parent-sync
            // ordering, exactly as the Games/Seasons upload paths do.
            guard let athleteStableId = athlete.firestoreId else { continue }
            let photos = athlete.photos ?? []

            // Upload new photos that haven't been synced
            for photo in photos where photo.cloudURL == nil && photo.needsSync {
                let resolvedPath = photo.resolvedFilePath
                guard FileManager.default.fileExists(atPath: resolvedPath) else { continue }
                // Enforce storage limit before uploading (use live StoreKit tier)
                let fileSize: Int64
                do {
                    let attrs = try FileManager.default.attributesOfItem(atPath: resolvedPath)
                    fileSize = (attrs[.size] as? Int64) ?? 0
                } catch {
                    syncLog.error("Failed to read photo file size at '\(resolvedPath)': \(error.localizedDescription)")
                    continue
                }
                let tier = SubscriptionGate.effectiveAthleteTier
                let limitBytes = Int64(tier.storageLimitGB) * StorageConstants.bytesPerGB
                guard user.cloudStorageUsedBytes + fileSize <= limitBytes else {
                    continue
                }
                do {
                    let cloudURL = try await VideoCloudManager.shared.uploadPhoto(
                        at: URL(fileURLWithPath: resolvedPath),
                        ownerUID: ownerUID
                    )
                    photo.cloudURL = cloudURL
                    do {
                        let firestoreId = try await FirestoreManager.shared.createPhoto(
                            data: photo.toFirestoreData(ownerUID: ownerUID)
                        )
                        photo.firestoreId = firestoreId
                    } catch {
                        // Firestore write failed after Storage upload — clean up orphaned file
                        syncLog.error("Firestore photo create failed, cleaning up Storage: \(error.localizedDescription)")
                        let capturedFileName = photo.fileName
                        Task {
                            await retryAsync {
                                try await VideoCloudManager.shared.deleteAthletePhoto(fileName: capturedFileName)
                            }
                        }
                        photo.cloudURL = nil
                        throw error
                    }
                    photo.needsSync = false
                    if let uploadedSize = (try? FileManager.default.attributesOfItem(atPath: resolvedPath)[.size] as? Int64) {
                        user.cloudStorageUsedBytes += uploadedSize
                    } else {
                        syncLog.warning("Could not read uploaded photo file size for storage tracking")
                    }
                    // Persist cloudURL + firestoreId (+ quota) IMMEDIATELY. If the
                    // batch save at the end of syncPhotos later fails, we must not
                    // lose the fact that this photo is already in Storage + Firestore
                    // — otherwise the next sync sees cloudURL == nil and re-uploads,
                    // leaking the first blob AND double-charging quota. Mirrors the
                    // firestoreId-immediate-save pattern in +Coaches / +Athletes.
                    ErrorHandlerService.shared.saveContext(context, caller: "SyncCoordinator.syncPhotos.uploaded")
                    syncedPhotos.append(photo)
                } catch {
                    syncLog.error("Failed to sync photo: \(error.localizedDescription)")
                }
            }

            // Update metadata for photos that have been edited locally
            let updatedPhotos = photos.filter { $0.needsSync && $0.firestoreId != nil && $0.cloudURL != nil }
            for photo in updatedPhotos {
                guard let firestoreId = photo.firestoreId else { continue }
                do {
                    try await FirestoreManager.shared.updatePhoto(
                        photoId: firestoreId,
                        data: photo.updatableFirestoreData()
                    )
                    photo.needsSync = false
                    syncedPhotos.append(photo)
                } catch {
                    syncLog.error("Failed to update photo metadata in Firestore: \(error.localizedDescription)")
                }
            }

            // Download photos that exist remotely but not locally
            let remotePhotos = try await FirestoreManager.shared.fetchPhotos(
                uploadedBy: ownerUID,
                athleteId: athleteStableId
            )
            for r in remotePhotos { if let id = r.id { globalRemotePhotoIds.insert(id) } }
            let localPhotoIds = Set(photos.compactMap { $0.firestoreId })
            let localPhotosByFirestoreId = Dictionary(
                photos.compactMap { p in p.firestoreId.map { ($0, p) } },
                uniquingKeysWith: { existing, _ in existing }
            )

            // Merge remote metadata changes onto an EXISTING-local photo (a re-tag,
            // caption edit, or favorite toggle made on another device). The download
            // loop below skips these (the `!localPhotoIds.contains` gate), so without
            // this branch a re-tag on device A never relinks game/practice/season on
            // device B. Mirrors the re-home branch's clean-wins rule: only apply when
            // the local row has no pending edits — a dirty local edit wins and uploads
            // on this same pass.
            for remotePhoto in remotePhotos {
                guard let rid = remotePhoto.id, let local = localPhotosByFirestoreId[rid], !local.needsSync else { continue }
                local.caption = remotePhoto.caption
                local.isScorecardPhoto = remotePhoto.isScorecardPhoto ?? false
                local.isHighlight = remotePhoto.isHighlight ?? false
                // Relink parents by id. Only OVERWRITE when the remote id RESOLVES
                // locally: a non-nil id that doesn't resolve means the parent hasn't
                // synced down yet (e.g. a partial sync where the Games/Practices/Seasons
                // step threw and Photos still ran) — preserve the existing link and let
                // a later pass relink, rather than clearing a correct tag (a subsequent
                // local edit would otherwise make the untag permanent via
                // updatableFirestoreData's `?? NSNull()`). A nil remote id is a real
                // untag, so clear it.
                if let gid = remotePhoto.gameId {
                    if let g = (athlete.games ?? []).first(where: { $0.id.uuidString == gid || $0.firestoreId == gid }) { local.game = g }
                } else {
                    local.game = nil
                }
                if let pid = remotePhoto.practiceId {
                    if let p = (athlete.practices ?? []).first(where: { $0.id.uuidString == pid || $0.firestoreId == pid }) { local.practice = p }
                } else {
                    local.practice = nil
                }
                if let sid = remotePhoto.seasonId {
                    if let s = (athlete.seasons ?? []).first(where: { $0.id.uuidString == sid || $0.firestoreId == sid }) { local.season = s }
                } else {
                    local.season = nil
                }
            }

            for remotePhoto in remotePhotos where !localPhotoIds.contains(remotePhoto.id ?? "") {
                // Re-home: this photo already exists locally under a DIFFERENT profile
                // (legacy-split migration moved it). Repoint it to the new owner
                // instead of inserting a duplicate — keeps the downloaded file. Skip
                // if the local row has pending edits (let the local upload win).
                if let rid = remotePhoto.id, let existing = globalLocalPhotosByFirestoreId[rid] {
                    if !existing.needsSync, existing.athlete?.id != athlete.id {
                        existing.athlete = athlete
                        existing.isScorecardPhoto = remotePhoto.isScorecardPhoto ?? false
                        existing.isHighlight = remotePhoto.isHighlight ?? false
                        if let gameId = remotePhoto.gameId {
                            existing.game = (athlete.games ?? []).first { $0.id.uuidString == gameId || $0.firestoreId == gameId }
                        }
                        if let practiceId = remotePhoto.practiceId {
                            existing.practice = (athlete.practices ?? []).first { $0.id.uuidString == practiceId || $0.firestoreId == practiceId }
                        }
                        if let seasonId = remotePhoto.seasonId {
                            existing.season = (athlete.seasons ?? []).first { $0.id.uuidString == seasonId || $0.firestoreId == seasonId }
                        }
                    }
                    continue
                }
                guard let downloadURL = remotePhoto.downloadURL else { continue }

                // Build relative path (resolvedFilePath handles absolute resolution at read time)
                let relativePath = "Photos/\(remotePhoto.fileName)"

                // Ensure the Photos directory exists for downloads
                if let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    let photosDir = documentsURL.appendingPathComponent("Photos", isDirectory: true)
                    try? FileManager.default.createDirectory(at: photosDir, withIntermediateDirectories: true)
                }

                let newPhoto = Photo(fileName: remotePhoto.fileName, filePath: relativePath)
                newPhoto.id = UUID(uuidString: remotePhoto.swiftDataId) ?? UUID()
                newPhoto.cloudURL = downloadURL
                newPhoto.caption = remotePhoto.caption
                newPhoto.createdAt = remotePhoto.createdAt
                newPhoto.firestoreId = remotePhoto.id
                newPhoto.needsSync = false
                newPhoto.athlete = athlete
                newPhoto.isScorecardPhoto = remotePhoto.isScorecardPhoto ?? false
                newPhoto.isHighlight = remotePhoto.isHighlight ?? false

                // Link to game/practice/season by ID if available
                if let gameId = remotePhoto.gameId {
                    newPhoto.game = (athlete.games ?? []).first { $0.id.uuidString == gameId || $0.firestoreId == gameId }
                }
                if let practiceId = remotePhoto.practiceId {
                    newPhoto.practice = (athlete.practices ?? []).first { $0.id.uuidString == practiceId || $0.firestoreId == practiceId }
                }
                if let seasonId = remotePhoto.seasonId {
                    newPhoto.season = (athlete.seasons ?? []).first { $0.id.uuidString == seasonId || $0.firestoreId == seasonId }
                }

                context.insert(newPhoto)

                // Queue the file download; drained with bounded concurrency after the
                // save (see drainPhotoDownloads). The old code spawned one Task PER
                // missing photo with no cap — a fresh install of a heavy account
                // launched thousands of parallel downloads + CGImageSource decodes,
                // risking OOM and main-thread starvation.
                pendingPhotoDownloads.append((photoID: newPhoto.id, url: downloadURL, path: newPhoto.resolvedFilePath))
            }

        }

        // Global delete pass — a synced local photo absent from the FULL remote set
        // (across every athlete) was deleted on another device. A re-homed photo is
        // still present under its new owner, so it survives. Gated on connectivity
        // (see +HoleScores): an offline/partial cached fetch must not drive deletions,
        // which would make a network blip look like a bulk delete.
        if !ConnectivityMonitor.shared.isConnected {
            syncLog.warning("Skipping photo deletion pass — offline (would risk wiping synced photos)")
        } else {
            for localPhoto in athletes.flatMap({ $0.photos ?? [] }) {
                guard let fsId = localPhoto.firestoreId, !globalRemotePhotoIds.contains(fsId) else { continue }
                syncLog.info("Photo \(localPhoto.id) deleted remotely — removing local copy")
                localPhoto.delete(in: context)
            }
        }

        // Save all changes to SwiftData — re-dirty on failure so next sync retries.
        // Inserts must be persisted before the background downloader runs, so it can
        // refetch each photo by id.
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                for photo in syncedPhotos { photo.needsSync = true }
                throw error
            }
        }

        // Drain queued downloads in the background with bounded concurrency. One
        // wrapper task is registered in pendingDownloadTasks so sign-out cancels the
        // whole batch (cancellation propagates to the TaskGroup children).
        if !pendingPhotoDownloads.isEmpty {
            let taskID = UUID()
            let jobs = pendingPhotoDownloads
            pendingDownloadTasks[taskID] = Task { [weak self] in
                await self?.drainPhotoDownloads(jobs, maxConcurrent: 6)
                _ = self?.pendingDownloadTasks.removeValue(forKey: taskID)
            }
        }
    }

    // MARK: - Bounded Background Photo Downloads

    /// Drains queued photo downloads with at most `maxConcurrent` in flight, so a
    /// heavy fresh install can't spawn thousands of simultaneous downloads +
    /// thumbnail decodes (OOM / main-thread starvation). Sliding-window TaskGroup.
    private func drainPhotoDownloads(
        _ jobs: [(photoID: UUID, url: String, path: String)],
        maxConcurrent: Int
    ) async {
        var iterator = jobs.makeIterator()
        await withTaskGroup(of: Void.self) { group in
            var inFlight = 0
            while inFlight < maxConcurrent, let job = iterator.next() {
                group.addTask { await self.downloadOnePhoto(job) }
                inFlight += 1
            }
            while await group.next() != nil {
                if let job = iterator.next() {
                    group.addTask { await self.downloadOnePhoto(job) }
                }
            }
        }
    }

    /// Downloads one photo's file + thumbnail, then writes the result back to the
    /// SwiftData row. The row is REFETCHED by id (not captured) so a sign-out or a
    /// deletion mid-download can't mutate a dead object — if it's gone, we bail.
    private func downloadOnePhoto(_ job: (photoID: UUID, url: String, path: String)) async {
        do {
            try await VideoCloudManager.shared.downloadPhoto(from: job.url, to: job.path)
            let thumbRelPath = await Self.makePhotoThumbnail(at: job.path, photoID: job.photoID)
            guard let photo = fetchPhoto(by: job.photoID) else { return }
            if let thumbRelPath { photo.thumbnailPath = thumbRelPath }
            if let context = modelContext {
                ErrorHandlerService.shared.saveContext(context, caller: "SyncCoordinator.syncPhotos.downloaded")
            }
        } catch {
            syncLog.error("Failed to download photo \(job.photoID): \(error.localizedDescription)")
            // Mark for re-download next sync — only if the row still exists.
            guard let photo = fetchPhoto(by: job.photoID) else { return }
            photo.needsSync = true
            if let context = modelContext {
                ErrorHandlerService.shared.saveContext(context, caller: "SyncCoordinator.syncPhotos.downloadFailed")
            }
        }
    }

    /// Fetches a single Photo by its stable id, or nil if it no longer exists.
    private func fetchPhoto(by id: UUID) -> Photo? {
        guard let context = modelContext else { return nil }
        var descriptor = FetchDescriptor<Photo>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Builds an aspect-preserving thumbnail (max 600px) off the main actor —
    /// CGImageSource decode + JPEG encode + disk write. Returns the relative path.
    nonisolated private static func makePhotoThumbnail(at resolvedPath: String, photoID: UUID) async -> String? {
        await Task.detached(priority: .utility) { () -> String? in
            let photoURL = URL(fileURLWithPath: resolvedPath)
            guard let source = CGImageSourceCreateWithURL(photoURL as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceThumbnailMaxPixelSize: 600,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
                  let thumbData = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.7),
                  let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                return nil
            }
            let thumbDir = documentsURL.appendingPathComponent("PhotoThumbnails", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: thumbDir, withIntermediateDirectories: true)
                let thumbPath = thumbDir.appendingPathComponent("thumb_\(photoID.uuidString).jpg")
                try thumbData.write(to: thumbPath, options: .atomic)
                return "PhotoThumbnails/thumb_\(photoID.uuidString).jpg"
            } catch {
                syncLog.error("Failed to save photo thumbnail for \(photoID): \(error.localizedDescription)")
                return nil
            }
        }.value
    }
}
