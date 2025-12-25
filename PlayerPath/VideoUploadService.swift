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
    
    let errorHandler: ErrorHandlerService
    
    init(errorHandler: ErrorHandlerService? = nil) {
        self.errorHandler = errorHandler ?? ErrorHandlerService()
    }
    
    func processSelectedVideo(_ item: PhotosPickerItem?) async -> Result<URL, PlayerPathError> {
        guard let item = item else {
            let error = PlayerPathError.videoUploadFailed(reason: "No video was selected")
            errorHandler.handle(error, context: "Video selection")
            return .failure(error)
        }
        
        isProcessingVideo = true
        defer { isProcessingVideo = false }
        
        return await errorHandler.withErrorHandling(context: "Video processing") {
            guard let video = try await item.loadTransferable(type: VideoTransferable.self) else {
                throw PlayerPathError.videoUploadFailed(reason: "Failed to load transferable video data")
            }
            
            // Validate the video
            let validationResult = await VideoFileManager.validateVideo(at: video.url)
            switch validationResult {
            case .success:
                print("VideoUploadService: Video validation successful")
                return video.url
            case .failure(let error):
                // Convert VideoFileManager errors to PlayerPath errors
                let playerPathError = convertVideoValidationError(error)
                throw playerPathError
            }
        }
    }
    
    func uploadVideo(from localURL: URL, to cloudManager: VideoCloudManager) async -> Result<String, PlayerPathError> {
        uploadProgress = 0.0

        return await errorHandler.withErrorHandling(context: "Video cloud upload", canRetry: true) {
            // Validate user authentication before upload
            guard let user = Auth.auth().currentUser else {
                throw PlayerPathError.authenticationRequired
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

            return downloadURL
        }
    }
    
    private func convertVideoValidationError(_ error: Error) -> PlayerPathError {
        // Convert VideoFileManager.ValidationError to PlayerPathError
        if let validationError = error as? VideoFileManager.ValidationError {
            switch validationError {
            case .fileNotFound:
                return .videoFileNotFound
            case .fileTooLarge(let size):
                return .videoFileTooLarge(size: size, maxSize: 500 * 1024 * 1024) // 500MB max
            case .fileTooSmall:
                return .videoFileTooSmall
            case .durationTooLong(let duration):
                return .videoDurationTooLong(duration: duration, maxDuration: 600) // 10 minutes max
            case .durationTooShort(let duration):
                return .videoDurationTooShort(duration: duration, minDuration: 1) // 1 second min
            case .invalidFormat:
                return .unsupportedVideoFormat(format: nil)
            case .corruptedFile:
                return .videoFileCorrupted
            }
        }
        
        // Fallback for other error types
        if let localizedError = error as? LocalizedError {
            let description = localizedError.localizedDescription
            
            if description.contains("format") || description.contains("codec") {
                return .unsupportedVideoFormat(format: nil)
            } else if description.contains("size") || description.contains("large") {
                return .videoFileTooLarge(size: 0, maxSize: 500 * 1024 * 1024)
            } else if description.contains("duration") {
                return .videoDurationTooLong(duration: 0, maxDuration: 600)
            }
        }
        
        return .videoProcessingFailed(reason: error.localizedDescription)
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
                throw PlayerPathError.videoUploadFailed(reason: "Could not access app documents directory")
            }
            let copy = documentsPath.appendingPathComponent("imported_\(UUID().uuidString).mov")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Self.init(url: copy)
        }
    }
}