//
//  VideoCloudManager+Photos.swift
//  PlayerPath
//
//  Photo upload, download, delete, and GDPR bulk delete operations.
//

import Foundation
import FirebaseStorage
import FirebaseAuth
import FirebaseFirestore
import os

private let videoCloudLog = Logger(subsystem: "com.playerpath.app", category: "VideoCloud")

extension VideoCloudManager {

    /// Uploads a photo file to Firebase Storage and returns its download URL.
    func uploadPhoto(at localURL: URL, ownerUID: String) async throws -> String {
        let storage = Storage.storage()
        let fileName = localURL.lastPathComponent
        let photoRef = storage.reference().child("athlete_photos/\(ownerUID)/\(fileName)")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        return try await withCheckedThrowingContinuation { continuation in
            let hasResumed = OSAllocatedUnfairLock(initialState: false)
            photoRef.putFile(from: localURL, metadata: metadata) { _, error in
                if let error = error {
                    let alreadyResumed = hasResumed.withLock { val -> Bool in
                        if val { return true }; val = true; return false
                    }
                    if !alreadyResumed { continuation.resume(throwing: error) }
                    return
                }
                photoRef.downloadURL { url, error in
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

    /// Deletes an athlete's photo from Firebase Storage.
    func deleteAthletePhoto(fileName: String) async throws {
        guard let ownerUID = Auth.auth().currentUser?.uid else {
            throw VideoCloudError.uploadFailed("User session expired — please sign in again")
        }
        let photoRef = Storage.storage().reference().child("athlete_photos/\(ownerUID)/\(fileName)")
        return try await withCheckedThrowingContinuation { continuation in
            photoRef.delete { error in
                if let error = error {
                    let nsError = error as NSError
                    if nsError.domain == "FIRStorageErrorDomain" && nsError.code == StorageErrorCode.objectNotFound.rawValue {
                        // Already gone — treat as success so cleanup is idempotent.
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

    /// Downloads a photo file from Firebase Storage to a local path.
    ///
    /// Coalesces concurrent callers writing to the same `localPath` so two
    /// `write(toFile:)` calls don't race on the same destination. Both
    /// `PhotoThumbnailLoader` and `PhotoDetailView` request the same file
    /// when a user taps an evicted photo; without this, GTMSessionFetcher
    /// flagged them as duplicates and the file could be corrupted.
    ///
    /// Assumes both call sites resolve to the same `localPath` for the same
    /// logical photo — true today because they both read `photo.resolvedFilePath`
    /// from the same SwiftData instance (cached via `@Transient`). If a
    /// future caller computes a different path the dedup is a no-op (back to
    /// today's behavior), no correctness break.
    func downloadPhoto(from cloudURL: String, to localPath: String) async throws {
        // Check + insert is atomic on @MainActor — no other caller can slip
        // in between these two lines.
        if let existing = inFlightPhotoDownloads[localPath] {
            try await existing.value
            return
        }

        // `Task.detached` so a single caller's cancellation cannot tear down
        // the shared download — other awaiters still need the file. The task
        // is owned by VideoCloudManager (via the dictionary), not by any
        // caller's structured-concurrency tree.
        //
        // Dict cleanup MUST happen inside the task body (not in a caller's
        // catch) so it's tied to the download's lifetime, not the caller's.
        // If a caller is cancelled mid-await, the underlying task keeps
        // running and a re-tap by the user finds the still-in-flight task
        // in the dict instead of spawning a second download.
        let task = Task.detached { [weak self] in
            var thrown: Error?
            do {
                try await Self.performPhotoDownload(from: cloudURL, to: localPath)
            } catch {
                thrown = error
            }
            await MainActor.run { [weak self] in self?.inFlightPhotoDownloads[localPath] = nil }
            if let thrown { throw thrown }
        }
        inFlightPhotoDownloads[localPath] = task

        try await task.value
    }

    /// Performs the actual photo download. Marked `nonisolated` (via `static`)
    /// so it can run off the main actor inside `Task.detached`.
    private static func performPhotoDownload(from cloudURL: String, to localPath: String) async throws {
        // ConnectivityMonitor is @MainActor; hop briefly to read the flag.
        let isConnected = await MainActor.run { ConnectivityMonitor.shared.isConnected }
        guard isConnected else {
            throw VideoCloudError.networkUnavailable
        }
        guard let storageURL = URL(string: cloudURL) else { throw VideoCloudError.invalidURL }
        let localURL = URL(fileURLWithPath: localPath)
        do {
            try FileManager.default.createDirectory(
                at: localURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            videoCloudLog.error("Failed to create photo download directory: \(error.localizedDescription)")
        }
        if FileManager.default.fileExists(atPath: localPath) {
            let attrs = try? FileManager.default.attributesOfItem(atPath: localPath)
            let size = attrs?[.size] as? Int64 ?? 0
            if size > 0 { return }
            // Remove corrupt/empty file so we can re-download
            try? FileManager.default.removeItem(atPath: localPath)
        }

        let storage = Storage.storage()
        let photoRef = storage.reference(forURL: storageURL.absoluteString)

        return try await withCheckedThrowingContinuation { continuation in
            photoRef.write(toFile: localURL) { _, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// Records a failed photo deletion for server-side cleanup.
    func recordPendingPhotoDeletion(photoId: UUID, fileName: String) async throws {
        guard let ownerUID = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        try await db.collection(FC.pendingDeletions).document(photoId.uuidString).setData([
            "ownerUID": ownerUID,
            "fileName": fileName,
            "storagePath": "athlete_photos/\(ownerUID)/\(fileName)",
            "type": "photo",
            "createdAt": Timestamp(date: Date())
        ])
    }

    /// Deletes all photo files from Firebase Storage for a user (GDPR compliance)
    func deleteAllUserPhotos(userID: String) async throws {
        guard ConnectivityMonitor.shared.isConnected else {
            throw VideoCloudError.networkUnavailable
        }

        let storage = Storage.storage()
        let userPhotoRef = storage.reference().child("athlete_photos/\(userID)")

        do {
            let result = try await userPhotoRef.listAll()
            for fileRef in result.items {
                do {
                    try await fileRef.delete()
                } catch {
                    videoCloudLog.warning("Failed to delete storage file: \(error.localizedDescription)")
                }
            }
        } catch {
            let nsError = error as NSError
            if nsError.domain == "FIRStorageErrorDomain" && nsError.code == StorageErrorCode.objectNotFound.rawValue {
                return
            }
            throw error
        }
    }
}
