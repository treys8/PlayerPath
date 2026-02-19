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
    @Published var hasCompletedOnboarding: Bool = false {
        didSet {
            // Persist onboarding completion to UserDefaults to survive app restarts
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: AuthConstants.UserDefaultsKeys.hasCompletedOnboarding)
            print("💾 Persisted hasCompletedOnboarding to UserDefaults: \(hasCompletedOnboarding)")
        }
    }
    
    // Make isSignedIn a @Published property for better UI reactivity
    @Published private(set) var isSignedIn: Bool = false
    
    // User role management (for coach sharing feature)
    @Published var userRole: UserRole = .athlete {
        didSet {
            // Persist role to UserDefaults to survive app state changes
            UserDefaults.standard.set(userRole.rawValue, forKey: AuthConstants.UserDefaultsKeys.userRole)
            print("💾 Persisted userRole to UserDefaults: \(userRole.rawValue)")
        }
    }
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

        // Restore persisted role from UserDefaults to survive app restarts/state changes
        if let persistedRoleString = UserDefaults.standard.string(forKey: AuthConstants.UserDefaultsKeys.userRole),
           let persistedRole = UserRole(rawValue: persistedRoleString) {
            userRole = persistedRole
            print("💾 Restored userRole from UserDefaults: \(persistedRole.rawValue)")
        }

        // Restore persisted onboarding completion from UserDefaults
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: AuthConstants.UserDefaultsKeys.hasCompletedOnboarding)
        if hasCompletedOnboarding {
            print("💾 Restored hasCompletedOnboarding from UserDefaults: true")
        }

        authStateDidChangeListenerHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            // ✅ Consolidated into a single MainActor Task to prevent race conditions
            Task { @MainActor in
                self?.currentFirebaseUser = user
                self?.isSignedIn = user != nil

                // Reset new user flag when auth state changes (unless it's a signup)
                if user == nil {
                    // Clear ALL user-specific data to prevent leakage between accounts
                    self?.isNewUser = false
                    self?.userRole = .athlete
                    self?.userProfile = nil
                    self?.localUser = nil
                    self?.hasCompletedOnboarding = false
                    self?.isPremiumUser = false
                    self?.trialDaysRemaining = 30
                    UserDefaults.standard.removeObject(forKey: AuthConstants.UserDefaultsKeys.userRole)
                    UserDefaults.standard.removeObject(forKey: AuthConstants.UserDefaultsKeys.hasCompletedOnboarding)
                    print("🔄 Cleared all user data on sign out")
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
                var needsSave = false
                // Sync role from authManager to SwiftData if different
                if existingUser.role != self.userRole.rawValue {
                    existingUser.role = self.userRole.rawValue
                    needsSave = true
                    print("🔄 Synced user role to SwiftData: \(self.userRole.rawValue)")
                }
                // Store Firebase Auth UID so SyncCoordinator queries the correct Firestore path
                if existingUser.firebaseAuthUid != firebaseUser.uid {
                    existingUser.firebaseAuthUid = firebaseUser.uid
                    needsSave = true
                    print("🔄 Stored Firebase Auth UID: \(firebaseUser.uid)")
                }
                if needsSave { try context.save() }
                await MainActor.run {
                    self.localUser = existingUser
                }
            } else {
                // Create new user with current role from authManager
                let newUser = User(username: firebaseUser.displayName ?? email, email: email, role: self.userRole.rawValue)
                newUser.firebaseAuthUid = firebaseUser.uid
                context.insert(newUser)
                try context.save()
                print("✅ Created new SwiftData user with role: \(self.userRole.rawValue), Firebase UID: \(firebaseUser.uid)")
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

        // Clear any existing upload queues from previous session (handles account switching)
        UploadQueueManager.shared.clearAllQueues()

        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            currentFirebaseUser = result.user
            isSignedIn = true

            // Load user profile from Firestore
            await loadUserProfile()

            // Track successful sign in
            AnalyticsService.shared.setUserID(result.user.uid)
            AnalyticsService.shared.trackSignIn(method: "email")

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

        // Clear any existing upload queues from previous session
        UploadQueueManager.shared.clearAllQueues()
        
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

            // Track successful sign up
            AnalyticsService.shared.setUserID(result.user.uid)
            AnalyticsService.shared.trackSignUp(method: "email")

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

        // Fetch and cache the profile with retry logic to handle Firestore propagation
        // This replaces the hardcoded 0.5s sleep with proper retry mechanism
        await loadUserProfileWithRetry(maxAttempts: 5)
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

    /// Loads user profile from Firestore with retry logic
    /// This handles Firestore propagation delays using exponential backoff instead of fixed delays
    private func loadUserProfileWithRetry(maxAttempts: Int = 5) async {
        guard let userID = currentFirebaseUser?.uid,
              let email = currentFirebaseUser?.email else {
            print("⚠️ loadUserProfileWithRetry: No user ID or email")
            return
        }

        var attempt = 0

        while attempt < maxAttempts {
            attempt += 1

            do {
                if let profile = try await FirestoreManager.shared.fetchUserProfile(userID: userID) {
                    // Successfully fetched profile
                    let currentRole = self.userRole

                    userProfile = profile

                    if isNewUser {
                        if profile.userRole != currentRole {
                            print("⚠️ WARNING: Firestore role (\(profile.userRole.rawValue)) doesn't match pre-set role (\(currentRole.rawValue)) for new user")
                            print("⚠️ Keeping pre-set role: \(currentRole.rawValue)")
                        } else {
                            print("✅ Firestore role matches pre-set role: \(currentRole.rawValue)")
                        }
                    } else {
                        userRole = profile.userRole
                        print("✅ Updated role from Firestore for existing user: \(profile.userRole.rawValue)")
                    }

                    print("✅ Loaded user profile on attempt \(attempt): \(profile.role) for \(email)")
                    return
                } else if attempt < maxAttempts {
                    // Profile not found yet, retry with exponential backoff
                    let delay = pow(2.0, Double(attempt - 1)) * 0.1 // 0.1s, 0.2s, 0.4s, 0.8s, 1.6s
                    print("⏳ Profile not found for \(email) on attempt \(attempt)/\(maxAttempts), retrying in \(delay)s...")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } else {
                    // Last attempt and still not found - create profile as fallback
                    print("⚠️ Profile not found for \(email) after \(maxAttempts) attempts")
                    print("🔧 Creating fallback Firestore profile with current role: \(self.userRole.rawValue)")

                    // Create profile with current role (from UserDefaults/SwiftData)
                    do {
                        try await createUserProfile(
                            userID: userID,
                            email: email,
                            displayName: self.currentFirebaseUser?.displayName ?? email,
                            role: self.userRole
                        )
                        print("✅ Successfully created fallback Firestore profile")
                    } catch {
                        print("❌ Failed to create fallback profile: \(error)")
                    }
                    return
                }
            } catch {
                if attempt < maxAttempts {
                    let delay = pow(2.0, Double(attempt - 1)) * 0.1
                    print("❌ Error loading profile on attempt \(attempt)/\(maxAttempts): \(error). Retrying in \(delay)s...")
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } else {
                    print("❌ Failed to load user profile after \(maxAttempts) attempts: \(error)")
                    print("🔧 Creating fallback Firestore profile with current role: \(self.userRole.rawValue)")

                    // Create profile with current role as fallback
                    do {
                        try await createUserProfile(
                            userID: userID,
                            email: email,
                            displayName: self.currentFirebaseUser?.displayName ?? email,
                            role: self.userRole
                        )
                        print("✅ Successfully created fallback Firestore profile after errors")
                    } catch {
                        print("❌ Failed to create fallback profile: \(error)")
                    }
                }
            }
        }
    }

    /// Signs up a coach with default coach role
    func signUpAsCoach(email: String, password: String, displayName: String) async {
        isLoading = true
        errorMessage = nil
        isNewUser = true

        // Clear any existing upload queues from previous session
        UploadQueueManager.shared.clearAllQueues()
        
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
            // Track sign out before clearing user data
            AnalyticsService.shared.trackSignOut()
            AnalyticsService.shared.clearUserID()

            try Auth.auth().signOut()
            currentFirebaseUser = nil
            isSignedIn = false
            isLoading = false
            isNewUser = false
            errorMessage = nil
            userRole = .athlete // Reset to default

            // Clear persisted role and onboarding completion from UserDefaults
            UserDefaults.standard.removeObject(forKey: AuthConstants.UserDefaultsKeys.userRole)
            UserDefaults.standard.removeObject(forKey: AuthConstants.UserDefaultsKeys.hasCompletedOnboarding)

            // Clear biometric credentials on logout for security
            BiometricAuthenticationManager.shared.disableBiometric()

            // Clear upload queues to prevent cross-account data leakage
            UploadQueueManager.shared.clearAllQueues()

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

    /// Deletes user account and all associated data (GDPR compliance)
    /// This deletes:
    /// - Firebase Auth account
    /// - Firestore user profile and related data
    /// - Firebase Storage files (videos, thumbnails)
    /// - Local biometric credentials
    func deleteAccount() async throws {
        guard let user = currentFirebaseUser else {
            throw NSError(domain: "ComprehensiveAuthManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user signed in"])
        }

        isLoading = true
        errorMessage = nil

        do {
            let userID = user.uid

            print("🗑️ Starting account deletion for user: \(user.email ?? "unknown")")

            // Track account deletion request
            AnalyticsService.shared.trackAccountDeletionRequested(userID: userID)

            // Step 1: Delete all user videos from Firebase Storage
            print("🗑️ Deleting user videos from Storage...")
            do {
                try await VideoCloudManager.shared.deleteAllUserVideos(userID: userID)
                print("✅ Deleted all videos from Storage")
            } catch {
                print("⚠️ Error deleting videos from Storage: \(error)")
                // Continue with deletion even if video deletion fails
            }

            // Step 2: Delete Firestore user profile and related data
            print("🗑️ Deleting user profile from Firestore...")
            do {
                try await FirestoreManager.shared.deleteUserProfile(userID: userID)
                print("✅ Deleted user profile from Firestore")
            } catch {
                print("⚠️ Error deleting Firestore profile: \(error)")
                // Continue with deletion even if Firestore deletion fails
            }

            // Step 3: Clear biometric credentials
            print("🗑️ Clearing biometric credentials...")
            BiometricAuthenticationManager.shared.disableBiometric()

            // Step 4: Delete Firebase Auth account
            print("🗑️ Deleting Firebase Auth account...")
            try await user.delete()

            // Step 5: Clear local state
            currentFirebaseUser = nil
            isSignedIn = false
            userProfile = nil
            localUser = nil
            isLoading = false
            isNewUser = false
            userRole = .athlete

            // Clear persisted role and onboarding completion from UserDefaults
            UserDefaults.standard.removeObject(forKey: AuthConstants.UserDefaultsKeys.userRole)
            UserDefaults.standard.removeObject(forKey: AuthConstants.UserDefaultsKeys.hasCompletedOnboarding)

            // Track account deletion completion
            AnalyticsService.shared.trackAccountDeletionCompleted(userID: userID)
            AnalyticsService.shared.clearUserID()

            print("✅ Account deletion successful")

        } catch {
            errorMessage = "Failed to delete account: \(error.localizedDescription)"
            isLoading = false
            print("🔴 Account deletion error: \(error.localizedDescription)")
            throw error
        }
    }

    /// Clears the current error message
    func clearError() {
        errorMessage = nil
    }
    
    func resetNewUserFlag() {
        isNewUser = false
    }

    /// Marks onboarding as completed and resets new user flag
    /// Use this when user skips onboarding or completes it
    func completeOnboarding() {
        hasCompletedOnboarding = true
        isNewUser = false
        print("✅ Onboarding marked as completed")
    }

    /// Allows user to skip onboarding process
    /// This is useful for returning users or users who want to explore first
    func skipOnboarding() {
        completeOnboarding()
        print("⏭️ User skipped onboarding")
    }

    // Method to allow external sign-in managers (like Apple Sign In) to update the user
    func updateCurrentUser(_ user: FirebaseAuth.User, isNewUser: Bool = false) {
        currentFirebaseUser = user
        isSignedIn = true
        self.isNewUser = isNewUser
    }

    /// Refreshes the current user's Firebase Auth token
    /// Firebase tokens expire after 1 hour. This method explicitly refreshes the token.
    /// The SDK usually handles this automatically, but this provides explicit control.
    func refreshAuthToken() async throws {
        guard let user = currentFirebaseUser else {
            throw NSError(domain: "ComprehensiveAuthManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user signed in"])
        }

        do {
            // Force refresh the ID token
            let _ = try await user.getIDTokenResult(forcingRefresh: true)
            print("✅ Auth token refreshed successfully")
        } catch {
            print("🔴 Failed to refresh auth token: \(error.localizedDescription)")
            throw error
        }
    }

    /// Checks if the current auth token is valid and refreshes if needed
    /// Returns true if token is valid or successfully refreshed, false otherwise
    func ensureValidToken() async -> Bool {
        guard let user = currentFirebaseUser else {
            print("⚠️ No user signed in for token validation")
            return false
        }

        do {
            let tokenResult = try await user.getIDTokenResult(forcingRefresh: false)

            // Check if token is about to expire (within 5 minutes)
            let expirationDate = tokenResult.expirationDate
            let timeUntilExpiration = expirationDate.timeIntervalSinceNow
            if timeUntilExpiration < 300 { // Less than 5 minutes
                print("⚠️ Token expiring soon, refreshing...")
                try await refreshAuthToken()
            }

            return true
        } catch {
            print("🔴 Token validation failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Email Verification

    /// Sends email verification to the current user
    func sendEmailVerification() async throws {
        guard let user = currentFirebaseUser else {
            throw NSError(domain: "ComprehensiveAuthManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user signed in"])
        }

        guard !user.isEmailVerified else {
            print("✅ Email already verified")
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            try await user.sendEmailVerification()
            isLoading = false
            print("✅ Verification email sent to: \(user.email ?? "unknown")")
        } catch {
            isLoading = false
            errorMessage = "Failed to send verification email: \(error.localizedDescription)"
            print("🔴 Email verification send error: \(error.localizedDescription)")
            throw error
        }
    }

    /// Checks if current user's email is verified
    var isEmailVerified: Bool {
        currentFirebaseUser?.isEmailVerified ?? false
    }

    /// Reloads user data to check for updated email verification status
    func reloadUser() async throws {
        guard let user = currentFirebaseUser else {
            throw NSError(domain: "ComprehensiveAuthManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user signed in"])
        }

        do {
            try await user.reload()
            // Update our reference to get the latest data
            currentFirebaseUser = Auth.auth().currentUser
            print("✅ User data reloaded - Email verified: \(user.isEmailVerified)")
        } catch {
            print("🔴 Failed to reload user: \(error.localizedDescription)")
            throw error
        }
    }

    private func friendlyErrorMessage(from error: Error) -> String {
        let authError = error as NSError

        switch authError.code {
        case AuthErrorCode.emailAlreadyInUse.rawValue:
            return AuthConstants.ErrorMessages.emailAlreadyInUse
        case AuthErrorCode.weakPassword.rawValue:
            return AuthConstants.ErrorMessages.weakPassword
        case AuthErrorCode.invalidEmail.rawValue:
            return AuthConstants.ErrorMessages.invalidEmail
        case AuthErrorCode.userNotFound.rawValue:
            return AuthConstants.ErrorMessages.userNotFound
        case AuthErrorCode.wrongPassword.rawValue:
            return AuthConstants.ErrorMessages.wrongPassword
        case AuthErrorCode.networkError.rawValue:
            return AuthConstants.ErrorMessages.networkError
        case AuthErrorCode.tooManyRequests.rawValue:
            return AuthConstants.ErrorMessages.tooManyRequests
        case AuthErrorCode.userDisabled.rawValue:
            return AuthConstants.ErrorMessages.userDisabled
        default:
            return error.localizedDescription
        }
    }
}
