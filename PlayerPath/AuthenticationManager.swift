//
//  AuthenticationManager.swift
//  PlayerPath
//
//  Created by Assistant on 11/1/25.
//
//  CRITICAL FIXES APPLIED:
//  1. ✅ Thread Safety - Explicit @MainActor on init and state updates
//  2. ✅ Race Condition Prevention - Fixed listener initialization order
//  3. ✅ Task Cancellation - Added cancellation checks throughout
//  4. ✅ Input Validation - Email and password validation before Firebase calls
//  5. ✅ Logging/Analytics - Added comprehensive debug logging
//  6. ✅ Extended API - Added reauthentication, email verification, display name updates
//  7. ✅ AuthManagerError conforms to Error protocol
//

import SwiftUI
import Combine
import SwiftData
import FirebaseAuth

/// Production-ready authentication manager with thread safety and comprehensive error handling
@MainActor
final class AuthenticationManager: ObservableObject {
    // MARK: - Published State
    @Published var isAuthenticated = false
    @Published var currentFirebaseUser: FirebaseAuth.User?
    @Published var currentUser: User?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // MARK: - Private State
    private var authStateListener: AuthStateDidChangeListenerHandle?
    private var modelContext: ModelContext?
    
    // MARK: - Computed Properties
    
    /// Returns true if the current user's email has been verified
    var isEmailVerified: Bool {
        currentFirebaseUser?.isEmailVerified ?? false
    }
    
    /// Returns the current user's email address
    var userEmail: String? {
        currentFirebaseUser?.email
    }
    
    /// Returns the current user's display name
    var displayName: String? {
        currentFirebaseUser?.displayName
    }
    
    // MARK: - Initialization
    
    @MainActor
    init() {
        logAuthEvent("AuthenticationManager initialized")
        startAuthStateListener()
    }
    
    deinit {
        if let listener = authStateListener {
            Auth.auth().removeStateDidChangeListener(listener)
            authStateListener = nil
            
            // Note: Can't call @MainActor methods from deinit
            #if DEBUG
            print("🔐 Auth: AuthenticationManager deinitialized - listener removed")
            #endif
        }
    }
    
    // MARK: - Model Context Integration
    
    /// Attach SwiftData model context for user management
    func attachModelContext(_ context: ModelContext) {
        self.modelContext = context
        logAuthEvent("Model context attached")
        
        // Reload user if already authenticated
        if let firebaseUser = currentFirebaseUser {
            Task {
                await loadOrCreateLocalUser(firebaseUser)
            }
        }
    }
    
    // MARK: - Authentication State
    
    private func startAuthStateListener() {
        // Set initial state FIRST (before listener to avoid race condition)
        let initialUser = Auth.auth().currentUser
        updateAuthState(initialUser)
        
        // Then register listener for future changes
        authStateListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor [weak self] in
                self?.updateAuthState(user)
            }
        }
        
        logAuthEvent("Auth state listener started", metadata: ["initiallyAuthenticated": initialUser != nil])
    }
    
    private func updateAuthState(_ user: FirebaseAuth.User?) {
        // Verify we're on main thread in debug builds
        dispatchPrecondition(condition: .onQueue(.main))
        
        let wasAuthenticated = isAuthenticated
        
        currentFirebaseUser = user
        isAuthenticated = user != nil
        errorMessage = nil
        
        logAuthEvent("Auth state updated", metadata: [
            "authenticated": user != nil,
            "email": user?.email ?? "none",
            "emailVerified": user?.isEmailVerified ?? false,
            "stateChanged": wasAuthenticated != isAuthenticated
        ])
        
        // Load or create local user if authenticated
        if let firebaseUser = user {
            Task {
                await loadOrCreateLocalUser(firebaseUser)
            }
        } else {
            currentUser = nil
        }
    }
    
    // MARK: - Local User Management
    
    private func loadOrCreateLocalUser(_ firebaseUser: FirebaseAuth.User) async {
        guard let context = modelContext else {
            logAuthEvent("Cannot load local user - no model context attached", isError: true)
            return
        }
        
        guard let email = firebaseUser.email else {
            logAuthEvent("Cannot load local user - no email on Firebase user", isError: true)
            return
        }
        
        let normalizedEmail = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Try to fetch existing user
        let descriptor = FetchDescriptor<User>(
            predicate: #Predicate { user in
                user.email == normalizedEmail
            }
        )
        
        do {
            let users = try context.fetch(descriptor)
            
            if let existingUser = users.first {
                currentUser = existingUser
                logAuthEvent("Loaded existing local user", metadata: ["email": normalizedEmail])
            } else {
                // Create new user
                let newUser = User(
                    username: firebaseUser.displayName ?? normalizedEmail,
                    email: normalizedEmail
                )
                context.insert(newUser)
                try context.save()
                
                currentUser = newUser
                logAuthEvent("Created new local user", metadata: ["email": normalizedEmail])
            }
        } catch {
            logAuthEvent("Failed to load/create local user: \(error.localizedDescription)", isError: true)
        }
    }
    
    // MARK: - Authentication Methods
    
    /// Sign in with email and password
    func signIn(email: String, password: String) async {
        // Validate inputs before calling Firebase
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedEmail.isEmpty, !password.isEmpty else {
            errorMessage = "Email and password are required."
            logAuthEvent("Sign in failed - empty credentials", isError: true)
            return
        }
        
        guard trimmedEmail.contains("@"), trimmedEmail.contains(".") else {
            errorMessage = "Please enter a valid email address."
            logAuthEvent("Sign in failed - invalid email format", isError: true)
            return
        }
        
        logAuthEvent("Sign in attempt", metadata: ["email": trimmedEmail])
        
        await performAuthAction {
            let result = try await Auth.auth().signIn(withEmail: trimmedEmail, password: password)
            return result.user
        }
    }
    
    /// Sign up with email, password, and optional display name
    func signUp(email: String, password: String, displayName: String? = nil) async {
        // Validate inputs before calling Firebase
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedEmail.isEmpty, !password.isEmpty else {
            errorMessage = "Email and password are required."
            logAuthEvent("Sign up failed - empty credentials", isError: true)
            return
        }
        
        guard trimmedEmail.contains("@"), trimmedEmail.contains(".") else {
            errorMessage = "Please enter a valid email address."
            logAuthEvent("Sign up failed - invalid email format", isError: true)
            return
        }
        
        guard password.count >= 6 else {
            errorMessage = "Password must be at least 6 characters long."
            logAuthEvent("Sign up failed - password too short", isError: true)
            return
        }
        
        logAuthEvent("Sign up attempt", metadata: ["email": trimmedEmail, "hasDisplayName": trimmedName != nil])
        
        await performAuthAction {
            let result = try await Auth.auth().createUser(withEmail: trimmedEmail, password: password)
            
            // Set display name if provided
            if let name = trimmedName, !name.isEmpty {
                let changeRequest = result.user.createProfileChangeRequest()
                changeRequest.displayName = name
                try await changeRequest.commitChanges()
                self.logAuthEvent("Display name set during sign up", metadata: ["name": name])
            }
            
            return result.user
        }
    }
    
    /// Sign out the current user
    func signOut() async {
        errorMessage = nil
        logAuthEvent("Sign out attempt")
        
        do {
            try Auth.auth().signOut()
            currentUser = nil
            logAuthEvent("Sign out successful")
        } catch {
            errorMessage = "Failed to sign out: \(error.localizedDescription)"
            logAuthEvent("Sign out failed: \(error.localizedDescription)", isError: true)
        }
    }
    
    /// Send password reset email
    func sendPasswordReset(email: String) async {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedEmail.isEmpty else {
            errorMessage = "Email is required."
            return
        }
        
        guard trimmedEmail.contains("@"), trimmedEmail.contains(".") else {
            errorMessage = "Please enter a valid email address."
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        logAuthEvent("Password reset requested", metadata: ["email": trimmedEmail])
        
        do {
            try await Auth.auth().sendPasswordReset(withEmail: trimmedEmail)
            logAuthEvent("Password reset email sent")
        } catch {
            let authError = AuthManagerError.fromFirebaseError(error)
            errorMessage = authError.userMessage
            logAuthEvent("Password reset failed: \(authError)", isError: true)
        }
        
        isLoading = false
    }
    
    /// Send email verification to current user
    func sendEmailVerification() async throws {
        guard let user = currentFirebaseUser else {
            throw AuthManagerError.unknown("Not signed in")
        }
        
        guard !user.isEmailVerified else {
            logAuthEvent("Email already verified")
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        logAuthEvent("Sending email verification")
        
        do {
            try await user.sendEmailVerification()
            logAuthEvent("Email verification sent")
        } catch {
            let authError = AuthManagerError.fromFirebaseError(error)
            logAuthEvent("Email verification failed: \(authError)", isError: true)
            throw authError
        }
    }
    
    /// Update the current user's display name
    func updateDisplayName(_ newName: String) async throws {
        guard let user = currentFirebaseUser else {
            throw AuthManagerError.unknown("Not signed in")
        }
        
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedName.isEmpty else {
            throw AuthManagerError.unknown("Display name cannot be empty")
        }
        
        isLoading = true
        
        logAuthEvent("Updating display name", metadata: ["newName": trimmedName])
        
        do {
            let changeRequest = user.createProfileChangeRequest()
            changeRequest.displayName = trimmedName
            try await changeRequest.commitChanges()
            
            // Update local user if available
            if let localUser = currentUser {
                localUser.username = trimmedName
                if let context = modelContext {
                    try context.save()
                }
            }
            
            logAuthEvent("Display name updated successfully")
        } catch {
            let authError = AuthManagerError.fromFirebaseError(error)
            logAuthEvent("Display name update failed: \(authError)", isError: true)
            throw authError
        }
        
        isLoading = false
    }
    
    /// Reauthenticate the current user (required for sensitive operations)
    func reauthenticate(password: String) async throws {
        guard let user = currentFirebaseUser,
              let email = user.email else {
            throw AuthManagerError.unknown("Not signed in")
        }
        
        guard !password.isEmpty else {
            throw AuthManagerError.unknown("Password is required")
        }
        
        isLoading = true
        
        logAuthEvent("Reauthentication attempt")
        
        do {
            let credential = EmailAuthProvider.credential(withEmail: email, password: password)
            try await user.reauthenticate(with: credential)
            logAuthEvent("Reauthentication successful")
        } catch {
            let authError = AuthManagerError.fromFirebaseError(error)
            logAuthEvent("Reauthentication failed: \(authError)", isError: true)
            throw authError
        }
        
        isLoading = false
    }
    
    /// Delete the current user account (requires recent authentication)
    func deleteAccount() async throws {
        guard let user = currentFirebaseUser else {
            throw AuthManagerError.unknown("Not signed in")
        }
        
        isLoading = true
        
        logAuthEvent("Account deletion attempt")
        
        do {
            // Delete local user first
            if let localUser = currentUser, let context = modelContext {
                context.delete(localUser)
                try context.save()
            }
            
            // Then delete Firebase user
            try await user.delete()
            
            currentUser = nil
            logAuthEvent("Account deleted successfully")
        } catch {
            let authError = AuthManagerError.fromFirebaseError(error)
            logAuthEvent("Account deletion failed: \(authError)", isError: true)
            throw authError
        }
        
        isLoading = false
    }
    
    /// Refresh the current user's token and email verification status
    func refreshUser() async throws {
        guard let user = currentFirebaseUser else {
            throw AuthManagerError.unknown("Not signed in")
        }
        
        logAuthEvent("Refreshing user data")
        
        do {
            try await user.reload()
            logAuthEvent("User data refreshed", metadata: ["emailVerified": user.isEmailVerified])
        } catch {
            let authError = AuthManagerError.fromFirebaseError(error)
            logAuthEvent("User refresh failed: \(authError)", isError: true)
            throw authError
        }
    }
    
    // MARK: - Private Helpers
    
    private func performAuthAction(_ action: @escaping () async throws -> FirebaseAuth.User) async {
        // Check if already cancelled before starting
        guard !Task.isCancelled else {
            logAuthEvent("Auth action cancelled before starting")
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            _ = try await action()
            
            // Check cancellation before updating state
            guard !Task.isCancelled else {
                logAuthEvent("Auth action cancelled after completion")
                isLoading = false
                return
            }
            
            logAuthEvent("Auth action completed successfully")
            // Auth state will be updated automatically via listener
        } catch {
            // Check cancellation before showing error
            guard !Task.isCancelled else {
                logAuthEvent("Auth action cancelled during error handling")
                isLoading = false
                return
            }
            
            let authError = AuthManagerError.fromFirebaseError(error)
            errorMessage = authError.userMessage
            logAuthEvent("Auth action failed: \(authError)", isError: true)
        }
        
        isLoading = false
    }
    
    // MARK: - Logging
    
    private func logAuthEvent(_ message: String, metadata: [String: Any] = [:], isError: Bool = false) {
        #if DEBUG
        let icon = isError ? "❌" : "🔐"
        var logMessage = "\(icon) Auth: \(message)"
        
        if !metadata.isEmpty {
            let metadataString = metadata.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            logMessage += " [\(metadataString)]"
        }
        
        print(logMessage)
        #endif
        
        // TODO: Add production analytics here
        // Analytics.logEvent("auth_\(message)", parameters: metadata)
    }
}

// MARK: - Simplified Error Handling

enum AuthManagerError: Error {
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

