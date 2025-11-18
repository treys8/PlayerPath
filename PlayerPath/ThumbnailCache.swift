//
//  ThumbnailCache.swift
//  PlayerPath
//
//  Created by Assistant on 11/17/25.
//  Extracted from VideoClipsView for shared use across the app
//

import UIKit

/// Thread-safe cache for video thumbnail images with automatic memory management
@MainActor
final class ThumbnailCache {
    
    static let shared = ThumbnailCache()
    
    private let cache = NSCache<NSString, UIImage>()
    private let maxCacheSize = 100 // Maximum number of thumbnails to cache
    private let maxMemorySize = 50 * 1024 * 1024 // 50MB
    
    // MARK: - Initialization
    
    private init() {
        // Configure cache limits
        cache.countLimit = maxCacheSize
        cache.totalCostLimit = maxMemorySize
        
        // Clear cache on memory warning
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                ThumbnailCache.shared.clearCache()
            }
        }
    }
    
    // MARK: - Public API
    
    /// Load a thumbnail from cache or disk
    /// - Parameter path: File path to the thumbnail image
    /// - Returns: The loaded UIImage
    /// - Throws: ThumbnailError if loading fails
    func loadThumbnail(at path: String) async throws -> UIImage {
        let key = path as NSString
        
        // Check memory cache first
        if let cachedImage = cache.object(forKey: key) {
            return cachedImage
        }
        
        // Load from disk in background
        return try await Task.detached(priority: .userInitiated) {
            guard FileManager.default.fileExists(atPath: path) else {
                throw ThumbnailError.fileNotFound
            }
            
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let image = UIImage(data: data) else {
                throw ThumbnailError.invalidImage
            }
            
            // Cache on main actor with cost calculation
            await MainActor.run {
                // Calculate cost: width * height * 4 bytes per pixel
                let cost = Int(image.size.width * image.size.height * 4)
                self.cache.setObject(image, forKey: key, cost: cost)
            }
            
            return image
        }.value
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
    }
    
    /// Clear all cached thumbnails
    func clearCache() {
        cache.removeAllObjects()
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
