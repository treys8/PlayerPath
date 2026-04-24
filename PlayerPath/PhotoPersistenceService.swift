//
//  PhotoPersistenceService.swift
//  PlayerPath
//
//  Saves photos to Documents/Photos, generates thumbnails, creates SwiftData records.
//

import UIKit
import SwiftData
import Foundation
import ImageIO
import UniformTypeIdentifiers

@MainActor
final class PhotoPersistenceService {

    private nonisolated enum Constants {
        static let photosFolderName = "Photos"
        static let thumbnailsFolderName = "PhotoThumbnails"
        static let thumbnailSize = CGSize(width: 300, height: 300)
        static let jpegQuality: CGFloat = 0.8
        static let thumbnailQuality: CGFloat = 0.7
    }

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    // MARK: - Directory Setup

    private nonisolated func ensurePhotosDirectory() throws -> URL {
        let documentsURL = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let photosDir = documentsURL.appendingPathComponent(Constants.photosFolderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: photosDir.path) {
            try FileManager.default.createDirectory(at: photosDir, withIntermediateDirectories: true)
        }
        return photosDir
    }

    private nonisolated func ensureThumbnailsDirectory() throws -> URL {
        let documentsURL = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let thumbDir = documentsURL.appendingPathComponent(Constants.thumbnailsFolderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: thumbDir.path) {
            try FileManager.default.createDirectory(at: thumbDir, withIntermediateDirectories: true)
        }
        return thumbDir
    }

    // MARK: - Image Processing (off main thread)

    private struct ProcessedPhoto: Sendable {
        let photoURL: URL
        let thumbURL: URL
        let captureDate: Date?
    }

    /// EXIF/TIFF date strings use `yyyy:MM:dd HH:mm:ss` with POSIX locale.
    /// The device's current time zone is used — EXIF itself carries no zone.
    private nonisolated static let exifDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()

    /// Reads the original capture date from a CGImageSource's metadata.
    /// Prefers EXIF `DateTimeOriginal`; falls back to TIFF `DateTime`.
    private nonisolated static func captureDate(from source: CGImageSource) -> Date? {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }
        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let s = exif[kCGImagePropertyExifDateTimeOriginal] as? String,
           let date = exifDateFormatter.date(from: s) {
            return date
        }
        if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
           let s = tiff[kCGImagePropertyTIFFDateTime] as? String,
           let date = exifDateFormatter.date(from: s) {
            return date
        }
        return nil
    }

    /// Lightweight EXIF capture-date probe — no image decode. Safe to call
    /// before deciding which season to assign on import.
    nonisolated func extractCaptureDate(from data: Data) -> Date? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return Self.captureDate(from: source)
    }

    /// Performs CPU-intensive image normalization, compression, and thumbnail
    /// generation off the main thread, returning file URLs for SwiftData.
    private nonisolated func processImage(
        _ image: UIImage,
        photoID: UUID
    ) async throws -> ProcessedPhoto {
        let photosDir = try ensurePhotosDirectory()
        let thumbDir = try ensureThumbnailsDirectory()

        let fileName = "\(photoID.uuidString).jpg"
        let photoURL = photosDir.appendingPathComponent(fileName)
        let thumbFileName = "thumb_\(photoID.uuidString).jpg"
        let thumbURL = thumbDir.appendingPathComponent(thumbFileName)

        // Normalize orientation
        let normalized = Self.normalizedImage(image)

        // Write full-size JPEG
        guard let imageData = normalized.jpegData(compressionQuality: Constants.jpegQuality) else {
            throw PhotoPersistenceError.failedToEncode
        }
        try imageData.write(to: photoURL, options: .atomic)

        // Generate and write aspect-preserving thumbnail (max 600px on the longest side)
        // via CGImageSource. Avoids square center-crops that chop heads/feet.
        if let source = CGImageSourceCreateWithURL(photoURL as CFURL, nil) {
            let options: [CFString: Any] = [
                kCGImageSourceThumbnailMaxPixelSize: 600,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true
            ]
            if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
               let thumbData = UIImage(cgImage: cgImage).jpegData(compressionQuality: Constants.thumbnailQuality) {
                try thumbData.write(to: thumbURL, options: .atomic)
            }
        }

        // UIImage source has no EXIF metadata to carry forward — camera-capture path
        // relies on the Photo init's default `createdAt = Date()`.
        return ProcessedPhoto(photoURL: photoURL, thumbURL: thumbURL, captureDate: nil)
    }

    // MARK: - Save Photo

    func savePhoto(
        image: UIImage,
        caption: String? = nil,
        context: ModelContext,
        athlete: Athlete,
        game: Game? = nil,
        practice: Practice? = nil,
        season: Season? = nil
    ) async throws -> Photo {
        let photoID = UUID()
        let fileName = "\(photoID.uuidString).jpg"

        // Process image off the main thread
        let processed = try await processImage(image, photoID: photoID)

        // Create SwiftData record (must be on @MainActor).
        // Persist RELATIVE paths so they survive app-container UUID changes across updates.
        let relativeFilePath = "\(Constants.photosFolderName)/\(fileName)"
        let relativeThumbPath = "\(Constants.thumbnailsFolderName)/\(processed.thumbURL.lastPathComponent)"
        let photo = Photo(fileName: fileName, filePath: relativeFilePath)
        photo.thumbnailPath = relativeThumbPath
        photo.caption = caption
        photo.athlete = athlete
        photo.game = game
        photo.practice = practice
        photo.season = season ?? athlete.activeSeason
        photo.needsSync = true  // Mark for cloud upload on next sync

        context.insert(photo)
        try context.save()

        return photo
    }

    // MARK: - Save Photo from Raw Data (memory-efficient)

    /// Saves a photo from raw file data (HEIC/JPEG from the photo library) without
    /// decoding into a full UIImage bitmap. Uses CGImageSource for orientation-correct
    /// JPEG conversion and thumbnail generation, keeping peak memory far below the
    /// UIImage path (~one OS-managed image tile vs. three full-res bitmaps).
    func savePhotoFromData(
        _ data: Data,
        caption: String? = nil,
        context: ModelContext,
        athlete: Athlete,
        game: Game? = nil,
        practice: Practice? = nil,
        season: Season? = nil,
        captureDate: Date? = nil
    ) async throws -> Photo {
        let photoID = UUID()
        let fileName = "\(photoID.uuidString).jpg"

        let processed = try await processRawData(data, photoID: photoID)

        let relativeFilePath = "\(Constants.photosFolderName)/\(fileName)"
        let relativeThumbPath = "\(Constants.thumbnailsFolderName)/\(processed.thumbURL.lastPathComponent)"
        let photo = Photo(fileName: fileName, filePath: relativeFilePath)
        photo.thumbnailPath = relativeThumbPath
        photo.caption = caption
        photo.athlete = athlete
        photo.game = game
        photo.practice = practice
        photo.season = season ?? athlete.activeSeason
        // Prefer caller-supplied date (bulk import may nudge for tie-break),
        // then EXIF, then fall back to the upload time the Photo init stamped.
        if let resolved = captureDate ?? processed.captureDate {
            photo.createdAt = resolved
        }
        photo.needsSync = true

        context.insert(photo)
        try context.save()

        return photo
    }

    /// CGImageSource pipeline: writes raw data to a temp file, produces an
    /// orientation-correct JPEG and thumbnail without UIImage decode.
    private nonisolated func processRawData(
        _ data: Data,
        photoID: UUID
    ) async throws -> ProcessedPhoto {
        let photosDir = try ensurePhotosDirectory()
        let thumbDir = try ensureThumbnailsDirectory()

        let fileName = "\(photoID.uuidString).jpg"
        let photoURL = photosDir.appendingPathComponent(fileName)
        let thumbFileName = "thumb_\(photoID.uuidString).jpg"
        let thumbURL = thumbDir.appendingPathComponent(thumbFileName)

        // Write raw data to a temp file so CGImageSource can stream from disk
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try data.write(to: tempURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        guard let source = CGImageSourceCreateWithURL(tempURL as CFURL, nil) else {
            throw PhotoPersistenceError.failedToEncode
        }

        // Pull the original capture date from EXIF/TIFF metadata before we
        // transcode — the re-encoded JPEG we write below drops EXIF.
        let captureDate = Self.captureDate(from: source)

        // Full-size orientation-correct image (cap at 4000px to avoid enormous output)
        let fullOptions: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: 4000,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let fullCG = CGImageSourceCreateThumbnailAtIndex(source, 0, fullOptions as CFDictionary) else {
            throw PhotoPersistenceError.failedToEncode
        }

        // JPEG is opaque — strip alpha before writing to avoid 2x decode memory.
        let fullOpaque = Self.opaqueCopy(of: fullCG) ?? fullCG
        try Self.writeJPEG(fullOpaque, to: photoURL, quality: Constants.jpegQuality)

        // Thumbnail (600px max)
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: 600,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        if let thumbCG = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) {
            let thumbOpaque = Self.opaqueCopy(of: thumbCG) ?? thumbCG
            try? Self.writeJPEG(thumbOpaque, to: thumbURL, quality: Constants.thumbnailQuality)
        }

        return ProcessedPhoto(photoURL: photoURL, thumbURL: thumbURL, captureDate: captureDate)
    }

    // MARK: - Delete Photo

    func deletePhoto(_ photo: Photo, context: ModelContext) {
        photo.delete(in: context)
        ErrorHandlerService.shared.saveContext(context, caller: "PhotoPersistence.deletePhoto")
    }

    // MARK: - Image Helpers (nonisolated for background processing)

    /// Redraws `cgImage` into an opaque RGB bitmap so JPEG encoding doesn't carry
    /// a premultiplied alpha channel (which ImageIO warns about and which doubles
    /// decode memory).
    private nonisolated static func opaqueCopy(of cgImage: CGImage) -> CGImage? {
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }
        let colorSpace = cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    private nonisolated static func writeJPEG(_ cgImage: CGImage, to url: URL, quality: CGFloat) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw PhotoPersistenceError.failedToEncode
        }
        let props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, cgImage, props as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw PhotoPersistenceError.failedToEncode
        }
    }

    private nonisolated static func normalizedImage(_ image: UIImage) -> UIImage {
        // Always redraw through a renderer so orientation is baked into the pixels.
        // UIImage(data:) from HEIC/photo-library data can report .up while the
        // pixel buffer is still un-transformed, producing rotated/black-bar saves.
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    private nonisolated static func resizedImage(_ image: UIImage, to targetSize: CGSize) -> UIImage {
        guard image.size.width > 0, image.size.height > 0, targetSize.width > 0, targetSize.height > 0 else { return image }
        let scale = max(targetSize.width / image.size.width, targetSize.height / image.size.height)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            let origin = CGPoint(x: (targetSize.width - newSize.width) / 2, y: (targetSize.height - newSize.height) / 2)
            image.draw(in: CGRect(origin: origin, size: newSize))
        }
    }
}

// MARK: - Errors

enum PhotoPersistenceError: LocalizedError {
    case failedToEncode

    var errorDescription: String? {
        switch self {
        case .failedToEncode:
            return "Failed to encode image as JPEG"
        }
    }
}
