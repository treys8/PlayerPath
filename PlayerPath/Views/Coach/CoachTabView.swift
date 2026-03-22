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
    @State private var coordinator = CoachNavigationCoordinator()
    private var invitationManager: CoachInvitationManager { .shared }
    @ObservedObject private var activityNotifService = ActivityNotificationService.shared
    @StateObject private var notificationManager = NotificationObserverManager()
    @State private var hasRunInitialSetup = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

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
        }
        .environment(coordinator)
        .addKeyboardShortcuts()
    }

    // MARK: - Tab View Content

    @ViewBuilder
    private var tabViewContent: some View {
        if horizontalSizeClass == .regular {
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
        .badge(invitationManager.pendingInvitationsCount > 0 ? invitationManager.pendingInvitationsCount : 0)
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
