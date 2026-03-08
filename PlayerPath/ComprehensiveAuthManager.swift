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
            #if DEBUG
            print("💾 Persisted hasCompletedOnboarding to UserDefaults: \(hasCompletedOnboarding)")
            #endif
        }
    }
    
    // Make isSignedIn a @Published property for better UI reactivity
    @Published private(set) var isSignedIn: Bool = false
    
    // User role management (for coach sharing feature)
    @Published var userRole: UserRole = .athlete {
        didSet {
            // Persist role to UserDefaults to survive app state changes
            UserDefaults.standard.set(userRole.rawValue, forKey: AuthConstants.UserDefaultsKeys.userRole)
            #if DEBUG
            print("💾 Persisted userRole to UserDefaults: \(userRole.rawValue)")
            #endif
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
    /// True while `signIn()` is in flight. Prevents the auth state listener from
    /// triggering a second `loadUserProfile()` concurrent with the one in `signIn()`.
    private var isHandlingSignIn = false
    
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
        #if DEBUG
        if hasCompletedOnboarding {
            print("💾 Restored hasCompletedOnboarding from UserDefaults: true")
        }
        #endif

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
                    #if DEBUG
                    print("🔄 Cleared all user data on sign out")
                    #endif
                } else {
                    // User signed in - ensure local user exists
                    await self?.ensureLocalUser()

                    // Only load profile if this isn't a brand new signup or an explicit
                    // signIn() call. signUp/signUpAsCoach handle profile creation themselves,
                    // and signIn() calls loadUserProfile() directly — loading here too would
                    // cause a redundant double-fetch.
                    if self?.isNewUser == false && self?.isHandlingSignIn == false {
                        #if DEBUG
                        print("🔍 Auth state changed - Loading profile for existing user")
                        #endif
                        await self?.loadUserProfile()
                    } else {
                        #if DEBUG
                        print("⏭️ Auth state changed - Skipping profile load (handled by signIn/signUp)")
                        #endif
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
                    #if DEBUG
                    print("🔄 Synced user role to SwiftData: \(self.userRole.rawValue)")
                    #endif
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
                self.localUser = existingUser
            } else {
                // Create new user with current role from authManager
                let newUser = User(username: firebaseUser.displayName ?? email, email: email, role: self.userRole.rawValue)
                newUser.firebaseAuthUid = firebaseUser.uid
                context.insert(newUser)
                try context.save()
                #if DEBUG
                print("✅ Created new SwiftData user with role: \(self.userRole.rawValue), Firebase UID: \(firebaseUser.uid)")
                #endif
                self.localUser = newUser
            }
        } catch {
            self.errorMessage = "Failed to load user profile"
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

    /// Restores sign-in state from an existing Firebase session without requiring credentials.
    /// Used by session-based biometric sign-in: biometric proves identity, Firebase token proves session.
    func restoreFirebaseSession() async {
        guard let user = Auth.auth().currentUser else {
            errorMessage = "Your session has expired. Please sign in with your password."
            return
        }
        isLoading = true
        errorMessage = nil
        currentFirebaseUser = user
        isSignedIn = true
        await loadUserProfile()
        isLoading = false
    }

    func signIn(email: String, password: String) async {
        isHandlingSignIn = true
        defer { isHandlingSignIn = false }
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
        #if DEBUG
        print("✅ Pre-set userRole to athlete BEFORE Firebase operations")
        #endif
        
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
                #if DEBUG
                print("⚠️ WARNING: userRole was changed after createUserProfile, resetting to athlete")
                #endif
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
    /// - Parameter loadAfterCreate: When true (default), fetches the profile from Firestore
    ///   after writing it. Pass false when called from within `loadUserProfileWithRetry` to
    ///   prevent the recursive loop: retry → fallback create → retry → fallback create.
    func createUserProfile(
        userID: String,
        email: String,
        displayName: String,
        role: UserRole,
        loadAfterCreate: Bool = true
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
            #if DEBUG
            print("⚠️ WARNING: Local userRole (\(self.userRole.rawValue)) doesn't match Firestore role (\(role.rawValue))")
            print("✅ Corrected userRole in memory to: \(role.rawValue)")
            #endif
            self.userRole = role
        } else {
            #if DEBUG
            print("✅ Verified userRole in memory matches Firestore: \(role.rawValue)")
            #endif
        }

        // Fetch and cache the profile with retry logic to handle Firestore propagation.
        // Skipped when called from the fallback path inside loadUserProfileWithRetry to
        // prevent mutual recursion (retry → create → retry → create).
        if loadAfterCreate {
            await loadUserProfileWithRetry(maxAttempts: 5)
        }
    }
    
    /// Loads user profile from Firestore
    func loadUserProfile() async {
        guard let userID = currentFirebaseUser?.uid,
              let email = currentFirebaseUser?.email else {
            #if DEBUG
            print("⚠️ loadUserProfile: No user ID or email")
            #endif
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
                    #if DEBUG
                    print("✅ Academy coach tier applied from Firestore override")
                    #endif
                }

                // Only update userRole if it's different AND this is not a new user
                // For new users, we want to keep the role we set synchronously at signup
                if isNewUser {
                    // New user: Keep the role we set at signup, but verify it matches Firestore
                    #if DEBUG
                    if profile.userRole != currentRole {
                        print("⚠️ WARNING: Firestore role (\(profile.userRole.rawValue)) doesn't match pre-set role (\(currentRole.rawValue)) for new user")
                        print("⚠️ Keeping pre-set role: \(currentRole.rawValue)")
                    } else {
                        print("✅ Firestore role matches pre-set role: \(currentRole.rawValue)")
                    }
                    #endif
                    // Keep the pre-set role, don't override
                } else {
                    // Existing user: Update role from Firestore
                    userRole = profile.userRole
                    #if DEBUG
                    print("✅ Updated role from Firestore for existing user: \(profile.userRole.rawValue)")
                    #endif
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
            #if DEBUG
            print("⚠️ loadUserProfileWithRetry: No user ID or email")
            #endif
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
                        #if DEBUG
                        if profile.userRole != currentRole {
                            print("⚠️ WARNING: Firestore role (\(profile.userRole.rawValue)) doesn't match pre-set role (\(currentRole.rawValue)) for new user")
                            print("⚠️ Keeping pre-set role: \(currentRole.rawValue)")
                        } else {
                            print("✅ Firestore role matches pre-set role: \(currentRole.rawValue)")
                        }
                        #endif
                    } else {
                        userRole = profile.userRole
                        #if DEBUG
                        print("✅ Updated role from Firestore for existing user: \(profile.userRole.rawValue)")
                        #endif
                    }

                    #if DEBUG
                    print("✅ Loaded user profile on attempt \(attempt): \(profile.role) for \(email)")
                    #endif
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

                    // Create profile with current role (from UserDefaults/SwiftData).
                    // loadAfterCreate: false prevents re-entering this retry loop.
                    do {
                        try await createUserProfile(
                            userID: userID,
                            email: email,
                            displayName: self.currentFirebaseUser?.displayName ?? email,
                            role: self.userRole,
                            loadAfterCreate: false
                        )
                        #if DEBUG
                        print("✅ Successfully created fallback Firestore profile")
                        #endif
                    } catch {
                        #if DEBUG
                        print("❌ Failed to create fallback profile: \(error)")
                        #endif
                    }
                    return
                }
            } catch {
                if attempt < maxAttempts {
                    let delay = pow(2.0, Double(attempt - 1)) * 0.1
                    #if DEBUG
                    print("❌ Error loading profile on attempt \(attempt)/\(maxAttempts): \(error). Retrying in \(delay)s...")
                    #endif
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } else {
                    #if DEBUG
                    print("❌ Failed to load user profile after \(maxAttempts) attempts: \(error)")
                    print("🔧 Creating fallback Firestore profile with current role: \(self.userRole.rawValue)")
                    #endif

                    // Create profile with current role as fallback.
                    // loadAfterCreate: false prevents re-entering this retry loop.
                    do {
                        try await createUserProfile(
                            userID: userID,
                            email: email,
                            displayName: self.currentFirebaseUser?.displayName ?? email,
                            role: self.userRole,
                            loadAfterCreate: false
                        )
                        #if DEBUG
                        print("✅ Successfully created fallback Firestore profile after errors")
                        #endif
                    } catch {
                        #if DEBUG
                        print("❌ Failed to create fallback profile: \(error)")
                        #endif
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
        #if DEBUG
        print("✅ Pre-set userRole to coach BEFORE Firebase operations")
        #endif
        
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
                #if DEBUG
                print("⚠️ WARNING: userRole was changed after createUserProfile, resetting to coach")
                #endif
                userRole = .coach
            }
            
            // Check for pending invitations
            let invitations = try await SharedFolderManager.shared.checkPendingInvitations(forEmail: email)
            #if DEBUG
            if !invitations.isEmpty {
                print("✅ Found \(invitations.count) pending invitations for new coach")
            }
            #endif
            
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

            // Remove this device's push token before signing out so it stops
            // receiving notifications for this account on this device.
            await PushNotificationService.shared.removeTokenFromServer()

            try Auth.auth().signOut()
            currentFirebaseUser = nil
            isSignedIn = false
            isLoading = false
            isNewUser = false
            errorMessage = nil
            userRole = .athlete // Reset to default
            UserDefaults.standard.removeObject(forKey: "LastSelectedTab")

            // Clear user-specific published state immediately (auth listener also does this
            // async, but clearing here eliminates any race window between accounts)
            userProfile = nil
            localUser = nil
            currentTier = .free
            currentCoachTier = .free

            // Clear persisted role and onboarding completion (both in memory and UserDefaults).
            // Don't wait for the auth listener — it fires asynchronously and leaves a race window.
            hasCompletedOnboarding = false
            UserDefaults.standard.removeObject(forKey: AuthConstants.UserDefaultsKeys.userRole)
            UserDefaults.standard.removeObject(forKey: AuthConstants.UserDefaultsKeys.hasCompletedOnboarding)

            // Stop active Firestore listeners and background sync for this user
            ActivityNotificationService.shared.stopListening()
            SyncCoordinator.shared.stopPeriodicSync()

            // Clear biometric credentials on logout for security
            BiometricAuthenticationManager.shared.disableBiometric()

            // Clear signed URL cache so another user can't access previous user's URLs
            SecureURLManager.shared.clearCache()

            // Clear upload queues to prevent cross-account data leakage
            UploadQueueManager.shared.clearAllQueues()

            #if DEBUG
            print("🟢 Sign out successful")
            #endif
        } catch {
            errorMessage = "Failed to sign out: \(error.localizedDescription)"
            isLoading = false
            #if DEBUG
            print("🔴 Sign out error: \(error.localizedDescription)")
            #endif
        }
    }
    
    func resetPassword(email: String) async throws {
        isLoading = true
        defer { isLoading = false }

        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
            #if DEBUG
            print("🟢 Password reset sent to: \(email)")
            #endif
        } catch {
            #if DEBUG
            print("🔴 Password reset error: \(error.localizedDescription)")
            #endif
            throw AppError.authenticationFailed(friendlyErrorMessage(from: error))
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
            #if DEBUG
            print("🗑️ Deleting user videos from Storage...")
            #endif
            do {
                try await VideoCloudManager.shared.deleteAllUserVideos(userID: userID)
                #if DEBUG
                print("✅ Deleted all videos from Storage")
                #endif
            } catch {
                #if DEBUG
                print("⚠️ Error deleting videos from Storage: \(error)")
                #endif
                // Continue with deletion even if video deletion fails
            }

            // Step 2: Delete Firestore user profile and related data
            #if DEBUG
            print("🗑️ Deleting user profile from Firestore...")
            #endif
            do {
                try await FirestoreManager.shared.deleteUserProfile(userID: userID)
                #if DEBUG
                print("✅ Deleted user profile from Firestore")
                #endif
            } catch {
                #if DEBUG
                print("⚠️ Error deleting Firestore profile: \(error)")
                #endif
                // Continue with deletion even if Firestore deletion fails
            }

            // Step 3: Clear biometric credentials
            BiometricAuthenticationManager.shared.disableBiometric()

            // Step 4: Delete Firebase Auth account
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

            #if DEBUG
            print("✅ Account deletion successful")
            #endif

        } catch {
            errorMessage = "Failed to delete account: \(error.localizedDescription)"
            isLoading = false
            #if DEBUG
            print("🔴 Account deletion error: \(error.localizedDescription)")
            #endif
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
        #if DEBUG
        print("✅ Onboarding marked as completed")
        #endif
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
