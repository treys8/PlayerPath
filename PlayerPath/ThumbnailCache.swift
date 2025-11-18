//
//  ThumbnailCache.swift
//  PlayerPath
//
//  Created by Assistant on 11/17/25.
//

import UIKit
import os

/// Thread-safe cache for video thumbnail images with automatic memory management
@MainActor
final class ThumbnailCache {
    
    static let shared = ThumbnailCache()
    
    private let cache = NSCache<NSString, UIImage>()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.example.PlayerPath", category: "ThumbnailCache")
    
    // MARK: - Configuration
    
    private init() {
        // Configure cache limits
        cache.countLimit = 100 // Maximum number of images
        cache.totalCostLimit = 50 * 1024 * 1024 // 50MB max memory usage
        
        // Clear cache on memory warning
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.clearCache()
        }
        
        logger.info("ThumbnailCache initialized with countLimit: 100, totalCostLimit: 50MB")
    }
    
    // MARK: - Public API
    
    /// Load a thumbnail from cache or disk
    /// - Parameter path: File path to the thumbnail image
    /// - Returns: The loaded UIImage
    /// - Throws: Error if loading fails
    func loadThumbnail(at path: String) async throws -> UIImage {
        let key = path as NSString
        
        // Check memory cache first
        if let cachedImage = cache.object(forKey: key) {
            logger.debug("Cache hit for thumbnail: \(path, privacy: .public)")
            return cachedImage
        }
        
        // Load from disk
        logger.debug("Cache miss, loading from disk: \(path, privacy: .public)")
        let url = URL(fileURLWithPath: path)
        
        return try await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url),
                  let image = UIImage(data: data) else {
                throw ThumbnailError.loadFailed
            }
            
            await MainActor.run {
                // Calculate cost based on image size (width * height * 4 bytes per pixel)
                let cost = Int(image.size.width * image.size.height * 4)
                self.cache.setObject(image, forKey: key, cost: cost)
                self.logger.debug("Cached thumbnail with cost: \(cost) bytes")
            }
            
            return image
        }.value
    }
    
    /// Preload a thumbnail into cache (useful for prefetching)
    func preloadThumbnail(at path: String) async {
        do {
            _ = try await loadThumbnail(at: path)
        } catch {
            logger.error("Failed to preload thumbnail at \(path, privacy: .public): \(error.localizedDescription)")
        }
    }
    
    /// Remove a specific thumbnail from cache
    func removeThumbnail(at path: String) {
        let key = path as NSString
        cache.removeObject(forKey: key)
        logger.debug("Removed thumbnail from cache: \(path, privacy: .public)")
    }
    
    /// Clear all cached thumbnails
    func clearCache() {
        cache.removeAllObjects()
        logger.info("Cleared all cached thumbnails")
    }
    
    // MARK: - Cache Statistics (for debugging)
    
    var cacheDescription: String {
        "ThumbnailCache - countLimit: \(cache.countLimit), totalCostLimit: \(cache.totalCostLimit / 1024 / 1024)MB"
    }
}

// MARK: - Error Types

enum ThumbnailError: LocalizedError {
    case loadFailed
    case fileNotFound
    case invalidImageData
    
    var errorDescription: String? {
        switch self {
        case .loadFailed:
            return "Failed to load thumbnail image"
        case .fileNotFound:
            return "Thumbnail file not found"
        case .invalidImageData:
            return "Thumbnail data is corrupted or invalid"
        }
    }
}
