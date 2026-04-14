//
//  ComprehensiveAuthManager.swift
//  PlayerPath
//
//  Core class definition: published state, init, deinit, and small helpers.
//  Auth operations → ComprehensiveAuthManager+Auth.swift
//  Profile management → ComprehensiveAuthManager+Profile.swift
//  Tier/subscription sync → ComprehensiveAuthManager+Tier.swift
//

import SwiftUI
import Combine
import FirebaseAuth
import SwiftData
import os

private let authLog = Logger(subsystem: "com.playerpath.app", category: "Auth")

@MainActor
final class ComprehensiveAuthManager: ObservableObject {
    @Published var currentFirebaseUser: FirebaseAuth.User?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var isNewUser: Bool = false // Session-level flag; NOT persisted across launches
    @Published var needsEmailVerification: Bool = false

    // MARK: - Account Lockout
    // Persisted to UserDefaults so a force-quit can't reset the counter and
    // bypass the lockout window.
    var failedSignInAttempts: Int {
        get { UserDefaults.standard.integer(forKey: AuthConstants.UserDefaultsKeys.failedSignInAttempts) }
        set { UserDefaults.standard.set(newValue, forKey: AuthConstants.UserDefaultsKeys.failedSignInAttempts) }
    }
    var signInLockedUntil: Date? {
        get { UserDefaults.standard.object(forKey: AuthConstants.UserDefaultsKeys.signInLockedUntil) as? Date }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: AuthConstants.UserDefaultsKeys.signInLockedUntil)
            } else {
                UserDefaults.standard.removeObject(forKey: AuthConstants.UserDefaultsKeys.signInLockedUntil)
            }
        }
    }
    var isSignInLocked: Bool {
        guard let lockedUntil = signInLockedUntil else { return false }
        return Date() < lockedUntil
    }
    /// Bumped by the lockout ticker so SwiftUI re-evaluates lockoutRemainingSeconds.
    @Published private(set) var lockoutTick: Date = Date()
    var lockoutRemainingSeconds: Int {
        _ = lockoutTick // force re-read on tick
        guard let lockedUntil = signInLockedUntil else { return 0 }
        return max(0, Int(lockedUntil.timeIntervalSinceNow.rounded(.up)))
    }
    var lockoutTimer: Timer?

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
    @Published var isSignedIn: Bool = false

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

    /// True when the user has no meaningful display name set (empty, "User", or nil).
    /// UI should prompt for name entry.
    @Published var needsDisplayName: Bool = false

    var userID: String? {
        currentFirebaseUser?.uid
    }

    // Subscription tier — kept in sync with StoreKitManager via Combine.
    // Can be overridden by Firestore for comped users (see loadUserProfile).
    @Published var currentTier: SubscriptionTier = .free

    /// True after the first loadUserProfile() completes. Prevents the StoreKit
    /// publisher from syncing a "free" tier to Firestore before we've had a chance
    /// to apply any comped tier overrides from the Firestore profile.
    var hasLoadedProfile: Bool = false

    /// Bridge for legacy call sites — true when user has Plus or Pro
    var isPremiumUser: Bool { currentTier >= .plus }

    /// True when user has Pro tier or higher (coach sharing is a Pro feature)
    var hasCoachingAccess: Bool { currentTier >= .pro }

    // Coach subscription tier — synced from StoreKit, overridable by Firestore (Academy)
    @Published var currentCoachTier: CoachSubscriptionTier = .free

    /// Maximum athletes the coach can have based on their tier
    var coachAthleteLimit: Int { currentCoachTier.athleteLimit }

    var authStateDidChangeListenerHandle: AuthStateDidChangeListenerHandle?
    var modelContext: ModelContext?
    var storeKitCancellables = Set<AnyCancellable>()
    /// Separate cancellable set for lifecycle observers (foreground, etc.)
    /// that should survive a StoreKit-only reset.
    var lifecycleCancellables = Set<AnyCancellable>()
    /// True while `signIn()` is in flight. Prevents the auth state listener from
    /// triggering a second `loadUserProfile()` concurrent with the one in `signIn()`.
    var isHandlingSignIn = false
    /// True while `checkEmailVerification()` is in flight. Prevents the listener
    /// from racing with verification (user.reload() can fire the listener).
    var isHandlingVerification = false
    /// Stored Apple credential-revoked observer so we can remove it on deinit.
    var appleCredentialObserver: NSObjectProtocol?

    // MARK: - Coach signup carryover
    /// Pending shared-folder invitations discovered during coach signup.
    /// Surfaced to the coach onboarding flow after email verification.
    @Published var pendingCoachInvitations: [CoachInvitation] = []
    /// True when the verification email could not be sent during signup.
    /// UI should show a "couldn't send — tap Resend" hint when true.
    @Published var verificationEmailSendFailed: Bool = false

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
        // On cold launch, StoreKit tier applies until Firestore loads.
        #if DEBUG
        if hasCompletedOnboarding {
            print("💾 Restored hasCompletedOnboarding from UserDefaults: true")
        }
        #endif

        setupStoreKitSubscribers()
        setupAuthStateListener()
        observeAppleCredentialRevocation()
        setupForegroundTierRefresh()
        // Resume lockout countdown if we relaunched while still locked.
        startLockoutTickerIfNeeded()

        // Profile loading for already signed-in users is handled by the
        // auth state listener above (which fires on init). No need to
        // double-fetch here.
    }

    deinit {
        if let handle = authStateDidChangeListenerHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
        if let obs = appleCredentialObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        lockoutTimer?.invalidate()
    }

    /// Starts (or restarts) a 1Hz timer that bumps `lockoutTick` so any UI
    /// reading `lockoutRemainingSeconds` stays current. No-op when not locked.
    func startLockoutTickerIfNeeded() {
        lockoutTimer?.invalidate()
        guard isSignInLocked else { return }
        lockoutTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] t in
            Task { @MainActor in
                guard let self else { t.invalidate(); return }
                self.lockoutTick = Date()
                if !self.isSignInLocked {
                    t.invalidate()
                    self.lockoutTimer = nil
                }
            }
        }
    }

    func attachModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func markOnboardingComplete() {
        hasCompletedOnboarding = true
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

    /// Removes all user-specific UserDefaults keys. Called from sign-out,
    /// account deletion, and the auth state listener on sign-out.
    func clearPersistedUserDefaults() {
        UserDefaults.standard.removeObject(forKey: AuthConstants.UserDefaultsKeys.userRole)
        UserDefaults.standard.removeObject(forKey: AuthConstants.UserDefaultsKeys.hasCompletedOnboarding)
        UserDefaults.standard.removeObject(forKey: AuthConstants.UserDefaultsKeys.failedSignInAttempts)
        UserDefaults.standard.removeObject(forKey: AuthConstants.UserDefaultsKeys.signInLockedUntil)
        // hasAthleteTierOverride removed — comp detection is now server-side
    }

    // MARK: - Email Verification Grandfathering

    /// Accounts created before this date bypass email verification.
    /// Set to the date this feature shipped — all prior accounts are grandfathered.
    static let emailVerificationCutoff: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 25
        return Calendar.current.date(from: components) ?? Date.distantPast
    }()

    /// Returns true if the user was created before the email verification requirement.
    func isGrandfathered(_ user: FirebaseAuth.User) -> Bool {
        guard let creationDate = user.metadata.creationDate else { return true }
        return creationDate < Self.emailVerificationCutoff
    }

    /// Returns true if the user needs to verify their email before accessing the app.
    /// Apple Sign In users and grandfathered accounts are exempt.
    func requiresEmailVerification(_ user: FirebaseAuth.User) -> Bool {
        // Already verified — no action needed
        if user.isEmailVerified { return false }
        // Grandfathered accounts skip verification
        if isGrandfathered(user) { return false }
        return true
    }

    func friendlyErrorMessage(from error: Error) -> String {
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
        case AuthErrorCode.invalidCredential.rawValue:
            return "Invalid email or password. Please try again."
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
