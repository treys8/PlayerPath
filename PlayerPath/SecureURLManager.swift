//
//  SecureURLManager.swift
//  PlayerPath
//
//  Created by Assistant on 11/22/25.
//  Manager for generating secure, time-limited video URLs using Firebase Cloud Functions
//

import Foundation
import FirebaseFunctions

/// Manager for generating secure, expiring URLs for video and thumbnail access
@MainActor
class SecureURLManager {
    static let shared = SecureURLManager()
    
    private let functions = Functions.functions()
    
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
        
        // Check cache unless force refresh
        if !forceRefresh,
           let cached = urlCache[cacheKey],
           !cached.isExpiringSoon {
            print("📦 Using cached video URL for \(fileName)")
            return cached.url
        }
        
        print("🔐 Generating secure video URL for \(fileName)")
        
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
            
            // Parse expiration date
            let formatter = ISO8601DateFormatter()
            guard let expiresAt = formatter.date(from: expiresAtString) else {
                throw SecureURLError.invalidExpirationDate
            }
            
            // Cache the URL
            urlCache[cacheKey] = CachedURL(url: signedURL, expiresAt: expiresAt)
            
            print("✅ Secure video URL generated, expires at \(expiresAt)")
            
            return signedURL
            
        } catch {
            print("❌ Failed to generate secure video URL: \(error)")
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
        
        // Check cache unless force refresh
        if !forceRefresh,
           let cached = urlCache[cacheKey],
           !cached.isExpiringSoon {
            print("📦 Using cached thumbnail URL for \(videoFileName)")
            return cached.url
        }
        
        print("🔐 Generating secure thumbnail URL for \(videoFileName)")
        
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
            
            // Parse expiration date
            let formatter = ISO8601DateFormatter()
            guard let expiresAt = formatter.date(from: expiresAtString) else {
                throw SecureURLError.invalidExpirationDate
            }
            
            // Cache the URL
            urlCache[cacheKey] = CachedURL(url: signedURL, expiresAt: expiresAt)
            
            print("✅ Secure thumbnail URL generated, expires at \(expiresAt)")
            
            return signedURL
            
        } catch {
            print("❌ Failed to generate secure thumbnail URL: \(error)")
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
        
        print("🔐 Generating \(fileNames.count) secure video URLs in batch")
        
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
                    print("⚠️ Error for \(fileName): \(error)")
                    continue
                }
                
                guard let signedURL = urlData["signedURL"] as? String,
                      let expiresAtString = urlData["expiresAt"] as? String else {
                    continue
                }
                
                // Parse expiration date
                let formatter = ISO8601DateFormatter()
                if let expiresAt = formatter.date(from: expiresAtString) {
                    // Cache the URL
                    let cacheKey = "video_\(folderID)_\(fileName)"
                    urlCache[cacheKey] = CachedURL(url: signedURL, expiresAt: expiresAt)
                }
                
                results.append((fileName: fileName, url: signedURL))
            }
            
            print("✅ Generated \(results.count) secure video URLs")
            
            return results
            
        } catch {
            print("❌ Failed to generate batch secure video URLs: \(error)")
            throw SecureURLError.functionCallFailed(error)
        }
    }
    
    /// Clears the URL cache
    func clearCache() {
        urlCache.removeAll()
        print("🗑️ Cleared secure URL cache")
    }
    
    /// Removes expired URLs from cache
    func cleanExpiredURLs() {
        let before = urlCache.count
        urlCache = urlCache.filter { !$0.value.isExpired }
        let removed = before - urlCache.count
        if removed > 0 {
            print("🗑️ Removed \(removed) expired URLs from cache")
        }
    }
}

// MARK: - Errors

enum SecureURLError: LocalizedError {
    case invalidResponse
    case invalidExpirationDate
    case functionCallFailed(Error)
    case functionNotDeployed
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from Cloud Function"
        case .invalidExpirationDate:
            return "Invalid expiration date format"
        case .functionCallFailed(let error):
            return "Cloud Function call failed: \(error.localizedDescription)"
        case .functionNotDeployed:
            return "Cloud Functions not deployed. Please deploy functions_index.ts"
        }
    }
}

// MARK: - Example Usage

/*
 
 // Get a secure URL for a single video
 Task {
     do {
         let url = try await SecureURLManager.shared.getSecureVideoURL(
             fileName: "game_video.mov",
             folderID: "folder123",
             expirationHours: 24
         )
         print("Video URL: \(url)")
     } catch {
         print("Error: \(error)")
     }
 }
 
 // Get a secure URL for a thumbnail
 Task {
     do {
         let url = try await SecureURLManager.shared.getSecureThumbnailURL(
             videoFileName: "game_video.mov",
             folderID: "folder123",
             expirationHours: 168 // 7 days
         )
         print("Thumbnail URL: \(url)")
     } catch {
         print("Error: \(error)")
     }
 }
 
 // Get batch URLs for multiple videos
 Task {
     do {
         let urls = try await SecureURLManager.shared.getBatchSecureVideoURLs(
             fileNames: ["video1.mov", "video2.mov", "video3.mov"],
             folderID: "folder123"
         )
         for (fileName, url) in urls {
             print("\(fileName): \(url)")
         }
     } catch {
         print("Error: \(error)")
     }
 }
 
 // Clean expired URLs periodically
 Task {
     SecureURLManager.shared.cleanExpiredURLs()
 }
 
 */
