//
//  AuthConstants.swift
//  PlayerPath
//
//  Created by Assistant on 12/24/25.
//  Centralized constants for authentication and onboarding
//

import Foundation

enum AuthConstants {
    // MARK: - Email & Support
    static let supportEmail = "support@playerpath.app"
    static let contactEmail = "contact@playerpath.app"

    // MARK: - Error Messages
    enum ErrorMessages {
        static let emailAlreadyInUse = "An account with this email already exists. Try signing in instead."
        static let weakPassword = "Password is too weak. Please use at least 8 characters with a mix of letters, numbers, and symbols."
        static let invalidEmail = "Please enter a valid email address."
        static let userNotFound = "No account found with this email. Please check your email or sign up for a new account."
        static let wrongPassword = "Incorrect password. Please try again or reset your password."
        static let networkError = "Network error. Please check your internet connection and try again."
        static let tooManyRequests = "Too many attempts. Please try again later."
        static let userDisabled = "This account has been disabled. Please contact support."
        static let authenticationRequired = "Please sign in to continue."
        static let noUserSignedIn = "No user signed in"
        static let accountDeletionFailed = "Failed to delete account"
        static let emailVerificationFailed = "Failed to send verification email"
        static let tokenRefreshFailed = "Failed to refresh authentication token"
    }

    // MARK: - Success Messages
    enum SuccessMessages {
        static let signInSuccessful = "Sign in successful"
        static let signUpSuccessful = "Sign up successful"
        static let signOutSuccessful = "Sign out successful"
        static let passwordResetSent = "Password reset email sent"
        static let emailVerificationSent = "Verification email sent"
        static let accountDeleted = "Account deleted successfully"
        static let tokenRefreshed = "Auth token refreshed successfully"
    }

    // MARK: - Time Constants
    enum Timing {
        static let tokenExpirationWarningSeconds: TimeInterval = 300 // 5 minutes
        static let nonceExpirationSeconds: TimeInterval = 300 // 5 minutes
        static let authTimeoutSeconds: TimeInterval = 30
        static let profileLoadRetryMaxAttempts = 5
    }

    // MARK: - UserDefaults Keys
    enum UserDefaultsKeys {
        static let userRole = "userRole"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let biometricEnabled = "biometric_enabled"
    }

    // MARK: - Biometric
    enum Biometric {
        static let faceIDName = "Face ID"
        static let touchIDName = "Touch ID"
        static let genericBiometricName = "Biometric"
    }

    // MARK: - Roles
    enum Roles {
        static let athlete = "athlete"
        static let coach = "coach"
    }

    // MARK: - Firestore Collections
    enum FirestoreCollections {
        static let users = "users"
        static let sharedFolders = "sharedFolders"
        static let videos = "videos"
        static let invitations = "invitations"
        static let annotations = "annotations"
        static let coachAccessRevocations = "coach_access_revocations"
    }

    // MARK: - Storage Paths
    enum StoragePaths {
        static func athleteVideos(userID: String) -> String {
            "athlete_videos/\(userID)"
        }

        static func sharedFolder(folderID: String) -> String {
            "shared_folders/\(folderID)"
        }

        static func thumbnails(folderID: String) -> String {
            "shared_folders/\(folderID)/thumbnails"
        }
    }
}
