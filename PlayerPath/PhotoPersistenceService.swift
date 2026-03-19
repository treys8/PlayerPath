//
//  PhotoPersistenceService.swift
//  PlayerPath
//
//  Saves photos to Documents/Photos, generates thumbnails, creates SwiftData records.
//

import UIKit
import SwiftData
import Foundation

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

        // Generate and write thumbnail
        let thumbnail = Self.resizedImage(normalized, to: Constants.thumbnailSize)
        let thumbData = thumbnail.jpegData(compressionQuality: Constants.thumbnailQuality)
        if let thumbData {
            try thumbData.write(to: thumbURL, options: .atomic)
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
        practice: Practice? = nil
    ) async throws -> Photo {
        let photoID = UUID()
        let fileName = "\(photoID.uuidString).jpg"

        // Process image off the main thread
        let processed = try await processImage(image, photoID: photoID)

        // Create SwiftData record (must be on @MainActor)
        let photo = Photo(fileName: fileName, filePath: processed.photoURL.path)
        photo.thumbnailPath = processed.thumbURL.path
        photo.caption = caption
        photo.athlete = athlete
        photo.game = game
        photo.practice = practice
        photo.season = athlete.activeSeason
        photo.needsSync = true  // Mark for cloud upload on next sync

        context.insert(photo)
        try context.save()

        return photo
    }

    // MARK: - Delete Photo

    func deletePhoto(_ photo: Photo, context: ModelContext) {
        photo.delete(in: context)
        try? context.save()
    }

    // MARK: - Image Helpers (nonisolated for background processing)

    private nonisolated static func normalizedImage(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up { return image }
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
