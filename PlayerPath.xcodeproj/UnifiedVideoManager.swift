//
//  UnifiedVideoManager.swift
//  PlayerPath
//
//  Created by Assistant on 10/30/25.
//

import Foundation
import SwiftUI
import AVFoundation
import CloudKit
import PhotosUI
import OSLog
import Combine

// MARK: - Video Entity Models

struct VideoRecord: Identifiable, Codable, Syncable {
    let id: String
    var title: String
    var createdDate: Date
    var lastModified: Date
    var duration: TimeInterval
    var fileSize: Int64
    var localURL: URL?
    var cloudURL: String?
    var thumbnailPath: String?
    var metadata: VideoMetadata
    var syncStatus: SyncStatus
    var processingStatus: ProcessingStatus
    var tags: [String]
    var isHighlight: Bool
    
    // Syncable conformance
    var recordType: String { "VideoRecord" }
    
    init(
        id: String = UUID().uuidString,
        title: String = "Untitled Video",
        createdDate: Date = Date(),
        duration: TimeInterval = 0,
        fileSize: Int64 = 0,
        localURL: URL? = nil,
        metadata: VideoMetadata = VideoMetadata()
    ) {
        self.id = id
        self.title = title
        self.createdDate = createdDate
        self.lastModified = createdDate
        self.duration = duration
        self.fileSize = fileSize
        self.localURL = localURL
        self.metadata = metadata
        self.syncStatus = .notSynced
        self.processingStatus = .pending
        self.tags = []
        self.isHighlight = false
    }
    
    enum SyncStatus: String, Codable {
        case notSynced
        case syncing
        case synced
        case syncFailed
        case syncConflict
    }
    
    enum ProcessingStatus: String, Codable {
        case pending
        case processing
        case completed
        case failed
        case cancelled
    }
    
    // MARK: - Syncable Implementation
    
    func toCKRecord() -> CKRecord {
        let recordID = CKRecord.ID(recordName: id)
        let record = CKRecord(recordType: recordType, recordID: recordID)
        
        record["title"] = title
        record["createdDate"] = createdDate
        record["lastModified"] = lastModified
        record["duration"] = duration
        record["fileSize"] = fileSize
        record["cloudURL"] = cloudURL
        record["thumbnailPath"] = thumbnailPath
        record["isHighlight"] = isHighlight
        record["tags"] = tags
        
        // Store metadata as a nested record or JSON
        if let metadataData = try? JSONEncoder().encode(metadata) {
            record["metadata"] = String(data: metadataData, encoding: .utf8)
        }
        
        return record
    }
    
    init(from record: CKRecord) throws {
        self.id = record.recordID.recordName
        self.title = record["title"] as? String ?? "Untitled Video"
        self.createdDate = record["createdDate"] as? Date ?? Date()
        self.lastModified = record["lastModified"] as? Date ?? Date()
        self.duration = record["duration"] as? TimeInterval ?? 0
        self.fileSize = record["fileSize"] as? Int64 ?? 0
        self.cloudURL = record["cloudURL"] as? String
        self.thumbnailPath = record["thumbnailPath"] as? String
        self.isHighlight = record["isHighlight"] as? Bool ?? false
        self.tags = record["tags"] as? [String] ?? []
        
        // Parse metadata
        if let metadataString = record["metadata"] as? String,
           let metadataData = metadataString.data(using: .utf8),
           let decodedMetadata = try? JSONDecoder().decode(VideoMetadata.self, from: metadataData) {
            self.metadata = decodedMetadata
        } else {
            self.metadata = VideoMetadata()
        }
        
        self.localURL = nil // Will be set locally
        self.syncStatus = .synced
        self.processingStatus = .completed
    }
}

struct VideoMetadata: Codable {
    var resolution: CGSize
    var frameRate: Double
    var codec: String
    var bitrate: Int
    var gameSession: GameSessionInfo?
    var location: LocationInfo?
    var cameraSettings: CameraSettings
    
    init() {
        self.resolution = .zero
        self.frameRate = 30.0
        self.codec = "Unknown"
        self.bitrate = 0
        self.gameSession = nil
        self.location = nil
        self.cameraSettings = CameraSettings()
    }
}

struct GameSessionInfo: Codable {
    let gameType: String
    let opponent: String?
    let score: String?
    let weather: String?
    let notes: String?
}

struct LocationInfo: Codable {
    let latitude: Double
    let longitude: Double
    let venue: String?
}

struct CameraSettings: Codable {
    var quality: VideoQuality
    var stabilization: Bool
    var autoFocus: Bool
    
    init() {
        self.quality = .high
        self.stabilization = true
        self.autoFocus = true
    }
}

// MARK: - Unified Video Manager

@MainActor
@Observable
final class UnifiedVideoManager {
    static let shared = UnifiedVideoManager()
    
    private let logger = Logger(subsystem: "PlayerPath", category: "UnifiedVideoManager")
    private let errorHandler = ErrorHandlerService.shared
    private let syncManager = UnifiedSyncManager.shared
    
    // MARK: - Published Properties
    
    private(set) var videos: [VideoRecord] = []
    private(set) var isLoading = false
    private(set) var processingVideos: Set<String> = []
    private(set) var uploadProgress: [String: Double] = [:]
    
    // Filtering and sorting
    var searchText = ""
    var selectedTags: Set<String> = []
    var showHighlightsOnly = false
    var sortOption: SortOption = .dateCreated
    
    // MARK: - Configuration
    
    private let maxConcurrentUploads = 3
    private let maxLocalVideos = 100 // Automatic cleanup threshold
    private var uploadTasks: [String: Task<Void, Never>] = [:]
    
    enum SortOption: CaseIterable {
        case dateCreated, dateModified, title, duration, fileSize
        
        var displayName: String {
            switch self {
            case .dateCreated: return "Date Created"
            case .dateModified: return "Date Modified"
            case .title: return "Title"
            case .duration: return "Duration"
            case .fileSize: return "File Size"
            }
        }
    }
    
    // MARK: - Computed Properties
    
    var filteredVideos: [VideoRecord] {
        videos
            .filter { video in
                // Search filter
                if !searchText.isEmpty {
                    let searchLower = searchText.lowercased()
                    return video.title.lowercased().contains(searchLower) ||
                           video.tags.contains { $0.lowercased().contains(searchLower) }
                }
                return true
            }
            .filter { video in
                // Highlights filter
                if showHighlightsOnly {
                    return video.isHighlight
                }
                return true
            }
            .filter { video in
                // Tag filter
                if !selectedTags.isEmpty {
                    return !Set(video.tags).isDisjoint(with: selectedTags)
                }
                return true
            }
            .sorted { video1, video2 in
                switch sortOption {
                case .dateCreated:
                    return video1.createdDate > video2.createdDate
                case .dateModified:
                    return video1.lastModified > video2.lastModified
                case .title:
                    return video1.title < video2.title
                case .duration:
                    return video1.duration > video2.duration
                case .fileSize:
                    return video1.fileSize > video2.fileSize
                }
            }
    }
    
    var allTags: [String] {
        Array(Set(videos.flatMap(\.tags))).sorted()
    }
    
    var storageInfo: StorageInfo {
        let totalSize = videos.reduce(0) { $0 + $1.fileSize }
        let localCount = videos.filter { $0.localURL != nil }.count
        let cloudCount = videos.filter { $0.cloudURL != nil }.count
        
        return StorageInfo(
            totalVideos: videos.count,
            localVideos: localCount,
            cloudVideos: cloudCount,
            totalSize: totalSize,
            syncPending: videos.filter { $0.syncStatus == .notSynced }.count
        )
    }
    
    struct StorageInfo {
        let totalVideos: Int
        let localVideos: Int
        let cloudVideos: Int
        let totalSize: Int64
        let syncPending: Int
        
        var formattedSize: String {
            ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
        }
    }
    
    private init() {
        loadLocalVideos()
        setupAutoSync()
    }
    
    // MARK: - Core Video Management
    
    /// Import a new video from PhotosPicker or camera
    func importVideo(from item: PhotosPickerItem) async -> Result<VideoRecord, PlayerPathError> {
        logger.info("Starting video import process")
        
        return await errorHandler.withErrorHandling(context: "Video Import") {
            // Process the selected video
            guard let transferable = try await item.loadTransferable(type: VideoTransferable.self) else {
                throw PlayerPathError.videoUploadFailed(reason: "Failed to load video from picker")
            }
            
            // Validate the video
            let validationResult = await VideoFileManager.validateVideo(at: transferable.url)
            switch validationResult {
            case .failure(let error):
                throw convertValidationError(error)
            case .success:
                break
            }
            
            // Create permanent copy
            let permanentURL = try VideoFileManager.copyToDocuments(from: transferable.url)
            
            // Extract metadata
            let metadata = await extractVideoMetadata(from: permanentURL)
            
            // Generate thumbnail
            let thumbnailResult = await VideoFileManager.generateThumbnail(from: permanentURL)
            let thumbnailPath = try? thumbnailResult.get()
            
            // Create video record
            var video = VideoRecord(
                title: generateVideoTitle(),
                duration: metadata.duration,
                fileSize: getFileSize(at: permanentURL),
                localURL: permanentURL,
                metadata: metadata.videoMetadata
            )
            
            video.thumbnailPath = thumbnailPath
            video.processingStatus = .completed
            
            // Add to collection
            addVideo(video)
            
            // Queue for sync if enabled
            queueForSync(video)
            
            logger.info("Successfully imported video: \(video.id)")
            return video
        }
    }
    
    /// Record a new video using the camera
    func recordVideo(with settings: CameraSettings) async -> Result<VideoRecord, PlayerPathError> {
        logger.info("Starting video recording")
        
        return await errorHandler.withErrorHandling(context: "Video Recording") {
            // TODO: Implement camera recording logic
            // This would integrate with AVFoundation's camera APIs
            
            throw PlayerPathError.unknownError("Camera recording not yet implemented")
        }
    }
    
    /// Update video metadata and sync
    func updateVideo(_ video: VideoRecord, with updates: VideoRecord) async {
        guard let index = videos.firstIndex(where: { $0.id == video.id }) else { return }
        
        var updatedVideo = updates
        updatedVideo.lastModified = Date()
        updatedVideo.syncStatus = .notSynced
        
        videos[index] = updatedVideo
        saveLocalVideos()
        
        // Queue for sync
        queueForSync(updatedVideo)
        
        logger.info("Updated video: \(video.id)")
    }
    
    /// Delete video from local storage and cloud
    func deleteVideo(_ video: VideoRecord) async {
        logger.info("Deleting video: \(video.id)")
        
        // Cancel any ongoing upload
        uploadTasks[video.id]?.cancel()
        uploadTasks.removeValue(forKey: video.id)
        
        // Remove from processing set
        processingVideos.remove(video.id)
        uploadProgress.removeValue(forKey: video.id)
        
        // Delete local files
        if let localURL = video.localURL {
            VideoFileManager.cleanup(url: localURL)
        }
        
        if let thumbnailPath = video.thumbnailPath {
            let thumbnailURL = URL(fileURLWithPath: thumbnailPath)
            VideoFileManager.cleanup(url: thumbnailURL)
        }
        
        // Remove from collection
        videos.removeAll { $0.id == video.id }
        saveLocalVideos()
        
        // Queue deletion for sync
        syncManager.queueOperation(.delete(video.id, recordType: video.recordType))
    }
    
    /// Upload video to cloud storage
    func uploadVideo(_ video: VideoRecord) async {
        guard let localURL = video.localURL,
              !processingVideos.contains(video.id) else {
            return
        }
        
        logger.info("Starting upload for video: \(video.id)")
        
        // Mark as processing
        processingVideos.insert(video.id)
        updateVideoSyncStatus(video.id, status: .syncing)
        
        let uploadTask = Task {
            let result = await uploadToCloud(video: video, localURL: localURL)
            
            await MainActor.run {
                self.processingVideos.remove(video.id)
                self.uploadProgress.removeValue(forKey: video.id)
                self.uploadTasks.removeValue(forKey: video.id)
                
                switch result {
                case .success(let cloudURL):
                    self.updateVideoCloudURL(video.id, cloudURL: cloudURL)
                    self.updateVideoSyncStatus(video.id, status: .synced)
                    self.logger.info("Successfully uploaded video: \(video.id)")
                    
                case .failure(let error):
                    self.updateVideoSyncStatus(video.id, status: .syncFailed)
                    self.errorHandler.handle(
                        error,
                        context: "Video Upload",
                        severity: .medium,
                        canRetry: true,
                        autoRetry: true
                    )
                }
            }
        }
        
        uploadTasks[video.id] = uploadTask
    }
    
    // MARK: - Cloud Operations
    
    private func uploadToCloud(video: VideoRecord, localURL: URL) async -> Result<String, PlayerPathError> {
        // Simulate upload progress
        for progress in stride(from: 0.0, through: 1.0, by: 0.1) {
            await MainActor.run {
                self.uploadProgress[video.id] = progress
            }
            
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
            
            // Check for cancellation
            if Task.isCancelled {
                return .failure(.videoUploadFailed(reason: "Upload cancelled"))
            }
        }
        
        // TODO: Implement actual cloud upload logic
        // This would integrate with your preferred cloud storage (iCloud, AWS S3, etc.)
        
        // Simulate success/failure
        if Bool.random() {
            return .success("https://cloud.example.com/videos/\(video.id).mp4")
        } else {
            return .failure(.videoUploadFailed(reason: "Network timeout"))
        }
    }
    
    // MARK: - Batch Operations
    
    /// Upload multiple videos concurrently
    func uploadVideos(_ videos: [VideoRecord]) async {
        logger.info("Starting batch upload of \(videos.count) videos")
        
        let chunks = videos.chunked(into: maxConcurrentUploads)
        
        for chunk in chunks {
            await withTaskGroup(of: Void.self) { group in
                for video in chunk {
                    group.addTask {
                        await self.uploadVideo(video)
                    }
                }
            }
        }
    }
    
    /// Delete multiple videos
    func deleteVideos(_ videos: [VideoRecord]) async {
        logger.info("Batch deleting \(videos.count) videos")
        
        for video in videos {
            await deleteVideo(video)
        }
    }
    
    /// Mark videos as highlights
    func markAsHighlights(_ videoIds: [String]) async {
        for id in videoIds {
            if let index = videos.firstIndex(where: { $0.id == id }) {
                videos[index].isHighlight = true
                videos[index].lastModified = Date()
                videos[index].syncStatus = .notSynced
                queueForSync(videos[index])
            }
        }
        
        saveLocalVideos()
        logger.info("Marked \(videoIds.count) videos as highlights")
    }
    
    // MARK: - Sync Management
    
    private func queueForSync(_ video: VideoRecord) {
        syncManager.queueOperation(.update(video))
    }
    
    private func setupAutoSync() {
        // Auto-sync every 5 minutes if there are pending changes
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            Task { @MainActor in
                let pendingSync = self.videos.filter { $0.syncStatus == .notSynced }
                if !pendingSync.isEmpty {
                    self.logger.info("Auto-syncing \(pendingSync.count) videos")
                    await self.syncManager.performFullSync()
                }
            }
        }
    }
    
    // MARK: - Storage Management
    
    /// Clean up old local videos to free space
    func performStorageCleanup() async {
        logger.info("Starting storage cleanup")
        
        // Sort by date, oldest first
        let oldestVideos = videos
            .filter { $0.localURL != nil && $0.cloudURL != nil } // Only videos backed up to cloud
            .sorted { $0.createdDate < $1.createdDate }
        
        // Keep only the most recent videos if we exceed the limit
        if videos.count > maxLocalVideos {
            let videosToCleanup = oldestVideos.prefix(videos.count - maxLocalVideos)
            
            for video in videosToCleanup {
                // Keep the record but remove local file
                if let localURL = video.localURL {
                    VideoFileManager.cleanup(url: localURL)
                }
                
                // Update record
                if let index = videos.firstIndex(where: { $0.id == video.id }) {
                    videos[index].localURL = nil
                }
            }
            
            saveLocalVideos()
            logger.info("Cleaned up \(videosToCleanup.count) local video files")
        }
    }
    
    // MARK: - Helper Methods
    
    private func addVideo(_ video: VideoRecord) {
        videos.append(video)
        saveLocalVideos()
    }
    
    private func updateVideoSyncStatus(_ videoId: String, status: VideoRecord.SyncStatus) {
        if let index = videos.firstIndex(where: { $0.id == videoId }) {
            videos[index].syncStatus = status
            videos[index].lastModified = Date()
        }
    }
    
    private func updateVideoCloudURL(_ videoId: String, cloudURL: String) {
        if let index = videos.firstIndex(where: { $0.id == videoId }) {
            videos[index].cloudURL = cloudURL
            videos[index].lastModified = Date()
            saveLocalVideos()
        }
    }
    
    private func extractVideoMetadata(from url: URL) async -> (duration: TimeInterval, videoMetadata: VideoMetadata) {
        do {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(duration)
            
            var metadata = VideoMetadata()
            metadata.resolution = await getVideoResolution(asset: asset)
            metadata.frameRate = await getVideoFrameRate(asset: asset)
            metadata.codec = await getVideoCodec(asset: asset)
            
            return (durationSeconds, metadata)
        } catch {
            logger.error("Failed to extract video metadata: \(error)")
            return (0, VideoMetadata())
        }
    }
    
    private func getVideoResolution(asset: AVURLAsset) async -> CGSize {
        do {
            guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                return .zero
            }
            let naturalSize = try await videoTrack.load(.naturalSize)
            return naturalSize
        } catch {
            return .zero
        }
    }
    
    private func getVideoFrameRate(asset: AVURLAsset) async -> Double {
        do {
            guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                return 30.0
            }
            let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
            return Double(nominalFrameRate)
        } catch {
            return 30.0
        }
    }
    
    private func getVideoCodec(asset: AVURLAsset) async -> String {
        do {
            guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                return "Unknown"
            }
            let formatDescriptions = try await videoTrack.load(.formatDescriptions)
            if let formatDescription = formatDescriptions.first {
                let codecType = CMFormatDescriptionGetMediaSubType(formatDescription)
                return FourCharCode(codecType).string
            }
        } catch {
            // Handle error
        }
        return "Unknown"
    }
    
    private func getFileSize(at url: URL) -> Int64 {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return attributes[.size] as? Int64 ?? 0
        } catch {
            return 0
        }
    }
    
    private func generateVideoTitle() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return "Video \(formatter.string(from: Date()))"
    }
    
    private func convertValidationError(_ error: VideoFileManager.ValidationError) -> PlayerPathError {
        switch error {
        case .fileNotFound:
            return .videoFileNotFound
        case .fileTooLarge(let size):
            return .videoFileTooLarge(size: size, maxSize: 500 * 1024 * 1024)
        case .fileTooSmall:
            return .videoFileTooSmall
        case .durationTooLong(let duration):
            return .videoDurationTooLong(duration: duration, maxDuration: 600)
        case .durationTooShort(let duration):
            return .videoDurationTooShort(duration: duration, minDuration: 1)
        case .invalidFormat:
            return .unsupportedVideoFormat(format: nil)
        case .corruptedFile:
            return .videoFileCorrupted
        }
    }
    
    // MARK: - Persistence
    
    private func loadLocalVideos() {
        // TODO: Implement local persistence (Core Data, SwiftData, or JSON)
        // For now, start with empty array
        videos = []
        logger.info("Loaded \(videos.count) local videos")
    }
    
    private func saveLocalVideos() {
        // TODO: Implement local persistence
        logger.debug("Saved video metadata to local storage")
    }
}

// MARK: - Extensions

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

extension FourCharCode {
    var string: String {
        let bytes = [
            UInt8((self >> 24) & 0xFF),
            UInt8((self >> 16) & 0xFF),
            UInt8((self >> 8) & 0xFF),
            UInt8(self & 0xFF)
        ]
        return String(bytes: bytes, encoding: .utf8) ?? "Unknown"
    }
}