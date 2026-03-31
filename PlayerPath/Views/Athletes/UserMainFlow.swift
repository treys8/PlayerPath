//
//  UserMainFlow.swift
//  PlayerPath
//
//  Extracted from MainAppView.swift
//

import SwiftUI
import SwiftData
import os

private let log = Logger(subsystem: "com.playerpath.app", category: "UserMainFlow")

struct UserMainFlow: View {
    let user: User
    let isNewUserFlag: Bool
    let hasCompletedOnboarding: Bool
    @Query(sort: \Athlete.createdAt) private var allAthletes: [Athlete]
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    private var sharedFolderManager: SharedFolderManager { .shared }
    @State private var selectedAthlete: Athlete?
    @State private var showCreationToast = false
    @State private var showingAthleteSelection = false
    @State private var hasRestoredSelection = false
    private let userID: UUID

    // NotificationCenter observer management using StateObject
    @StateObject private var notificationManager = NotificationObserverManager()

    // Activity notification service (Firestore-backed in-app notifications)
    @ObservedObject private var activityNotifService = ActivityNotificationService.shared

    // Quick Actions manager
    @ObservedObject private var quickActionsManager = QuickActionsManager.shared

    // Coach announcement
    @ObservedObject private var onboardingManager = OnboardingManager.shared
    @State private var showingCoachAnnouncement = false

    // Onboarding (tutorial shown from MainTabView after setup is complete)

    init(user: User, isNewUserFlag: Bool, hasCompletedOnboarding: Bool) {
        self.user = user
        self.isNewUserFlag = isNewUserFlag
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.userID = user.id
    }

    // Helper for athlete selection persistence (user-specific)
    private var lastSelectedAthleteID: String? {
        get {
            UserDefaults.standard.string(forKey: "lastSelectedAthleteID_\(userID.uuidString)")
        }
        nonmutating set {
            if let value = newValue {
                UserDefaults.standard.set(value, forKey: "lastSelectedAthleteID_\(userID.uuidString)")
            } else {
                UserDefaults.standard.removeObject(forKey: "lastSelectedAthleteID_\(userID.uuidString)")
            }
        }
    }

    private var athletesForUser: [Athlete] {
        // Filter safely in Swift to avoid force unwrap in predicate
        allAthletes.filter { athlete in
            athlete.user?.id == userID
        }
    }

    private var resolvedAthlete: Athlete? {
        selectedAthlete ?? athletesForUser.first
    }

    var body: some View {
        Group {
            // IMPORTANT: Check if user is a coach FIRST before any athlete logic
            if authManager.userRole == .coach {
                CoachTabView()
                    .onAppear {
                    }
            }
            // Show athlete selection if user explicitly requested it via "Manage Athletes"
            else if showingAthleteSelection {
                AthleteSelectionView(
                    user: user,
                    selectedAthlete: $selectedAthlete,
                    authManager: authManager,
                    onDismiss: {
                        showingAthleteSelection = false
                    }
                )
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
            // After athlete exists but no seasons - show season creation
            else if let athlete = resolvedAthlete,
                    isNewUserFlag,
                    (athlete.seasons ?? []).isEmpty {
                OnboardingSeasonCreationView(athlete: athlete)
                    .onAppear {
                    }
            }
            // After season exists but still new user - show backup preference
            else if let athlete = resolvedAthlete,
                    isNewUserFlag,
                    !(athlete.seasons ?? []).isEmpty {
                OnboardingBackupView(athlete: athlete)
                    .onAppear {
                    }
            }
            // Only check athlete-related logic if user is an athlete
            else if let athlete = resolvedAthlete {
                MainTabView(
                    user: user,
                    selectedAthlete: Binding(
                        get: { selectedAthlete ?? athlete },
                        set: { selectedAthlete = $0 }
                    )
                )
                .fullScreenCover(isPresented: $showingCoachAnnouncement) {
                    CoachAnnouncementFlow(
                        athlete: selectedAthlete ?? athlete,
                        onDismiss: { showingCoachAnnouncement = false }
                    )
                    .environmentObject(authManager)
                }
                .onAppear {
                }
            } else if athletesForUser.isEmpty && isNewUserFlag {
                // New athletes need to create their first athlete profile
                AddAthleteView(
                    user: user,
                    selectedAthlete: $selectedAthlete,
                    isFirstAthlete: true
                )
            } else if athletesForUser.isEmpty && (SyncCoordinator.shared.isSyncing || (!isNewUserFlag && SyncCoordinator.shared.lastSyncDate == nil)) {
                // Returning user on new device — sync is downloading their athletes,
                // or sync hasn't started yet (lastSyncDate is nil).
                // Show loading instead of AddAthleteView to prevent duplicate creation.
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Syncing your data...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if athletesForUser.isEmpty {
                // Returning user with no athletes after sync finished — let them add one
                AddAthleteView(
                    user: user,
                    selectedAthlete: $selectedAthlete,
                    isFirstAthlete: true
                )
            } else {
                // Fallback: @Query hasn't populated yet — show loading briefly
                ProgressView("Loading athletes...")
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showingAthleteSelection)
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                if showCreationToast {
                    Text("Athlete created")
                        .font(.subheadline).bold()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.top, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showCreationToast)
                }
                if let banner = activityNotifService.incomingBanner {
                    ActivityNotificationBanner(notification: banner, onDismiss: {
                        if let notifID = banner.id, let userID = authManager.userID {
                            Task { await activityNotifService.markRead(notifID, forUserID: userID) }
                        }
                        activityNotifService.dismissBanner()
                    }, onTap: {
                        handleActivityNotificationTap(banner)
                    })
                    .padding(.top, showCreationToast ? 0 : 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: activityNotifService.incomingBanner?.id)
                }
            }
        }
        .onChange(of: athletesForUser) { _, newValue in
            log.debug("Athletes changed for user \(user.id, privacy: .private) (\(user.email, privacy: .private)): \(newValue.count) athletes")
            for athlete in newValue {
                log.debug("  - \(athlete.name) (ID: \(athlete.id, privacy: .private), User: \(athlete.user?.email ?? "None", privacy: .private))")
            }

            // Clear selection if the selected athlete was deleted
            if let current = selectedAthlete, !newValue.contains(where: { $0.id == current.id }) {
                selectedAthlete = nil
            }

            // If a new athlete was created and we now have 2+ athletes, the newest one should already be selected
            // If exactly one athlete exists and none is selected, select it.
            if selectedAthlete == nil, newValue.count == 1, let only = newValue.first {
                log.debug("Auto-selecting only athlete: \(only.name) (ID: \(only.id, privacy: .private))")
                selectedAthlete = only
                // Only show the toast if the initial restoration has already run.
                // Otherwise this fires on every app launch when @Query populates
                // before .task restores the saved selection.
                if hasRestoredSelection {
                    showCreationToast = true
                    Task {
                        try? await Task.sleep(for: .milliseconds(1200))
                        showCreationToast = false
                    }
                }
            } else if let current = selectedAthlete {
                log.debug("Athletes changed. Current selection: \(current.name) (ID: \(current.id, privacy: .private))")
            }
        }
        .onAppear {
            setupNotificationObservers()
        }
        .task {
            log.debug("UserMainFlow task - User: \(user.id, privacy: .private), Athletes: \(athletesForUser.count)")

            // Restore last selected athlete from persistence
            if selectedAthlete == nil {
                if let savedID = lastSelectedAthleteID,
                   let savedUUID = UUID(uuidString: savedID),
                   let savedAthlete = athletesForUser.first(where: { $0.id == savedUUID }) {
                    log.debug("Restoring saved athlete: \(savedAthlete.name) (ID: \(savedAthlete.id, privacy: .private))")
                    selectedAthlete = savedAthlete
                } else if athletesForUser.count == 1, let only = athletesForUser.first {
                    log.debug("Task auto-selecting athlete: \(only.name) (ID: \(only.id, privacy: .private))")
                    selectedAthlete = only
                }
            }
            // Ensure SyncCoordinator knows which athlete to prioritise on launch
            if let athlete = selectedAthlete ?? athletesForUser.first {
                SyncCoordinator.shared.activeAthleteID = athlete.id.uuidString
            }
            hasRestoredSelection = true

            // Show coach announcement for existing athletes after coach features are enabled
            if onboardingManager.shouldShowCoachAnnouncement
               && authManager.userRole == .athlete {
                showingCoachAnnouncement = true
            }
        }
        .onChange(of: selectedAthlete) { _, newValue in
            // Persist athlete selection
            if let athlete = newValue {
                lastSelectedAthleteID = athlete.id.uuidString
                SyncCoordinator.shared.activeAthleteID = athlete.id.uuidString
                log.debug("Saved athlete selection: \(athlete.name) (ID: \(athlete.id, privacy: .private))")
            } else {
                lastSelectedAthleteID = nil
                SyncCoordinator.shared.activeAthleteID = nil
            }
        }
        .onChange(of: quickActionsManager.selectedQuickAction) { _, newAction in
            // Execute quick action when it changes
            if let action = newAction {
                log.info("Executing quick action: \(action.title)")
                quickActionsManager.executeAction(action)
            }
        }
    }

    // MARK: - Activity Notification Tap Handling

    private func handleActivityNotificationTap(_ notification: ActivityNotification) {
        switch notification.type {
        case .coachComment, .newVideo:
            // Deep link to the specific shared folder if we have a folderID
            if let folderID = notification.folderID {
                NotificationCenter.default.post(name: .navigateToSharedFolder, object: folderID)
            } else {
                postSwitchTab(.more)
            }
        case .invitationAccepted:
            postSwitchTab(.more)
        case .invitationReceived:
            // Athlete shouldn't normally receive this (coaches do), but handle gracefully
            postSwitchTab(.more)
        case .accessRevoked, .accessLapsed:
            // Informational only — no navigation target
            break
        }

        // Mark-read is handled by the banner's onDismiss closure
    }

    // MARK: - NotificationCenter Management

    private func setupNotificationObservers() {
        // Clean up any existing observers first (safety)
        notificationManager.cleanup()

        notificationManager.observe(name: Notification.Name.showAthleteSelection) { _ in
            MainActor.assumeIsolated {
                showingAthleteSelection = true
            }
        }
    }
}
