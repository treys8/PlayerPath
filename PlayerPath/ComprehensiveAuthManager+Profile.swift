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
            authLog.error("Failed to load user profile for \(email, privacy: .private): \(error.localizedDescription)")
        }
    }

    /// Loads user profile from Firestore with retry logic
    /// This handles Firestore propagation delays using exponential backoff instead of fixed delays
    func loadUserProfileWithRetry(maxAttempts: Int = 5) async {
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
}
