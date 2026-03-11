//
//  SecureURLManager.swift
//  PlayerPath
//
//  Created by Assistant on 11/22/25.
//  Manager for generating secure, time-limited video URLs using Firebase Cloud Functions
//

import Foundation
import FirebaseFunctions
import os

/// Manager for generating secure, expiring URLs for video and thumbnail access
@MainActor
class SecureURLManager {
    static let shared = SecureURLManager()
    
    private let functions = Functions.functions()
    private let log = Logger(subsystem: "com.playerpath.app", category: "SecureURLManager")
    private static let isoFormatter = ISO8601DateFormatter()

    // Cache for signed URLs to avoid repeated function calls
    private var urlCache: [String: CachedURL] = [:]

    private init() {}
    
    // MARK: - Cached URL Structure
    
    private struct CachedURL {
        let url: String
        let expiresAt: Date
        
        var isExpired: Bool {
            Date() >= expiresAt
        }
        
        var isExpiringSoon: Bool {
            // Consider expired if less than 5 minutes remaining
            Date().addingTimeInterval(300) >= expiresAt
        }
    }
    
    // MARK: - Public Methods
    
    /// Gets a secure, time-limited URL for a video file
    /// - Parameters:
    ///   - fileName: Name of the video file in storage
    ///   - folderID: Shared folder ID
    ///   - expirationHours: Hours until URL expires (default: 24)
    ///   - forceRefresh: Force generation of new URL even if cached
    /// - Returns: A secure, time-limited download URL
    func getSecureVideoURL(
        fileName: String,
        folderID: String,
        expirationHours: Int = 24,
        forceRefresh: Bool = false
    ) async throws -> String {
        
        let cacheKey = "video_\(folderID)_\(fileName)"

        cleanExpiredURLs()

        // Check cache unless force refresh
        if !forceRefresh,
           let cached = urlCache[cacheKey],
           !cached.isExpiringSoon {
            log.debug("Using cached video URL for \(fileName, privacy: .private)")
            return cached.url
        }

        log.debug("Generating secure video URL for \(fileName, privacy: .private)")

        let callable = functions.httpsCallable("getSignedVideoURL")

        let data: [String: Any] = [
            "folderID": folderID,
            "fileName": fileName,
            "expirationHours": expirationHours
        ]

        do {
            let result = try await callable.call(data)

            guard let response = result.data as? [String: Any],
                  let signedURL = response["signedURL"] as? String,
                  let expiresAtString = response["expiresAt"] as? String else {
                throw SecureURLError.invalidResponse
            }

            guard let expiresAt = Self.isoFormatter.date(from: expiresAtString) else {
                throw SecureURLError.invalidExpirationDate
            }

            urlCache[cacheKey] = CachedURL(url: signedURL, expiresAt: expiresAt)
            log.debug("Secure video URL generated, expires at \(expiresAt, privacy: .public)")

            return signedURL

        } catch {
            log.error("Failed to generate secure video URL: \(error.localizedDescription, privacy: .public)")
            throw SecureURLError.functionCallFailed(error)
        }
    }
    
    /// Gets a secure, time-limited URL for a thumbnail image
    /// - Parameters:
    ///   - videoFileName: Name of the video file (thumbnail name will be derived)
    ///   - folderID: Shared folder ID
    ///   - expirationHours: Hours until URL expires (default: 168 = 7 days)
    ///   - forceRefresh: Force generation of new URL even if cached
    /// - Returns: A secure, time-limited download URL for the thumbnail
    func getSecureThumbnailURL(
        videoFileName: String,
        folderID: String,
        expirationHours: Int = 168,
        forceRefresh: Bool = false
    ) async throws -> String {
        
        let cacheKey = "thumbnail_\(folderID)_\(videoFileName)"

        cleanExpiredURLs()

        // Check cache unless force refresh
        if !forceRefresh,
           let cached = urlCache[cacheKey],
           !cached.isExpiringSoon {
            log.debug("Using cached thumbnail URL for \(videoFileName, privacy: .private)")
            return cached.url
        }

        log.debug("Generating secure thumbnail URL for \(videoFileName, privacy: .private)")

        let callable = functions.httpsCallable("getSignedThumbnailURL")

        let data: [String: Any] = [
            "folderID": folderID,
            "videoFileName": videoFileName,
            "expirationHours": expirationHours
        ]

        do {
            let result = try await callable.call(data)

            guard let response = result.data as? [String: Any],
                  let signedURL = response["signedURL"] as? String,
                  let expiresAtString = response["expiresAt"] as? String else {
                throw SecureURLError.invalidResponse
            }

            guard let expiresAt = Self.isoFormatter.date(from: expiresAtString) else {
                throw SecureURLError.invalidExpirationDate
            }

            urlCache[cacheKey] = CachedURL(url: signedURL, expiresAt: expiresAt)
            log.debug("Secure thumbnail URL generated, expires at \(expiresAt, privacy: .public)")

            return signedURL

        } catch {
            log.error("Failed to generate secure thumbnail URL: \(error.localizedDescription, privacy: .public)")
            throw SecureURLError.functionCallFailed(error)
        }
    }
    
    /// Gets secure URLs for multiple videos in batch
    /// - Parameters:
    ///   - fileNames: Array of video file names
    ///   - folderID: Shared folder ID
    ///   - expirationHours: Hours until URLs expire (default: 24)
    /// - Returns: Array of tuples with file name and secure URL
    func getBatchSecureVideoURLs(
        fileNames: [String],
        folderID: String,
        expirationHours: Int = 24
    ) async throws -> [(fileName: String, url: String)] {
        
        log.debug("Generating \(fileNames.count) secure video URLs in batch")

        let callable = functions.httpsCallable("getBatchSignedVideoURLs")

        let data: [String: Any] = [
            "folderID": folderID,
            "fileNames": fileNames,
            "expirationHours": expirationHours
        ]

        do {
            let result = try await callable.call(data)

            guard let response = result.data as? [String: Any],
                  let urlsData = response["urls"] as? [[String: Any]] else {
                throw SecureURLError.invalidResponse
            }

            var results: [(fileName: String, url: String)] = []

            for urlData in urlsData {
                guard let fileName = urlData["fileName"] as? String else { continue }

                if let error = urlData["error"] as? String {
                    log.warning("Batch URL error for \(fileName, privacy: .private): \(error, privacy: .public)")
                    continue
                }

                guard let signedURL = urlData["signedURL"] as? String,
                      let expiresAtString = urlData["expiresAt"] as? String else {
                    continue
                }

                if let expiresAt = Self.isoFormatter.date(from: expiresAtString) {
                    let cacheKey = "video_\(folderID)_\(fileName)"
                    urlCache[cacheKey] = CachedURL(url: signedURL, expiresAt: expiresAt)
                }

                results.append((fileName: fileName, url: signedURL))
            }

            log.debug("Generated \(results.count) of \(fileNames.count) secure video URLs")

            return results

        } catch {
            log.error("Failed to generate batch secure video URLs: \(error.localizedDescription, privacy: .public)")
            throw SecureURLError.functionCallFailed(error)
        }
    }
    
    /// Gets a secure, time-limited URL for a personal athlete video.
    /// Only the owning user may request their own video URLs.
    func getPersonalVideoURL(
        ownerUID: String,
        fileName: String,
        expirationHours: Int = 24,
        forceRefresh: Bool = false
    ) async throws -> String {

        let cacheKey = "personal_\(ownerUID)_\(fileName)"

        cleanExpiredURLs()

        if !forceRefresh,
           let cached = urlCache[cacheKey],
           !cached.isExpiringSoon {
            return cached.url
        }

        let callable = functions.httpsCallable("getPersonalVideoSignedURL")
        let data: [String: Any] = [
            "ownerUID": ownerUID,
            "fileName": fileName,
            "expirationHours": expirationHours
        ]

        do {
            let result = try await callable.call(data)
            guard let response = result.data as? [String: Any],
                  let signedURL = response["signedURL"] as? String,
                  let expiresAtString = response["expiresAt"] as? String else {
                throw SecureURLError.invalidResponse
            }
            guard let expiresAt = Self.isoFormatter.date(from: expiresAtString) else {
                throw SecureURLError.invalidExpirationDate
            }
            urlCache[cacheKey] = CachedURL(url: signedURL, expiresAt: expiresAt)
            return signedURL
        } catch {
            throw SecureURLError.functionCallFailed(error)
        }
    }

    /// Clears the URL cache
    func clearCache() {
        urlCache.removeAll()
        log.debug("Cleared secure URL cache")
    }

    /// Removes expired URLs from cache
    func cleanExpiredURLs() {
        let before = urlCache.count
        urlCache = urlCache.filter { !$0.value.isExpired }
        let removed = before - urlCache.count
        if removed > 0 {
            log.debug("Removed \(removed) expired URLs from cache")
        }
    }
}

// MARK: - Errors

enum SecureURLError: LocalizedError {
    case invalidResponse
    case invalidExpirationDate
    case functionCallFailed(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Unable to load video. Please try again."
        case .invalidExpirationDate:
            return "Unable to load video. Please try again."
        case .functionCallFailed(let error):
            #if DEBUG
            return "Cloud Function call failed: \(error.localizedDescription)"
            #else
            return "Unable to load video. Please try again."
            #endif
        }
    }
}
