//
//  AuthenticationManager.swift
//  PlayerPath
//
//  Created by Assistant on 11/1/25.
//

import SwiftUI
import Combine
import SwiftData
import FirebaseAuth

/// Simplified, unified authentication manager
@MainActor
final class AuthenticationManager: ObservableObject {
    // MARK: - Published State
    @Published var isAuthenticated = false
    @Published var currentFirebaseUser: FirebaseAuth.User?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // MARK: - Private State
    private var authStateListener: AuthStateDidChangeListenerHandle?
    
    init() {
        startAuthStateListener()
    }
    
    deinit {
        if let listener = authStateListener {
            Auth.auth().removeStateDidChangeListener(listener)
            authStateListener = nil
        }
    }
    
    // MARK: - Authentication State
    
    private func startAuthStateListener() {
        authStateListener = Auth.auth().addStateDidChangeListener { _, user in
            Task { @MainActor [weak self] in
                self?.updateAuthState(user)
            }
        }
        
        // Set initial state on main actor
        Task { @MainActor [weak self] in
            self?.updateAuthState(Auth.auth().currentUser)
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
        errorMessage = nil
        do {
            try Auth.auth().signOut()
        } catch {
            errorMessage = "Failed to sign out: \(error.localizedDescription)"
        }
    }
    
    func sendPasswordReset(email: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
        } catch {
            errorMessage = AuthManagerError.fromFirebaseError(error).userMessage
        }
    }
    
    // MARK: - Private Helpers
    
    private func performAuthAction(_ action: @escaping () async throws -> FirebaseAuth.User) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            _ = try await action()
            // Auth state will be updated automatically via listener
        } catch {
            errorMessage = AuthManagerError.fromFirebaseError(error).userMessage
        }
    }
}

// MARK: - Simplified Error Handling

enum AuthManagerError {
    case invalidEmail
    case emailInUse
    case weakPassword
    case wrongPassword
    case userNotFound
    case networkError
    case tooManyRequests
    case operationNotAllowed
    case requiresRecentLogin
    case userDisabled
    case accountExistsWithDifferentCredential
    case unknown(String)
    
    static func fromFirebaseError(_ error: Error) -> AuthManagerError {
        let nsError = error as NSError
        guard nsError.domain == AuthErrorDomain,
              let errorCode = AuthErrorCode(rawValue: nsError.code) else {
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
        case .tooManyRequests:
            return .tooManyRequests
        case .operationNotAllowed:
            return .operationNotAllowed
        case .requiresRecentLogin:
            return .requiresRecentLogin
        case .userDisabled:
            return .userDisabled
        case .accountExistsWithDifferentCredential:
            return .accountExistsWithDifferentCredential
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
        case .tooManyRequests:
            return "Too many attempts. Please wait a moment before trying again."
        case .operationNotAllowed:
            return "This sign-in method is not enabled for this app."
        case .requiresRecentLogin:
            return "For your security, please sign out and sign back in, then try again."
        case .userDisabled:
            return "This account has been disabled. Please contact support."
        case .accountExistsWithDifferentCredential:
            return "An account already exists with a different sign-in method for this email."
        case .unknown(let message):
            return message
        }
    }
}

