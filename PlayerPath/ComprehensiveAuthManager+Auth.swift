//
//  ComprehensiveAuthManager+Auth.swift
//  PlayerPath
//
//  Sign in, sign up, sign out, password reset, session restore, and auth state listener.
//

import AuthenticationServices
import FirebaseAuth
import os

private let authLog = Logger(subsystem: "com.playerpath.app", category: "Auth")

extension ComprehensiveAuthManager {

    /// Signs the user out when Apple ID credentials are revoked
    /// (Settings → Password & Security → Apps Using Apple ID).
    func observeAppleCredentialRevocation() {
        NotificationCenter.default.addObserver(
            forName: ASAuthorizationAppleIDProvider.credentialRevokedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            authLog.warning("Apple ID credential revoked — signing user out")
            Task { @MainActor in
                await self?.signOut()
            }
        }
    }

    /// Sets up the Firebase auth state change listener.
    func setupAuthStateListener() {
        authStateDidChangeListenerHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            // Consolidated into a single MainActor Task to prevent race conditions
            Task { @MainActor in
                self?.currentFirebaseUser = user

                // Reset new user flag when auth state changes (unless it's a signup)
                if user == nil {
                    self?.isSignedIn = false
                    // Clear ALL user-specific data to prevent leakage between accounts
                    self?.isNewUser = false
                    self?.needsEmailVerification = false
                    self?.userRole = .athlete
                    self?.userProfile = nil
                    self?.localUser = nil
                    self?.hasCompletedOnboarding = false
                    self?.currentTier = .free
                    self?.currentCoachTier = .free
                    self?.hasAthleteTierOverride = false
                    self?.clearPersistedUserDefaults()
                    authLog.debug("Cleared all user data on sign out")
                } else if self?.isHandlingSignIn == true || self?.needsEmailVerification == true {
                    // signIn()/signUp() is in progress or user needs to verify email —
                    // skip automatic isSignedIn to prevent bypassing verification gate.
                    authLog.debug("Auth state changed - Skipping (handled by signIn/signUp or pending verification)")
                } else {
                    // User signed in via Apple Sign In or app relaunch —
                    // load profile BEFORE setting isSignedIn so the UI
                    // routes to the correct role (athlete vs coach).

                    // Only load profile if this isn't a brand new signup.
                    // signUp/signUpAsCoach handle profile creation themselves.
                    if self?.isNewUser == false {
                        authLog.debug("Auth state changed - Loading profile for existing user")
                        // Use retry logic for the listener path (app relaunch, Apple Sign In).
                        // A single-shot loadUserProfile() silently swallows errors, leaving
                        // the role as the stale default. Retry with backoff gives Firestore
                        // time to establish a connection after a cold launch.
                        await self?.loadUserProfileWithRetry(maxAttempts: 3)
                    } else {
                        authLog.debug("Auth state changed - Skipping profile load (new user signup)")
                    }

                    // Sync local SwiftData user AFTER profile load so
                    // the correct role is written (not the stale default).
                    await self?.ensureLocalUser()

                    // Block unverified non-grandfathered accounts on app relaunch
                    if let user = user, self?.requiresEmailVerification(user) == true {
                        self?.needsEmailVerification = true
                        authLog.info("Auth state listener — email not verified, blocking access")
                        return
                    }

                    self?.isSignedIn = true

                    // Firestore rules compare request.auth.token.email (original case)
                    // against stored lowercased emails. If Apple Sign In preserves
                    // mixed-case, invitation reads will fail with permission denied.
                    // Known Firestore limitation: rules have no toLower() function.
                    if let email = user?.email, email != email.lowercased() {
                        authLog.warning("Firebase Auth email is not lowercase: \(email, privacy: .private) — invitation queries may fail for this user")
                    }
                }
            }
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

        // Check email verification for non-grandfathered accounts
        if requiresEmailVerification(user) {
            needsEmailVerification = true
            isLoading = false
            return
        }

        isSignedIn = true
        isLoading = false
    }

    func signIn(email: String, password: String) async {
        // Enforce client-side lockout before attempting Firebase auth
        if isSignInLocked {
            errorMessage = "Too many failed attempts. Please wait \(lockoutRemainingSeconds) seconds before trying again."
            return
        }

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

            // Reset lockout on success
            failedSignInAttempts = 0
            signInLockedUntil = nil

            // Load user profile from Firestore BEFORE setting isSignedIn,
            // so userRole is resolved before the UI transitions to AuthenticatedFlow.
            await loadUserProfile()

            // Check email verification for non-grandfathered accounts
            if requiresEmailVerification(result.user) {
                needsEmailVerification = true
                authLog.info("Sign in blocked — email not verified for \(result.user.email ?? "unknown", privacy: .private)")
                isLoading = false
                return
            }

            isSignedIn = true

            // Track successful sign in
            AnalyticsService.shared.setUserID(result.user.uid)
            AnalyticsService.shared.trackSignIn(method: "email")

            isLoading = false
            authLog.info("Sign in successful for \(result.user.email ?? "unknown", privacy: .private) as \(self.userRole.rawValue)")
        } catch {
            // Track failed attempts and enforce progressive lockout
            failedSignInAttempts += 1
            if failedSignInAttempts >= 5 {
                // Exponential lockout: 60s at 5 attempts, 120s at 10, 240s at 15
                let lockoutTier = (failedSignInAttempts - 5) / 5
                let lockoutSeconds = 60.0 * pow(2.0, Double(min(lockoutTier, 3)))
                signInLockedUntil = Date().addingTimeInterval(lockoutSeconds)
                errorMessage = "Too many failed attempts. Please wait \(Int(lockoutSeconds)) seconds before trying again."
                authLog.warning("Account lockout triggered: \(self.failedSignInAttempts) attempts, locked for \(Int(lockoutSeconds))s")
            } else {
                errorMessage = friendlyErrorMessage(from: error)
            }
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
        authLog.debug("Pre-set userRole to athlete BEFORE Firebase operations")

        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            if let displayName = displayName, !displayName.isEmpty {
                let changeRequest = result.user.createProfileChangeRequest()
                changeRequest.displayName = displayName
                try await changeRequest.commitChanges()
            }
            currentFirebaseUser = result.user

            authLog.debug("Creating athlete profile for \(email, privacy: .private)")

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
                authLog.warning("userRole was changed after createUserProfile, resetting to athlete")
                userRole = .athlete
            }

            // Track successful sign up
            AnalyticsService.shared.setUserID(result.user.uid)
            AnalyticsService.shared.trackSignUp(method: "email")

            // Send verification email and gate access until verified
            do {
                try await result.user.sendEmailVerification()
                authLog.info("Verification email sent to \(email, privacy: .private)")
            } catch {
                authLog.error("Failed to send verification email: \(error.localizedDescription)")
            }
            needsEmailVerification = true

            isLoading = false
            authLog.info("Sign up successful for athlete: \(result.user.email ?? "unknown", privacy: .private) with role: \(self.userRole.rawValue)")
        } catch {
            errorMessage = friendlyErrorMessage(from: error)
            isLoading = false
            isNewUser = false
            authLog.error("Sign up failed: \(error.localizedDescription)")
            ErrorHandlerService.shared.handle(error, context: "Auth.signUp", showAlert: false)
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
        authLog.debug("Pre-set userRole to coach BEFORE Firebase operations")

        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            let changeRequest = result.user.createProfileChangeRequest()
            changeRequest.displayName = displayName
            try await changeRequest.commitChanges()

            currentFirebaseUser = result.user

            authLog.debug("Creating coach profile for \(email, privacy: .private)")

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
                authLog.warning("userRole was changed after createUserProfile, resetting to coach")
                userRole = .coach
            }

            // Check for pending invitations
            let invitations = try await SharedFolderManager.shared.checkPendingInvitations(forEmail: email)
            if !invitations.isEmpty {
                authLog.debug("Found \(invitations.count) pending invitations for new coach")
            }

            // Send verification email and gate access until verified
            do {
                try await result.user.sendEmailVerification()
                authLog.info("Verification email sent to \(email, privacy: .private)")
            } catch {
                authLog.error("Failed to send verification email: \(error.localizedDescription)")
            }
            needsEmailVerification = true

            // Note: We DON'T mark hasCompletedOnboarding = true here
            // We want coaches to see their coach-specific onboarding flow

            isLoading = false
            authLog.info("Coach sign up successful for \(email, privacy: .private) with role: \(self.userRole.rawValue)")
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
            needsEmailVerification = false
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

            // Clear local SwiftData and local video/photo files to prevent data leakage
            SyncCoordinator.shared.clearLocalData(fallbackContext: modelContext)

            // Clear biometric credentials on logout for security
            BiometricAuthenticationManager.shared.disableBiometric()

            // Clear signed URL cache so another user can't access previous user's URLs
            SecureURLManager.shared.clearCache()

            // Clear upload queues to prevent cross-account data leakage
            UploadQueueManager.shared.clearAllQueues()

            authLog.info("Sign out successful")
        } catch {
            errorMessage = "Failed to sign out: \(error.localizedDescription)"
            authLog.error("Sign out failed: \(error.localizedDescription)")
            ErrorHandlerService.shared.handle(error, context: "Auth.signOut", showAlert: false)
        }
    }

    // MARK: - Email Verification

    /// Resends the verification email to the current user.
    func resendVerificationEmail() async throws {
        guard let user = currentFirebaseUser else {
            throw AppError.authenticationFailed(AuthConstants.ErrorMessages.noUserSignedIn)
        }
        try await user.sendEmailVerification()
        authLog.info("Verification email resent to \(user.email ?? "unknown", privacy: .private)")
    }

    /// Reloads the Firebase user and checks if their email is now verified.
    /// If verified, transitions to the signed-in state.
    func checkEmailVerification() async -> Bool {
        guard let user = currentFirebaseUser else { return false }
        do {
            try await user.reload()
            // Re-fetch the user object after reload to get updated properties
            guard let refreshedUser = Auth.auth().currentUser else { return false }
            currentFirebaseUser = refreshedUser

            if refreshedUser.isEmailVerified {
                needsEmailVerification = false
                isSignedIn = true
                authLog.info("Email verified for \(refreshedUser.email ?? "unknown", privacy: .private)")
                return true
            }
            return false
        } catch {
            authLog.error("Failed to reload user for verification check: \(error.localizedDescription)")
            return false
        }
    }

    /// Signs out an unverified user and resets verification state.
    func cancelEmailVerification() async {
        needsEmailVerification = false
        await signOut()
    }

    func resetPassword(email: String) async throws {
        isLoading = true
        defer { isLoading = false }

        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
            authLog.info("Password reset sent to \(email, privacy: .private)")
        } catch {
            authLog.error("Password reset failed: \(error.localizedDescription)")
            throw AppError.authenticationFailed(friendlyErrorMessage(from: error))
        }
    }
}
