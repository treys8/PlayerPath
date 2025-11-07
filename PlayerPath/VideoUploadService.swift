//
//  VideoUploadService.swift
//  PlayerPath
//
//  Created by Assistant on 10/27/25.
//

import Foundation
import PhotosUI
import SwiftUI

@MainActor
class VideoUploadService: ObservableObject {
    @Published var isProcessingVideo = false
    @Published var showingErrorAlert = false
    @Published var errorMessage = ""
    
    func processSelectedVideo(_ item: PhotosPickerItem?) async -> Result<URL, Error> {
        guard let item = item else {
            return .failure(VideoUploadError.noItemSelected)
        }
        
        isProcessingVideo = true
        defer { isProcessingVideo = false }
        
        do {
            guard let video = try await item.loadTransferable(type: VideoTransferable.self) else {
                throw VideoUploadError.failedToLoadVideo
            }
            
            // Validate the video
            let validationResult = await VideoFileManager.validateVideo(at: video.url)
            switch validationResult {
            case .success:
                print("VideoUploadService: Video validation successful")
                return .success(video.url)
            case .failure(let error):
                await showError(error.localizedDescription)
                return .failure(error)
            }
            
        } catch {
            let errorMsg = "Failed to load video: \(error.localizedDescription)"
            await showError(errorMsg)
            return .failure(error)
        }
    }
    
    private func showError(_ message: String) {
        errorMessage = message
        showingErrorAlert = true
    }
}

enum VideoUploadError: LocalizedError {
    case noItemSelected
    case failedToLoadVideo
    
    var errorDescription: String? {
        switch self {
        case .noItemSelected:
            return "No video was selected"
        case .failedToLoadVideo:
            return "Failed to load the selected video"
        }
    }
}

// MARK: - Video Transferable for PhotosPicker
struct VideoTransferable: Transferable {
    let url: URL
    
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let copy = documentsPath.appendingPathComponent("imported_\(UUID().uuidString).mov")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Self.init(url: copy)
        }
    }
}