//
//  CoachTabView.swift
//  PlayerPath
//
//  Root tab bar view for coaches. Mirrors MainTabView for athletes
//  with three tabs: Dashboard, Athletes, Profile.
//

import SwiftUI

struct CoachTabView: View {
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    private var sharedFolderManager: SharedFolderManager { .shared }
    private var downgradeManager: CoachDowngradeManager { .shared }
    @State private var coordinator = CoachNavigationCoordinator()
    private var invitationManager: CoachInvitationManager { .shared }
    @ObservedObject private var activityNotifService = ActivityNotificationService.shared
    @StateObject private var notificationManager = NotificationObserverManager()
    @State private var hasRunInitialSetup = false
    @State private var showDowngradeSelection = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var athletesTabBadge: Int {
        activityNotifService.unreadFolderVideoCount + invitationManager.pendingInvitationsCount
    }

    var body: some View {
        tabViewContent
        .tint(.brandNavy)
        .task {
            coordinator.restoreSelectedTab()
            setupNotificationObservers()

            guard !hasRunInitialSetup else { return }
            hasRunInitialSetup = true

            // Configure archive manager
            if let coachID = authManager.userID {
                CoachFolderArchiveManager.shared.configure(coachUID: coachID)
                await downgradeManager.evaluate(coachID: coachID, coachTier: authManager.currentCoachTier)
            }

            AnalyticsService.shared.trackScreenView(
                screenName: coordinator.selectedTab.title,
                screenClass: "CoachTabView"
            )
        }
        .onChange(of: coordinator.selectedTab) { _, newTab in
            coordinator.saveSelectedTab()
            AnalyticsService.shared.trackScreenView(
                screenName: newTab.title,
                screenClass: "CoachTabView"
            )
        }
        .onChange(of: sharedFolderManager.coachFolders) { _, folders in
            coordinator.resolvePendingNavigation(folders: folders)
            // Re-evaluate downgrade state when folders change
            if let coachID = authManager.userID {
                Task { await downgradeManager.evaluate(coachID: coachID, coachTier: authManager.currentCoachTier) }
            }
        }
        .onChange(of: authManager.currentCoachTier) { _, _ in
            // Re-evaluate when coach tier changes (upgrade or downgrade)
            if let coachID = authManager.userID {
                Task { await downgradeManager.evaluate(coachID: coachID, coachTier: authManager.currentCoachTier) }
            }
        }
        .fullScreenCover(isPresented: $showDowngradeSelection) {
            if let coachID = authManager.userID {
                CoachDowngradeSelectionView(coachID: coachID)
                    .environmentObject(authManager)
            }
        }
        .onChange(of: downgradeManager.state) { _, newState in
            showDowngradeSelection = newState == .selectionRequired
        }
        .environment(coordinator)
        .addKeyboardShortcuts()
    }

    // MARK: - Tab View Content

    @ViewBuilder
    private var tabViewContent: some View {
        VStack(spacing: 0) {
            downgradeGraceBanner
            if #available(iOS 18.0, *), horizontalSizeClass == .regular {
                TabView(selection: Binding(
                    get: { coordinator.selectedTab.rawValue },
                    set: { if let tab = CoachTab(rawValue: $0) { coordinator.selectedTab = tab } }
                )) {
                    dashboardTab
                    athletesTab
                    profileTab
                }
                .tabViewStyle(.sidebarAdaptable)
            } else {
                TabView(selection: Binding(
                    get: { coordinator.selectedTab.rawValue },
                    set: { if let tab = CoachTab(rawValue: $0) { coordinator.selectedTab = tab } }
                )) {
                    dashboardTab
                    athletesTab
                    profileTab
                }
            }
        }
    }

    // MARK: - Downgrade Grace Banner

    @ViewBuilder
    private var downgradeGraceBanner: some View {
        if case .gracePeriod(let daysRemaining) = downgradeManager.state {
            CoachDowngradeGraceBanner(
                daysRemaining: daysRemaining,
                connectedCount: downgradeManager.connectedCount,
                limit: downgradeManager.currentLimit
            )
            .padding(.top, 4)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Tabs

    private var dashboardTab: some View {
        NavigationStack(path: $coordinator.dashboardPath) {
            CoachDashboardView()
        }
        .tabItem {
            Label(CoachTab.dashboard.title, systemImage: CoachTab.dashboard.icon)
        }
        .tag(CoachTab.dashboard.rawValue)
        .badge(activityNotifService.unreadCount > 0 ? activityNotifService.unreadCount : 0)
        .accessibilityLabel("Home tab")
        .accessibilityHint("View your dashboard and quick actions")
    }

    private var athletesTab: some View {
        NavigationStack(path: $coordinator.athletesPath) {
            CoachAthletesTab()
                .navigationDestination(for: SharedFolder.self) { folder in
                    CoachFolderDetailView(folder: folder)
                }
        }
        .tabItem {
            Label(CoachTab.athletes.title, systemImage: CoachTab.athletes.icon)
        }
        .tag(CoachTab.athletes.rawValue)
        .badge(athletesTabBadge)
        .accessibilityLabel("Athletes tab")
        .accessibilityHint("View and manage connected athletes")
    }

    private var profileTab: some View {
        NavigationStack {
            CoachProfileView()
        }
        .tabItem {
            Label(CoachTab.profile.title, systemImage: CoachTab.profile.icon)
        }
        .tag(CoachTab.profile.rawValue)
        .accessibilityLabel("More tab")
        .accessibilityHint("Access settings, invitations, and account")
    }

    // MARK: - Notification Observers

    private func setupNotificationObservers() {
        notificationManager.cleanup()

        notificationManager.observe(name: .navigateToCoachFolder) { note in
            MainActor.assumeIsolated {
                if let folderID = note.object as? String {
                    coordinator.navigateToFolder(folderID, folders: sharedFolderManager.coachFolders)
                }
            }
        }

        notificationManager.observe(name: .openCoachInvitations) { _ in
            MainActor.assumeIsolated {
                coordinator.navigateToInvitations()
            }
        }

        notificationManager.observe(name: .switchCoachTab) { note in
            MainActor.assumeIsolated {
                if let rawValue = note.object as? Int,
                   let tab = CoachTab(rawValue: rawValue) {
                    coordinator.selectedTab = tab
                    Haptics.light()
                }
            }
        }

    }
}
