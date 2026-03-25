//
//  AuthenticatedFlow.swift
//  PlayerPath
//
//  Extracted from MainAppView.swift
//

import SwiftUI
import SwiftData
import FirebaseAuth
import os

private let log = Logger(subsystem: "com.playerpath.app", category: "AuthenticatedFlow")

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
                let _ = log.debug("AuthenticatedFlow - isNewUser: \(authManager.isNewUser), hasCompletedOnboarding: \(hasCompletedOnboarding), userRole: \(authManager.userRole.rawValue)")
                
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
            AthleteInvitationManager.shared.stopInvitationsListener()
        }
        .onChange(of: authManager.isSignedIn) { oldValue, newValue in
            if oldValue == true && newValue == false {
                // User signed out — stop all listeners immediately
                ActivityNotificationService.shared.stopListening()
                SharedFolderManager.shared.stopCoachFoldersListener()
                CoachInvitationManager.shared.stopInvitationsListener()
                AthleteInvitationManager.shared.stopInvitationsListener()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                ActivityNotificationService.shared.stopListening()
                SharedFolderManager.shared.stopCoachFoldersListener()
                CoachInvitationManager.shared.stopInvitationsListener()
                AthleteInvitationManager.shared.stopInvitationsListener()
            case .active:
                // Re-start listeners if user is authenticated
                if let firebaseUID = authManager.currentFirebaseUser?.uid {
                    ActivityNotificationService.shared.startListening(forUserID: firebaseUID)
                    if authManager.userRole == .coach {
                        SharedFolderManager.shared.startCoachFoldersListener(coachID: firebaseUID)
                        if let email = authManager.currentFirebaseUser?.email?.lowercased() {
                            CoachInvitationManager.shared.startInvitationsListener(forCoachEmail: email)
                        }
                    } else {
                        if let email = authManager.currentFirebaseUser?.email?.lowercased() {
                            AthleteInvitationManager.shared.startInvitationsListener(forAthleteEmail: email)
                        }
                    }
                    // Refresh tier from Firestore to catch changes from other devices
                    Task { await authManager.refreshTierFromFirestore() }
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

            // Start Firestore listeners for real-time updates
            if let firebaseUID = authManager.currentFirebaseUser?.uid {
                ActivityNotificationService.shared.startListening(forUserID: firebaseUID)
            }

            if authManager.userRole == .coach {
                // Coach-specific listeners
                if let coachID = authManager.currentFirebaseUser?.uid {
                    CoachFolderArchiveManager.shared.configure(coachUID: coachID)
                    SharedFolderManager.shared.startCoachFoldersListener(coachID: coachID)
                }
                if let coachEmail = authManager.currentFirebaseUser?.email?.lowercased() {
                    CoachInvitationManager.shared.startInvitationsListener(forCoachEmail: coachEmail)
                }
            } else {
                // Athlete-specific services — coaches don't have athletes/videos to sync
                SyncCoordinator.shared.configure(modelContext: modelContext)
                UploadQueueManager.shared.configure(modelContext: modelContext)
                QuickActionsManager.shared.setupQuickActions()

                // Start athlete invitation listener so invitations are visible on all tabs
                if let athleteEmail = authManager.currentFirebaseUser?.email?.lowercased() {
                    AthleteInvitationManager.shared.startInvitationsListener(forAthleteEmail: athleteEmail)
                }

                // Run migration, recovery, and sync in background
                Task(priority: .utility) {
                    do {
                        try await ClipPersistenceService().migrateVideosToDocuments(context: modelContext)
                    } catch {
                        // Don't block app launch on migration failure
                    }

                    let athletes = (currentUser?.athletes ?? [])
                    await OrphanedClipRecoveryService.shared.recoverIfNeeded(
                        context: modelContext,
                        athletes: athletes
                    )

                    if let user = currentUser, user.firebaseAuthUid != nil {
                        do {
                            try await SyncCoordinator.shared.syncAll(for: user)
                        } catch {
                            ErrorHandlerService.shared.handle(error, context: "AuthenticatedFlow.initialSync", showAlert: false)
                        }
                    }
                }
            }
        }
    }
    
    // Single source of truth: UserDefaults via authManager (device-local, always available).
    // SwiftData OnboardingProgress is kept for backward compatibility but not used for routing.
    private var hasCompletedOnboarding: Bool {
        authManager.hasCompletedOnboarding
    }
    
    private func loadUser() async {
        defer { isLoading = false }

        guard let authUser = authManager.currentFirebaseUser,
              let rawEmail = authUser.email else {
            return
        }
        
        // Check for cancellation early
        guard !Task.isCancelled else {
            return
        }
        
        // Attach model context to auth manager for consistency
        authManager.attachModelContext(modelContext)
        
        let email = rawEmail.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        log.debug("Looking up user with email: \(email, privacy: .private)")
        
        // Find or create user
        if let existingUser = users.first(where: { $0.email == email }) {
            // If the SwiftData record has a Firebase UID that differs from the current
            // auth session (e.g. account was deleted and re-created with the same email),
            // treat this as a new account to prevent data from leaking across sessions.
            if let storedUID = existingUser.firebaseAuthUid,
               !storedUID.isEmpty,
               storedUID != authUser.uid {
                log.warning("Email match but Firebase UID mismatch — treating as new account (stored: \(storedUID, privacy: .private), current: \(authUser.uid, privacy: .private))")
                guard !Task.isCancelled else { return }
                await createNewUser(authUser: authUser, email: email)
            } else {
            log.debug("Found existing user: \(existingUser.username, privacy: .private) (ID: \(existingUser.id, privacy: .private)) with \((existingUser.athletes ?? []).count) athletes")

            // Check cancellation before updating state
            guard !Task.isCancelled else {
                return
            }

            currentUser = existingUser
            
            await MainActor.run {
                if let refreshedByEmail = users.first(where: { $0.email == email }) {
                    currentUser = refreshedByEmail
                    log.debug("Using persisted user by email: \(refreshedByEmail.username, privacy: .private) | athletes: \((refreshedByEmail.athletes ?? []).count)")
                } else if let refreshedByID = users.first(where: { $0.id == existingUser.id }) {
                    currentUser = refreshedByID
                    log.debug("Fallback persisted user by id: \(refreshedByID.username, privacy: .private) | athletes: \((refreshedByID.athletes ?? []).count)")
                } else {
                    log.warning("Could not re-fetch persisted user; using in-memory instance")
                }
            }
            } // end UID-match else
        } else {
            log.info("Creating new user")
            
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
            log.info("Successfully created new user with ID: \(newUser.id, privacy: .private)")
            
            // Attach the model context to auth manager for future use
            authManager.attachModelContext(modelContext)
            
            // Re-fetch the newly created user from the store using normalized email to ensure we use the persisted instance
            await MainActor.run {
                if let refreshed = users.first(where: { $0.email == normalizedEmail }) {
                    currentUser = refreshed
                    log.debug("Using refreshed user: \(refreshed.id, privacy: .private)")
                } else {
                    currentUser = newUser
                    log.warning("Using original user instance: \(newUser.id, privacy: .private)")
                }
            }
        } catch {
            log.warning("Failed to save new user to SwiftData: \(error.localizedDescription)")
        }
    }
}
