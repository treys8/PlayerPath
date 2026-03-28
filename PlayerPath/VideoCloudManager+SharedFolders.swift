//
//  VideoCloudManager+SharedFolders.swift
//  PlayerPath
//
//  Shared folder video/thumbnail upload, download URLs, delete, and rollback.
//

import Foundation
import FirebaseStorage
import os

private let videoCloudLog = Logger(subsystem: "com.playerpath.app", category: "VideoCloud")

extension VideoCloudManager {

    // MARK: - Shared Folder Upload

    /// Uploads a video file to Firebase Storage for a shared folder
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

        return try await withCheckedThrowingContinuation { continuation in
            let hasResumed = OSAllocatedUnfairLock(initialState: false)
            let uploadTask = videoRef.putFile(from: localURL, metadata: metadata) { metadata, error in
                if let error = error {
                    let alreadyResumed = hasResumed.withLock { val -> Bool in
                        if val { return true }; val = true; return false
                    }
                    if !alreadyResumed { continuation.resume(throwing: error) }
                    return
                }

                videoRef.downloadURL { url, error in
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

    /// Uploads a thumbnail image to Firebase Storage for a shared folder video
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

    // MARK: - Shared Folder Download URLs

    /// Gets a secure download URL for a file in Firebase Storage
    func getSecureDownloadURL(
        fileName: String,
        folderID: String,
        isThumbnail: Bool = false
    ) async throws -> String {
        guard ConnectivityMonitor.shared.isConnected else {
            throw VideoCloudError.networkUnavailable
        }

        let storage = Storage.storage()
        let storageRef = storage.reference()

        let filePath: String
        if isThumbnail {
            let thumbnailFileName = (fileName as NSString).deletingPathExtension + "_thumbnail.jpg"
            filePath = "shared_folders/\(folderID)/thumbnails/\(thumbnailFileName)"
        } else {
            filePath = "shared_folders/\(folderID)/\(fileName)"
        }

        let fileRef = storageRef.child(filePath)

        return try await withCheckedThrowingContinuation { continuation in
            fileRef.downloadURL { url, error in
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

    // MARK: - Shared Folder Delete

    /// Deletes a video from Firebase Storage for a shared folder
    func deleteVideo(fileName: String, folderID: String) async throws {
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
