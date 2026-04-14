//
//  CoachVideoLoader.swift
//  PlayerPath
//
//  Shared playback-URL resolution for coach-side video views.
//  Consolidates the cache → signed-URL → download → fallback flow
//  used by CoachVideoPlayerViewModel and ClipReviewSheet.
//

import Foundation

enum CoachVideoLoader {
    /// Returns a cached file URL if one exists, without triggering any network work.
    static func cachedURL(folderID: String, fileName: String) -> URL? {
        CoachVideoCacheService.shared.cachedURL(folderID: folderID, fileName: fileName)
    }

    /// Fetches a signed URL and downloads the video to the on-disk cache.
    /// If the signed URL expires mid-download, one fresh fetch + retry is attempted.
    /// If caching ultimately fails but the signed URL is valid, falls back to streaming it.
    static func fetchAndCache(folderID: String, fileName: String) async throws -> URL {
        let cache = CoachVideoCacheService.shared

        let signedURLString = try await SecureURLManager.shared.getSecureVideoURL(
            fileName: fileName,
            folderID: folderID
        )

        do {
            return try await cache.downloadAndCache(
                signedURLString: signedURLString,
                folderID: folderID,
                fileName: fileName
            )
        } catch let err as CoachVideoCacheError where err == .signedURLExpired {
            let freshURL = try await SecureURLManager.shared.getSecureVideoURL(
                fileName: fileName,
                folderID: folderID,
                forceRefresh: true
            )
            do {
                return try await cache.downloadAndCache(
                    signedURLString: freshURL,
                    folderID: folderID,
                    fileName: fileName
                )
            } catch {
                if let url = URL(string: freshURL) { return url }
                throw error
            }
        } catch {
            if let url = URL(string: signedURLString) { return url }
            throw error
        }
    }
}
