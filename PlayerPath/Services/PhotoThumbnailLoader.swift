//
//  PhotoThumbnailLoader.swift
//  PlayerPath
//
//  Shared CGImageSource pipeline for photo thumbnails. Used by PhotoThumbnailCell
//  and PhotoHeroCell so both render through the same fallback chain.
//

import UIKit
import ImageIO

enum PhotoThumbnailLoader {
    // In-memory cache keyed by photo.id + maxPixelSize. NSCache is thread-safe,
    // bounded by both count and total decoded-byte cost, and self-evicts under
    // memory pressure. Mirrors ThumbnailCache (the video path) so the photo grid
    // stops re-decoding from disk on every cell re-appearance — the video grid
    // already had this; the photo grid did not.
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 200
        c.totalCostLimit = StorageConstants.thumbnailCacheSizeBytes
        return c
    }()

    // Deduplicate concurrent loads of the same key so a fast scroll doesn't kick off
    // N decodes of the same photo. MainActor-confined — this enum is MainActor-isolated
    // by the module's default actor isolation (see the `nonisolated` on makeThumbnail).
    private static var inFlight: [NSString: Task<UIImage?, Never>] = [:]

    /// Load a downsampled thumbnail for the given photo. Returns nil if all paths fail.
    /// Serves from the in-memory cache on repeat appearances; otherwise decodes once
    /// (off-main) and caches the result.
    ///
    /// The uncached decode tries, in order:
    /// 1. The cached aspect-preserving thumbnail at `resolvedThumbnailPath`. Legacy
    ///    300×300 square crops are detected by aspect ratio and skipped.
    /// 2. The full-size photo at `resolvedFilePath` (handles legacy squares + missing thumbs).
    /// 3. Cloud download via `VideoCloudManager` when `cloudURL` is set.
    static func load(for photo: Photo, maxPixelSize: Int = 600) async -> UIImage? {
        let key = "\(photo.id.uuidString)#\(maxPixelSize)" as NSString

        if let cached = cache.object(forKey: key) { return cached }
        if let existing = inFlight[key] { return await existing.value }

        // `Photo` is a non-Sendable @Model — snapshot the paths on the main actor
        // before handing the synchronous decode to a detached (off-main) task.
        let thumbPath = photo.resolvedThumbnailPath
        let filePath = photo.resolvedFilePath
        let cloudURL = photo.cloudURL

        let task = Task<UIImage?, Never> {
            let image = await loadUncached(thumbPath: thumbPath, filePath: filePath, cloudURL: cloudURL, maxPixelSize: maxPixelSize)
            if let image {
                let cost = Int(image.size.width * image.scale * image.size.height * image.scale * 4)
                cache.setObject(image, forKey: key, cost: cost)
            }
            inFlight[key] = nil
            return image
        }
        inFlight[key] = task
        return await task.value
    }

    /// Evict cached entries for a photo whose underlying bytes changed (e.g. a cloud
    /// re-download or a re-home/split that repoints the file). Re-tag/caption don't
    /// touch pixels, so they need not call this.
    static func invalidate(photoID: UUID) {
        for size in [300, 600, 1200] {
            cache.removeObject(forKey: "\(photoID.uuidString)#\(size)" as NSString)
        }
    }

    /// The disk → cloud-download → disk decode chain, cache-free so `load` can wrap it.
    private static func loadUncached(thumbPath: String?, filePath: String, cloudURL: String?, maxPixelSize: Int) async -> UIImage? {
        if let image = await decode(thumbPath: thumbPath, filePath: filePath, maxPixelSize: maxPixelSize) {
            return image
        }

        if let cloudURL, !cloudURL.isEmpty {
            do {
                try await VideoCloudManager.shared.downloadPhoto(from: cloudURL, to: filePath)
                // The full-size file now exists; `thumbPath: nil` skips the cached-thumb branch.
                if let image = await decode(thumbPath: nil, filePath: filePath, maxPixelSize: maxPixelSize) {
                    return image
                }
            } catch {
                // Download failed; fall through to nil.
            }
        }

        return nil
    }

    /// Runs the synchronous ImageIO pipeline off the main thread via `Task.detached`
    /// — the codebase's established off-main convention (see `SyncCoordinator+Photos`
    /// and `VideoFileManager`). Takes only Sendable Strings; never touches the @Model.
    private static func decode(thumbPath: String?, filePath: String, maxPixelSize: Int) async -> UIImage? {
        await Task.detached(priority: .userInitiated) { () -> UIImage? in
            if let thumbPath, FileManager.default.fileExists(atPath: thumbPath) {
                let thumbURL = URL(fileURLWithPath: thumbPath) as CFURL
                if let source = CGImageSourceCreateWithURL(thumbURL, nil),
                   let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                   let pw = props[kCGImagePropertyPixelWidth] as? Int,
                   let ph = props[kCGImagePropertyPixelHeight] as? Int,
                   abs(Double(pw) / Double(max(ph, 1)) - 1.0) > 0.05, // not square → new-style
                   max(pw, ph) >= maxPixelSize { // thumb is big enough for this request
                    // The cached thumb (~600px longest side) satisfies grid/headshot
                    // requests but NOT the hero's 1200px ask — ImageIO won't upscale,
                    // so a larger request must fall through to the full-size file below
                    // to render crisp instead of a 600px image stretched to fill.
                    if let cgImage = makeThumbnail(source: source, maxPixelSize: maxPixelSize) {
                        return UIImage(cgImage: cgImage)
                    }
                }
            }

            let url = URL(fileURLWithPath: filePath) as CFURL
            if let source = CGImageSourceCreateWithURL(url, nil),
               let cgImage = makeThumbnail(source: source, maxPixelSize: maxPixelSize) {
                return UIImage(cgImage: cgImage)
            }

            return nil
        }.value
    }

    nonisolated private static func makeThumbnail(source: CGImageSource, maxPixelSize: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
