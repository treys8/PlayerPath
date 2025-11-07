//
//  PlayerPathErrors.swift
//  PlayerPath
//
//  Unified error system for PlayerPath application
//

import Foundation
import CloudKit
import FirebaseAuth

// MARK: - PlayerPath Error Types
enum PlayerPathError: Error, LocalizedError {
    // MARK: - Network Errors
    case networkUnavailable
    case requestTimeout
    case serverError(code: Int, message: String?)
    case rateLimited(retryAfter: TimeInterval?)
    
    // MARK: - Authentication Errors
    case authenticationFailed(reason: String)
    case unauthorized
    case accountNotFound
    case accountAlreadyExists
    case invalidCredentials
    case appleSignInFailed(String)
    case signOutFailed
    
    // MARK: - Video Errors
    case videoRecordingFailed(reason: String?)
    case videoUploadFailed(reason: String)
    case videoDownloadFailed(reason: String)
    case videoCompressionFailed(reason: String?)
    case unsupportedVideoFormat(format: String?)
    case videoFileTooLarge(size: Int64, maxSize: Int64)
    case videoProcessingFailed(reason: String)
    case cameraAccessDenied
    case microphoneAccessDenied
    
    // MARK: - CloudKit Errors
    case cloudKitUnavailable
    case cloudKitNotSignedIn
    case syncConflict(localVersion: Date, remoteVersion: Date)
    case quotaExceeded
    case cloudKitRecordNotFound
    case cloudKitZoneNotFound
    case cloudKitAccountRestricted
    
    // MARK: - Data Errors
    case dataCorrupted(entity: String?)
    case saveFailed(entity: String, reason: String?)
    case loadFailed(entity: String, reason: String?)
    case validationFailed(field: String, reason: String)
    case swiftDataError(String)
    
    // MARK: - Storage Errors
    case localStorageFull
    case fileNotFound(path: String)
    case fileWriteFailed(path: String)
    case fileReadFailed(path: String)
    case invalidFilePath(path: String)
    
    // MARK: - Permission Errors
    case cameraPermissionDenied
    case photoLibraryPermissionDenied
    case notificationPermissionDenied
    
    // MARK: - Feature Errors
    case featureNotAvailable(feature: String)
    case premiumFeatureRequired(feature: String)
    case trialExpired
    
    // MARK: - Unknown/Generic Errors
    case unknownError(Error)
    case configurationError(String)
    
    // MARK: - LocalizedError Implementation
    var errorDescription: String? {
        switch self {
        // Network Errors
        case .networkUnavailable:
            return "No internet connection available"
        case .requestTimeout:
            return "Request timed out"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message ?? "Unknown server error")"
        case .rateLimited(let retryAfter):
            if let retryAfter = retryAfter {
                return "Too many requests. Please wait \(Int(retryAfter)) seconds before trying again."
            }
            return "Too many requests. Please wait a moment before trying again."
            
        // Authentication Errors
        case .authenticationFailed(let reason):
            return "Authentication failed: \(reason)"
        case .unauthorized:
            return "You don't have permission to access this feature"
        case .accountNotFound:
            return "No account found with these credentials"
        case .accountAlreadyExists:
            return "An account with this email already exists"
        case .invalidCredentials:
            return "Invalid email or password"
        case .appleSignInFailed(let reason):
            return "Apple Sign In failed: \(reason)"
        case .signOutFailed:
            return "Failed to sign out"
            
        // Video Errors
        case .videoRecordingFailed(let reason):
            return "Video recording failed\(reason.map { ": \($0)" } ?? "")"
        case .videoUploadFailed(let reason):
            return "Video upload failed: \(reason)"
        case .videoDownloadFailed(let reason):
            return "Video download failed: \(reason)"
        case .videoCompressionFailed(let reason):
            return "Video compression failed\(reason.map { ": \($0)" } ?? "")"
        case .unsupportedVideoFormat(let format):
            return "Unsupported video format\(format.map { ": \($0)" } ?? "")"
        case .videoFileTooLarge(let size, let maxSize):
            let sizeMB = size / (1024 * 1024)
            let maxSizeMB = maxSize / (1024 * 1024)
            return "Video file is too large (\(sizeMB)MB). Maximum size is \(maxSizeMB)MB."
        case .videoProcessingFailed(let reason):
            return "Video processing failed: \(reason)"
        case .cameraAccessDenied:
            return "Camera access is required to record videos"
        case .microphoneAccessDenied:
            return "Microphone access is required to record audio"
            
        // CloudKit Errors
        case .cloudKitUnavailable:
            return "iCloud is not available"
        case .cloudKitNotSignedIn:
            return "Please sign in to iCloud to sync your data"
        case .syncConflict(let local, let remote):
            return "Data conflict detected. Local: \(local.formatted()), Remote: \(remote.formatted())"
        case .quotaExceeded:
            return "Your iCloud storage is full"
        case .cloudKitRecordNotFound:
            return "Record not found in iCloud"
        case .cloudKitZoneNotFound:
            return "iCloud zone not found"
        case .cloudKitAccountRestricted:
            return "iCloud account is restricted"
            
        // Data Errors
        case .dataCorrupted(let entity):
            return "Data corruption detected\(entity.map { " in \($0)" } ?? "")"
        case .saveFailed(let entity, let reason):
            return "Failed to save \(entity)\(reason.map { ": \($0)" } ?? "")"
        case .loadFailed(let entity, let reason):
            return "Failed to load \(entity)\(reason.map { ": \($0)" } ?? "")"
        case .validationFailed(let field, let reason):
            return "\(field) validation failed: \(reason)"
        case .swiftDataError(let message):
            return "Database error: \(message)"
            
        // Storage Errors
        case .localStorageFull:
            return "Device storage is full"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .fileWriteFailed(let path):
            return "Failed to write file: \(path)"
        case .fileReadFailed(let path):
            return "Failed to read file: \(path)"
        case .invalidFilePath(let path):
            return "Invalid file path: \(path)"
            
        // Permission Errors
        case .cameraPermissionDenied:
            return "Camera permission is required"
        case .photoLibraryPermissionDenied:
            return "Photo library access is required"
        case .notificationPermissionDenied:
            return "Notification permission is required"
            
        // Feature Errors
        case .featureNotAvailable(let feature):
            return "\(feature) is not available on this device"
        case .premiumFeatureRequired(let feature):
            return "\(feature) requires a premium subscription"
        case .trialExpired:
            return "Your free trial has expired"
            
        // Generic Errors
        case .unknownError(let error):
            return "An unexpected error occurred: \(error.localizedDescription)"
        case .configurationError(let message):
            return "Configuration error: \(message)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        // Network Errors
        case .networkUnavailable:
            return "Check your internet connection and try again."
        case .requestTimeout:
            return "Check your internet connection and try again."
        case .serverError:
            return "Please try again later. If the problem persists, contact support."
        case .rateLimited:
            return "This is temporary. Please wait before making more requests."
            
        // Authentication Errors
        case .authenticationFailed:
            return "Verify your credentials and try again."
        case .unauthorized:
            return "Sign in to access this feature."
        case .accountNotFound:
            return "Create a new account or check your login credentials."
        case .accountAlreadyExists:
            return "Try signing in instead, or use a different email address."
        case .invalidCredentials:
            return "Double-check your email and password."
        case .appleSignInFailed:
            return "Try signing in with email/password or check your Apple ID settings."
        case .signOutFailed:
            return "Try restarting the app."
            
        // Video Errors
        case .videoRecordingFailed:
            return "Check camera permissions and try again."
        case .videoUploadFailed:
            return "Check your internet connection and try uploading again."
        case .videoDownloadFailed:
            return "Check your internet connection and try again."
        case .videoCompressionFailed:
            return "Try recording a shorter video or free up device storage."
        case .unsupportedVideoFormat:
            return "Please use a supported video format (MP4, MOV)."
        case .videoFileTooLarge:
            return "Try recording a shorter video or reducing video quality."
        case .videoProcessingFailed:
            return "Free up device storage and try again."
        case .cameraAccessDenied, .microphoneAccessDenied:
            return "Go to Settings > Privacy & Security to grant camera and microphone permissions."
            
        // CloudKit Errors
        case .cloudKitUnavailable:
            return "Check your iCloud settings and internet connection."
        case .cloudKitNotSignedIn:
            return "Sign in to iCloud in Settings > [Your Name] > iCloud."
        case .syncConflict:
            return "Choose which version to keep or manually merge the changes."
        case .quotaExceeded:
            return "Free up iCloud storage in Settings > [Your Name] > iCloud > Manage Storage."
        case .cloudKitRecordNotFound:
            return "This is normal for new data. Try syncing again."
        case .cloudKitZoneNotFound:
            return "Reset your sync settings or contact support."
        case .cloudKitAccountRestricted:
            return "Check your iCloud account restrictions in Settings."
            
        // Data Errors
        case .dataCorrupted:
            return "Try restarting the app or reinstalling if the problem persists."
        case .saveFailed:
            return "Free up device storage and try again."
        case .loadFailed:
            return "Try restarting the app."
        case .validationFailed:
            return "Please check your input and try again."
        case .swiftDataError:
            return "Try restarting the app. If the problem persists, contact support."
            
        // Storage Errors
        case .localStorageFull:
            return "Free up device storage by deleting unused files or apps."
        case .fileNotFound:
            return "The file may have been moved or deleted. Try refreshing."
        case .fileWriteFailed:
            return "Free up device storage and try again."
        case .fileReadFailed:
            return "Try restarting the app."
        case .invalidFilePath:
            return "Contact support if this problem persists."
            
        // Permission Errors
        case .cameraPermissionDenied:
            return "Go to Settings > Privacy & Security > Camera and enable access for PlayerPath."
        case .photoLibraryPermissionDenied:
            return "Go to Settings > Privacy & Security > Photos and enable access for PlayerPath."
        case .notificationPermissionDenied:
            return "Go to Settings > Notifications > PlayerPath to enable notifications."
            
        // Feature Errors
        case .featureNotAvailable:
            return "This feature may require a newer device or iOS version."
        case .premiumFeatureRequired:
            return "Upgrade to premium to access this feature."
        case .trialExpired:
            return "Subscribe to continue using premium features."
            
        // Generic Errors
        case .unknownError:
            return "Try restarting the app. If the problem persists, contact support."
        case .configurationError:
            return "Contact support for assistance with this configuration issue."
        }
    }
    
    var failureReason: String? {
        switch self {
        case .networkUnavailable:
            return "Network connection is not available"
        case .authenticationFailed(let reason):
            return reason
        case .videoRecordingFailed(let reason):
            return reason
        case .dataCorrupted(let entity):
            return entity.map { "Corrupted \($0) data" }
        default:
            return nil
        }
    }
}

// MARK: - Error Conversion Helpers
extension PlayerPathError {
    
    /// Convert CloudKit errors to PlayerPath errors
    static func from(cloudKitError: CKError) -> PlayerPathError {
        switch cloudKitError.code {
        case .networkUnavailable, .networkFailure:
            return .networkUnavailable
        case .notAuthenticated:
            return .cloudKitNotSignedIn
        case .quotaExceeded:
            return .quotaExceeded
        case .unknownItem:
            return .cloudKitRecordNotFound
        case .zoneNotFound:
            return .cloudKitZoneNotFound
        case .requestRateLimited:
            let retryAfter = cloudKitError.userInfo[CKErrorRetryAfterKey] as? TimeInterval
            return .rateLimited(retryAfter: retryAfter)
        case .accountTemporarilyUnavailable:
            return .cloudKitAccountRestricted
        default:
            return .unknownError(cloudKitError)
        }
    }
    
    /// Convert Firebase Auth errors to PlayerPath errors
    static func from(firebaseAuthError: NSError) -> PlayerPathError {
        guard let errorCode = AuthErrorCode(rawValue: firebaseAuthError.code) else {
            return .unknownError(firebaseAuthError)
        }
        
        switch errorCode {
        case .emailAlreadyInUse:
            return .accountAlreadyExists
        case .userNotFound:
            return .accountNotFound
        case .wrongPassword:
            return .invalidCredentials
        case .invalidEmail:
            return .validationFailed(field: "Email", reason: "Invalid email format")
        case .weakPassword:
            return .validationFailed(field: "Password", reason: "Password is too weak")
        case .networkError:
            return .networkUnavailable
        case .tooManyRequests:
            return .rateLimited(retryAfter: nil)
        default:
            return .authenticationFailed(reason: firebaseAuthError.localizedDescription)
        }
    }
}