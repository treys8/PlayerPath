//
//  ThumbnailCache.swift
//  PlayerPath
//
//  Created by Assistant on 11/17/25.
//  Extracted from VideoClipsView for shared use across the app
//

import UIKit

/// Thread-safe cache for video thumbnail images with automatic memory management
@MainActor final class ThumbnailCache {
    
    static let shared = ThumbnailCache()
    
    private let cache = NSCache<NSString, UIImage>()
    private let maxCacheSize = 100
    private let maxMemorySize = StorageConstants.thumbnailCacheSizeBytes
    private var loadingTasks: [String: Task<UIImage, Error>] = [:]
    private var memoryWarningObserver: NSObjectProtocol?
    
    // MARK: - Initialization
    
    private init() {
        cache.countLimit = maxCacheSize
        cache.totalCostLimit = maxMemorySize

        // Properly handle memory warnings
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.cache.removeAllObjects()
            }
        }
    }
    
    deinit {
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // MARK: - Public API
    
    /// Normalize a stored thumbnail path to an absolute filesystem path.
    /// Accepts both legacy absolute paths and new paths stored relative to Documents.
    /// Callers may pass either form — this resolver makes the cache transparent to the storage convention.
    static func resolveLocalPath(_ path: String) -> String {
        if path.hasPrefix("/") { return path }
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return path
        }
        return docs.appendingPathComponent(path).path
    }

    /// Load a thumbnail from cache or disk (deduplicates concurrent requests)
    /// - Parameters:
    ///   - path: File path to the thumbnail (absolute or relative to Documents)
    ///   - targetSize: Optional target size for downsampling (reduces memory usage)
    func loadThumbnail(at rawPath: String, targetSize: CGSize? = nil) async throws -> UIImage {
        let path = Self.resolveLocalPath(rawPath)
        let key = path as NSString

        // Check memory cache first (NSCache is thread-safe)
        if let cachedImage = cache.object(forKey: key) {
            return cachedImage
        }

        // Check if already loading this path
        if let existingTask = loadingTasks[path] {
            return try await existingTask.value
        }

        // Capture scale on MainActor before dispatching to the background thread.
        let screenScale = UITraitCollection.current.displayScale

        // Create new loading task
        let task = Task<UIImage, Error> {
            // Perform disk IO off the main actor
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    if !FileManager.default.fileExists(atPath: path) {
                        continuation.resume(throwing: ThumbnailError.fileNotFound)
                        return
                    }

                    // Use downsampling if target size is provided
                    if let targetSize = targetSize {
                        if let downsampledImage = self.downsampleImage(at: URL(fileURLWithPath: path), to: targetSize, scale: screenScale) {
                            continuation.resume(returning: downsampledImage)
                            return
                        }
                    }

                    // Fall back to regular loading
                    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                          let image = UIImage(data: data) else {
                        continuation.resume(throwing: ThumbnailError.invalidImage)
                        return
                    }
                    continuation.resume(returning: image)
                }
            }
        }
        
        loadingTasks[path] = task
        
        do {
            let image = try await task.value
            
            // Calculate proper cost with scale factor
            let pixelWidth = image.size.width * image.scale
            let pixelHeight = image.size.height * image.scale
            let cost = Int(pixelWidth * pixelHeight * 4) // 4 bytes per pixel (RGBA)
            
            cache.setObject(image, forKey: key, cost: cost)
            
            loadingTasks.removeValue(forKey: path)
            return image
        } catch {
            loadingTasks.removeValue(forKey: path)
            throw error
        }
    }
    
    /// Preload a thumbnail into cache (useful for scroll prefetching)
    /// - Parameters:
    ///   - path: File path to the thumbnail
    ///   - targetSize: Optional target size for downsampling
    func preloadThumbnail(at rawPath: String, targetSize: CGSize? = nil) async {
        do {
            _ = try await loadThumbnail(at: rawPath, targetSize: targetSize)
        } catch {
            // Silently fail for preloading
        }
    }

    /// Prefetch multiple thumbnails in the background (useful for scroll anticipation)
    /// - Parameters:
    ///   - paths: Array of thumbnail paths to prefetch
    ///   - targetSize: Optional target size for downsampling
    func prefetchThumbnails(paths: [String], targetSize: CGSize? = nil) {
        Task(priority: .utility) {
            await withTaskGroup(of: Void.self) { group in
                for path in paths.prefix(10) { // Limit to 10 concurrent prefetches
                    group.addTask {
                        await self.preloadThumbnail(at: path, targetSize: targetSize)
                    }
                }
            }
        }
    }
    
    /// Remove a specific thumbnail from cache
    func removeThumbnail(at rawPath: String) {
        let path = Self.resolveLocalPath(rawPath)
        let key = path as NSString
        cache.removeObject(forKey: key)
        loadingTasks[path]?.cancel()
        loadingTasks.removeValue(forKey: path)
    }
    
    // MARK: - Remote Thumbnail API

    /// Load a thumbnail from a remote URL, caching to disk + memory for instant subsequent loads.
    /// Uses the same NSCache, deduplication, and downsampling as local thumbnails.
    /// - Parameters:
    ///   - cacheKey: Stable key for this thumbnail (e.g. "folderID_videoFileName")
    ///   - urlProvider: Async closure that returns the download URL (e.g. signed URL from Cloud Function)
    ///   - targetSize: Optional target size for downsampling
    func loadRemoteThumbnail(
        cacheKey: String,
        urlProvider: @escaping () async throws -> String,
        targetSize: CGSize? = nil
    ) async throws -> UIImage {
        let nsKey = cacheKey as NSString

        // 1. Check memory cache
        if let cached = cache.object(forKey: nsKey) {
            return cached
        }

        // 2. Check disk cache — load and store under cacheKey (not disk path)
        let diskPath = sharedThumbnailPath(for: cacheKey)
        if FileManager.default.fileExists(atPath: diskPath) {
            let image = try await loadThumbnail(at: diskPath, targetSize: targetSize)
            // Also store under cacheKey so future memory cache lookups hit
            let pixelW = image.size.width * image.scale
            let pixelH = image.size.height * image.scale
            cache.setObject(image, forKey: nsKey, cost: Int(pixelW * pixelH * 4))
            return image
        }

        // 3. Deduplicate concurrent requests
        if let existingTask = loadingTasks[cacheKey] {
            return try await existingTask.value
        }

        let screenScale = UITraitCollection.current.displayScale

        // 4. Download, save to disk, load into cache
        let task = Task<UIImage, Error> {
            let urlString = try await urlProvider()
            guard let url = URL(string: urlString) else {
                throw ThumbnailError.downloadFailed
            }

            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  !data.isEmpty else {
                throw ThumbnailError.downloadFailed
            }

            // Write to disk and downsample off MainActor
            let capturedData = data
            let capturedDiskPath = diskPath
            let capturedTargetSize = targetSize
            let capturedScale = screenScale

            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let diskURL = URL(fileURLWithPath: capturedDiskPath)
                    try? FileManager.default.createDirectory(
                        at: diskURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try? capturedData.write(to: diskURL)

                    if let targetSize = capturedTargetSize {
                        if let image = self.downsampleImage(at: diskURL, to: targetSize, scale: capturedScale) {
                            continuation.resume(returning: image)
                            return
                        }
                    }

                    guard let image = UIImage(data: capturedData) else {
                        continuation.resume(throwing: ThumbnailError.invalidImage)
                        return
                    }
                    continuation.resume(returning: image)
                }
            }
        }

        loadingTasks[cacheKey] = task

        do {
            let image = try await task.value
            let pixelWidth = image.size.width * image.scale
            let pixelHeight = image.size.height * image.scale
            let cost = Int(pixelWidth * pixelHeight * 4)
            cache.setObject(image, forKey: nsKey, cost: cost)
            loadingTasks.removeValue(forKey: cacheKey)
            return image
        } catch {
            loadingTasks.removeValue(forKey: cacheKey)
            throw error
        }
    }

    /// Prefetch multiple remote thumbnails in the background
    func prefetchRemoteThumbnails(
        items: [(cacheKey: String, urlProvider: () async throws -> String)],
        targetSize: CGSize? = nil
    ) {
        Task(priority: .utility) {
            await withTaskGroup(of: Void.self) { group in
                for item in items.prefix(6) {
                    let key = item.cacheKey
                    let provider = item.urlProvider
                    group.addTask {
                        _ = try? await self.loadRemoteThumbnail(
                            cacheKey: key,
                            urlProvider: provider,
                            targetSize: targetSize
                        )
                    }
                }
            }
        }
    }

    /// Clear all cached thumbnails
    func clearCache() {
        cache.removeAllObjects()
        loadingTasks.values.forEach { $0.cancel() }
        loadingTasks.removeAll()
    }

    // MARK: - Private Helpers

    private func sharedThumbnailPath(for cacheKey: String) -> String {
        guard let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return "" }
        let thumbDir = cacheDir.appendingPathComponent("shared_thumbnails", isDirectory: true)
        let sanitized = cacheKey.replacingOccurrences(of: "/", with: "_")
        return thumbDir.appendingPathComponent("\(sanitized).jpg").path
    }

    /// Downsample an image to reduce memory usage
    /// This is much more memory-efficient than loading full resolution and then scaling
    private nonisolated func downsampleImage(at imageURL: URL, to pointSize: CGSize, scale: CGFloat) -> UIImage? {
        let pixelSize = CGSize(width: max(pointSize.width * scale, 1), height: max(pointSize.height * scale, 1))

        // Create image source
        guard let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil) else {
            return nil
        }

        // Configure downsampling options
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: max(pixelSize.width, pixelSize.height),
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]

        // Generate downsampled image
        guard let downsampledImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            return nil
        }

        return UIImage(cgImage: downsampledImage)
    }
}

// MARK: - Error Types

enum ThumbnailError: LocalizedError {
    case fileNotFound
    case invalidImage
    case downloadFailed

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Thumbnail file not found"
        case .invalidImage:
            return "Invalid image file"
        case .downloadFailed:
            return "Failed to download thumbnail"
        }
    }
}
