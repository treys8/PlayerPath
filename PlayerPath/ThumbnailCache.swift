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
        let cacheRef = cache
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { _ in
            cacheRef.removeAllObjects()
        }
    }
    
    deinit {
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // MARK: - Public API
    
    /// Load a thumbnail from cache or disk (deduplicates concurrent requests)
    func loadThumbnail(at path: String) async throws -> UIImage {
        let key = path as NSString
        
        // Check memory cache first (NSCache is thread-safe)
        if let cachedImage = cache.object(forKey: key) {
            return cachedImage
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
    func preloadThumbnail(at path: String) async {
        do {
            _ = try await loadThumbnail(at: path)
        } catch {
            // Silently fail for preloading
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
