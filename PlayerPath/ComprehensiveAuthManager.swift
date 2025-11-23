import SwiftUI
import Combine
import FirebaseAuth
import SwiftData

@MainActor
final class ComprehensiveAuthManager: ObservableObject {
    @Published private(set) var currentFirebaseUser: FirebaseAuth.User?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var isNewUser: Bool = false // Track if this was a signup vs signin
    
    @Published var localUser: User?
    @Published var hasCompletedOnboarding: Bool = false
    
    // Make isSignedIn a @Published property for better UI reactivity
    @Published private(set) var isSignedIn: Bool = false
    
    // User role management (for coach sharing feature)
    @Published var userRole: UserRole = .athlete
    @Published var userProfile: UserProfile?
    
    // Computed properties to access Firebase user information
    var userEmail: String? {
        currentFirebaseUser?.email
    }
    
    var userDisplayName: String? {
        currentFirebaseUser?.displayName
    }
    
    var userID: String? {
        currentFirebaseUser?.uid
    }
    
    // Premium features
    @Published var isPremiumUser: Bool = false
    @Published var trialDaysRemaining: Int = 30
    
    private var authStateDidChangeListenerHandle: AuthStateDidChangeListenerHandle?
    private var modelContext: ModelContext?
    
    init() {
        currentFirebaseUser = Auth.auth().currentUser
        isSignedIn = currentFirebaseUser != nil
        authStateDidChangeListenerHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            // ✅ Consolidated into a single MainActor Task to prevent race conditions
            Task { @MainActor in
                self?.currentFirebaseUser = user
                self?.isSignedIn = user != nil
                
                // Reset new user flag when auth state changes (unless it's a signup)
                if user == nil {
                    self?.isNewUser = false
                } else {
                    // User signed in - ensure local user exists
                    await self?.ensureLocalUser()
                    
                    // Only load profile if this isn't a brand new signup
                    // (signUp/signUpAsCoach already handle profile creation and loading)
                    if self?.isNewUser == false {
                        print("🔍 Auth state changed - Loading profile for existing user")
                        await self?.loadUserProfile()
                    } else {
                        print("⏭️ Auth state changed - Skipping profile load for new user (already handled in signup)")
                    }
                }
            }
        }
        
        // Load profile for already signed-in users
        if currentFirebaseUser != nil {
            Task {
                await self.loadUserProfile()
            }
        }
    }
    
    deinit {
        if let handle = authStateDidChangeListenerHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }
    
    func attachModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    func ensureLocalUser() async {
        guard let context = modelContext,
              let firebaseUser = Auth.auth().currentUser,
              let email = firebaseUser.email else {
            return
        }
        
        let fetchDescriptor = FetchDescriptor<User>(predicate: #Predicate<User> { $0.email == email })
        
        do {
            let users = try context.fetch(fetchDescriptor)
            if let existingUser = users.first {
                await MainActor.run {
                    self.localUser = existingUser
                }
            } else {
                let newUser = User(username: firebaseUser.displayName ?? email, email: email)
                context.insert(newUser)
                try context.save()
                await MainActor.run {
                    self.localUser = newUser
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load user profile"
            }
        }
    }
    
    func markOnboardingComplete() {
        hasCompletedOnboarding = true
    }
    
    func signIn(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        isNewUser = false // This is a sign-in, not a new user
        
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            currentFirebaseUser = result.user
            isSignedIn = true
            
            // Load user profile from Firestore
            await loadUserProfile()
            
            isLoading = false
            print("🟢 Sign in successful for: \(result.user.email ?? "unknown") as \(userRole.rawValue)")
        } catch {
            errorMessage = friendlyErrorMessage(from: error)
            isLoading = false
            print("🔴 Sign in error: \(error.localizedDescription)")
        }
    }
    
    func signUp(email: String, password: String, displayName: String?) async {
        isLoading = true
        errorMessage = nil
        isNewUser = true // This is a signup, mark as new user
        
        // Set the role IMMEDIATELY before any async operations
        // This ensures the UI sees the correct role right away
        userRole = .athlete
        print("✅ Pre-set userRole to athlete BEFORE Firebase operations")
        
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            if let displayName = displayName, !displayName.isEmpty {
                let changeRequest = result.user.createProfileChangeRequest()
                changeRequest.displayName = displayName
                try await changeRequest.commitChanges()
            }
            currentFirebaseUser = result.user
            isSignedIn = true
            
            print("🔵 Creating athlete profile for: \(email)")
            
            // Create user profile in Firestore with default athlete role
            // Note: createUserProfile will also set userRole = .athlete internally
            try await createUserProfile(
                userID: result.user.uid,
                email: email,
                displayName: displayName ?? email,
                role: .athlete // Default to athlete, can be changed later
            )
            
            // Double-check the role is still set (defensive programming)
            if userRole != .athlete {
                print("⚠️ WARNING: userRole was changed after createUserProfile, resetting to athlete")
                userRole = .athlete
            }
            
            isLoading = false
            print("🟢 Sign up successful for athlete: \(result.user.email ?? "unknown") with role: \(userRole.rawValue)")
        } catch {
            errorMessage = friendlyErrorMessage(from: error)
            isLoading = false
            isNewUser = false
            print("🔴 Sign up error: \(error.localizedDescription)")
        }
    }
    
    /// Creates a user profile in Firestore
    func createUserProfile(
        userID: String,
        email: String,
        displayName: String,
        role: UserRole
    ) async throws {
        let profileData: [String: Any] = [
            "email": email.lowercased(),
            "role": role.rawValue,
            "isPremium": false,
            "createdAt": Date(),
            "displayName": displayName
        ]
        
        print("🔵 Creating user profile in Firestore - Role: \(role.rawValue), Email: \(email)")
        
        try await FirestoreManager.shared.updateUserProfile(
            userID: userID,
            email: email,
            role: role,
            profileData: profileData
        )
        
        // Note: userRole is already set synchronously before this function is called
        // We verify it matches what we're saving to Firestore
        if self.userRole != role {
            print("⚠️ WARNING: Local userRole (\(self.userRole.rawValue)) doesn't match Firestore role (\(role.rawValue))")
            self.userRole = role
            print("✅ Corrected userRole in memory to: \(role.rawValue)")
        } else {
            print("✅ Verified userRole in memory matches Firestore: \(role.rawValue)")
        }
        
        // Wait a moment for Firestore to propagate, then verify
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Fetch and cache the profile to confirm it was created correctly
        await loadUserProfile()
    }
    
    /// Loads user profile from Firestore
    func loadUserProfile() async {
        guard let userID = currentFirebaseUser?.uid,
              let email = currentFirebaseUser?.email else {
            print("⚠️ loadUserProfile: No user ID or email")
            return
        }
        
        print("🔍 loadUserProfile: Fetching profile for user \(email)")
        
        do {
            if let profile = try await FirestoreManager.shared.fetchUserProfile(userID: userID) {
                // Store the current role before updating from Firestore
                let currentRole = self.userRole
                
                // Update profile and role from Firestore
                userProfile = profile
                
                // Only update userRole if it's different AND this is not a new user
                // For new users, we want to keep the role we set synchronously at signup
                if isNewUser {
                    // New user: Keep the role we set at signup, but verify it matches Firestore
                    if profile.userRole != currentRole {
                        print("⚠️ WARNING: Firestore role (\(profile.userRole.rawValue)) doesn't match pre-set role (\(currentRole.rawValue)) for new user")
                        print("⚠️ Keeping pre-set role: \(currentRole.rawValue)")
                    } else {
                        print("✅ Firestore role matches pre-set role: \(currentRole.rawValue)")
                    }
                    // Keep the pre-set role, don't override
                } else {
                    // Existing user: Update role from Firestore
                    userRole = profile.userRole
                    print("✅ Updated role from Firestore for existing user: \(profile.userRole.rawValue)")
                }
                
                print("✅ Loaded user profile: \(profile.role) for \(email)")
            } else {
                // Profile doesn't exist - only create if this is NOT a new user
                // (new users should have had their profile created in signUp/signUpAsCoach)
                if !isNewUser {
                    print("⚠️ Profile doesn't exist for existing user \(email), creating default athlete profile")
                    try await createUserProfile(
                        userID: userID,
                        email: email,
                        displayName: currentFirebaseUser?.displayName ?? email,
                        role: .athlete
                    )
                } else {
                    print("⚠️ Profile not found for new user \(email), but keeping existing role: \(userRole.rawValue)")
                }
            }
        } catch {
            print("❌ Failed to load user profile for \(email): \(error)")
        }
    }
    
    /// Signs up a coach with default coach role
    func signUpAsCoach(email: String, password: String, displayName: String) async {
        isLoading = true
        errorMessage = nil
        isNewUser = true
        
        // Set the role IMMEDIATELY before any async operations
        // This ensures the UI sees the correct role right away
        userRole = .coach
        print("✅ Pre-set userRole to coach BEFORE Firebase operations")
        
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            let changeRequest = result.user.createProfileChangeRequest()
            changeRequest.displayName = displayName
            try await changeRequest.commitChanges()
            
            currentFirebaseUser = result.user
            isSignedIn = true
            
            print("🔵 Creating coach profile for: \(email)")
            
            // Create coach profile in Firestore
            // Note: createUserProfile will also set userRole = .coach internally
            try await createUserProfile(
                userID: result.user.uid,
                email: email,
                displayName: displayName,
                role: .coach
            )
            
            // Double-check the role is still set (defensive programming)
            if userRole != .coach {
                print("⚠️ WARNING: userRole was changed after createUserProfile, resetting to coach")
                userRole = .coach
            }
            
            // Check for pending invitations
            let invitations = try await SharedFolderManager.shared.checkPendingInvitations(forEmail: email)
            if !invitations.isEmpty {
                print("✅ Found \(invitations.count) pending invitations for new coach")
                // UI will show these invitations after sign-up
            }
            
            // Note: We DON'T mark hasCompletedOnboarding = true here
            // We want coaches to see their coach-specific onboarding flow
            
            isLoading = false
            print("🟢 Coach sign up successful for: \(email) with role: \(userRole.rawValue)")
        } catch {
            errorMessage = friendlyErrorMessage(from: error)
            isLoading = false
            isNewUser = false
            // Reset role on error
            userRole = .athlete
            print("🔴 Coach sign up error: \(error.localizedDescription)")
        }
    }
    
    func signOut() async {
        isLoading = true
        errorMessage = nil
        
        do {
            try Auth.auth().signOut()
            currentFirebaseUser = nil
            isSignedIn = false
            isLoading = false
            isNewUser = false
            errorMessage = nil
            print("🟢 Sign out successful")
        } catch {
            errorMessage = "Failed to sign out: \(error.localizedDescription)"
            isLoading = false
            print("🔴 Sign out error: \(error.localizedDescription)")
        }
    }
    
    func resetPassword(email: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
            isLoading = false
            print("🟢 Password reset sent to: \(email)")
        } catch {
            errorMessage = friendlyErrorMessage(from: error)
            isLoading = false
            print("🔴 Password reset error: \(error.localizedDescription)")
        }
    }
    
    /// Clears the current error message
    func clearError() {
        errorMessage = nil
    }
    
    func resetNewUserFlag() {
        isNewUser = false
    }
    
    // Method to allow external sign-in managers (like Apple Sign In) to update the user
    func updateCurrentUser(_ user: FirebaseAuth.User, isNewUser: Bool = false) {
        currentFirebaseUser = user
        isSignedIn = true
        self.isNewUser = isNewUser
    }
    
    private func friendlyErrorMessage(from error: Error) -> String {
        let authError = error as NSError
        
        switch authError.code {
        case AuthErrorCode.emailAlreadyInUse.rawValue:
            return "An account with this email already exists. Try signing in instead."
        case AuthErrorCode.weakPassword.rawValue:
            return "Password is too weak. Please use at least 8 characters with a mix of letters, numbers, and symbols."
        case AuthErrorCode.invalidEmail.rawValue:
            return "Please enter a valid email address."
        case AuthErrorCode.userNotFound.rawValue:
            return "No account found with this email. Please check your email or sign up for a new account."
        case AuthErrorCode.wrongPassword.rawValue:
            return "Incorrect password. Please try again or reset your password."
        case AuthErrorCode.networkError.rawValue:
            return "Network error. Please check your internet connection and try again."
        case AuthErrorCode.tooManyRequests.rawValue:
            return "Too many attempts. Please try again later."
        case AuthErrorCode.userDisabled.rawValue:
            return "This account has been disabled. Please contact support."
        default:
            return error.localizedDescription
        }
    }
}
