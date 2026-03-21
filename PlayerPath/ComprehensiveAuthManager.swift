import SwiftUI
import Combine
import FirebaseAuth
import SwiftData
import os

private let authLog = Logger(subsystem: "com.playerpath.app", category: "Auth")

@MainActor
final class ComprehensiveAuthManager: ObservableObject {
    @Published private(set) var currentFirebaseUser: FirebaseAuth.User?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var isNewUser: Bool = false // Session-level flag; NOT persisted across launches
    
    @Published var localUser: User?
    @Published var hasCompletedOnboarding: Bool = false {
        didSet {
            guard oldValue != hasCompletedOnboarding else { return }
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
            guard oldValue != userRole else { return }
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
    
    // Subscription tier — kept in sync with StoreKitManager via Combine.
    // Can be overridden by Firestore for comped users (see loadUserProfile).
    @Published var currentTier: SubscriptionTier = .free

    /// True when the athlete tier was manually granted via Firestore (not StoreKit).
    /// Used to prevent syncSubscriptionTiers from overwriting the comped value.
    /// NOT persisted to UserDefaults (security: tamper-resistant). Re-derived from
    /// Firestore profile on every app launch via loadUserProfile().
    private(set) var hasAthleteTierOverride: Bool = false

    /// True after the first loadUserProfile() completes. Prevents the StoreKit
    /// publisher from syncing a "free" tier to Firestore before we've had a chance
    /// to apply any comped tier overrides from the Firestore profile.
    private var hasLoadedProfile: Bool = false

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

        // Do NOT set isSignedIn here. Even if a Firebase session exists,
        // the auth state listener will set isSignedIn = true AFTER loading
        // the user's profile from Firestore. This prevents the UI from
        // rendering with a stale or default role (e.g. after a reinstall
        // where UserDefaults is wiped but the Firebase keychain token survives).

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
        // isNewUser is NOT restored from UserDefaults. It is a session-level flag
        // that prevents the auth state listener from racing with signUp() during
        // the same session. Persisting it is dangerous: if the app is killed during
        // signup, a stale true value permanently prevents loadUserProfile() from
        // running on subsequent launches, leaving the user with a default .athlete role.
        // hasAthleteTierOverride is NOT restored from UserDefaults (security).
        // It will be re-derived from Firestore profile in loadUserProfile().
        // On cold launch, StoreKit tier applies until Firestore loads.
        #if DEBUG
        if hasCompletedOnboarding {
            print("💾 Restored hasCompletedOnboarding from UserDefaults: true")
        }
        // hasAthleteTierOverride is no longer persisted — derived from Firestore on load
        #endif

        // Keep athlete tier in sync with StoreKitManager.
        // If Firestore granted a comped tier (hasAthleteTierOverride), only accept
        // StoreKit updates that are equal or higher — don't downgrade a comp.
        StoreKitManager.shared.$currentTier
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] tier in
                guard let self else { return }
                if self.hasAthleteTierOverride && tier < self.currentTier {
                    // StoreKit resolved lower than the Firestore comp — keep the comp
                    #if DEBUG
                    print("⏭️ StoreKit tier \(tier.rawValue) lower than comped tier \(self.currentTier.rawValue) — keeping comp")
                    #endif
                } else {
                    let hadOverride = self.hasAthleteTierOverride
                    self.currentTier = tier
                    // If StoreKit now meets or exceeds the comped tier, clear the override
                    if hadOverride { self.hasAthleteTierOverride = false }
                }
                // Don't sync until profile has loaded — otherwise a "free" StoreKit
                // tier overwrites a Firestore-comped "pro" before the override is applied.
                guard self.hasLoadedProfile else { return }
                self.syncSubscriptionTierToFirestore()
                // Keep SwiftData User model in sync so user.tier doesn't go stale
                // (e.g. subscription expires while app is backgrounded)
                self.syncTierToLocalUser(self.currentTier)
            }
            .store(in: &storeKitCancellables)

        // Keep coach tier in sync with StoreKitManager (Academy override happens in loadUserProfile)
        StoreKitManager.shared.$currentCoachTier
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] tier in
                guard let self else { return }
                self.currentCoachTier = tier
                guard self.hasLoadedProfile else { return }
                self.syncSubscriptionTierToFirestore()
            }
            .store(in: &storeKitCancellables)

        authStateDidChangeListenerHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            // ✅ Consolidated into a single MainActor Task to prevent race conditions
            Task { @MainActor in
                self?.currentFirebaseUser = user

                // Reset new user flag when auth state changes (unless it's a signup)
                if user == nil {
                    self?.isSignedIn = false
                    // Clear ALL user-specific data to prevent leakage between accounts
                    self?.isNewUser = false
                    self?.userRole = .athlete
                    self?.userProfile = nil
                    self?.localUser = nil
                    self?.hasCompletedOnboarding = false
                    self?.currentTier = .free
                    self?.currentCoachTier = .free
                    self?.hasAthleteTierOverride = false
                    self?.clearPersistedUserDefaults()
                    #if DEBUG
                    print("🔄 Cleared all user data on sign out")
                    #endif
                } else if self?.isHandlingSignIn == true {
                    // signIn() is in progress — it will set isSignedIn after
                    // loadUserProfile() completes so the UI sees the correct role.
                    #if DEBUG
                    print("⏭️ Auth state changed - Skipping (handled by signIn())")
                    #endif
                } else {
                    // User signed in via Apple Sign In or app relaunch —
                    // load profile BEFORE setting isSignedIn so the UI
                    // routes to the correct role (athlete vs coach).

                    // Only load profile if this isn't a brand new signup.
                    // signUp/signUpAsCoach handle profile creation themselves.
                    if self?.isNewUser == false {
                        #if DEBUG
                        print("🔍 Auth state changed - Loading profile for existing user")
                        #endif
                        // Use retry logic for the listener path (app relaunch, Apple Sign In).
                        // A single-shot loadUserProfile() silently swallows errors, leaving
                        // the role as the stale default. Retry with backoff gives Firestore
                        // time to establish a connection after a cold launch.
                        await self?.loadUserProfileWithRetry(maxAttempts: 3)
                    } else {
                        #if DEBUG
                        print("⏭️ Auth state changed - Skipping profile load (new user signup)")
                        #endif
                    }

                    // Sync local SwiftData user AFTER profile load so
                    // the correct role is written (not the stale default).
                    await self?.ensureLocalUser()

                    self?.isSignedIn = true

                    // Defensive check: Firestore invitation rules compare
                    // request.auth.token.email against stored (lowercased) emails.
                    // If Firebase Auth preserves mixed-case (e.g. Apple Sign In),
                    // invitation reads will fail with permission denied.
                    if let email = user?.email, email != email.lowercased() {
                        authLog.warning("Firebase Auth email is not lowercase: \(email) — invitation queries may fail for this user")
                    }
                }
            }
        }
        
        // Profile loading for already signed-in users is handled by the
        // auth state listener above (which fires on init). No need to
        // double-fetch here.
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
    
    /// Keeps the SwiftData User.subscriptionTier in sync with the live StoreKit tier.
    /// Without this, the SwiftData field only updates at purchase time in the paywall
    /// and becomes stale when a subscription expires or renews in the background.
    private func syncTierToLocalUser(_ tier: SubscriptionTier) {
        guard let localUser, localUser.subscriptionTier != tier.rawValue else { return }
        localUser.subscriptionTier = tier.rawValue
        do {
            try modelContext?.save()
        } catch {
            authLog.error("Failed to sync subscription tier to SwiftData: \(error.localizedDescription)")
        }
        #if DEBUG
        print("🔄 Synced SwiftData User.subscriptionTier to \(tier.rawValue)")
        #endif
    }

    private func syncSubscriptionTierToFirestore() {
        guard let userID = currentFirebaseUser?.uid else { return }
        let tier = currentTier
        let coachTier = currentCoachTier
        let hasOverride = hasAthleteTierOverride
        Task {
            await retryAsync(maxAttempts: 3) {
                try await FirestoreManager.shared.syncSubscriptionTiersWithThrow(
                    userID: userID, tier: tier, coachTier: coachTier,
                    hasAthleteTierOverride: hasOverride
                )
            }
        }
    }

    /// Refreshes the subscription tier from Firestore to pick up changes
    /// made on other devices or via Cloud Function. Only upgrades — never
    /// downgrades from a locally-resolved StoreKit tier.
    func refreshTierFromFirestore() async {
        guard let userID = currentFirebaseUser?.uid else { return }
        do {
            guard let profile = try await FirestoreManager.shared.fetchUserProfile(userID: userID) else { return }
            if let tierStr = profile.subscriptionTier,
               let firestoreTier = SubscriptionTier(rawValue: tierStr),
               firestoreTier > currentTier {
                currentTier = firestoreTier
                hasAthleteTierOverride = true
            }
            if let coachTierStr = profile.coachSubscriptionTier,
               let firestoreCoachTier = CoachSubscriptionTier(rawValue: coachTierStr),
               firestoreCoachTier > currentCoachTier {
                currentCoachTier = firestoreCoachTier
            }
        } catch {
            authLog.warning("Failed to refresh tier from Firestore: \(error.localizedDescription)")
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
        await loadUserProfile()
        isSignedIn = true
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

            // Load user profile from Firestore BEFORE setting isSignedIn,
            // so userRole is resolved before the UI transitions to AuthenticatedFlow.
            await loadUserProfile()

            isSignedIn = true

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
            authLog.error("Sign in failed: \(error.localizedDescription)")
            ErrorHandlerService.shared.handle(error, context: "Auth.signIn", showAlert: false)
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
            authLog.error("Sign up failed: \(error.localizedDescription)")
            ErrorHandlerService.shared.handle(error, context: "Auth.signUp", showAlert: false)
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
        var profileData: [String: Any] = [
            "email": email.lowercased(),
            "role": role.rawValue,
            "subscriptionTier": "free",
            "createdAt": Date(),
            "displayName": displayName
        ]
        if role == .coach {
            profileData["coachSubscriptionTier"] = "coach_free"
        }
        
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

                // Apply Firestore tier overrides BEFORE syncing back to Firestore,
                // so comped tiers aren't overwritten by lower StoreKit values.

                // Academy coach tier is manually granted via Firestore — override StoreKit resolution
                if profile.coachSubscriptionTier == CoachSubscriptionTier.academy.rawValue {
                    currentCoachTier = .academy
                    #if DEBUG
                    print("✅ Academy coach tier applied from Firestore override")
                    #endif
                }

                // Athlete tier can be comped via Firestore — if Firestore holds a higher
                // tier than StoreKit resolved, treat it as a manual grant and override.
                // This mirrors the coach Academy pattern for athlete tiers.
                if profile.tier > currentTier {
                    currentTier = profile.tier
                    hasAthleteTierOverride = true
                    #if DEBUG
                    print("✅ Comped athlete tier applied from Firestore override: \(profile.tier.displayName)")
                    #endif
                } else {
                    hasAthleteTierOverride = false
                }

                hasLoadedProfile = true
                syncSubscriptionTierToFirestore()

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
                    // Use the current in-memory role (restored from UserDefaults)
                    // rather than hardcoding .athlete. If the user was a coach,
                    // the UserDefaults cache preserves that from the last successful
                    // profile load. This prevents overwriting a coach's Firestore
                    // doc with "athlete" if the profile transiently isn't found.
                    let fallbackRole = self.userRole
                    #if DEBUG
                    print("⚠️ Profile doesn't exist for existing user \(email), creating profile with role: \(fallbackRole.rawValue)")
                    #endif
                    try await createUserProfile(
                        userID: userID,
                        email: email,
                        displayName: currentFirebaseUser?.displayName ?? email,
                        role: fallbackRole
                    )
                    syncSubscriptionTierToFirestore()
                } else {
                    #if DEBUG
                    print("⚠️ Profile not found for new user \(email), but keeping existing role: \(userRole.rawValue)")
                    #endif
                }
            }
        } catch {
            authLog.error("Failed to load user profile for \(email): \(error.localizedDescription)")
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
                        authLog.error("Failed to create fallback profile: \(error.localizedDescription)")
                    }
                    return
                }
            } catch {
                if attempt < maxAttempts {
                    let delay = pow(2.0, Double(attempt - 1)) * 0.1
                    authLog.warning("Profile load attempt \(attempt)/\(maxAttempts) failed: \(error.localizedDescription). Retrying in \(delay)s...")
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } else {
                    authLog.error("Failed to load user profile after \(maxAttempts) attempts: \(error.localizedDescription)")

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
                        authLog.error("Failed to create fallback profile: \(error.localizedDescription)")
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
                authLog.warning("Coach sign up: post-auth step failed but account exists — preserving onboarding state: \(error.localizedDescription)")
            } else {
                isNewUser = false
                userRole = .athlete
                errorMessage = friendlyErrorMessage(from: error)
                authLog.error("Coach sign up failed: \(error.localizedDescription)")
                ErrorHandlerService.shared.handle(error, context: "Auth.coachSignUp", showAlert: false)
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

    /// Removes all user-specific UserDefaults keys. Called from sign-out,
    /// account deletion, and the auth state listener on sign-out.
    private func clearPersistedUserDefaults() {
        UserDefaults.standard.removeObject(forKey: AuthConstants.UserDefaultsKeys.userRole)
        UserDefaults.standard.removeObject(forKey: AuthConstants.UserDefaultsKeys.hasCompletedOnboarding)
        UserDefaults.standard.removeObject(forKey: AuthConstants.UserDefaultsKeys.hasAthleteTierOverride)
    }

    func signOut() async {
        isLoading = true
        defer { isLoading = false }
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
            isNewUser = false
            errorMessage = nil
            userRole = .athlete // Reset to default

            // Clear user-specific published state immediately (auth listener also does this
            // async, but clearing here eliminates any race window between accounts)
            userProfile = nil
            localUser = nil
            currentTier = .free
            currentCoachTier = .free
            hasAthleteTierOverride = false
            hasLoadedProfile = false

            // Clear persisted role and onboarding completion (both in memory and UserDefaults).
            // Don't wait for the auth listener — it fires asynchronously and leaves a race window.
            hasCompletedOnboarding = false
            clearPersistedUserDefaults()

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
            authLog.error("Sign out failed: \(error.localizedDescription)")
            ErrorHandlerService.shared.handle(error, context: "Auth.signOut", showAlert: false)
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
            authLog.error("Password reset failed: \(error.localizedDescription)")
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
        guard ConnectivityMonitor.shared.isConnected else {
            throw NSError(domain: "ComprehensiveAuthManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Account deletion requires an internet connection. Please connect and try again."])
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
                authLog.warning("Error deleting videos from Storage during account deletion: \(error.localizedDescription)")
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
                authLog.warning("Error deleting Firestore profile during account deletion: \(error.localizedDescription)")
                // Continue with deletion even if Firestore deletion fails
            }

            // Step 3: Clear biometric credentials
            BiometricAuthenticationManager.shared.disableBiometric()

            // Step 4: Clear local SwiftData records (before Firebase Auth deletion
            // so data isn't orphaned if the app crashes after auth deletion)
            if let context = modelContext, let localUser = localUser {
                // Deep-delete all athletes and their children (videos, games, photos, etc.)
                for athlete in localUser.athletes ?? [] {
                    athlete.delete(in: context)
                }
                context.delete(localUser)
                ErrorHandlerService.shared.saveContext(context, caller: "AuthManager.deleteAccount")
            }

            // Step 5: Delete Firebase Auth account
            try await user.delete()

            // Step 6: Clear local state
            currentFirebaseUser = nil
            isSignedIn = false
            userProfile = nil
            localUser = nil
            isLoading = false
            isNewUser = false
            userRole = .athlete

            // Clear all persisted user data from UserDefaults
            clearPersistedUserDefaults()

            // Track account deletion completion
            AnalyticsService.shared.trackAccountDeletionCompleted(userID: userID)
            AnalyticsService.shared.clearUserID()

            #if DEBUG
            print("✅ Account deletion successful")
            #endif

        } catch {
            errorMessage = "Failed to delete account: \(error.localizedDescription)"
            isLoading = false
            authLog.error("Account deletion failed: \(error.localizedDescription)")
            ErrorHandlerService.shared.handle(error, context: "Auth.deleteAccount", showAlert: false)
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

    // Method to allow external sign-in managers (like Apple Sign In) to update the user.
    // For new users the role is known from the sign-up picker, so we set isSignedIn immediately.
    // For returning users the role must be loaded from Firestore first — the auth state
    // listener will set isSignedIn after loadUserProfile() completes.
    func updateCurrentUser(_ user: FirebaseAuth.User, isNewUser: Bool = false, role: UserRole? = nil) {
        currentFirebaseUser = user
        self.isNewUser = isNewUser
        if let role = role {
            userRole = role
        }
        // Only set isSignedIn immediately for new users (role is already known).
        // Returning users need the auth state listener to load their profile first.
        if isNewUser {
            isSignedIn = true
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
