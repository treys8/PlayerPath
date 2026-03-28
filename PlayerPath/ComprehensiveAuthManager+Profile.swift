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

        let fetchDescriptor = FetchDescriptor<User>(predicate: #Predicate<User> { $0.email == email })

        do {
            let users = try context.fetch(fetchDescriptor)
            if let existingUser = users.first {
                var needsSave = false
                // Sync role from authManager to SwiftData if different
                if existingUser.role != self.userRole.rawValue {
                    existingUser.role = self.userRole.rawValue
                    needsSave = true
                    authLog.debug("Synced user role to SwiftData: \(self.userRole.rawValue)")
                }
                // Store Firebase Auth UID so SyncCoordinator queries the correct Firestore path
                if existingUser.firebaseAuthUid != firebaseUser.uid {
                    existingUser.firebaseAuthUid = firebaseUser.uid
                    needsSave = true
                    authLog.debug("Stored Firebase Auth UID: \(firebaseUser.uid, privacy: .private)")
                }
                if needsSave { try context.save() }
                self.localUser = existingUser
            } else {
                // Create new user with current role from authManager
                let newUser = User(username: firebaseUser.displayName ?? email, email: email, role: self.userRole.rawValue)
                newUser.firebaseAuthUid = firebaseUser.uid
                context.insert(newUser)
                try context.save()
                authLog.debug("Created new SwiftData user with role: \(self.userRole.rawValue), Firebase UID: \(firebaseUser.uid, privacy: .private)")
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
                if profile.tier > currentTier {
                    currentTier = profile.tier
                    hasAthleteTierOverride = true
                    authLog.debug("Comped athlete tier applied from Firestore override: \(profile.tier.displayName)")
                } else {
                    hasAthleteTierOverride = false
                }

                hasLoadedProfile = true

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
                // Profile doesn't exist - only create if this is NOT a new user
                // (new users should have had their profile created in signUp/signUpAsCoach)
                if !isNewUser {
                    // Use the current in-memory role (restored from UserDefaults)
                    // rather than hardcoding .athlete. If the user was a coach,
                    // the UserDefaults cache preserves that from the last successful
                    // profile load. This prevents overwriting a coach's Firestore
                    // doc with "athlete" if the profile transiently isn't found.
                    let fallbackRole = self.userRole
                    authLog.warning("Profile doesn't exist for existing user \(email, privacy: .private), creating profile with role: \(fallbackRole.rawValue)")
                    try await createUserProfile(
                        userID: userID,
                        email: email,
                        displayName: currentFirebaseUser?.displayName ?? email,
                        role: fallbackRole
                    )
                    syncSubscriptionTierToFirestore()
                } else {
                    authLog.warning("Profile not found for new user \(email, privacy: .private), but keeping existing role: \(self.userRole.rawValue)")
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
                    // Last attempt and still not found - create profile as fallback
                    authLog.warning("Profile not found for \(email, privacy: .private) after \(maxAttempts) attempts — creating fallback Firestore profile with current role: \(self.userRole.rawValue)")

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
                        authLog.debug("Successfully created fallback Firestore profile")
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
                        authLog.debug("Successfully created fallback Firestore profile after errors")
                    } catch {
                        authLog.error("Failed to create fallback profile: \(error.localizedDescription)")
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

            authLog.info("Starting account deletion for user: \(user.email ?? "unknown", privacy: .private)")

            // Track account deletion request
            AnalyticsService.shared.trackAccountDeletionRequested(userID: userID)

            // Step 1: Delete all user videos from Firebase Storage
            authLog.info("Deleting user videos from Storage...")
            do {
                try await VideoCloudManager.shared.deleteAllUserVideos(userID: userID)
                authLog.debug("Deleted all videos from Storage")
            } catch {
                authLog.warning("Error deleting videos from Storage during account deletion: \(error.localizedDescription)")
                // Continue with deletion even if video deletion fails
            }

            // Step 2: Delete Firestore user profile and related data
            authLog.info("Deleting user profile from Firestore...")
            do {
                try await FirestoreManager.shared.deleteUserProfile(userID: userID)
                authLog.debug("Deleted user profile from Firestore")
            } catch {
                authLog.warning("Error deleting Firestore profile during account deletion: \(error.localizedDescription)")
                // Continue with deletion even if Firestore deletion fails
            }

            // Step 3: Clear biometric credentials
            BiometricAuthenticationManager.shared.disableBiometric()

            // Step 4: Cancel any in-flight uploads and clear local data
            UploadQueueManager.shared.clearAllQueues()
            SyncCoordinator.shared.clearLocalData(fallbackContext: modelContext)

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

            authLog.debug("Account deletion successful")

        } catch {
            errorMessage = "Failed to delete account: \(error.localizedDescription)"
            isLoading = false
            authLog.error("Account deletion failed: \(error.localizedDescription)")
            ErrorHandlerService.shared.handle(error, context: "Auth.deleteAccount", showAlert: false)
            throw error
        }
    }
}
