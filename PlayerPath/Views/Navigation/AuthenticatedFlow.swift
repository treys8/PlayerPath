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
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @Query private var users: [User]
    @Query(sort: \OnboardingProgress.createdAt, order: .forward) private var onboardingProgress: [OnboardingProgress]
    
    @State private var currentUser: User?
    @State private var isLoading = true

    
    var body: some View {
        Group {
            if isLoading {
                LoadingView(title: "Setting up your profile...", subtitle: "This will only take a moment")
            } else if let user = currentUser {
                #if DEBUG
                let _ = print("🎯 AuthenticatedFlow - isNewUser: \(authManager.isNewUser), hasCompletedOnboarding: \(hasCompletedOnboarding), userRole: \(authManager.userRole.rawValue)")
                #endif
                
                // Show onboarding whenever it hasn't been completed. isNewUser alone is not
                // sufficient — a user who signs out mid-onboarding has isNewUser reset to false
                // but still needs to finish onboarding. hasCompletedOnboarding is backed by
                // both UserDefaults and SwiftData OnboardingProgress, so fully-onboarded
                // returning users always evaluate it as true and skip correctly.
                if !hasCompletedOnboarding {
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
                ErrorView(
                    message: "Unable to load your profile. This may be a connection issue or a problem with your account.",
                    retry: {
                        Task {
                            await authManager.signOut()
                        }
                    },
                    errorType: .network,
                    title: "Profile Load Failed",
                    suggestion: "Check your internet connection or sign in again."
                )
            }
        }
        .onDisappear {
            ActivityNotificationService.shared.stopListening()
            SharedFolderManager.shared.stopCoachFoldersListener()
            CoachInvitationManager.shared.stopInvitationsListener()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                ActivityNotificationService.shared.stopListening()
                SharedFolderManager.shared.stopCoachFoldersListener()
                CoachInvitationManager.shared.stopInvitationsListener()
            case .active:
                // Re-start listeners if user is authenticated
                if let firebaseUID = authManager.currentFirebaseUser?.uid {
                    ActivityNotificationService.shared.startListening(forUserID: firebaseUID)
                    if authManager.userRole == .coach {
                        SharedFolderManager.shared.startCoachFoldersListener(coachID: firebaseUID)
                        if let email = authManager.currentFirebaseUser?.email?.lowercased() {
                            CoachInvitationManager.shared.startInvitationsListener(forCoachEmail: email)
                        }
                    }
                }
            default:
                break
            }
        }
        .task(priority: .userInitiated) {
            // Scope OnboardingManager to the current user (needed for routing)
            OnboardingManager.shared.configure(forUserID: authManager.currentFirebaseUser?.uid)

            // Load user FIRST — this gates the UI appearing.
            // Everything else is deferred until after the UI is visible.
            await loadUser()

            // Ensure firebaseAuthUid is written before sync builds Firestore paths.
            await authManager.ensureLocalUser()

            // --- Post-UI setup: none of this blocks the loading screen ---

            // Configure services that need ModelContext
            SyncCoordinator.shared.configure(modelContext: modelContext)
            UploadQueueManager.shared.configure(modelContext: modelContext)
            QuickActionsManager.shared.setupQuickActions()

            // Start Firestore listeners for real-time updates
            if let firebaseUID = authManager.currentFirebaseUser?.uid {
                ActivityNotificationService.shared.startListening(forUserID: firebaseUID)
            }

            // Coach-specific listeners
            if authManager.userRole == .coach {
                if let coachID = authManager.currentFirebaseUser?.uid {
                    CoachFolderArchiveManager.shared.configure(coachUID: coachID)
                    SharedFolderManager.shared.startCoachFoldersListener(coachID: coachID)
                }
                if let coachEmail = authManager.currentFirebaseUser?.email?.lowercased() {
                    CoachInvitationManager.shared.startInvitationsListener(forCoachEmail: coachEmail)
                }
            }

            // Run migration, recovery, and sync in background — don't block the UI
            Task(priority: .utility) {
                // Migrate videos from Caches to Documents (one-time operation)
                do {
                    try await ClipPersistenceService().migrateVideosToDocuments(context: modelContext)
                } catch {
                    // Don't block app launch on migration failure
                }

                // Recover any video files orphaned by a SwiftData store reset
                let athletes = (currentUser?.athletes ?? [])
                await OrphanedClipRecoveryService.shared.recoverIfNeeded(
                    context: modelContext,
                    athletes: athletes
                )

                // Trigger full sync so all data is available on new device
                if let user = currentUser, user.firebaseAuthUid != nil {
                    try? await SyncCoordinator.shared.syncAll(for: user)
                }
            }
        }
    }
    
    // Computed property to check if onboarding has been completed
    private var hasCompletedOnboarding: Bool {
        // Check if onboarding progress exists for the current user, or auth manager flag is set
        let currentUID = authManager.currentFirebaseUser?.uid
        return onboardingProgress.contains { $0.hasCompletedOnboarding && $0.firebaseAuthUid == currentUID }
            || authManager.hasCompletedOnboarding
    }
    
    private func loadUser() async {
        guard let authUser = authManager.currentFirebaseUser,
              let rawEmail = authUser.email else {
            isLoading = false
            return
        }
        
        // Check for cancellation early
        guard !Task.isCancelled else {
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
                return
            }
            
            await createNewUser(authUser: authUser, email: email)
        }
        
        // Final cancellation check before marking complete
        guard !Task.isCancelled else {
            return
        }

        // For existing users (sign-in or app re-launch), mark the welcome tutorial as seen
        // so they never unexpectedly receive the new-user tutorial after an app update.
        // New users (isNewUser = true from signUp()) need a clean slate — clear any stale
        // UserDefaults that may have been left by a previous account on this device.
        if !authManager.isNewUser {
            OnboardingManager.shared.markMilestoneComplete(.welcomeTutorial)
            // Ensure existing users always skip onboarding even if their
            // OnboardingProgress record was lost (reinstall, data migration, etc.)
            if !hasCompletedOnboarding {
                authManager.markOnboardingComplete()
            }
        } else {
            // Ensure welcome tutorial fires when the new user first reaches MainTabView,
            // even if a previous account on this device had already seen it.
            OnboardingManager.shared.resetWelcomeTutorial()
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
            #if DEBUG
            print("❌ Failed to save new user to SwiftData: \(error.localizedDescription)")
            #endif
        }
    }
}
