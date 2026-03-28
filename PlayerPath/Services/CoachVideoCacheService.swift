//
//  CoachVideoCacheService.swift
//  PlayerPath
//
//  Caches coach shared folder videos locally for offline playback.
//  Uses Caches directory so iOS can reclaim space under storage pressure.
//

import Foundation
import os

private let cacheLog = Logger(subsystem: "com.playerpath.app", category: "CoachVideoCache")

@MainActor
final class CoachVideoCacheService {
    static let shared = CoachVideoCacheService()
    private init() {}

    var downloadProgress: Double = 0

    private var cacheRoot: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("coach_videos", isDirectory: true)
    }

    /// Returns local URL if the video is already cached.
    func cachedURL(folderID: String, fileName: String) -> URL? {
        let url = cacheRoot
            .appendingPathComponent(folderID, isDirectory: true)
            .appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Downloads a video from a signed URL and caches it locally. Returns the local file URL.
    func downloadAndCache(signedURLString: String, folderID: String, fileName: String) async throws -> URL {
        guard let signedURL = URL(string: signedURLString) else {
            throw URLError(.badURL)
        }

        let folderDir = cacheRoot.appendingPathComponent(folderID, isDirectory: true)
        try FileManager.default.createDirectory(at: folderDir, withIntermediateDirectories: true)

        let destinationURL = folderDir.appendingPathComponent(fileName)

        // Download with progress tracking
        downloadProgress = 0
        let (tempURL, response) = try await URLSession.shared.download(from: signedURL)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        // Detect expired signed URLs so callers can refresh and retry
        if httpResponse.statusCode == 403 || httpResponse.statusCode == 401 {
            throw CoachVideoCacheError.signedURLExpired
        }

        guard httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        // Move to cache location (overwrite if exists)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: destinationURL)

        let size = (try? FileManager.default.attributesOfItem(atPath: destinationURL.path)[.size] as? Int64) ?? 0
        let mb = Double(size) / 1_048_576.0
        cacheLog.info("Cached video: \(fileName) in folder \(folderID) (\(String(format: "%.1f", mb)) MB)")

        downloadProgress = 1.0
        return destinationURL
    }

    /// Deletes all cached coach videos.
    func clearCache() {
        try? FileManager.default.removeItem(at: cacheRoot)
        cacheLog.info("Cleared coach video cache")
    }

    /// Deletes cached videos for a specific folder (e.g., after access revocation).
    func clearCache(forFolderID folderID: String) {
        let folderDir = cacheRoot.appendingPathComponent(folderID, isDirectory: true)
        try? FileManager.default.removeItem(at: folderDir)
        cacheLog.info("Cleared cache for folder \(folderID)")
    }

}

enum CoachVideoCacheError: LocalizedError {
    case signedURLExpired

    var errorDescription: String? {
        switch self {
        case .signedURLExpired:
            return "Video link has expired. Refreshing..."
        }
    }
}
