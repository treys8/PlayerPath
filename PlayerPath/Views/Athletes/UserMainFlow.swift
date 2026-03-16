//
//  UserMainFlow.swift
//  PlayerPath
//
//  Extracted from MainAppView.swift
//

import SwiftUI
import SwiftData

struct UserMainFlow: View {
    let user: User
    let isNewUserFlag: Bool
    let hasCompletedOnboarding: Bool
    @Query(sort: \Athlete.createdAt) private var allAthletes: [Athlete]
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @ObservedObject private var sharedFolderManager = SharedFolderManager.shared
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
                CoachDashboardView()
                    .environmentObject(sharedFolderManager)
                    .onAppear {
                    }
            }
            // Show athlete selection if user explicitly requested it via "Manage Athletes"
            else if showingAthleteSelection {
                AthleteSelectionView(
                    user: user,
                    selectedAthlete: $selectedAthlete,
                    authManager: authManager
                )
                .onChange(of: selectedAthlete) { _, newValue in
                    // Reset the flag when an athlete is selected
                    if newValue != nil {
                        showingAthleteSelection = false
                    }
                }
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
                .onAppear {
                }
            } else if athletesForUser.count > 1 {
                AthleteSelectionView(
                    user: user,
                    selectedAthlete: $selectedAthlete,
                    authManager: authManager
                )
            } else if athletesForUser.isEmpty && isNewUserFlag {
                // New athletes need to create their first athlete profile
                // Show AddAthleteView directly (not FirstAthleteCreationView → AthleteSelectionView)
                // to avoid asking for athlete creation twice
                AddAthleteView(
                    user: user,
                    selectedAthlete: $selectedAthlete,
                    isFirstAthlete: true
                )
            } else {
                // Fallback: show athlete selection
                AthleteSelectionView(
                    user: user,
                    selectedAthlete: $selectedAthlete,
                    authManager: authManager
                )
            }
        }
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
            #if DEBUG
            print("🟡 Athletes changed for user \(user.id) (\(user.email)): \(newValue.count) athletes")
            for athlete in newValue {
                print("  - \(athlete.name) (ID: \(athlete.id), User: \(athlete.user?.email ?? "None"))")
            }
            #endif

            // If a new athlete was created and we now have 2+ athletes, the newest one should already be selected
            // If exactly one athlete exists and none is selected, select it.
            if selectedAthlete == nil, newValue.count == 1, let only = newValue.first {
                #if DEBUG
                print("🟢 Auto-selecting only athlete: \(only.name) (ID: \(only.id))")
                #endif
                selectedAthlete = only
                // Only show the toast if the initial restoration has already run.
                // Otherwise this fires on every app launch when @Query populates
                // before .task restores the saved selection.
                if hasRestoredSelection {
                    showCreationToast = true
                    Task {
                        try? await Task.sleep(nanoseconds: 1_200_000_000)
                        showCreationToast = false
                    }
                }
            } else if let current = selectedAthlete {
                #if DEBUG
                print("🟡 Athletes changed. Current selection: \(current.name) (ID: \(current.id))")
                #endif
            }
        }
        .task {
            // Use task modifier for automatic cancellation handling

            // Activity notification listener is now started in AuthenticatedFlow
            // before this view appears, so navigation is not blocked by Firestore setup.

            setupNotificationObservers()

            #if DEBUG
            print("🟡 UserMainFlow task - User: \(user.id), Athletes: \(athletesForUser.count)")
            #endif

            // Restore last selected athlete from persistence
            if selectedAthlete == nil {
                if let savedID = lastSelectedAthleteID,
                   let savedUUID = UUID(uuidString: savedID),
                   let savedAthlete = athletesForUser.first(where: { $0.id == savedUUID }) {
                    #if DEBUG
                    print("🟢 Restoring saved athlete: \(savedAthlete.name) (ID: \(savedAthlete.id))")
                    #endif
                    selectedAthlete = savedAthlete
                } else if athletesForUser.count == 1, let only = athletesForUser.first {
                    #if DEBUG
                    print("🟢 Task auto-selecting athlete: \(only.name) (ID: \(only.id))")
                    #endif
                    selectedAthlete = only
                }
            }
            hasRestoredSelection = true
        }
        .onChange(of: selectedAthlete) { _, newValue in
            // Persist athlete selection
            if let athlete = newValue {
                lastSelectedAthleteID = athlete.id.uuidString
                #if DEBUG
                print("💾 Saved athlete selection: \(athlete.name) (ID: \(athlete.id))")
                #endif
            } else {
                lastSelectedAthleteID = nil
            }
        }
        .onChange(of: quickActionsManager.selectedQuickAction) { _, newAction in
            // Execute quick action when it changes
            if let action = newAction {
                #if DEBUG
                print("🎯 UserMainFlow - Executing quick action: \(action.title)")
                #endif
                quickActionsManager.executeAction(action)
            }
        }
    }

    // MARK: - Activity Notification Tap Handling

    private func handleActivityNotificationTap(_ notification: ActivityNotification) {
        switch notification.type {
        case .invitationAccepted, .coachComment, .newVideo:
            // Navigate to the More tab where Shared Folders lives
            postSwitchTab(.more)
        case .invitationReceived:
            // Athlete shouldn't normally receive this (coaches do), but handle gracefully
            postSwitchTab(.more)
        case .accessRevoked:
            // Informational only — no navigation target
            break
        }

        // Mark as read
        if let notifID = notification.id, let userID = authManager.userID {
            Task {
                await activityNotifService.markRead(notifID, forUserID: userID)
            }
        }
    }

    // MARK: - NotificationCenter Management

    private func setupNotificationObservers() {
        // Clean up any existing observers first (safety)
        notificationManager.cleanup()

        notificationManager.observe(name: Notification.Name.showAthleteSelection) { _ in
            MainActor.assumeIsolated {
                selectedAthlete = nil
                showingAthleteSelection = true
            }
        }
    }
}
