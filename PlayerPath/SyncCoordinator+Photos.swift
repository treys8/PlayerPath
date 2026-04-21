import Foundation
import SwiftData
import FirebaseAuth
import UIKit
import os

private let syncLog = Logger(subsystem: "com.playerpath.app", category: "Sync")

extension SyncCoordinator {

    // MARK: - Photos Sync

    func syncPhotos(for user: User) async throws {
        guard let context = modelContext else { return }
        guard let ownerUID = Auth.auth().currentUser?.uid else { return }

        let athletes = user.athletes ?? []

        var syncedPhotos: [Photo] = []

        for athlete in athletes {
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
                let tier = StoreKitManager.shared.currentTier
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
                    syncedPhotos.append(photo)
                    if let uploadedSize = (try? FileManager.default.attributesOfItem(atPath: resolvedPath)[.size] as? Int64) {
                        user.cloudStorageUsedBytes += uploadedSize
                    } else {
                        syncLog.warning("Could not read uploaded photo file size for storage tracking")
                    }
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
            let athleteStableId = athlete.firestoreId ?? athlete.id.uuidString
            let remotePhotos = try await FirestoreManager.shared.fetchPhotos(
                uploadedBy: ownerUID,
                athleteId: athleteStableId
            )
            let localPhotoIds = Set(photos.compactMap { $0.firestoreId })

            for remotePhoto in remotePhotos where !localPhotoIds.contains(remotePhoto.id ?? "") {
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

                // Download the image file in the background if not already present.
                // Outer Task inherits @MainActor; CPU-bound thumbnail work is offloaded
                // to a detached utility-priority task to keep the main thread responsive.
                let taskID = UUID()
                let photoRef = newPhoto
                let resolvedPath = newPhoto.resolvedFilePath
                let photoID = newPhoto.id
                pendingDownloadTasks[taskID] = Task { [weak self] in
                    do {
                        try await VideoCloudManager.shared.downloadPhoto(from: downloadURL, to: resolvedPath)
                        // Generate aspect-preserving thumbnail via CGImageSource (max 600px)
                        // off the main actor — CGImageSource decode + JPEG encode + disk write.
                        let thumbRelPath = await Task.detached(priority: .utility) { () -> String? in
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
                        if let thumbRelPath {
                            photoRef.thumbnailPath = thumbRelPath
                        }
                    } catch {
                        // Mark for re-download on next sync so the photo doesn't remain as a ghost record
                        syncLog.error("Failed to download photo \(photoID): \(error.localizedDescription)")
                        photoRef.needsSync = true
                    }
                    _ = self?.pendingDownloadTasks.removeValue(forKey: taskID)
                }
            }

            // Detect photos deleted on other devices
            let remotePhotoIds = Set(remotePhotos.compactMap { $0.id })
            let syncedLocalPhotos = photos.filter { $0.firestoreId != nil }
            let remoteReturnedTooFew = !syncedLocalPhotos.isEmpty
                && remotePhotoIds.count < syncedLocalPhotos.count / 2
            if remoteReturnedTooFew {
                syncLog.warning("Remote returned \(remotePhotoIds.count) photos but \(syncedLocalPhotos.count) synced locally — skipping deletion pass")
            } else {
                for localPhoto in syncedLocalPhotos {
                    guard let fsId = localPhoto.firestoreId, !remotePhotoIds.contains(fsId) else { continue }
                    syncLog.info("Photo \(localPhoto.id) deleted remotely — removing local copy")
                    localPhoto.delete(in: context)
                }
            }
        }

        // Save all changes to SwiftData — re-dirty on failure so next sync retries
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                for photo in syncedPhotos { photo.needsSync = true }
                throw error
            }
        }
    }
}
