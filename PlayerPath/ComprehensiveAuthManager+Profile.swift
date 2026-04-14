//
//  ComprehensiveAuthManager+Profile.swift
//  PlayerPath
//
//  User profile CRUD: load, create, update display name, ensure local user, delete account.
//

import FirebaseAuth
import SwiftData
import os

private let authLog = Logger(subsystem: "com.playerpath.app", category: "Auth")

extension ComprehensiveAuthManager {

    func ensureLocalUser() async {
        guard let context = modelContext,
              let firebaseUser = Auth.auth().currentUser,
              let email = firebaseUser.email else {
            return
        }

        let firebaseUID = firebaseUser.uid

        do {
            // Primary: match on firebaseAuthUid (the stable identity). Email can
            // change via verified-email-change flow; UID cannot.
            let uidDescriptor = FetchDescriptor<User>(
                predicate: #Predicate<User> { $0.firebaseAuthUid == firebaseUID }
            )
            var existingUser = try context.fetch(uidDescriptor).first

            // Fallback: migrate legacy rows whose firebaseAuthUid was never populated.
            // Require firebaseAuthUid == nil to avoid adopting a different account's row.
            if existingUser == nil {
                let noUID: String? = nil
                let emailDescriptor = FetchDescriptor<User>(
                    predicate: #Predicate<User> {
                        $0.email == email && $0.firebaseAuthUid == noUID
                    }
                )
                if let legacy = try context.fetch(emailDescriptor).first {
                    legacy.firebaseAuthUid = firebaseUID
                    authLog.info("Migrated legacy SwiftData user (email match) to firebaseAuthUid: \(firebaseUID, privacy: .private)")
                    existingUser = legacy
                }
            }

            if let user = existingUser {
                var needsSave = false
                if user.role != self.userRole.rawValue {
                    user.role = self.userRole.rawValue
                    needsSave = true
                    authLog.debug("Synced user role to SwiftData: \(self.userRole.rawValue)")
                }
                if user.firebaseAuthUid != firebaseUID {
                    user.firebaseAuthUid = firebaseUID
                    needsSave = true
                }
                // Pick up verified email changes from Firebase Auth.
                if user.email != email {
                    user.email = email
                    needsSave = true
                    authLog.debug("Synced email change from Firebase Auth to SwiftData")
                }
                if let displayName = firebaseUser.displayName,
                   !displayName.isEmpty,
                   user.username == user.email || user.username.isEmpty {
                    user.username = displayName
                    needsSave = true
                    authLog.debug("Synced display name from Firebase Auth to SwiftData")
                }
                if needsSave { try context.save() }
                self.localUser = user
            } else {
                let newUser = User(username: firebaseUser.displayName ?? email, email: email, role: self.userRole.rawValue)
                newUser.firebaseAuthUid = firebaseUID
                context.insert(newUser)
                try context.save()
                authLog.debug("Created new SwiftData user with role: \(self.userRole.rawValue), Firebase UID: \(firebaseUID, privacy: .private)")
                self.localUser = newUser
            }
        } catch {
            authLog.error("Failed to load user profile: \(error.localizedDescription)")
            self.errorMessage = "Failed to load user profile"
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

        authLog.debug("Creating user profile in Firestore - Role: \(role.rawValue), Email: \(email, privacy: .private)")

        try await FirestoreManager.shared.updateUserProfile(
            userID: userID,
            email: email,
            role: role,
            profileData: profileData
        )

        // Note: userRole is already set synchronously before this function is called
        // We verify it matches what we're saving to Firestore
        if self.userRole != role {
            authLog.warning("Local userRole (\(self.userRole.rawValue)) doesn't match Firestore role (\(role.rawValue)) — correcting to: \(role.rawValue)")
            self.userRole = role
        } else {
            authLog.debug("Verified userRole in memory matches Firestore: \(role.rawValue)")
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
            authLog.warning("loadUserProfile: No user ID or email")
            return
        }

        authLog.debug("loadUserProfile: Fetching profile for user \(email, privacy: .private)")

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
                    authLog.debug("Academy coach tier applied from Firestore override")
                }

                // Athlete tier can be comped via Firestore — if Firestore holds a higher
                // tier than StoreKit resolved, treat it as a manual grant and override.
                // This mirrors the coach Academy pattern for athlete tiers.
                // Comp preservation is handled server-side in syncSubscriptionTier.
                if profile.tier > currentTier {
                    currentTier = profile.tier
                    authLog.debug("Comped athlete tier applied from Firestore: \(profile.tier.displayName)")
                }

                // Sync Firebase Auth email to Firestore if they differ
                // (e.g. after a verified email change via sendEmailVerification(beforeUpdatingEmail:))
                if email.lowercased() != profile.email.lowercased() {
                    authLog.info("Email mismatch: Auth=\(email, privacy: .private), Firestore=\(profile.email, privacy: .private) — syncing to Firestore")
                    do {
                        try await FirestoreManager.shared.updateUserProfile(
                            userID: userID,
                            email: email.lowercased(),
                            role: profile.userRole,
                            profileData: ["email": email.lowercased()]
                        )
                    } catch {
                        authLog.warning("Failed to sync email to Firestore: \(error.localizedDescription)")
                    }
                }

                hasLoadedProfile = true

                // Check if user needs to set a display name
                let firebaseName = currentFirebaseUser?.displayName ?? ""
                let firestoreName = profile.displayName ?? ""
                let hasRealName = (!firebaseName.isEmpty && firebaseName != "User")
                                  || (!firestoreName.isEmpty && firestoreName != "User")
                needsDisplayName = !hasRealName

                // Only sync to Firestore after StoreKit's initial entitlement
                // resolution completes. On a second device, StoreKit may not have
                // synced transactions yet and would overwrite the correct Firestore
                // tier with .free via empty JWS tokens.
                if StoreKitManager.shared.hasResolvedEntitlements {
                    syncSubscriptionTierToFirestore()
                }

                // Only update userRole if it's different AND this is not a new user
                // For new users, we want to keep the role we set synchronously at signup
                if isNewUser {
                    // New user: Keep the role we set at signup, but verify it matches Firestore
                    if profile.userRole != currentRole {
                        authLog.warning("Role mismatch for new user: Firestore (\(profile.userRole.rawValue)) vs pre-set (\(currentRole.rawValue)) — keeping pre-set role: \(currentRole.rawValue)")
                    } else {
                        authLog.debug("Firestore role matches pre-set role: \(currentRole.rawValue)")
                    }
                    // Keep the pre-set role, don't override
                } else {
                    // Existing user: Update role from Firestore
                    userRole = profile.userRole
                    authLog.debug("Updated role from Firestore for existing user: \(profile.userRole.rawValue)")
                }

                authLog.debug("Loaded user profile: \(profile.role) for \(email, privacy: .private)")
            } else {
                // Profile doesn't exist. Do NOT fallback-create here — this path
                // is the eager single-shot load called from signIn(). A nil result
                // for a non-new user is more often a transient Firestore miss than
                // a truly missing profile; creating one would risk overwriting an
                // existing coach's Firestore doc with "athlete" on a fresh install
                // where UserDefaults is wiped. The listener path uses
                // loadUserProfileWithRetry which retries with backoff and has its
                // own (gated) fallback-create.
                if isNewUser {
                    authLog.warning("Profile not found for new user \(email, privacy: .private), keeping pre-set role: \(self.userRole.rawValue)")
                } else {
                    authLog.error("Profile not found for existing user \(email, privacy: .private) — NOT creating fallback (would risk overwriting a real profile). User should retry.")
                    self.errorMessage = "Couldn't load your profile. Please check your connection and try again."
                }
            }
        } catch {
            authLog.error("Failed to load user profile for \(email, privacy: .private): \(error.localizedDescription)")
        }
    }

    /// Loads user profile from Firestore with retry logic
    /// This handles Firestore propagation delays using exponential backoff instead of fixed delays
    func loadUserProfileWithRetry(maxAttempts: Int = 5) async {
        guard let userID = currentFirebaseUser?.uid,
              let email = currentFirebaseUser?.email else {
            authLog.warning("loadUserProfileWithRetry: No user ID or email")
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
                            authLog.warning("Role mismatch for new user: Firestore (\(profile.userRole.rawValue)) vs pre-set (\(currentRole.rawValue)) — keeping pre-set role: \(currentRole.rawValue)")
                        } else {
                            authLog.debug("Firestore role matches pre-set role: \(currentRole.rawValue)")
                        }
                    } else {
                        userRole = profile.userRole
                        authLog.debug("Updated role from Firestore for existing user: \(profile.userRole.rawValue)")
                    }

                    authLog.debug("Loaded user profile on attempt \(attempt): \(profile.role) for \(email, privacy: .private)")
                    return
                } else if attempt < maxAttempts {
                    // Profile not found yet, retry with exponential backoff.
                    // Use try? so task cancellation (e.g. from SignInView.onDisappear) does NOT
                    // propagate a CancellationError up through signUpAsCoach's catch block,
                    // which would incorrectly reset isNewUser/userRole for a successfully-created account.
                    let delay = pow(2.0, Double(attempt - 1)) * 0.1 // 0.1s, 0.2s, 0.4s, 0.8s, 1.6s
                    authLog.debug("Profile not found for \(email, privacy: .private) on attempt \(attempt)/\(maxAttempts), retrying in \(delay)s...")
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } else {
                    // Last attempt and still not found. Only create a fallback
                    // profile if this looks like a brand-new account (Firestore
                    // write may have failed during signUp). For established
                    // accounts, a persistent nil is almost certainly a backend
                    // issue — creating here would risk overwriting an existing
                    // coach profile with an athlete role on a fresh install
                    // where UserDefaults is wiped.
                    let creationDate = self.currentFirebaseUser?.metadata.creationDate ?? .distantPast
                    let looksLikeNewAccount = Date().timeIntervalSince(creationDate) < 300

                    if looksLikeNewAccount {
                        authLog.warning("Profile not found for new-ish account \(email, privacy: .private) after \(maxAttempts) attempts — creating fallback with role: \(self.userRole.rawValue)")
                        do {
                            try await createUserProfile(
                                userID: userID,
                                email: email,
                                displayName: self.currentFirebaseUser?.displayName ?? email,
                                role: self.userRole,
                                loadAfterCreate: false
                            )
                            authLog.debug("Successfully created fallback Firestore profile")
                        } catch {
                            authLog.error("Failed to create fallback profile: \(error.localizedDescription)")
                        }
                    } else {
                        authLog.error("Profile not found for established account \(email, privacy: .private) after \(maxAttempts) attempts — NOT creating fallback (would risk overwriting a real profile).")
                        self.errorMessage = "Couldn't load your profile. Please check your connection and try again."
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

                    // Same gating as above: only fallback-create for brand-new
                    // accounts. Errors for established accounts are almost
                    // always network/backend issues, not missing profiles.
                    let creationDate = self.currentFirebaseUser?.metadata.creationDate ?? .distantPast
                    let looksLikeNewAccount = Date().timeIntervalSince(creationDate) < 300

                    if looksLikeNewAccount {
                        do {
                            try await createUserProfile(
                                userID: userID,
                                email: email,
                                displayName: self.currentFirebaseUser?.displayName ?? email,
                                role: self.userRole,
                                loadAfterCreate: false
                            )
                            authLog.debug("Successfully created fallback Firestore profile after errors")
                        } catch {
                            authLog.error("Failed to create fallback profile: \(error.localizedDescription)")
                        }
                    } else {
                        authLog.error("NOT creating fallback profile for established account \(email, privacy: .private) — would risk overwriting a real profile.")
                        self.errorMessage = "Couldn't load your profile. Please check your connection and try again."
                    }
                }
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

    /// Deletes user account and all associated data (GDPR compliance).
    ///
    /// Order matters:
    ///   1. Remove this device's push tokens while still authenticated (the FCM
    ///      removal writes to the user's Firestore doc, which is about to go away).
    ///   2. Delete the Firebase Auth account FIRST. If this fails with
    ///      `requiresRecentLogin`, we abort before destroying any data so the
    ///      user can re-authenticate and retry without a zombie account.
    ///   3. Best-effort cleanup of Storage videos, Firestore profile, and local
    ///      data. Once the Auth token is invalidated by step 2, these client
    ///      calls will usually fail under `request.auth.uid == userID` rules —
    ///      the authoritative cleanup path is an `onDelete` Auth Cloud Function
    ///      (follow-up, not blocking).
    func deleteAccount() async throws {
        guard let user = currentFirebaseUser else {
            throw NSError(domain: "ComprehensiveAuthManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user signed in"])
        }
        guard ConnectivityMonitor.shared.isConnected else {
            throw NSError(domain: "ComprehensiveAuthManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Account deletion requires an internet connection. Please connect and try again."])
        }

        isLoading = true
        errorMessage = nil

        let userID = user.uid
        authLog.info("Starting account deletion for user: \(user.email ?? "unknown", privacy: .private)")
        AnalyticsService.shared.trackAccountDeletionRequested(userID: userID)

        // Step 1: Remove this device's push tokens BEFORE deleting the Auth account.
        // FCM token removal writes to the user's Firestore doc and requires an
        // authenticated session.
        await PushNotificationService.shared.removeTokenFromServer()
        await PushNotificationService.shared.removeFCMTokenFromServer()

        // Step 2: Delete the Firebase Auth account FIRST. If this throws
        // (typically requiresRecentLogin), no data has been destroyed yet.
        do {
            try await user.delete()
        } catch {
            let nsError = error as NSError
            isLoading = false
            if nsError.code == AuthErrorCode.requiresRecentLogin.rawValue {
                errorMessage = "For your security, please sign in again before deleting your account."
                authLog.warning("Account deletion requires recent login — aborting before any data loss")
                ErrorHandlerService.shared.handle(error, context: "Auth.deleteAccount.requiresRecentLogin", showAlert: false)
                throw AppError.authenticationFailed("Please sign in again, then retry account deletion.")
            }
            errorMessage = "Failed to delete account: \(error.localizedDescription)"
            authLog.error("Firebase Auth deletion failed: \(error.localizedDescription)")
            ErrorHandlerService.shared.handle(error, context: "Auth.deleteAccount", showAlert: false)
            throw error
        }

        // Step 3: Best-effort data cleanup. The Auth account is already gone;
        // failures here are logged but do NOT revive the account. An onDelete
        // Cloud Function is the authoritative path.
        do {
            try await VideoCloudManager.shared.deleteAllUserVideos(userID: userID)
            authLog.debug("Deleted all videos from Storage")
        } catch {
            authLog.warning("Post-auth-delete: error deleting videos from Storage: \(error.localizedDescription)")
        }

        do {
            try await FirestoreManager.shared.deleteUserProfile(userID: userID)
            authLog.debug("Deleted user profile from Firestore")
        } catch {
            authLog.warning("Post-auth-delete: error deleting Firestore profile: \(error.localizedDescription)")
        }

        UploadQueueManager.shared.clearAllQueues()
        SyncCoordinator.shared.clearLocalData(fallbackContext: modelContext)

        // Step 4: Clear local state
        currentFirebaseUser = nil
        isSignedIn = false
        userProfile = nil
        localUser = nil
        isNewUser = false
        userRole = .athlete
        currentTier = .free
        currentCoachTier = .free
        hasLoadedProfile = false
        hasCompletedOnboarding = false

        clearPersistedUserDefaults()

        AnalyticsService.shared.trackAccountDeletionCompleted(userID: userID)
        AnalyticsService.shared.clearUserID()

        isLoading = false
        authLog.debug("Account deletion successful")
    }
}
