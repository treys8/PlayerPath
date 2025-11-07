//
//  VideoStorageProtocols.swift
//  PlayerPath
//
//  Storage abstractions and implementations for video management
//

import Foundation
import AVFoundation

// MARK: - Cloud Storage Protocol
protocol VideoCloudStorageProtocol {
    func upload(
        _ localURL: URL, 
        metadata: VideoMetadata,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> String
    
    func download(from cloudURL: String, to localURL: URL) async throws
    func delete(_ cloudURL: String) async throws
    func listVideos(for userID: String) async throws -> [VideoMetadata]
}

// MARK: - Local Storage Implementation
@MainActor
class VideoLocalStorage: ObservableObject {
    private let fileManager = FileManager.default
    private let videosDirectory: URL
    
    init() {
        // Create videos directory in documents
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        videosDirectory = documentsPath.appendingPathComponent("Videos")
        
        // Ensure directory exists
        try? fileManager.createDirectory(at: videosDirectory, withIntermediateDirectories: true)
    }
    
    func store(_ sourceURL: URL, for videoClip: VideoClip) async throws -> URL {
        let destinationURL = videosDirectory.appendingPathComponent(videoClip.fileName)
        
        // Copy file to local storage
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        
        return destinationURL
    }
    
    func getURL(for videoClip: VideoClip) async throws -> URL? {
        let url = videosDirectory.appendingPathComponent(videoClip.fileName)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }
    
    func getVideoClip(id: UUID) async throws -> VideoClip? {
        // TODO: This would need to integrate with SwiftData to fetch the VideoClip
        // For now, return nil as placeholder
        return nil
    }
    
    func delete(_ videoClip: VideoClip) async throws {
        let url = videosDirectory.appendingPathComponent(videoClip.fileName)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }
    
    func listLocalVideos() async throws -> [URL] {
        let contents = try fileManager.contentsOfDirectory(
            at: videosDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )
        
        return contents.filter { url in
            ["mp4", "mov", "m4v"].contains(url.pathExtension.lowercased())
        }
    }
    
    func getStorageSize() async throws -> Int64 {
        let videos = try await listLocalVideos()
        var totalSize: Int64 = 0
        
        for videoURL in videos {
            let resourceValues = try videoURL.resourceValues(forKeys: [.fileSizeKey])
            totalSize += Int64(resourceValues.fileSize ?? 0)
        }
        
        return totalSize
    }
}

// MARK: - Firebase Storage Implementation
class FirebaseVideoStorage: VideoCloudStorageProtocol {
    // Note: Commented out until Firebase Storage is properly set up
    // private let storage = Storage.storage()
    
    func upload(
        _ localURL: URL, 
        metadata: VideoMetadata,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> String {
        // TODO: Implement when Firebase Storage is configured
        throw PlayerPathError.featureNotAvailable(feature: "Firebase Storage not yet configured")
        
        /*
        let storageRef = storage.reference()
            .child("videos")
            .child(metadata.userID)
            .child("\(metadata.id.uuidString).mp4")
        
        // Create metadata for the upload
        let firebaseMetadata = StorageMetadata()
        firebaseMetadata.contentType = "video/mp4"
        firebaseMetadata.customMetadata = [
            "originalFileName": metadata.fileName,
            "duration": String(metadata.duration),
            "resolution": metadata.resolution,
            "isHighlight": String(metadata.isHighlight)
        ]
        
        let uploadTask = storageRef.putFile(from: localURL, metadata: firebaseMetadata)
        
        // Monitor progress
        uploadTask.observe(.progress) { snapshot in
            let progress = Double(snapshot.progress?.completedUnitCount ?? 0) / 
                          Double(snapshot.progress?.totalUnitCount ?? 1)
            progressHandler(progress)
        }
        
        let _ = try await uploadTask
        let downloadURL = try await storageRef.downloadURL()
        return downloadURL.absoluteString
        */
    }
    
    func download(from cloudURL: String, to localURL: URL) async throws {
        throw PlayerPathError.featureNotAvailable(feature: "Firebase Storage not yet configured")
        
        /*
        guard let url = URL(string: cloudURL) else {
            throw PlayerPathError.invalidFilePath(path: cloudURL)
        }
        
        let data = try Data(contentsOf: url)
        try data.write(to: localURL)
        */
    }
    
    func delete(_ cloudURL: String) async throws {
        throw PlayerPathError.featureNotAvailable(feature: "Firebase Storage not yet configured")
        
        /*
        let storageRef = Storage.storage().reference(forURL: cloudURL)
        try await storageRef.delete()
        */
    }
    
    func listVideos(for userID: String) async throws -> [VideoMetadata] {
        throw PlayerPathError.featureNotAvailable(feature: "Firebase Storage not yet configured")
        
        /*
        let storageRef = storage.reference().child("videos").child(userID)
        let result = try await storageRef.listAll()
        
        var videos: [VideoMetadata] = []
        
        for item in result.items {
            let metadata = try await item.getMetadata()
            let downloadURL = try await item.downloadURL()
            
            // Parse metadata
            let customMetadata = metadata.customMetadata ?? [:]
            let videoMetadata = VideoMetadata(
                id: UUID(uuidString: item.name.replacingOccurrences(of: ".mp4", with: "")) ?? UUID(),
                fileName: customMetadata["originalFileName"] ?? item.name,
                userID: userID,
                createdAt: metadata.timeCreated ?? Date(),
                duration: TimeInterval(customMetadata["duration"] ?? "0") ?? 0,
                fileSize: Int(metadata.size),
                resolution: customMetadata["resolution"] ?? "unknown",
                isHighlight: customMetadata["isHighlight"] == "true"
            )
            
            videos.append(videoMetadata)
        }
        
        return videos
        */
    }
}

// MARK: - CloudKit Storage Implementation (Alternative)
class CloudKitVideoStorage: VideoCloudStorageProtocol {
    // CloudKit doesn't support large file uploads directly
    // This would need to use CKAsset for file references and external storage
    
    func upload(
        _ localURL: URL, 
        metadata: VideoMetadata,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> String {
        throw PlayerPathError.featureNotAvailable(feature: "CloudKit video storage not recommended for large files")
        
        // CloudKit approach would be:
        // 1. Create CKAsset from local file
        // 2. Create CKRecord with metadata + asset
        // 3. Save to CloudKit
        // But this has file size limitations and is not ideal for videos
    }
    
    func download(from cloudURL: String, to localURL: URL) async throws {
        throw PlayerPathError.featureNotAvailable(feature: "CloudKit video storage not implemented")
    }
    
    func delete(_ cloudURL: String) async throws {
        throw PlayerPathError.featureNotAvailable(feature: "CloudKit video storage not implemented")
    }
    
    func listVideos(for userID: String) async throws -> [VideoMetadata] {
        throw PlayerPathError.featureNotAvailable(feature: "CloudKit video storage not implemented")
    }
}

// MARK: - Video Compression Service
@MainActor
class VideoCompressionService: ObservableObject {
    @Published var isCompressing = false
    
    func compressVideo(
        at inputURL: URL,
        quality: VideoQuality,
        progressHandler: @escaping (Double) -> Void = { _ in }
    ) async throws -> URL {
        isCompressing = true
        defer { isCompressing = false }
        
        return try await withCheckedThrowingContinuation { continuation in
            let asset = AVAsset(url: inputURL)
            
            guard let exportSession = AVAssetExportSession(
                asset: asset,
                presetName: quality.exportPreset
            ) else {
                continuation.resume(throwing: PlayerPathError.videoCompressionFailed(reason: "Could not create export session"))
                return
            }
            
            // Create output URL
            let outputURL = createTempURL(extension: "mp4")
            exportSession.outputURL = outputURL
            exportSession.outputFileType = .mp4
            
            // Configure compression settings if using custom preset
            if quality != .high {
                exportSession.videoComposition = createVideoComposition(for: asset, quality: quality)
            }
            
            // Monitor progress
            let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                let progress = Double(exportSession.progress)
                Task { @MainActor in
                    progressHandler(progress)
                }
            }
            
            // Start compression
            exportSession.exportAsynchronously {
                progressTimer.invalidate()
                
                switch exportSession.status {
                case .completed:
                    continuation.resume(returning: outputURL)
                case .failed:
                    let error = exportSession.error ?? 
                               PlayerPathError.videoCompressionFailed(reason: "Export failed with unknown error")
                    continuation.resume(throwing: error)
                case .cancelled:
                    continuation.resume(throwing: PlayerPathError.videoCompressionFailed(reason: "Export was cancelled"))
                default:
                    continuation.resume(throwing: PlayerPathError.videoCompressionFailed(reason: "Export failed with status: \(exportSession.status)"))
                }
            }
        }
    }
    
    private func createTempURL(extension: String) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = UUID().uuidString + ".\(`extension`)"
        return tempDir.appendingPathComponent(fileName)
    }
    
    private func createVideoComposition(for asset: AVAsset, quality: VideoQuality) -> AVVideoComposition? {
        // TODO: Implement custom video composition for fine-grained control
        // This would allow custom resolution, bitrate, etc.
        return nil
    }
}

// MARK: - Mock Storage for Testing
class MockVideoCloudStorage: VideoCloudStorageProtocol {
    var shouldSimulateError = false
    var uploadDelay: TimeInterval = 1.0
    var mockVideos: [VideoMetadata] = []
    
    func upload(
        _ localURL: URL,
        metadata: VideoMetadata,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> String {
        if shouldSimulateError {
            throw PlayerPathError.videoUploadFailed(reason: "Mock upload failure")
        }
        
        // Simulate progress
        for i in 1...10 {
            try await Task.sleep(nanoseconds: UInt64(uploadDelay * 100_000_000)) // 0.1 * delay
            progressHandler(Double(i) / 10.0)
        }
        
        let mockURL = "https://mock-storage.com/\(metadata.id.uuidString).mp4"
        mockVideos.append(metadata)
        return mockURL
    }
    
    func download(from cloudURL: String, to localURL: URL) async throws {
        if shouldSimulateError {
            throw PlayerPathError.videoDownloadFailed(reason: "Mock download failure")
        }
        
        // Simulate download delay
        try await Task.sleep(nanoseconds: UInt64(uploadDelay * 1_000_000_000))
        
        // Create a dummy file
        try Data().write(to: localURL)
    }
    
    func delete(_ cloudURL: String) async throws {
        if shouldSimulateError {
            throw PlayerPathError.unknownError(NSError(domain: "MockError", code: -1))
        }
        
        mockVideos.removeAll { metadata in
            cloudURL.contains(metadata.id.uuidString)
        }
    }
    
    func listVideos(for userID: String) async throws -> [VideoMetadata] {
        if shouldSimulateError {
            throw PlayerPathError.networkUnavailable
        }
        
        return mockVideos.filter { $0.userID == userID }
    }
}