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
import os.log

@MainActor
class VideoUploadService: ObservableObject {
    @Published var isProcessingVideo = false

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
                return .success(video.url)
            case .failure(let error):
                // Clean up the imported file since validation failed
                try? FileManager.default.removeItem(at: video.url)
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
    
    private func convertVideoValidationError(_ error: Error) -> AppError {
        // Convert VideoFileManager.ValidationError to AppError
        if let validationError = error as? VideoFileManager.ValidationError {
            switch validationError {
            case .fileNotFound:
                return .videoNotFound
            case .fileTooLarge(let size):
                let sizeMB = Double(size) / Double(StorageConstants.bytesPerMB)
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
            case .cancelled:
                return .videoUploadFailed("Video upload was cancelled")
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
            let tmpDir = FileManager.default.temporaryDirectory
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let copy = tmpDir.appendingPathComponent("imported_\(UUID().uuidString).\(ext)")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Self.init(url: copy)
        }
    }
}
