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

    private enum Constants {
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

    private func ensurePhotosDirectory() throws -> URL {
        let documentsURL = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let photosDir = documentsURL.appendingPathComponent(Constants.photosFolderName, isDirectory: true)
        if !fileManager.fileExists(atPath: photosDir.path) {
            try fileManager.createDirectory(at: photosDir, withIntermediateDirectories: true)
        }
        return photosDir
    }

    private func ensureThumbnailsDirectory() throws -> URL {
        let documentsURL = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let thumbDir = documentsURL.appendingPathComponent(Constants.thumbnailsFolderName, isDirectory: true)
        if !fileManager.fileExists(atPath: thumbDir.path) {
            try fileManager.createDirectory(at: thumbDir, withIntermediateDirectories: true)
        }
        return thumbDir
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
        let photosDir = try ensurePhotosDirectory()
        let thumbDir = try ensureThumbnailsDirectory()

        let photoID = UUID()
        let fileName = "\(photoID.uuidString).jpg"

        // Normalize orientation
        let normalized = normalizedImage(image)

        // Write full-size JPEG
        guard let imageData = normalized.jpegData(compressionQuality: Constants.jpegQuality) else {
            throw PhotoPersistenceError.failedToEncode
        }
        let photoURL = photosDir.appendingPathComponent(fileName)
        try imageData.write(to: photoURL, options: .atomic)

        // Generate and write thumbnail
        let thumbnail = resizedImage(normalized, to: Constants.thumbnailSize)
        let thumbFileName = "thumb_\(photoID.uuidString).jpg"
        let thumbURL = thumbDir.appendingPathComponent(thumbFileName)
        if let thumbData = thumbnail.jpegData(compressionQuality: Constants.thumbnailQuality) {
            try thumbData.write(to: thumbURL, options: .atomic)
        }

        // Create SwiftData record
        let photo = Photo(fileName: fileName, filePath: photoURL.path)
        photo.thumbnailPath = thumbURL.path
        photo.caption = caption
        photo.athlete = athlete
        photo.game = game
        photo.practice = practice
        photo.season = athlete.activeSeason

        context.insert(photo)
        try context.save()

        print("PhotoPersistenceService: Saved photo \(fileName)")
        return photo
    }

    // MARK: - Delete Photo

    func deletePhoto(_ photo: Photo, context: ModelContext) {
        photo.delete(in: context)
        try? context.save()
        print("PhotoPersistenceService: Deleted photo \(photo.fileName)")
    }

    // MARK: - Image Helpers

    private func normalizedImage(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    private func resizedImage(_ image: UIImage, to targetSize: CGSize) -> UIImage {
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
