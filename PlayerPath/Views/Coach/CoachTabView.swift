//
//  CoachTabView.swift
//  PlayerPath
//
//  Root tab bar view for coaches. Mirrors MainTabView for athletes
//  with four tabs: Dashboard, Athletes, Recordings, Profile.
//

import SwiftUI

struct CoachTabView: View {
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @EnvironmentObject private var sharedFolderManager: SharedFolderManager
    @State private var coordinator = CoachNavigationCoordinator()
    @ObservedObject private var invitationManager = CoachInvitationManager.shared
    @ObservedObject private var activityNotifService = ActivityNotificationService.shared
    @StateObject private var notificationManager = NotificationObserverManager()
    @State private var hasRunInitialSetup = false

    var body: some View {
        TabView(selection: Binding(
            get: { coordinator.selectedTab.rawValue },
            set: { if let tab = CoachTab(rawValue: $0) { coordinator.selectedTab = tab } }
        )) {
            dashboardTab
            athletesTab
            recordingsTab
            profileTab
        }
        .tint(.green)
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
    }

    private var recordingsTab: some View {
        NavigationStack {
            CoachRecordingsTab()
        }
        .tabItem {
            Label(CoachTab.recordings.title, systemImage: CoachTab.recordings.icon)
        }
        .tag(CoachTab.recordings.rawValue)
    }

    private var profileTab: some View {
        NavigationStack {
            CoachProfileView()
        }
        .tabItem {
            Label(CoachTab.profile.title, systemImage: CoachTab.profile.icon)
        }
        .tag(CoachTab.profile.rawValue)
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

        notificationManager.observe(name: .navigateToCoachRecordings) { _ in
            MainActor.assumeIsolated {
                coordinator.navigateToRecordings()
                Haptics.light()
            }
        }
    }
}
