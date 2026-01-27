//
//  VideoUploadService.swift
//  PlayerPath
//
//  Created by Assistant on 10/27/25.
//

import Foundation
import PhotosUI
import SwiftUI
import Combine
import CloudKit
import AVFoundation
import FirebaseAuth
import os.log

@MainActor
class VideoUploadService: ObservableObject {
    @Published var isProcessingVideo = false
    @Published var uploadProgress: Double = 0.0

    func processSelectedVideo(_ item: PhotosPickerItem?) async -> Result<URL, AppError> {
        guard let item = item else {
            let error = AppError.videoUploadFailed("No video was selected")
            ErrorHandlerService.shared.handle(error, context: "Video selection")
            return .failure(error)
        }

        isProcessingVideo = true
        defer { isProcessingVideo = false }

        do {
            guard let video = try await item.loadTransferable(type: VideoTransferable.self) else {
                let error = AppError.videoUploadFailed("Failed to load transferable video data")
                ErrorHandlerService.shared.handle(error, context: "Video processing")
                return .failure(error)
            }

            // Validate the video
            let validationResult = await VideoFileManager.validateVideo(at: video.url)
            switch validationResult {
            case .success:
                print("VideoUploadService: Video validation successful")
                return .success(video.url)
            case .failure(let error):
                // Convert VideoFileManager errors to AppError
                let appError = convertVideoValidationError(error)
                ErrorHandlerService.shared.handle(appError, context: "Video validation")
                return .failure(appError)
            }
        } catch {
            let appError = AppError.from(error)
            ErrorHandlerService.shared.handle(appError, context: "Video processing")
            return .failure(appError)
        }
    }
    
    func uploadVideo(from localURL: URL, to cloudManager: VideoCloudManager) async -> Result<String, AppError> {
        uploadProgress = 0.0

        do {
            // Validate user authentication before upload
            guard let user = Auth.auth().currentUser else {
                let error = AppError.authenticationFailed("User must be signed in to upload videos")
                ErrorHandlerService.shared.handle(error, context: "Video cloud upload")
                return .failure(error)
            }

            #if DEBUG
            print("🔐 VideoUploadService: Authenticated user: \(user.uid)")
            #endif

            // Generate unique filename for the video
            let fileName = "\(UUID().uuidString).mov"

            // Use user-specific folder ID for better organization
            let folderID = "athlete_videos/\(user.uid)"

            // Upload with progress tracking
            let downloadURL = try await cloudManager.uploadVideo(
                localURL: localURL,
                fileName: fileName,
                folderID: folderID,
                progressHandler: { [weak self] progress in
                    self?.uploadProgress = progress
                }
            )

            #if DEBUG
            print("✅ VideoUploadService: Upload completed - \(downloadURL)")
            #endif

            return .success(downloadURL)
        } catch {
            let appError = AppError.videoUploadFailed(error.localizedDescription)
            ErrorHandlerService.shared.handle(appError, context: "Video cloud upload")
            return .failure(appError)
        }
    }
    
    private func convertVideoValidationError(_ error: Error) -> AppError {
        // Convert VideoFileManager.ValidationError to AppError
        if let validationError = error as? VideoFileManager.ValidationError {
            switch validationError {
            case .fileNotFound:
                return .videoNotFound
            case .fileTooLarge(let size):
                let sizeMB = Double(size) / (1024 * 1024)
                return .videoUploadFailed("Video file is too large (\(String(format: "%.1f", sizeMB)) MB). Maximum size is 500 MB")
            case .fileTooSmall:
                return .videoUploadFailed("Video file is too small")
            case .durationTooLong(let duration):
                let minutes = Int(duration / 60)
                return .videoUploadFailed("Video is too long (\(minutes) minutes). Maximum duration is 10 minutes")
            case .durationTooShort(let duration):
                return .videoUploadFailed("Video is too short (\(Int(duration)) seconds). Minimum duration is 1 second")
            case .invalidFormat:
                return .videoUploadFailed("Unsupported video format. Please use MP4 or MOV")
            case .corruptedFile:
                return .videoUploadFailed("Video file appears to be corrupted")
            }
        }

        // Fallback for other error types
        if let localizedError = error as? LocalizedError {
            let description = localizedError.localizedDescription

            if description.contains("format") || description.contains("codec") {
                return .videoUploadFailed("Unsupported video format. Please use MP4 or MOV")
            } else if description.contains("size") || description.contains("large") {
                return .videoUploadFailed("Video file is too large. Maximum size is 500 MB")
            } else if description.contains("duration") {
                return .videoUploadFailed("Video duration exceeds maximum of 10 minutes")
            }
        }

        return .videoRecordingFailed(error.localizedDescription)
    }
}

// MARK: - Video Transferable for PhotosPicker
struct VideoTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                throw AppError.videoUploadFailed("Could not access app documents directory")
            }
            let copy = documentsPath.appendingPathComponent("imported_\(UUID().uuidString).mov")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Self.init(url: copy)
        }
    }
}