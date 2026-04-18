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

        return ProcessedPhoto(photoURL: photoURL, thumbURL: thumbURL)
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
        season: Season? = nil
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

        // Full-size orientation-correct image (cap at 4000px to avoid enormous output)
        let fullOptions: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: 4000,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let fullCG = CGImageSourceCreateThumbnailAtIndex(source, 0, fullOptions as CFDictionary) else {
            throw PhotoPersistenceError.failedToEncode
        }

        // Write full-size JPEG via CGImageDestination
        guard let destination = CGImageDestinationCreateWithURL(
            photoURL as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw PhotoPersistenceError.failedToEncode
        }
        let jpegProps: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: Constants.jpegQuality]
        CGImageDestinationAddImage(destination, fullCG, jpegProps as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw PhotoPersistenceError.failedToEncode
        }

        // Thumbnail (600px max)
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: 600,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        if let thumbCG = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary),
           let thumbData = UIImage(cgImage: thumbCG).jpegData(compressionQuality: Constants.thumbnailQuality) {
            try thumbData.write(to: thumbURL, options: .atomic)
        }

        return ProcessedPhoto(photoURL: photoURL, thumbURL: thumbURL)
    }

    // MARK: - Delete Photo

    func deletePhoto(_ photo: Photo, context: ModelContext) {
        photo.delete(in: context)
        ErrorHandlerService.shared.saveContext(context, caller: "PhotoPersistence.deletePhoto")
    }

    // MARK: - Image Helpers (nonisolated for background processing)

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
