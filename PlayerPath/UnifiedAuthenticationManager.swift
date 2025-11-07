//
//  UnifiedAuthenticationManager.swift
//  PlayerPath
//
//  Created by Assistant on 11/1/25.
//

import SwiftUI
import SwiftData
import FirebaseAuth
import Combine

/// Unified authentication manager combining Firebase Auth with SwiftData
@MainActor
final class UnifiedAuthenticationManager: ObservableObject {
    // MARK: - Published State
    @Published var currentUser: User?
    @Published var currentFirebaseUser: FirebaseAuth.User?
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // MARK: - Private State
    private var modelContext: ModelContext?
    private var authStateListener: AuthStateDidChangeListenerHandle?
    
    init() {
        startAuthStateListener()
    }
    
    deinit {
        if let listener = authStateListener {
            Auth.auth().removeStateDidChangeListener(listener)
        }
    }
    
    // MARK: - Setup
    
    func setup(context: ModelContext) {
        self.modelContext = context
        
        // Load user if already authenticated
        if isAuthenticated {
            Task { 
                await loadUser() 
            }
        }
    }
    
    // MARK: - Authentication State Management
    
    private func startAuthStateListener() {
        authStateListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor [weak self] in
                await self?.updateAuthState(user)
            }
        }
        
        // Set initial state
        Task { @MainActor [weak self] in
            await self?.updateAuthState(Auth.auth().currentUser)
        }
    }
    
    private func updateAuthState(_ user: FirebaseAuth.User?) async {
        currentFirebaseUser = user
        isAuthenticated = user != nil
        errorMessage = nil
        
        if user != nil {
            await loadUser()
        } else {
            currentUser = nil
        }
    }
    
    // MARK: - User Management
    
    private func loadUser() async {
        guard let firebaseUser = Auth.auth().currentUser,
              let email = firebaseUser.email,
              let context = modelContext else {
            return
        }
        
        isLoading = true
        
        do {
            let descriptor = FetchDescriptor<User>(
                predicate: #Predicate<User> { user in
                    user.email == email
                }
            )
            
            let users = try context.fetch(descriptor)
            
            if let existingUser = users.first {
                currentUser = existingUser
            } else {
                // Create new user
                let newUser = User(
                    username: firebaseUser.displayName ?? email,
                    email: email
                )
                context.insert(newUser)
                try context.save()
                currentUser = newUser
            }
        } catch {
            print("Failed to load/create user: \(error)")
            errorMessage = AuthError.fromSwiftDataError(error).userMessage
        }
        
        isLoading = false
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
            currentUser = nil
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
            errorMessage = AuthError.fromFirebaseError(error).userMessage
        }
        
        isLoading = false
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

// MARK: - Enhanced Error Handling

enum AuthError {
    case invalidEmail
    case emailInUse
    case weakPassword
    case wrongPassword
    case userNotFound
    case networkError
    case dataError
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
    
    static func fromSwiftDataError(_ error: Error) -> AuthError {
        return .dataError
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
        case .dataError:
            return "Failed to save user profile. Please try again."
        case .unknown(let message):
            return message
        }
    }
}