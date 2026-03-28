//
//  SecureURLManager.swift
//  PlayerPath
//
//  Created by Assistant on 11/22/25.
//  Manager for generating secure, time-limited video URLs using Firebase Cloud Functions
//

import Foundation
import FirebaseAuth
import os

/// Manager for generating secure, expiring URLs for video and thumbnail access.
/// Uses direct URLSession calls instead of HTTPSCallable.call() to avoid a Firebase SDK
/// crash (asyncLet_finish_after_task_completion) where Firebase's internal async let
/// is interrupted by SwiftUI task cancellation on iOS 26.
@MainActor
class SecureURLManager {
    static let shared = SecureURLManager()

    private let log = Logger(subsystem: "com.playerpath.app", category: "SecureURLManager")
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let baseURL = "https://us-central1-playerpath-159b2.cloudfunctions.net"

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

    // MARK: - Direct HTTPS Helper

    /// Calls a Firebase Cloud Function via direct URLSession POST instead of HTTPSCallable.
    /// This avoids the Firebase SDK's internal async let crash on iOS 26.
    private func callCloudFunction(
        _ functionName: String,
        data: [String: Any]
    ) async throws -> [String: Any] {
        guard let user = Auth.auth().currentUser else {
            throw SecureURLError.functionCallFailed(
                NSError(domain: "SecureURLManager", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
            )
        }
        let token = try await user.getIDToken()

        let url = URL(string: "\(Self.baseURL)/\(functionName)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let body: [String: Any] = ["data": data]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (responseData, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            log.error("[\(functionName)] No HTTP response")
            throw SecureURLError.invalidResponse
        }

        let rawBody = String(data: responseData, encoding: .utf8) ?? "<non-utf8>"
        log.debug("[\(functionName)] HTTP \(httpResponse.statusCode) response: \(rawBody, privacy: .public)")

        guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            log.error("[\(functionName)] Failed to parse JSON from response")
            throw SecureURLError.invalidResponse
        }

        if let errorInfo = json["error"] as? [String: Any] {
            let message = errorInfo["message"] as? String ?? "Unknown error"
            log.error("[\(functionName)] Cloud Function error: \(message, privacy: .public)")
            throw SecureURLError.functionCallFailed(
                NSError(domain: "CloudFunction", code: httpResponse.statusCode,
                        userInfo: [NSLocalizedDescriptionKey: message])
            )
        }

        guard httpResponse.statusCode == 200,
              let result = json["result"] as? [String: Any] else {
            log.error("[\(functionName)] Unexpected response: status=\(httpResponse.statusCode), keys=\(Array(json.keys))")
            throw SecureURLError.functionCallFailed(
                NSError(domain: "CloudFunction", code: httpResponse.statusCode,
                        userInfo: [NSLocalizedDescriptionKey: "Server error (\(httpResponse.statusCode))"])
            )
        }

        return result
    }

    // MARK: - Public Methods

    /// Gets a secure, time-limited URL for a video file
    func getSecureVideoURL(
        fileName: String,
        folderID: String,
        expirationHours: Int = 24,
        forceRefresh: Bool = false
    ) async throws -> String {

        let cacheKey = "video_\(folderID)_\(fileName)"

        cleanExpiredURLs()

        if !forceRefresh,
           let cached = urlCache[cacheKey],
           !cached.isExpiringSoon {
            log.debug("Using cached video URL for \(fileName, privacy: .private)")
            return cached.url
        }

        log.debug("Generating secure video URL for \(fileName, privacy: .private)")

        let data: [String: Any] = [
            "folderID": folderID,
            "fileName": fileName,
            "expirationHours": expirationHours
        ]

        do {
            let response = try await callCloudFunction("getSignedVideoURL", data: data)

            guard let signedURL = response["signedURL"] as? String,
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
    func getSecureThumbnailURL(
        videoFileName: String,
        folderID: String,
        expirationHours: Int = 168,
        forceRefresh: Bool = false
    ) async throws -> String {

        let cacheKey = "thumbnail_\(folderID)_\(videoFileName)"

        cleanExpiredURLs()

        if !forceRefresh,
           let cached = urlCache[cacheKey],
           !cached.isExpiringSoon {
            log.debug("Using cached thumbnail URL for \(videoFileName, privacy: .private)")
            return cached.url
        }

        log.debug("Generating secure thumbnail URL for \(videoFileName, privacy: .private)")

        let data: [String: Any] = [
            "folderID": folderID,
            "videoFileName": videoFileName,
            "expirationHours": expirationHours
        ]

        do {
            let response = try await callCloudFunction("getSignedThumbnailURL", data: data)

            guard let signedURL = response["signedURL"] as? String,
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
    func getBatchSecureVideoURLs(
        fileNames: [String],
        folderID: String,
        expirationHours: Int = 24
    ) async throws -> [(fileName: String, url: String)] {

        log.debug("Generating \(fileNames.count) secure video URLs in batch")

        let data: [String: Any] = [
            "folderID": folderID,
            "fileNames": fileNames,
            "expirationHours": expirationHours
        ]

        do {
            let response = try await callCloudFunction("getBatchSignedVideoURLs", data: data)

            guard let urlsData = response["urls"] as? [[String: Any]] else {
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

        let data: [String: Any] = [
            "ownerUID": ownerUID,
            "fileName": fileName,
            "expirationHours": expirationHours
        ]

        do {
            let response = try await callCloudFunction("getPersonalVideoSignedURL", data: data)
            guard let signedURL = response["signedURL"] as? String,
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
