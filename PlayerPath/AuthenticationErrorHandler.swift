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
        // First check if it's a FirebaseAuth error
        if let authError = error as? AuthErrorCode {
            return messageForAuthError(authError)
        }
        
        // Check if it's wrapped in NSError
        if let nsError = error as NSError?,
           let authErrorCode = AuthErrorCode(rawValue: nsError.code) {
            return messageForAuthError(authErrorCode)
        }
        
        // Generic error handling
        let errorMessage = error.localizedDescription
        
        // Handle common network-related errors
        if errorMessage.lowercased().contains("network") ||
           errorMessage.lowercased().contains("internet") {
            return "Please check your internet connection and try again."
        }
        
        // Handle timeout errors
        if errorMessage.lowercased().contains("timeout") {
            return "The request timed out. Please try again."
        }
        
        return errorMessage
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
        default:
            return "Authentication failed. Please try again."
        }
    }
    
    /// Provides user-friendly suggestions based on the error
    static func suggestionForError(_ error: Error) -> String? {
        if let authError = error as? AuthErrorCode {
            return suggestionForAuthError(authError)
        }
        
        if let nsError = error as NSError?,
           let authErrorCode = AuthErrorCode(rawValue: nsError.code) {
            return suggestionForAuthError(authErrorCode)
        }
        
        return nil
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
            return "Wait 5-10 minutes before attempting to sign in again."
        default:
            return nil
        }
    }
}