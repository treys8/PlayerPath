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
    /// Load a downsampled thumbnail for the given photo. Returns nil if all paths fail.
    ///
    /// Tries, in order:
    /// 1. The cached aspect-preserving thumbnail at `resolvedThumbnailPath`. Legacy
    ///    300×300 square crops are detected by aspect ratio and skipped.
    /// 2. The full-size photo at `resolvedFilePath` (handles legacy squares + missing thumbs).
    /// 3. Cloud download via `VideoCloudManager` when `cloudURL` is set.
    static func load(for photo: Photo, maxPixelSize: Int = 600) async -> UIImage? {
        // `Photo` is a non-Sendable @Model — snapshot the paths on the main actor
        // before handing the synchronous decode to a detached (off-main) task.
        let thumbPath = photo.resolvedThumbnailPath
        let filePath = photo.resolvedFilePath
        let cloudURL = photo.cloudURL

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
                   abs(Double(pw) / Double(max(ph, 1)) - 1.0) > 0.05 { // not square → new-style
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
