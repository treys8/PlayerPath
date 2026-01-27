//
//  AppError.swift
//  PlayerPath
//
//  Centralized error types and user-friendly error messages
//

import Foundation

// MARK: - AppError

enum AppError: LocalizedError {
    // Authentication Errors
    case authenticationFailed(String?)
    case invalidCredentials
    case accountNotFound
    case emailAlreadyInUse
    case weakPassword
    case signOutFailed

    // Network Errors
    case noInternetConnection
    case requestTimeout
    case serverError(Int)
    case invalidResponse
    case networkFailure(Error)

    // Database Errors
    case saveFailed(String?)
    case loadFailed(String?)
    case deleteFailed(String?)
    case syncFailed(String?)
    case dataCorrupted

    // Video/Media Errors
    case cameraPermissionDenied
    case microphonePermissionDenied
    case videoRecordingFailed(String?)
    case videoUploadFailed(String?)
    case videoNotFound
    case thumbnailGenerationFailed

    // Firebase Storage Errors
    case storageUploadFailed(String?)
    case storageDownloadFailed(String?)
    case storageQuotaExceeded

    // Firestore Errors
    case firestoreReadFailed(String?)
    case firestoreWriteFailed(String?)
    case firestorePermissionDenied

    // Validation Errors
    case invalidInput(String)
    case missingRequiredField(String)
    case invalidEmailFormat
    case passwordTooShort

    // General Errors
    case unknown(Error?)
    case notImplemented
    case operationCancelled

    // MARK: - Error Descriptions

    var errorDescription: String? {
        switch self {
        // Authentication
        case .authenticationFailed(let message):
            return message ?? "Authentication failed. Please try again."
        case .invalidCredentials:
            return "Invalid email or password. Please check your credentials and try again."
        case .accountNotFound:
            return "No account found with this email. Please sign up first."
        case .emailAlreadyInUse:
            return "This email is already associated with an account. Please sign in instead."
        case .weakPassword:
            return "Password is too weak. Please use at least 8 characters with letters and numbers."
        case .signOutFailed:
            return "Failed to sign out. Please try again."

        // Network
        case .noInternetConnection:
            return "No internet connection. Please check your network settings and try again."
        case .requestTimeout:
            return "Request timed out. Please check your internet connection and try again."
        case .serverError(let code):
            return "Server error (\(code)). Please try again later."
        case .invalidResponse:
            return "Received invalid response from server. Please try again."
        case .networkFailure(let error):
            return "Network error: \(error.localizedDescription)"

        // Database
        case .saveFailed(let details):
            return details ?? "Failed to save data. Please try again."
        case .loadFailed(let details):
            return details ?? "Failed to load data. Please try again."
        case .deleteFailed(let details):
            return details ?? "Failed to delete item. Please try again."
        case .syncFailed(let details):
            return details ?? "Failed to sync data. Your changes are saved locally and will sync when connection is restored."
        case .dataCorrupted:
            return "Data appears to be corrupted. Please contact support if this persists."

        // Video/Media
        case .cameraPermissionDenied:
            return "Camera access is required to record videos. Please enable it in Settings > PlayerPath > Camera."
        case .microphonePermissionDenied:
            return "Microphone access is required to record audio. Please enable it in Settings > PlayerPath > Microphone."
        case .videoRecordingFailed(let details):
            return details ?? "Video recording failed. Please try again."
        case .videoUploadFailed(let details):
            return details ?? "Video upload failed. Your video is saved locally and will upload when connection is restored."
        case .videoNotFound:
            return "Video file not found. It may have been deleted or moved."
        case .thumbnailGenerationFailed:
            return "Failed to generate video thumbnail. The video is still available."

        // Firebase Storage
        case .storageUploadFailed(let details):
            return details ?? "Upload failed. Please check your internet connection and try again."
        case .storageDownloadFailed(let details):
            return details ?? "Download failed. Please check your internet connection and try again."
        case .storageQuotaExceeded:
            return "Storage quota exceeded. Please delete some videos or contact support to upgrade your storage."

        // Firestore
        case .firestoreReadFailed(let details):
            return details ?? "Failed to load data from cloud. Please check your internet connection and try again."
        case .firestoreWriteFailed(let details):
            return details ?? "Failed to save data to cloud. Your changes are saved locally and will sync later."
        case .firestorePermissionDenied:
            return "Permission denied. Please sign in again or contact support."

        // Validation
        case .invalidInput(let field):
            return "Invalid \(field). Please check your input and try again."
        case .missingRequiredField(let field):
            return "\(field) is required. Please fill in all required fields."
        case .invalidEmailFormat:
            return "Invalid email format. Please enter a valid email address."
        case .passwordTooShort:
            return "Password must be at least 8 characters long."

        // General
        case .unknown(let error):
            if let error = error {
                return "An unexpected error occurred: \(error.localizedDescription)"
            }
            return "An unexpected error occurred. Please try again."
        case .notImplemented:
            return "This feature is not yet implemented."
        case .operationCancelled:
            return "Operation was cancelled."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .noInternetConnection, .requestTimeout, .networkFailure:
            return "Check your internet connection and try again."
        case .cameraPermissionDenied, .microphonePermissionDenied:
            return "Open Settings and grant permission to continue."
        case .storageQuotaExceeded:
            return "Delete old videos or contact support to increase storage."
        case .authenticationFailed, .invalidCredentials:
            return "Double-check your email and password, or reset your password."
        case .emailAlreadyInUse:
            return "Try signing in with this email instead."
        case .syncFailed, .videoUploadFailed, .firestoreWriteFailed:
            return "Your changes are saved locally and will sync automatically when you're back online."
        default:
            return nil
        }
    }

    // MARK: - Error Severity

    enum Severity {
        case low        // Non-blocking, can be dismissed
        case medium     // Important but not critical
        case high       // Critical, blocks user flow
        case critical   // App cannot continue
    }

    var severity: Severity {
        switch self {
        case .thumbnailGenerationFailed, .syncFailed, .videoUploadFailed:
            return .low
        case .saveFailed, .loadFailed, .videoRecordingFailed, .networkFailure:
            return .medium
        case .cameraPermissionDenied, .microphonePermissionDenied, .authenticationFailed:
            return .high
        case .dataCorrupted:
            return .critical
        default:
            return .medium
        }
    }

    // MARK: - User Action

    enum UserAction {
        case retry
        case openSettings
        case contactSupport
        case dismiss
        case signIn
    }

    var suggestedActions: [UserAction] {
        switch self {
        case .cameraPermissionDenied, .microphonePermissionDenied:
            return [.openSettings, .dismiss]
        case .noInternetConnection, .requestTimeout, .networkFailure, .saveFailed, .videoRecordingFailed:
            return [.retry, .dismiss]
        case .storageQuotaExceeded, .dataCorrupted:
            return [.contactSupport, .dismiss]
        case .authenticationFailed, .invalidCredentials, .accountNotFound:
            return [.retry, .dismiss]
        case .firestorePermissionDenied:
            return [.signIn, .contactSupport]
        case .syncFailed, .videoUploadFailed, .thumbnailGenerationFailed:
            return [.dismiss]
        default:
            return [.retry, .dismiss]
        }
    }
}

// MARK: - Error Mapping

extension AppError {
    /// Convert a generic Error to AppError
    static func from(_ error: Error) -> AppError {
        if let appError = error as? AppError {
            return appError
        }

        let nsError = error as NSError

        // Network errors
        switch nsError.code {
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
            return .noInternetConnection
        case NSURLErrorTimedOut:
            return .requestTimeout
        case NSURLErrorCancelled:
            return .operationCancelled
        default:
            break
        }

        // Firebase Auth errors
        if nsError.domain == "FIRAuthErrorDomain" {
            switch nsError.code {
            case 17007: // FIRAuthErrorCodeEmailAlreadyInUse
                return .emailAlreadyInUse
            case 17008: // FIRAuthErrorCodeInvalidEmail
                return .invalidEmailFormat
            case 17009: // FIRAuthErrorCodeWrongPassword
                return .invalidCredentials
            case 17011: // FIRAuthErrorCodeUserNotFound
                return .accountNotFound
            case 17026: // FIRAuthErrorCodeWeakPassword
                return .weakPassword
            default:
                return .authenticationFailed(nsError.localizedDescription)
            }
        }

        // Firebase Storage errors
        if nsError.domain == "FIRStorageErrorDomain" {
            switch nsError.code {
            case -13030: // FIRStorageErrorCodeUnauthenticated
                return .firestorePermissionDenied
            case -13040: // FIRStorageErrorCodeQuotaExceeded
                return .storageQuotaExceeded
            default:
                return .storageUploadFailed(nsError.localizedDescription)
            }
        }

        return .unknown(error)
    }
}
