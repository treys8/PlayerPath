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
    @State private var showingCoachPaywall = false
    /// Fallback-path permission primer. CoachOnboardingFlow's last page already
    /// primes a fresh signup; this covers a returning coach on a new device.
    @State private var showingNotificationPrimer = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    /// The ONE coach recorder owner: the Dashboard's live card and the iOS 26.1+
    /// Live Now accessory both open the camera through it, presented here.
    @State private var liveSession = CoachLiveSessionController()
    private var sessionManager: CoachSessionManager { .shared }

    /// The session the Live Now accessory surfaces — live only. A reviewing
    /// session has nothing to record into; its Dashboard card handles it.
    private var liveCoachSession: CoachSession? {
        guard let session = sessionManager.activeSession, session.status == .live else { return nil }
        return session
    }

    private var athletesTabBadge: Int {
        activityNotifService.unreadFolderVideoCount + invitationManager.pendingInvitationsCount
    }

    var body: some View {
        tabViewContent
        .tint(.brandNavy)
        .task {
            coordinator.restoreSelectedTab()
            setupNotificationObservers()
            // Now that observers are live, replay any cold-launch notification tap
            // that arrived in scene(willConnectTo:) before this tab bar mounted.
            PushNotificationService.shared.replayPendingLaunchNotification()

            guard !hasRunInitialSetup else { return }
            hasRunInitialSetup = true

            // Coaches who never visit Profile → Notifications would otherwise stay
            // .notDetermined, never register for APNs/FCM, and silently drop every
            // server push. A fresh signup was primed by CoachOnboardingFlow's last
            // page and answered the dialog on the way in, so this only presents for
            // a coach whose onboarding is behind them — a new device or a reinstall.
            if await NotificationPermissionPrimer.shouldPresent() {
                showingNotificationPrimer = true
            }

            // Configure archive manager
            if let coachID = authManager.userID {
                CoachFolderArchiveManager.shared.configure(coachUID: coachID)
                await downgradeManager.evaluate(coachID: coachID,
                                                coachTier: authManager.currentCoachTier,
                                                serverGraceStartedAt: authManager.userProfile?.coachDowngradeGraceStartedAt,
                                                serverUnresolved: authManager.userProfile?.downgradeUnresolved ?? false)
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
            if let coachID = authManager.userID {
                Task {
                    if newTab == .dashboard {
                        await ActivityNotificationService.shared.markDashboardNotificationsRead(forUserID: coachID)
                    } else if newTab == .athletes {
                        // Only mark invitation-type notifications read — switching to
                        // the Athletes tab implies the coach has seen any pending
                        // invitations listed there. Per-folder unread badges are
                        // preserved and cleared individually when the coach opens
                        // each folder (see CoachFolderDetailView).
                        await ActivityNotificationService.shared.markInvitationNotificationsRead(forUserID: coachID)
                    }
                }
            }
        }
        .onChange(of: sharedFolderManager.coachFolders) { _, folders in
            coordinator.resolvePendingNavigation(folders: folders)
            // Re-evaluate downgrade state when folders change
            if let coachID = authManager.userID {
                Task { await downgradeManager.evaluate(coachID: coachID,
                                                coachTier: authManager.currentCoachTier,
                                                serverGraceStartedAt: authManager.userProfile?.coachDowngradeGraceStartedAt,
                                                serverUnresolved: authManager.userProfile?.downgradeUnresolved ?? false) }
            }
        }
        .onChange(of: authManager.currentCoachTier) { _, _ in
            // Re-evaluate when coach tier changes (upgrade or downgrade)
            if let coachID = authManager.userID {
                Task { await downgradeManager.evaluate(coachID: coachID,
                                                coachTier: authManager.currentCoachTier,
                                                serverGraceStartedAt: authManager.userProfile?.coachDowngradeGraceStartedAt,
                                                serverUnresolved: authManager.userProfile?.downgradeUnresolved ?? false) }
            }
        }
        .onChange(of: authManager.userProfile?.downgradeUnresolved) { _, _ in
            // The daily audit flips downgradeUnresolved server-side; re-evaluate when
            // the refreshed profile surfaces it so the resolve banner + feedback block
            // engage without needing a folder or tier change first.
            if let coachID = authManager.userID {
                Task { await downgradeManager.evaluate(coachID: coachID,
                                                coachTier: authManager.currentCoachTier,
                                                serverGraceStartedAt: authManager.userProfile?.coachDowngradeGraceStartedAt,
                                                serverUnresolved: authManager.userProfile?.downgradeUnresolved ?? false) }
            }
        }
        // Opened on demand from the resolve banner (no longer auto-forced) — the
        // coach can dismiss and keep viewing; feedback stays blocked server-side
        // until they actually shed or upgrade.
        .sheet(isPresented: $showDowngradeSelection) {
            if let coachID = authManager.userID {
                CoachDowngradeSelectionView(coachID: coachID)
                    .environmentObject(authManager)
            }
        }
        // Coach-side observer for .showSubscriptionPaywall. The athlete tab bar
        // (MainTabView) is the only other observer and isn't mounted for coaches,
        // so without this the over-limit "View Plans" button is a no-op.
        .sheet(isPresented: $showingCoachPaywall) {
            CoachPaywallView()
                .environmentObject(authManager)
        }
        .sheet(isPresented: $showingNotificationPrimer) {
            NotificationPermissionPrimer(isCoach: true) {
                showingNotificationPrimer = false
            }
        }
        .fullScreenCover(item: $liveSession.cameraContext) { context in
            DirectCameraRecorderView(coachContext: context)
        }
        .onChange(of: liveSession.cameraContext == nil) { _, becameNil in
            guard becameNil, let coachID = authManager.userID else { return }
            Task { await sessionManager.fetchSessions(coachID: coachID) }
        }
        .onChange(of: sessionManager.activeSession) { _, newValue in
            // Dismiss the recorder if the session was ended/completed externally.
            // Only while active: backgrounding tears the listener down and nils
            // activeSession (AuthenticatedFlow → stopListeningActiveSession), and
            // that must not throw away a clip mid-flow when the coach locks the
            // phone between reps.
            if newValue == nil, scenePhase == .active { liveSession.cameraContext = nil }
        }
        .environment(coordinator)
        .environment(liveSession)
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
                .ppTabBarMinimizesOnScroll()
                .modifier(LiveNowAccessoryModifier(isEnabled: liveCoachSession != nil) {
                    if #available(iOS 26.1, *) { coachLiveAccessory }
                })
            }
        }
    }

    // MARK: - Live Now accessory

    @available(iOS 26.1, *)
    @ViewBuilder
    private var coachLiveAccessory: some View {
        if let session = liveCoachSession {
            LiveNowAccessory(
                title: session.athleteNamesSummary,
                actionTitle: "Record",
                actionIcon: "video.fill",
                // Abandoned sessions auto-end at 24 h (cleanupAbandonedSessions),
                // so the bar never needs the "Still playing?" state or its End.
                staleAt: nil,
                openHint: "Opens the Dashboard",
                isEnding: false,
                onOpen: { coordinator.selectedTab = .dashboard },
                onAction: { liveSession.recordIntoActiveSession() },
                onEnd: {}
            )
        }
    }

    // MARK: - Downgrade Grace Banner

    @ViewBuilder
    private var downgradeGraceBanner: some View {
        switch downgradeManager.state {
        case .gracePeriod(let daysRemaining):
            CoachDowngradeGraceBanner(
                daysRemaining: daysRemaining,
                connectedCount: downgradeManager.connectedCount,
                limit: downgradeManager.currentLimit
            )
            .padding(.top, 4)
            .transition(.move(edge: .top).combined(with: .opacity))
        case .selectionRequired:
            // Grace expired and still over limit. Feedback delivery is blocked
            // server-side (firestore.rules), but viewing stays open — so this is a
            // persistent banner, not the old non-dismissable full-screen blocker.
            CoachDowngradeResolveBanner(
                connectedCount: downgradeManager.connectedCount,
                limit: downgradeManager.currentLimit,
                onChooseAthletes: { showDowngradeSelection = true }
            )
            .padding(.top, 4)
            .transition(.move(edge: .top).combined(with: .opacity))
        case .none:
            EmptyView()
        }
    }

    // MARK: - Tabs

    private var dashboardTab: some View {
        NavigationStack {
            CoachDashboardView()
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        NotificationBellToolbarButton()
                    }
                }
        }
        .tabItem {
            Label(CoachTab.dashboard.title, systemImage: CoachTab.dashboard.icon)
        }
        .tag(CoachTab.dashboard.rawValue)
        .badge(activityNotifService.unreadCount > 0 ? activityNotifService.unreadCount : 0)
        .accessibilityLabel("Dashboard tab")
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
        // Bind the path so the coordinator can deep-link straight to the
        // invitations list (push / inbox taps) instead of dropping the coach
        // on the More root. CoachProfileView owns the navigationDestination.
        NavigationStack(path: $coordinator.profilePath) {
            CoachProfileView()
        }
        .tabItem {
            Label(CoachTab.more.title, systemImage: CoachTab.more.icon)
        }
        .tag(CoachTab.more.rawValue)
        .accessibilityLabel("More tab")
        .accessibilityHint("Access settings, invitations, and account")
    }

    // MARK: - Notification Observers

    private func setupNotificationObservers() {
        notificationManager.cleanup()

        // Hop to the main actor via Task instead of MainActor.assumeIsolated —
        // some posters (PushNotificationService) can fire from non-main threads
        // and assumeIsolated would trap.
        notificationManager.observe(name: .navigateToCoachFolder) { note in
            let folderID = note.object as? String
            let videoID = note.userInfo?["videoID"] as? String
            Task { @MainActor in
                guard let folderID else { return }
                coordinator.navigateToFolder(folderID, folders: sharedFolderManager.coachFolders, targetVideoID: videoID)
            }
        }

        notificationManager.observe(name: .openInvitations) { _ in
            Task { @MainActor in
                coordinator.navigateToInvitations()
            }
        }

        notificationManager.observe(name: .showSubscriptionPaywall) { _ in
            Task { @MainActor in
                showingCoachPaywall = true
            }
        }

        notificationManager.observe(name: .switchCoachTab) { note in
            let rawValue = note.object as? Int
            Task { @MainActor in
                if let rawValue, let tab = CoachTab(rawValue: rawValue) {
                    coordinator.selectedTab = tab
                    Haptics.light()
                }
            }
        }
    }
}
