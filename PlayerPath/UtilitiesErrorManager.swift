//
//  ErrorManager.swift
//  PlayerPath
//
//  Created by Assistant on 10/26/25.
//

import SwiftUI

// MARK: - App Error Types
enum AppError: LocalizedError, Identifiable {
    case authentication(AuthenticationError)
    case dataModel(DataModelError)
    case network(NetworkError)
    case validation(ValidationError)
    
    var id: String {
        switch self {
        case .authentication(let error): return "auth_\(error.id)"
        case .dataModel(let error): return "data_\(error.id)"
        case .network(let error): return "network_\(error.id)"
        case .validation(let error): return "validation_\(error.id)"
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .authentication(let error): return error.localizedDescription
        case .dataModel(let error): return error.localizedDescription
        case .network(let error): return error.localizedDescription
        case .validation(let error): return error.localizedDescription
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .authentication(let error): return error.recoverySuggestion
        case .dataModel(let error): return error.recoverySuggestion
        case .network(let error): return error.recoverySuggestion
        case .validation(let error): return error.recoverySuggestion
        }
    }
}

// MARK: - Authentication Errors
enum AuthenticationError: LocalizedError, Identifiable {
    case invalidCredentials
    case userNotFound
    case emailAlreadyInUse
    case weakPassword
    case networkError
    case unknownError(String)
    
    var id: String {
        switch self {
        case .invalidCredentials: return "invalid_credentials"
        case .userNotFound: return "user_not_found"
        case .emailAlreadyInUse: return "email_in_use"
        case .weakPassword: return "weak_password"
        case .networkError: return "network_error"
        case .unknownError(let message): return "unknown_\(message.hashValue)"
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid email or password"
        case .userNotFound:
            return "Account not found"
        case .emailAlreadyInUse:
            return "Email address is already registered"
        case .weakPassword:
            return "Password is too weak"
        case .networkError:
            return "Connection error"
        case .unknownError(let message):
            return "Authentication failed: \(message)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .invalidCredentials:
            return "Please check your email and password and try again."
        case .userNotFound:
            return "Please check your email address or sign up for a new account."
        case .emailAlreadyInUse:
            return "Try signing in instead, or use a different email address."
        case .weakPassword:
            return "Please choose a stronger password with at least 8 characters."
        case .networkError:
            return "Please check your internet connection and try again."
        case .unknownError:
            return "Please try again in a moment."
        }
    }
}

// MARK: - Data Model Errors
enum DataModelError: LocalizedError, Identifiable {
    case saveFailure(String)
    case fetchFailure(String)
    case duplicateRecord
    case invalidData
    
    var id: String {
        switch self {
        case .saveFailure: return "save_failure"
        case .fetchFailure: return "fetch_failure"
        case .duplicateRecord: return "duplicate_record"
        case .invalidData: return "invalid_data"
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .saveFailure:
            return "Failed to save data"
        case .fetchFailure:
            return "Failed to load data"
        case .duplicateRecord:
            return "Record already exists"
        case .invalidData:
            return "Invalid data format"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .saveFailure:
            return "Please try again. If the problem persists, restart the app."
        case .fetchFailure:
            return "Please restart the app or check your device storage."
        case .duplicateRecord:
            return "Please choose a different name or modify the existing record."
        case .invalidData:
            return "Please check your input and try again."
        }
    }
}

// MARK: - Network Errors
enum NetworkError: LocalizedError, Identifiable {
    case noConnection
    case timeout
    case serverError
    case invalidResponse
    
    var id: String {
        switch self {
        case .noConnection: return "no_connection"
        case .timeout: return "timeout"
        case .serverError: return "server_error"
        case .invalidResponse: return "invalid_response"
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .noConnection:
            return "No internet connection"
        case .timeout:
            return "Request timed out"
        case .serverError:
            return "Server error"
        case .invalidResponse:
            return "Invalid server response"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .noConnection:
            return "Please check your internet connection and try again."
        case .timeout:
            return "The request took too long. Please try again."
        case .serverError:
            return "Server is experiencing issues. Please try again later."
        case .invalidResponse:
            return "Please update the app or try again later."
        }
    }
}

// MARK: - Validation Errors
enum ValidationError: LocalizedError, Identifiable {
    case emptyField(String)
    case invalidFormat(String)
    case tooShort(String, Int)
    case tooLong(String, Int)
    
    var id: String {
        switch self {
        case .emptyField(let field): return "empty_\(field)"
        case .invalidFormat(let field): return "invalid_\(field)"
        case .tooShort(let field, _): return "short_\(field)"
        case .tooLong(let field, _): return "long_\(field)"
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .emptyField(let field):
            return "\(field) cannot be empty"
        case .invalidFormat(let field):
            return "Invalid \(field) format"
        case .tooShort(let field, let min):
            return "\(field) must be at least \(min) characters"
        case .tooLong(let field, let max):
            return "\(field) must be no more than \(max) characters"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .emptyField:
            return "Please enter a value for this field."
        case .invalidFormat:
            return "Please check the format and try again."
        case .tooShort, .tooLong:
            return "Please adjust the length and try again."
        }
    }
}

// MARK: - Error Display Component
struct ErrorDisplayView: View {
    let error: AppError
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.title3)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Error")
                        .font(.headline)
                        .foregroundColor(.red)
                    
                    if let description = error.errorDescription {
                        Text(description)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    }
                }
                
                Spacer()
                
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
            
            if let recovery = error.recoverySuggestion {
                Text(recovery)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}