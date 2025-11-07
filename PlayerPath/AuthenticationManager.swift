//
//  AuthenticationManager.swift
//  PlayerPath
//
//  Created by Assistant on 11/1/25.
//

import SwiftUI
import SwiftData
import FirebaseAuth
import Combine

/// Simplified, unified authentication manager
@MainActor
@Observable
final class AuthenticationManager {
    // MARK: - Published State
    var isAuthenticated = false
    var currentFirebaseUser: FirebaseAuth.User?
    var isLoading = false
    var errorMessage: String?
    
    // MARK: - Private State
    private var authStateListener: AuthStateDidChangeListenerHandle?
    
    init() {
        startAuthStateListener()
    }
    
    deinit {
        if let listener = authStateListener {
            Auth.auth().removeStateDidChangeListener(listener)
        }
    }
    
    // MARK: - Authentication State
    
    private func startAuthStateListener() {
        authStateListener = Auth.auth().addStateDidChangeListener { _, user in
            Task { @MainActor [weak self] in
                await self?.updateAuthState(user)
            }
        }
        
        // Set initial state on main actor
        Task { @MainActor [weak self] in
            await self?.updateAuthState(Auth.auth().currentUser)
        }
    }
    
    private func updateAuthState(_ user: FirebaseAuth.User?) {
        currentFirebaseUser = user
        isAuthenticated = user != nil
        
        // Clear any previous errors when auth state changes
        errorMessage = nil
    }
    
    // MARK: - Authentication Methods
    
    func signIn(email: String, password: String) async {
        await performAuthAction {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            return result.user
        }
    }
    
    func signUp(email: String, password: String, displayName: String? = nil) async {
        await performAuthAction {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            
            // Set display name if provided
            if let displayName = displayName, !displayName.isEmpty {
                let changeRequest = result.user.createProfileChangeRequest()
                changeRequest.displayName = displayName
                try await changeRequest.commitChanges()
            }
            
            return result.user
        }
    }
    
    func signOut() {
        do {
            try Auth.auth().signOut()
        } catch {
            errorMessage = "Failed to sign out: \(error.localizedDescription)"
        }
    }
    
    func sendPasswordReset(email: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
        } catch {
            errorMessage = "Failed to send password reset: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    func clearError() {
        errorMessage = nil
    }
    
    // MARK: - Private Helpers
    
    private func performAuthAction(_ action: @escaping () async throws -> FirebaseAuth.User) async {
        isLoading = true
        errorMessage = nil
        
        do {
            _ = try await action()
            // Auth state will be updated automatically via listener
        } catch {
            errorMessage = AuthError.fromFirebaseError(error).userMessage
        }
        
        isLoading = false
    }
}

// MARK: - Simplified Error Handling

enum AuthError {
    case invalidEmail
    case emailInUse
    case weakPassword
    case wrongPassword
    case userNotFound
    case networkError
    case unknown(String)
    
    static func fromFirebaseError(_ error: Error) -> AuthError {
        guard let authError = error as NSError?,
              let errorCode = AuthErrorCode(rawValue: authError.code) else {
            return .unknown(error.localizedDescription)
        }
        
        switch errorCode {
        case .invalidEmail:
            return .invalidEmail
        case .emailAlreadyInUse:
            return .emailInUse
        case .weakPassword:
            return .weakPassword
        case .wrongPassword:
            return .wrongPassword
        case .userNotFound:
            return .userNotFound
        case .networkError:
            return .networkError
        default:
            return .unknown(error.localizedDescription)
        }
    }
    
    var userMessage: String {
        switch self {
        case .invalidEmail:
            return "Please enter a valid email address."
        case .emailInUse:
            return "An account with this email already exists."
        case .weakPassword:
            return "Password must be at least 6 characters long."
        case .wrongPassword:
            return "Incorrect password. Please try again."
        case .userNotFound:
            return "No account found with this email address."
        case .networkError:
            return "Network error. Please check your connection."
        case .unknown(let message):
            return message
        }
    }
}