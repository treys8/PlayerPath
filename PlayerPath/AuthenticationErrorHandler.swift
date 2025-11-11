//
//  AuthenticationErrorHandler.swift
//  PlayerPath
//
//  Created by Assistant on 11/1/25.
//

import Foundation
import FirebaseAuth

struct AuthenticationErrorHandler {
    
    static func handleAuthError(_ error: Error) -> String {
        // Normalize to NSError and check Firebase Auth domain
        if let authCode = authErrorCode(from: error) {
            return messageForAuthError(authCode)
        }
        
        // Generic error handling
        let lowercased = error.localizedDescription.lowercased()
        
        // Handle common network-related errors
        if lowercased.contains("network") || lowercased.contains("internet") {
            return "Please check your internet connection and try again."
        }
        
        // Handle timeout errors
        if lowercased.contains("timeout") {
            return "The request timed out. Please try again."
        }
        
        // Fallback: show localized description in Debug, friendly message in Release
        #if DEBUG
        return error.localizedDescription
        #else
        return "Something went wrong. Please try again."
        #endif
    }
    
    /// Provides user-friendly suggestions based on the error
    static func suggestionForError(_ error: Error) -> String? {
        if let authCode = authErrorCode(from: error) {
            return suggestionForAuthError(authCode)
        }
        return nil
    }
    
    // MARK: - Private helpers
    
    private static func authErrorCode(from error: Error) -> AuthErrorCode? {
        let nsError = error as NSError
        guard nsError.domain == AuthErrorDomain else { return nil }
        return AuthErrorCode(rawValue: nsError.code)
    }
    
    private static func messageForAuthError(_ authError: AuthErrorCode) -> String {
        switch authError {
        case .emailAlreadyInUse:
            return "This email address is already associated with an account."
        case .invalidEmail:
            return "Please enter a valid email address."
        case .weakPassword:
            return "Your password must be at least 6 characters long."
        case .wrongPassword:
            return "The password you entered is incorrect."
        case .userNotFound:
            return "No account found with this email address."
        case .userDisabled:
            return "This account has been disabled. Please contact support."
        case .tooManyRequests:
            return "Too many attempts. Please wait a moment before trying again."
        case .networkError:
            return "Network error. Please check your connection."
        case .invalidCredential:
            return "Invalid credentials. Please check your email and password."
        case .operationNotAllowed:
            return "This sign-in method is not enabled for this app."
        case .requiresRecentLogin:
            return "For your security, please sign out and sign back in, then try again."
        case .accountExistsWithDifferentCredential:
            return "An account already exists with a different sign-in method for this email."
        case .userTokenExpired:
            return "Your session has expired. Please sign in again."
        default:
            return "Authentication failed. Please try again."
        }
    }
    
    private static func suggestionForAuthError(_ authError: AuthErrorCode) -> String? {
        switch authError {
        case .emailAlreadyInUse:
            return "Try signing in instead, or use password reset if you forgot your password."
        case .weakPassword:
            return "Use a combination of letters, numbers, and special characters."
        case .wrongPassword:
            return "Double-check your password or use 'Forgot Password' to reset it."
        case .userNotFound:
            return "Create a new account or verify you're using the correct email address."
        case .tooManyRequests:
            return "Wait 5–10 minutes before attempting to sign in again."
        case .requiresRecentLogin:
            return "Sign out and sign back in, then retry the operation."
        case .operationNotAllowed:
            return "Contact support if you believe this sign-in method should be enabled."
        default:
            return nil
        }
    }
}
