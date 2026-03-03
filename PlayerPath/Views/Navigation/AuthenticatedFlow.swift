//
//  AuthenticatedFlow.swift
//  PlayerPath
//
//  Extracted from MainAppView.swift
//

import SwiftUI
import SwiftData
import FirebaseAuth

struct AuthenticatedFlow: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @Query private var users: [User]
    @Query(sort: \OnboardingProgress.createdAt, order: .forward) private var onboardingProgress: [OnboardingProgress]
    
    @State private var currentUser: User?
    @State private var isLoading = true
    @State private var loadTask: Task<Void, Never>?
    
    var body: some View {
        Group {
            if isLoading {
                LoadingView(title: "Setting up your profile...", subtitle: "This will only take a moment")
            } else if let user = currentUser {
                let _ = print("🎯 AuthenticatedFlow - isNewUser: \(authManager.isNewUser), hasCompletedOnboarding: \(hasCompletedOnboarding), userRole: \(authManager.userRole.rawValue)")
                
                // Show onboarding for all new users who haven't completed it yet
                if authManager.isNewUser && !hasCompletedOnboarding {
                    if authManager.userRole == .coach {
                        CoachOnboardingFlow(modelContext: modelContext, authManager: authManager, user: user)
                    } else {
                        OnboardingFlow(user: user)
                    }
                } else {
                    UserMainFlow(
                        user: user,
                        isNewUserFlag: authManager.isNewUser,
                        hasCompletedOnboarding: hasCompletedOnboarding
                    )
                }
            } else {
                ErrorView(message: "Unable to load user profile") {
                    Task {
                        await authManager.signOut()
                    }
                }
            }
        }
        .task(priority: .userInitiated) {
            loadTask = Task {
                // Configure SyncCoordinator with ModelContext
                SyncCoordinator.shared.configure(modelContext: modelContext)

                // Configure UploadQueueManager with ModelContext
                UploadQueueManager.shared.configure(modelContext: modelContext)

                // Setup iOS Home Screen Quick Actions
                QuickActionsManager.shared.setupQuickActions()

                // Load user
                await loadUser()

                // Migrate videos from Caches to Documents (one-time operation)
                do {
                    try await ClipPersistenceService().migrateVideosToDocuments(context: modelContext)
                } catch {
                    print("⚠️ Video migration failed (non-blocking): \(error)")
                    // Don't block app launch on migration failure
                }

                // Recover any video files orphaned by a SwiftData store reset
                // (happens between TestFlight builds when model schema changes).
                // Run after loadUser() so athletes are in the context.
                let athletes = (currentUser?.athletes ?? [])
                await OrphanedClipRecoveryService.shared.recoverIfNeeded(
                    context: modelContext,
                    athletes: athletes
                )

                // Ensure firebaseAuthUid is written before sync builds Firestore paths.
                // ensureLocalUser() is called from the auth state listener but modelContext
                // is nil at that point, so it returns early. Now that loadUser() has attached
                // the context, call it again so user.firebaseAuthUid is populated.
                await authManager.ensureLocalUser()

                // Trigger initial sync after user loads
                if let user = currentUser, user.firebaseAuthUid != nil {
                    do {
                        try await SyncCoordinator.shared.syncAthletes(for: user)
                        print("✅ Initial athlete sync completed on app launch")
                    } catch {
                        print("⚠️ Initial sync failed (will retry in background): \(error)")
                        // Don't block app launch on sync failure
                    }
                } else if currentUser?.firebaseAuthUid == nil {
                    print("⚠️ Skipping sync — firebaseAuthUid not yet available (will sync on next foreground)")
                }
            }
        }
        .onDisappear {
            loadTask?.cancel()
        }
    }
    
    // Computed property to check if onboarding has been completed
    private var hasCompletedOnboarding: Bool {
        // Check if onboarding progress exists or auth manager flag is set
        return onboardingProgress.contains { $0.hasCompletedOnboarding } || authManager.hasCompletedOnboarding
    }
    
    private func loadUser() async {
        guard let authUser = authManager.currentFirebaseUser,
              let rawEmail = authUser.email else {
            print("🔴 No authenticated user found")
            isLoading = false
            return
        }
        
        // Check for cancellation early
        guard !Task.isCancelled else {
            print("🟡 loadUser cancelled early")
            return
        }
        
        // Attach model context to auth manager for consistency
        authManager.attachModelContext(modelContext)
        
        let email = rawEmail.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        #if DEBUG
        print("🟢 Looking up user with email: \(email)")
        #endif
        
        // Find or create user
        if let existingUser = users.first(where: { $0.email == email }) {
            // If the SwiftData record has a Firebase UID that differs from the current
            // auth session (e.g. account was deleted and re-created with the same email),
            // treat this as a new account to prevent data from leaking across sessions.
            if let storedUID = existingUser.firebaseAuthUid,
               !storedUID.isEmpty,
               storedUID != authUser.uid {
                #if DEBUG
                print("🟡 Email match but Firebase UID mismatch — treating as new account")
                print("  stored: \(storedUID), current: \(authUser.uid)")
                #endif
                guard !Task.isCancelled else { return }
                await createNewUser(authUser: authUser, email: email)
            } else {
            #if DEBUG
            print("🟢 Found existing user: \(existingUser.username) (ID: \(existingUser.id))")
            print("🟢 User has \((existingUser.athletes ?? []).count) athletes")
            #endif

            // Check cancellation before updating state
            guard !Task.isCancelled else {
                print("🟡 loadUser cancelled before setting currentUser")
                return
            }

            currentUser = existingUser
            
            await MainActor.run {
                if let refreshedByEmail = users.first(where: { $0.email == email }) {
                    currentUser = refreshedByEmail
                    #if DEBUG
                    print("🟢 Using persisted user by email: \(refreshedByEmail.username) | athletes: \((refreshedByEmail.athletes ?? []).count)")
                    #endif
                } else if let refreshedByID = users.first(where: { $0.id == existingUser.id }) {
                    currentUser = refreshedByID
                    #if DEBUG
                    print("🟢 Fallback persisted user by id: \(refreshedByID.username) | athletes: \((refreshedByID.athletes ?? []).count)")
                    #endif
                } else {
                    #if DEBUG
                    print("🟠 Could not re-fetch persisted user; using in-memory instance")
                    #endif
                }
            }
            } // end UID-match else
        } else {
            #if DEBUG
            print("🟡 Creating new user")
            #endif
            
            // Check cancellation before creating
            guard !Task.isCancelled else {
                print("🟡 loadUser cancelled before createNewUser")
                return
            }
            
            await createNewUser(authUser: authUser, email: email)
        }
        
        // Final cancellation check before marking complete
        guard !Task.isCancelled else {
            print("🟡 loadUser cancelled before setting isLoading false")
            return
        }

        // For existing users (sign-in or app re-launch), mark the welcome tutorial as seen
        // so they never unexpectedly receive the new-user tutorial after an app update.
        // New users (isNewUser = true from signUp()) need a clean slate — clear any stale
        // UserDefaults that may have been left by a previous account on this device.
        if !authManager.isNewUser {
            OnboardingManager.shared.markMilestoneComplete(.welcomeTutorial)
        } else {
            // Ensure welcome tutorial fires when the new user first reaches MainTabView,
            // even if a previous account on this device had already seen it.
            OnboardingManager.shared.resetWelcomeTutorial()
            // Always start new users on the Home tab, not whatever tab a previous
            // account had selected last.
            UserDefaults.standard.removeObject(forKey: "LastSelectedTab")
            // Athletes skip AthleteOnboardingFlow — WelcomeTutorialView in MainTabView
            // is the welcome. Coaches keep their multi-page onboarding flow.
            if authManager.userRole != .coach {
                authManager.markOnboardingComplete()
            }
        }

        isLoading = false
    }
    
    private func createNewUser(authUser: FirebaseAuth.User, email: String) async {
        let normalizedEmail = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        let newUser = User(
            username: authUser.displayName ?? normalizedEmail,
            email: normalizedEmail
        )
        
        modelContext.insert(newUser)
        
        do {
            try modelContext.save()
            #if DEBUG
            print("🟢 Successfully created new user with ID: \(newUser.id)")
            #endif
            
            // Attach the model context to auth manager for future use
            authManager.attachModelContext(modelContext)
            
            // Re-fetch the newly created user from the store using normalized email to ensure we use the persisted instance
            await MainActor.run {
                if let refreshed = users.first(where: { $0.email == normalizedEmail }) {
                    currentUser = refreshed
                    #if DEBUG
                    print("🟢 Using refreshed user: \(refreshed.id)")
                    #endif
                } else {
                    currentUser = newUser
                    #if DEBUG
                    print("🟠 Using original user instance: \(newUser.id)")
                    #endif
                }
            }
        } catch {
            print("🔴 Failed to create user: \(error)")
        }
    }
}
