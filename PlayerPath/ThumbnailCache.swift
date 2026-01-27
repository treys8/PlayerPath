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
    private let maxMemorySize = 50 * 1024 * 1024 // 50MB
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
    
    /// Load a thumbnail from cache or disk (deduplicates concurrent requests)
    /// - Parameters:
    ///   - path: File path to the thumbnail
    ///   - targetSize: Optional target size for downsampling (reduces memory usage)
    func loadThumbnail(at path: String, targetSize: CGSize? = nil) async throws -> UIImage {
        let key = path as NSString

        // Check memory cache first (NSCache is thread-safe)
        if let cachedImage = cache.object(forKey: key) {
            Task { @MainActor in
                PerformanceMonitor.shared.recordCacheHit()
            }
            return cachedImage
        }

        // Record cache miss
        Task { @MainActor in
            PerformanceMonitor.shared.recordCacheMiss()
        }

        // Check if already loading this path
        if let existingTask = loadingTasks[path] {
            return try await existingTask.value
        }

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
                        if let downsampledImage = self.downsampleImage(at: URL(fileURLWithPath: path), to: targetSize) {
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
    func preloadThumbnail(at path: String, targetSize: CGSize? = nil) async {
        do {
            _ = try await loadThumbnail(at: path, targetSize: targetSize)
        } catch {
            // Silently fail for preloading
        }
    }

    /// Prefetch multiple thumbnails in the background (useful for scroll anticipation)
    /// - Parameters:
    ///   - paths: Array of thumbnail paths to prefetch
    ///   - targetSize: Optional target size for downsampling
    func prefetchThumbnails(paths: [String], targetSize: CGSize? = nil) {
        Task.detached(priority: .utility) {
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
    func removeThumbnail(at path: String) {
        let key = path as NSString
        cache.removeObject(forKey: key)
        loadingTasks[path]?.cancel()
        loadingTasks.removeValue(forKey: path)
    }
    
    /// Clear all cached thumbnails
    func clearCache() {
        cache.removeAllObjects()
        loadingTasks.values.forEach { $0.cancel() }
        loadingTasks.removeAll()
    }

    // MARK: - Private Helpers

    /// Downsample an image to reduce memory usage
    /// This is much more memory-efficient than loading full resolution and then scaling
    private nonisolated func downsampleImage(at imageURL: URL, to pointSize: CGSize) -> UIImage? {
        // Calculate scale for screen
        let scale = UIScreen.main.scale
        let pixelSize = CGSize(width: pointSize.width * scale, height: pointSize.height * scale)

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
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Thumbnail file not found"
        case .invalidImage:
            return "Invalid image file"
        }
    }
}
