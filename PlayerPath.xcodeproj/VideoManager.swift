//
//  VideoManager.swift
//  PlayerPath
//
//  Unified video management system for PlayerPath
//

import Foundation
import SwiftUI
import PhotosUI
import AVFoundation
import SwiftData

// MARK: - Video Manager
@MainActor
class VideoManager: ObservableObject {
    // MARK: - Published Properties
    @Published var uploadProgress: [UUID: Double] = [:]
    @Published var processingVideos: Set<UUID> = []
    @Published var compressionProgress: [UUID: Double] = [:]
    
    // MARK: - Dependencies
    private let localStorage: VideoLocalStorage
    private let cloudStorage: VideoCloudStorageProtocol
    private let compressionService: VideoCompressionService
    let errorHandler: ErrorHandlerService
    
    // MARK: - Configuration
    private let maxVideoSizeMB = 100
    private let supportedFormats = ["mp4", "mov", "m4v"]
    
    init(
        localStorage: VideoLocalStorage = VideoLocalStorage(),
        cloudStorage: VideoCloudStorageProtocol = FirebaseVideoStorage(),
        compressionService: VideoCompressionService = VideoCompressionService()
    ) {
        self.localStorage = localStorage
        self.cloudStorage = cloudStorage
        self.compressionService = compressionService
        self.errorHandler = ErrorHandlerService()
    }
    
    // MARK: - Public Interface
    
    /// Record a new video using the camera
    func recordVideo() async -> Result<VideoClip, PlayerPathError> {
        return await errorHandler.withErrorHandling(context: "Video recording", canRetry: true) {
            // Check camera permissions
            let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
            guard cameraStatus == .authorized else {
                if cameraStatus == .notDetermined {
                    let granted = await AVCaptureDevice.requestAccess(for: .video)
                    guard granted else {
                        throw PlayerPathError.cameraPermissionDenied
                    }
                } else {
                    throw PlayerPathError.cameraAccessDenied
                }
            }
            
            // Check microphone permissions
            let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            guard micStatus == .authorized else {
                if micStatus == .notDetermined {
                    let granted = await AVCaptureDevice.requestAccess(for: .audio)
                    guard granted else {
                        throw PlayerPathError.microphoneAccessDenied
                    }
                } else {
                    throw PlayerPathError.microphoneAccessDenied
                }
            }
            
            // TODO: Implement actual camera recording
            // For now, return a placeholder
            throw PlayerPathError.featureNotAvailable(feature: "Camera recording not yet implemented")
        }
    }
    
    /// Import a video from the photo library
    func importVideo(_ item: PhotosPickerItem) async -> Result<VideoClip, PlayerPathError> {
        let videoId = UUID()
        processingVideos.insert(videoId)
        
        defer {
            processingVideos.remove(videoId)
            uploadProgress.removeValue(forKey: videoId)
            compressionProgress.removeValue(forKey: videoId)
        }
        
        return await errorHandler.withErrorHandling(context: "Video import", canRetry: true) {
            // Load the video from PhotosPicker
            guard let video = try await item.loadTransferable(type: VideoTransferable.self) else {
                throw PlayerPathError.videoUploadFailed(reason: "Failed to load video from photo library")
            }
            
            // Validate the video file
            try await validateVideo(at: video.url)
            
            // Create VideoClip metadata
            let videoClip = try await createVideoClip(from: video.url, id: videoId)
            
            // Store locally first
            let localURL = try await localStorage.store(video.url, for: videoClip)
            
            return videoClip
        }
    }
    
    /// Upload a video to cloud storage
    func uploadVideo(_ videoClip: VideoClip, quality: VideoQuality = .medium) async -> Result<String, PlayerPathError> {
        uploadProgress[videoClip.id] = 0.0
        
        defer {
            uploadProgress.removeValue(forKey: videoClip.id)
            compressionProgress.removeValue(forKey: videoClip.id)
        }
        
        return await errorHandler.withErrorHandling(context: "Video cloud upload", canRetry: true) {
            // Get local file URL
            guard let localURL = try await localStorage.getURL(for: videoClip) else {
                throw PlayerPathError.fileNotFound(path: videoClip.fileName)
            }
            
            // Compress if needed
            let compressedURL = try await compressVideoIfNeeded(
                localURL,
                videoId: videoClip.id,
                quality: quality
            )
            
            // Upload to cloud storage
            let cloudURL = try await cloudStorage.upload(
                compressedURL,
                metadata: VideoMetadata(from: videoClip)
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.uploadProgress[videoClip.id] = progress
                }
            }
            
            // Clean up compressed file if it's different from original
            if compressedURL != localURL {
                try? FileManager.default.removeItem(at: compressedURL)
            }
            
            return cloudURL
        }
    }
    
    /// Download a video from cloud storage
    func downloadVideo(id: UUID) async -> Result<VideoClip, PlayerPathError> {
        return await errorHandler.withErrorHandling(context: "Video download", canRetry: true) {
            // Check if already available locally
            if let localVideoClip = try await localStorage.getVideoClip(id: id) {
                return localVideoClip
            }
            
            // TODO: Download from cloud storage
            // This requires implementing cloud metadata storage first
            throw PlayerPathError.featureNotAvailable(feature: "Cloud video download not yet implemented")
        }
    }
    
    /// Sync all videos between local and cloud storage
    func syncAllVideos() async -> Result<[VideoClip], PlayerPathError> {
        return await errorHandler.withErrorHandling(context: "Video sync", canRetry: true) {
            // TODO: Implement comprehensive sync
            // 1. Get list of local videos
            // 2. Get list of cloud videos
            // 3. Resolve conflicts
            // 4. Download missing videos
            // 5. Upload pending videos
            
            throw PlayerPathError.featureNotAvailable(feature: "Video sync not yet implemented")
        }
    }
    
    /// Delete a video from both local and cloud storage
    func deleteVideo(_ videoClip: VideoClip) async -> Result<Void, PlayerPathError> {
        return await errorHandler.withErrorHandling(context: "Video deletion") {
            // Delete from local storage
            try await localStorage.delete(videoClip)
            
            // Delete from cloud if it exists
            if let cloudURL = videoClip.cloudURL {
                try await cloudStorage.delete(cloudURL)
            }
        }
    }
    
    // MARK: - Private Implementation
    
    private func validateVideo(at url: URL) async throws {
        let asset = AVAsset(url: url)
        
        // Check if the file is readable
        guard await asset.load(.isReadable) else {
            throw PlayerPathError.videoProcessingFailed(reason: "Video file is not readable")
        }
        
        // Check duration (example: max 10 minutes)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        guard durationSeconds > 0 && durationSeconds <= 600 else {
            throw PlayerPathError.videoProcessingFailed(reason: "Video duration must be between 1 second and 10 minutes")
        }
        
        // Check file size
        let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
        if let fileSize = resourceValues.fileSize {
            let maxSize = Int64(maxVideoSizeMB * 1024 * 1024)
            guard fileSize <= maxSize else {
                throw PlayerPathError.videoFileTooLarge(size: Int64(fileSize), maxSize: maxSize)
            }
        }
        
        // Check format
        let fileExtension = url.pathExtension.lowercased()
        guard supportedFormats.contains(fileExtension) else {
            throw PlayerPathError.unsupportedVideoFormat(format: fileExtension)
        }
    }
    
    private func createVideoClip(from url: URL, id: UUID) async throws -> VideoClip {
        let asset = AVAsset(url: url)
        
        // Load video properties
        let duration = try await asset.load(.duration)
        let tracks = try await asset.load(.tracks)
        
        let videoTrack = tracks.first { track in
            track.mediaType == .video
        }
        
        let naturalSize = try await videoTrack?.load(.naturalSize) ?? .zero
        
        // Create VideoClip object
        let videoClip = VideoClip()
        videoClip.id = id
        videoClip.fileName = "\(id.uuidString).mp4"
        videoClip.originalFileName = url.lastPathComponent
        videoClip.duration = CMTimeGetSeconds(duration)
        videoClip.fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        videoClip.resolution = "\(Int(naturalSize.width))x\(Int(naturalSize.height))"
        videoClip.createdAt = Date()
        
        return videoClip
    }
    
    private func compressVideoIfNeeded(
        _ inputURL: URL,
        videoId: UUID,
        quality: VideoQuality
    ) async throws -> URL {
        compressionProgress[videoId] = 0.0
        
        defer {
            compressionProgress.removeValue(forKey: videoId)
        }
        
        return try await compressionService.compressVideo(
            at: inputURL,
            quality: quality
        ) { [weak self] progress in
            Task { @MainActor in
                self?.compressionProgress[videoId] = progress
            }
        }
    }
}

// MARK: - Video Metadata
struct VideoMetadata {
    let id: UUID
    let fileName: String
    let userID: String
    let createdAt: Date
    let duration: TimeInterval
    let fileSize: Int
    let resolution: String
    let isHighlight: Bool
    
    init(from videoClip: VideoClip) {
        self.id = videoClip.id
        self.fileName = videoClip.fileName
        self.userID = "current-user" // TODO: Get from auth manager
        self.createdAt = videoClip.createdAt
        self.duration = videoClip.duration
        self.fileSize = videoClip.fileSize
        self.resolution = videoClip.resolution ?? "unknown"
        self.isHighlight = videoClip.isHighlight
    }
}

// MARK: - Video Quality Extension
extension VideoQuality {
    var exportPreset: String {
        switch self {
        case .low:
            return AVAssetExportPresetLowQuality
        case .medium:
            return AVAssetExportPresetMediumQuality
        case .high:
            return AVAssetExportPresetHighestQuality
        }
    }
    
    var compressionSettings: [String: Any] {
        switch self {
        case .low:
            return [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 480,
                AVVideoHeightKey: 640,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 400_000
                ]
            ]
        case .medium:
            return [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 720,
                AVVideoHeightKey: 1280,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 1_000_000
                ]
            ]
        case .high:
            return [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 1080,
                AVVideoHeightKey: 1920,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 2_000_000
                ]
            ]
        }
    }
}