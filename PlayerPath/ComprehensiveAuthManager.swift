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
    
    // Subscription tier — kept in sync with StoreKitManager via Combine
    @Published var currentTier: SubscriptionTier = .free

    /// Bridge for legacy call sites — true when user has Plus or Pro
    var isPremiumUser: Bool { currentTier >= .plus }

    /// True when user has Pro tier (coach sharing is a Pro feature)
    var hasCoachingAccess: Bool { currentTier == .pro }

    // Coach subscription tier — synced from StoreKit, overridable by Firestore (Academy)
    @Published var currentCoachTier: CoachSubscriptionTier = .free

    /// Maximum athletes the coach can have based on their tier
    var coachAthleteLimit: Int { currentCoachTier.athleteLimit }

    private var authStateDidChangeListenerHandle: AuthStateDidChangeListenerHandle?
    private var modelContext: ModelContext?
    private var storeKitCancellables = Set<AnyCancellable>()
    
    init() {
        currentFirebaseUser = Auth.auth().currentUser
        isSignedIn = currentFirebaseUser != nil

        // Restore persisted role from UserDefaults for initial UI routing only.
        // This is a display hint to prevent flicker on launch — it is NOT authoritative.
        // The real role is always loaded from Firestore in loadUserProfile() and
        // overwrites this value. Never use userRole for security decisions client-side;
        // security enforcement is handled by Firebase Security Rules server-side.
        if let persistedRoleString = UserDefaults.standard.string(forKey: AuthConstants.UserDefaultsKeys.userRole),
           let persistedRole = UserRole(rawValue: persistedRoleString) {
            userRole = persistedRole
            #if DEBUG
            print("💾 Restored userRole from UserDefaults: \(persistedRole.rawValue)")
            #endif
        }

        // Restore persisted onboarding completion from UserDefaults
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: AuthConstants.UserDefaultsKeys.hasCompletedOnboarding)
        if hasCompletedOnboarding {
            print("💾 Restored hasCompletedOnboarding from UserDefaults: true")
        }

        // Keep athlete tier in sync with StoreKitManager
        StoreKitManager.shared.$currentTier
            .receive(on: RunLoop.main)
            .sink { [weak self] tier in
                self?.currentTier = tier
                self?.syncSubscriptionTierToFirestore()
            }
            .store(in: &storeKitCancellables)

        // Keep coach tier in sync with StoreKitManager (Academy override happens in loadUserProfile)
        StoreKitManager.shared.$currentCoachTier
            .receive(on: RunLoop.main)
            .sink { [weak self] tier in
                self?.currentCoachTier = tier
                self?.syncSubscriptionTierToFirestore()
            }
            .store(in: &storeKitCancellables)

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
                    self?.currentTier = .free
                    self?.currentCoachTier = .free
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
                    #if DEBUG
                    print("🔄 Stored Firebase Auth UID: \(firebaseUser.uid)")
                    #endif
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
                #if DEBUG
                print("✅ Created new SwiftData user with role: \(self.userRole.rawValue), Firebase UID: \(firebaseUser.uid)")
                #endif
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
    
    private func syncSubscriptionTierToFirestore() {
        guard let userID = currentFirebaseUser?.uid else { return }
        let tier = currentTier
        let coachTier = currentCoachTier
        Task {
            await FirestoreManager.shared.syncSubscriptionTiers(
                userID: userID, tier: tier, coachTier: coachTier
            )
        }
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
            #if DEBUG
            print("🟢 Sign in successful for: \(result.user.email ?? "unknown") as \(userRole.rawValue)")
            #endif
        } catch {
            errorMessage = friendlyErrorMessage(from: error)
            isLoading = false
            #if DEBUG
            print("🔴 Sign in error: \(error.localizedDescription)")
            #endif
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
            
            #if DEBUG
            print("🔵 Creating athlete profile for: \(email)")
            #endif
            
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
            #if DEBUG
            print("🟢 Sign up successful for athlete: \(result.user.email ?? "unknown") with role: \(userRole.rawValue)")
            #endif
        } catch {
            errorMessage = friendlyErrorMessage(from: error)
            isLoading = false
            isNewUser = false
            #if DEBUG
            print("🔴 Sign up error: \(error.localizedDescription)")
            #endif
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
            "subscriptionTier": "free",
            "createdAt": Date(),
            "displayName": displayName
        ]
        
        #if DEBUG
        print("🔵 Creating user profile in Firestore - Role: \(role.rawValue), Email: \(email)")
        #endif
        
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
        
        #if DEBUG
        print("🔍 loadUserProfile: Fetching profile for user \(email)")
        #endif
        
        do {
            if let profile = try await FirestoreManager.shared.fetchUserProfile(userID: userID) {
                // Store the current role before updating from Firestore
                let currentRole = self.userRole
                
                // Update profile and role from Firestore
                userProfile = profile
                syncSubscriptionTierToFirestore()

                // Academy coach tier is manually granted via Firestore — override StoreKit resolution
                if profile.coachSubscriptionTier == CoachSubscriptionTier.academy.rawValue {
                    currentCoachTier = .academy
                    print("✅ Academy coach tier applied from Firestore override")
                }

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
                
                #if DEBUG
                print("✅ Loaded user profile: \(profile.role) for \(email)")
                #endif
            } else {
                // Profile doesn't exist - only create if this is NOT a new user
                // (new users should have had their profile created in signUp/signUpAsCoach)
                if !isNewUser {
                    #if DEBUG
                    print("⚠️ Profile doesn't exist for existing user \(email), creating default athlete profile")
                    #endif
                    try await createUserProfile(
                        userID: userID,
                        email: email,
                        displayName: currentFirebaseUser?.displayName ?? email,
                        role: .athlete
                    )
                    syncSubscriptionTierToFirestore()
                } else {
                    #if DEBUG
                    print("⚠️ Profile not found for new user \(email), but keeping existing role: \(userRole.rawValue)")
                    #endif
                }
            }
        } catch {
            #if DEBUG
            print("❌ Failed to load user profile for \(email): \(error)")
            #endif
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
                    // Profile not found yet, retry with exponential backoff.
                    // Use try? so task cancellation (e.g. from SignInView.onDisappear) does NOT
                    // propagate a CancellationError up through signUpAsCoach's catch block,
                    // which would incorrectly reset isNewUser/userRole for a successfully-created account.
                    let delay = pow(2.0, Double(attempt - 1)) * 0.1 // 0.1s, 0.2s, 0.4s, 0.8s, 1.6s
                    #if DEBUG
                    print("⏳ Profile not found for \(email) on attempt \(attempt)/\(maxAttempts), retrying in \(delay)s...")
                    #endif
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } else {
                    // Last attempt and still not found - create profile as fallback
                    #if DEBUG
                    print("⚠️ Profile not found for \(email) after \(maxAttempts) attempts")
                    print("🔧 Creating fallback Firestore profile with current role: \(self.userRole.rawValue)")
                    #endif

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
            
            #if DEBUG
            print("🔵 Creating coach profile for: \(email)")
            #endif
            
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
            #if DEBUG
            print("🟢 Coach sign up successful for: \(email) with role: \(userRole.rawValue)")
            #endif
        } catch {
            isLoading = false
            // Only reset isNewUser/userRole if the Firebase account was never created.
            // If the account was created (isSignedIn = true) but a later step failed
            // (e.g. Firestore profile write, task cancellation from SignInView.onDisappear),
            // keep isNewUser = true so the coach still sees the onboarding flow.
            // Any missing Firestore profile will be re-created on the next loadUserProfile() call.
            if isSignedIn {
                #if DEBUG
                print("🟡 Coach sign up: post-auth step failed but account exists — preserving onboarding state")
                print("🟡 Error: \(error.localizedDescription)")
                #endif
            } else {
                isNewUser = false
                userRole = .athlete
                errorMessage = friendlyErrorMessage(from: error)
                #if DEBUG
                print("🔴 Coach sign up error: \(error.localizedDescription)")
                #endif
            }
        }
    }
    
    func updateDisplayName(_ name: String) async throws {
        guard let user = currentFirebaseUser else {
            throw NSError(domain: "ComprehensiveAuthManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user signed in"])
        }
        // Update Firebase Auth profile
        let changeRequest = user.createProfileChangeRequest()
        changeRequest.displayName = name
        try await changeRequest.commitChanges()
        // Reload so currentFirebaseUser reflects the new displayName immediately
        try await user.reload()
        currentFirebaseUser = Auth.auth().currentUser
        // Persist display name to Firestore
        try await FirestoreManager.shared.updateUserProfile(
            userID: user.uid,
            email: user.email ?? userEmail ?? "",
            role: userRole,
            profileData: ["displayName": name]
        )
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

            // Clear signed URL cache so another user can't access previous user's URLs
            SecureURLManager.shared.clearCache()

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
            #if DEBUG
            print("🟢 Password reset sent to: \(email)")
            #endif
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

            #if DEBUG
            print("🗑️ Starting account deletion for user: \(user.email ?? "unknown")")
            #endif

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

    // Method to allow external sign-in managers (like Apple Sign In) to update the user
    func updateCurrentUser(_ user: FirebaseAuth.User, isNewUser: Bool = false, role: UserRole? = nil) {
        currentFirebaseUser = user
        isSignedIn = true
        self.isNewUser = isNewUser
        if let role = role {
            userRole = role
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
            #if DEBUG
            return error.localizedDescription
            #else
            return "Something went wrong. Please try again."
            #endif
        }
    }
}
