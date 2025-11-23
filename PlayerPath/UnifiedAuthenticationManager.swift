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

#if DEBUG
private func debugLog(_ message: @autoclosure () -> String) {
    print(message())
}
#else
@inline(__always)
private func debugLog(_ message: @autoclosure () -> String) { }
#endif

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
    private var loadUserTask: Task<Void, Never>?
    private var pendingLoad = false
    
    init() {
        startAuthStateListener()
    }
    
    deinit {
        loadUserTask?.cancel()
        if let listener = authStateListener {
            Auth.auth().removeStateDidChangeListener(listener)
        }
    }
    
    // MARK: - Setup
    
    func setup(context: ModelContext) {
        loadUserTask?.cancel()
        self.modelContext = context
        
        // If we're already authenticated and a load was pending before context arrived, perform it now
        if isAuthenticated && pendingLoad {
            pendingLoad = false
            loadUserTask = Task {
                await loadUser(usingEmail: Auth.auth().currentUser?.email)
            }
        } else if let _ = Auth.auth().currentUser {
            loadUserTask = Task {
                await loadUser(usingEmail: Auth.auth().currentUser?.email)
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
        loadUserTask?.cancel()
        currentFirebaseUser = user
        isAuthenticated = user != nil
        errorMessage = nil
        
        if let user = user {
            // If context is not ready yet, mark pending and return
            guard modelContext != nil else {
                pendingLoad = true
                return
            }
            let email = user.email
            loadUserTask = Task {
                await loadUser(usingEmail: email)
            }
        } else {
            currentUser = nil
        }
    }
    
    // MARK: - User Management
    
    private func loadUser(usingEmail emailParam: String?) async {
        if Task.isCancelled { return }
        
        let firebaseUser = Auth.auth().currentUser
        let context = modelContext
        let rawEmail = emailParam ?? firebaseUser?.email
        
        guard let emailRaw = rawEmail, let context else {
            debugLog("loadUser: Missing firebaseUser email or modelContext")
            return
        }
        
        let lowercasedEmail = emailRaw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        debugLog("loadUser: Looking for user with email: '\(lowercasedEmail)'")
        isLoading = true
        defer { isLoading = false }
        
        do {
            // First, let's see ALL users in the database for debugging
            let allUsersDescriptor = FetchDescriptor<User>()
            let allUsers = try context.fetch(allUsersDescriptor)
            debugLog("loadUser: Total users in database: \(allUsers.count)")
            for user in allUsers {
                debugLog("loadUser: Existing user - Email: '\(user.email)', Athletes: \((user.athletes ?? []).count)")
            }
            
            // Find user by lowercased email
            let descriptor = FetchDescriptor<User>(
                predicate: #Predicate<User> { user in
                    user.email == lowercasedEmail
                }
            )
            
            let users = try context.fetch(descriptor)
            let existingUser = users.first
            
            debugLog("loadUser: Found matching user: \(existingUser?.email ?? "none")")
            
            if let existingUser = existingUser {
                debugLog("loadUser: Loading existing user with \((existingUser.athletes ?? []).count) athletes")
                currentUser = existingUser
                
                // Refresh the athletes relationship to ensure it's loaded
                for athlete in (existingUser.athletes ?? []) {
                    debugLog("loadUser: User has athlete: '\(athlete.name)'")
                }
            } else {
                // No user found - check for orphaned athletes
                let orphanDescriptor = FetchDescriptor<Athlete>(
                    predicate: #Predicate<Athlete> { athlete in
                        athlete.user == nil
                    }
                )
                
                let orphanedAthletes = try context.fetch(orphanDescriptor)
                debugLog("loadUser: Found \(orphanedAthletes.count) orphaned athletes")
                
                // Also check ALL athletes to see what's in the database
                let allAthletesDescriptor = FetchDescriptor<Athlete>()
                let allAthletes = try context.fetch(allAthletesDescriptor)
                debugLog("loadUser: Total athletes in database: \(allAthletes.count)")
                for athlete in allAthletes {
                    debugLog("loadUser: Athlete '\(athlete.name)' has user: \(athlete.user?.email ?? "nil")")
                }
                
                // Create new user with lowercased email
                let newUser = User(
                    username: (firebaseUser?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? lowercasedEmail,
                    email: lowercasedEmail
                )
                
                // Associate orphaned athletes with the new user
                // SwiftData handles inverse relationships automatically
                for athlete in orphanedAthletes {
                    debugLog("loadUser: Associating athlete '\(athlete.name)' with new user")
                    athlete.user = newUser
                    if var list = newUser.athletes {
                        list.append(athlete)
                        newUser.athletes = list
                    }
                }
                
                context.insert(newUser)
                try context.save()
                currentUser = newUser
                
                debugLog("loadUser: Created new user '\(lowercasedEmail)' with \((newUser.athletes ?? []).count) athletes")
            }
        } catch {
            debugLog("loadUser: Failed to load/create user: \(error)")
            errorMessage = AuthError.fromSwiftDataError(error).userMessage
        }
    }
    
    // MARK: - Authentication Methods
    
    func signIn(email: String, password: String) async {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        guard Validators.isValidEmail(normalizedEmail) else {
            errorMessage = AuthError.invalidEmail.userMessage
            return
        }
        await performAuthAction {
            let result = try await Auth.auth().signIn(withEmail: normalizedEmail, password: password)
            return result.user
        }
    }
    
    func signUp(email: String, password: String, displayName: String? = nil) async {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        guard Validators.isValidEmail(normalizedEmail) else {
            errorMessage = AuthError.invalidEmail.userMessage
            return
        }
        
        guard Validators.isStrongPassword(password) else {
            errorMessage = AuthError.weakPassword.userMessage
            return
        }
        await performAuthAction {
            let result = try await Auth.auth().createUser(withEmail: normalizedEmail, password: password)
            
            if let displayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !displayName.isEmpty {
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
            // NOTE: Keep currentUser = nil but don't clear SwiftData - it should persist
            currentUser = nil
            debugLog("signOut: User signed out, but local data preserved")
        } catch {
            debugLog("signOut: Failed to sign out: \(error.localizedDescription)")
            errorMessage = "Failed to sign out: \(error.localizedDescription)"
        }
    }
    
    func sendPasswordReset(email: String) async {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // Early validate email format to avoid unnecessary network calls
        guard Validators.isValidEmail(normalizedEmail) else {
            errorMessage = AuthError.invalidEmail.userMessage
            return
        }
        
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            try await Auth.auth().sendPasswordReset(withEmail: normalizedEmail)
        } catch {
            errorMessage = AuthError.fromFirebaseError(error).userMessage
        }
    }
    
    // MARK: - Private Helpers
    
    private func performAuthAction(_ action: @escaping () async throws -> FirebaseAuth.User) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            if Task.isCancelled { return }
            _ = try await action()
            // Auth state will be updated automatically via listener
        } catch {
            errorMessage = AuthError.fromFirebaseError(error).userMessage
            debugLog("Auth action failed: \(error)")
        }
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
