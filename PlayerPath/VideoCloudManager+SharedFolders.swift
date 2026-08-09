//
//  VideoCloudManager+SharedFolders.swift
//  PlayerPath
//
//  Shared folder video/thumbnail upload, download URLs, delete, and rollback.
//

import Foundation
import FirebaseStorage
import FirebaseAuth
import os

private let videoCloudLog = Logger(subsystem: "com.playerpath.app", category: "VideoCloud")

extension VideoCloudManager {

    // MARK: - Shared Folder Upload

    /// Uploads a video file to Firebase Storage for a shared folder.
    ///
    /// Returns the deterministic Storage **path**, not a URL — deliberately, and do not
    /// "fix" this back to `downloadURL()`.
    ///
    /// `downloadURL()` permanently attaches a `firebaseStorageDownloadTokens` value to the
    /// object and hands back a link Firebase serves with **no authentication and without
    /// evaluating storage.rules**, forever. That string was persisted to
    /// `videos/{id}.firebaseStorageURL`, which every coach on the folder can read. Nothing in
    /// the app or the Cloud Functions ever rotated it, and removing a coach only arrayRemoves
    /// them and writes a revocation doc — neither of which touches the token. So the entire
    /// signed-URL architecture (SecureURLManager → getSignedVideoURL, short expiry, membership
    /// re-check, revocation check) was bypassable indefinitely by anyone who had captured the
    /// stored URL while they still had access.
    ///
    /// Nothing reads the returned value as a URL: playback goes through `CoachVideoLoader` →
    /// `SecureURLManager.getSecureVideoURL`, whose only fallback is another signed URL.
    func uploadVideo(
        localURL: URL,
        fileName: String,
        folderID: String,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> String {

        let storage = Storage.storage()
        let storageRef = storage.reference()
        let videoRef = storageRef.child("shared_folders/\(folderID)/\(fileName)")

        let metadata = StorageMetadata()
        metadata.contentType = "video/quicktime"

        let uploadBox = UploadTaskBox()
        return try await withCheckedThrowingContinuation { continuation in
            let hasResumed = OSAllocatedUnfairLock(initialState: false)
            let uploadTask = videoRef.putFile(from: localURL, metadata: metadata) { [weak uploadBox] metadata, error in
                // Remove the progress observer to prevent a leak — Firebase
                // retains the task (and its progress closure) until observers
                // are cleared. Mirrors the athlete upload path.
                uploadBox?.task?.removeAllObservers()

                if let error = error {
                    let alreadyResumed = hasResumed.withLock { val -> Bool in
                        if val { return true }; val = true; return false
                    }
                    if !alreadyResumed { continuation.resume(throwing: error) }
                    return
                }

                // Return the path. No downloadURL() round-trip, so no permanent public token
                // is ever minted for this object (see the doc comment above).
                let alreadyResumed = hasResumed.withLock { val -> Bool in
                    if val { return true }; val = true; return false
                }
                if !alreadyResumed { continuation.resume(returning: videoRef.fullPath) }
            }

            uploadBox.task = uploadTask

            // Monitor upload progress with throttling
            uploadTask.observe(.progress) { [weak self] snapshot in
                guard let progress = snapshot.progress else { return }
                let percentComplete = progress.totalUnitCount > 0 ? Double(progress.completedUnitCount) / Double(progress.totalUnitCount) : 0.0

                Task { @MainActor in
                    guard let self = self else {
                        progressHandler(percentComplete)
                        return
                    }

                    _ = self.throttledProgressUpdate(
                        key: "upload_\(fileName)",
                        progress: percentComplete,
                        handler: progressHandler
                    )
                }
            }
        }
    }

    /// Uploads a thumbnail image to Firebase Storage for a shared folder video.
    ///
    /// Returns the Storage **path**, for the same reason `uploadVideo` above does. Thumbnails
    /// were arguably the worse half of that defect: the client fetches them automatically
    /// during ordinary browsing, so recognizable images of a minor were pulled through
    /// unauthenticated token URLs with no deliberate act by anyone — and this object also
    /// carries `max-age=31536000`, so those images sat in intermediary and on-device caches
    /// for a year. Reads go through `RemoteThumbnailView`'s secure branch
    /// (`SecureURLManager.getSecureThumbnailURL`), which every shared-folder call site takes.
    func uploadThumbnail(
        thumbnailURL: URL,
        videoFileName: String,
        folderID: String
    ) async throws -> String {

        let storage = Storage.storage()
        let storageRef = storage.reference()

        let thumbnailFileName = (videoFileName as NSString).deletingPathExtension + "_thumbnail.jpg"
        let thumbnailRef = storageRef.child("shared_folders/\(folderID)/thumbnails/\(thumbnailFileName)")

        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        metadata.cacheControl = "public, max-age=31536000" // Cache for 1 year

        return try await withCheckedThrowingContinuation { continuation in
            let hasResumed = OSAllocatedUnfairLock(initialState: false)
            thumbnailRef.putFile(from: thumbnailURL, metadata: metadata) { metadata, error in
                if let error = error {
                    let alreadyResumed = hasResumed.withLock { val -> Bool in
                        if val { return true }; val = true; return false
                    }
                    if !alreadyResumed { continuation.resume(throwing: error) }
                    return
                }

                // Path, not a token URL — see the doc comment above.
                let alreadyResumed = hasResumed.withLock { val -> Bool in
                    if val { return true }; val = true; return false
                }
                if !alreadyResumed { continuation.resume(returning: thumbnailRef.fullPath) }
            }
        }
    }

    // `getSecureDownloadURL` was removed here. It had ZERO callers, and despite the name it
    // was not secure — it returned the same permanent `downloadURL()` token link as the upload
    // paths above, gated only on a connectivity check. Anything needing a shared-folder URL
    // must go through `SecureURLManager` (getSecureVideoURL / getSecureThumbnailURL), which
    // calls the Cloud Function that re-checks folder membership and signs a short-lived URL.

    // MARK: - Shared Folder Delete

    /// Deletes a video from Firebase Storage for a shared folder
    func deleteVideo(fileName: String, folderID: String) async throws {
        guard Auth.auth().currentUser != nil else {
            throw VideoCloudError.deletionFailed("Session expired — please sign in again")
        }
        let storage = Storage.storage()
        let storageRef = storage.reference()
        let videoRef = storageRef.child("shared_folders/\(folderID)/\(fileName)")

        return try await withCheckedThrowingContinuation { continuation in
            videoRef.delete { error in
                if let error = error {
                    let nsError = error as NSError
                    if nsError.domain == "FIRStorageErrorDomain" && nsError.code == StorageErrorCode.objectNotFound.rawValue {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: error)
                    }
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// Deletes a thumbnail from Firebase Storage for a shared folder
    func deleteThumbnail(videoFileName: String, folderID: String) async throws {
        guard Auth.auth().currentUser != nil else {
            throw VideoCloudError.deletionFailed("Session expired — please sign in again")
        }
        let storage = Storage.storage()
        let storageRef = storage.reference()

        let thumbnailFileName = (videoFileName as NSString).deletingPathExtension + "_thumbnail.jpg"
        let thumbnailRef = storageRef.child("shared_folders/\(folderID)/thumbnails/\(thumbnailFileName)")

        return try await withCheckedThrowingContinuation { continuation in
            thumbnailRef.delete { error in
                if let error = error {
                    let nsError = error as NSError
                    if nsError.domain == "FIRStorageErrorDomain" && nsError.code == StorageErrorCode.objectNotFound.rawValue {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: error)
                    }
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
