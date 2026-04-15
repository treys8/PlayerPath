//
//  MainTabView.swift
//  PlayerPath
//
//  Extracted from MainAppView.swift
//

import SwiftUI
import SwiftData

struct MainTabView: View {
    let user: User
    @Binding var selectedAthlete: Athlete
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @State private var selectedTab: Int = MainTab.home.rawValue
    @State private var hideFloatingRecordButton = false
    @State private var showingSeasons = false
    @State private var showingCoaches = false
    @State private var showingCoachVideos = false
    @State private var showingWelcomeTutorial = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase

    // More tab programmatic navigation
    @State private var morePath = NavigationPath()

    // Onboarding milestone tracking
    @ObservedObject private var onboardingManager = OnboardingManager.shared
    @State private var hasRunInitialSetup = false

    // Athlete downgrade detection (shared folders + Pro lapse)
    private var athleteDowngradeManager: AthleteDowngradeManager { .shared }

    // Global paywall triggered by notification from any tab
    @State private var showingPaywall = false

    // Swipe gesture tracking
    @GestureState private var dragOffset: CGFloat = 0
    @State private var tabTransition: AnyTransition = .identity

    // Per-tab athlete IDs — only the active tab updates on athlete switch,
    // inactive tabs defer until selected (avoids rebuilding all 5 tabs at once).
    @State private var homeAthleteID: UUID?
    @State private var gamesAthleteID: UUID?
    @State private var videosAthleteID: UUID?
    @State private var statsAthleteID: UUID?

    enum MoreDestination: Hashable {
        case practice, highlights, seasons, photos, coaches, sharedFolders
        case sharedFolder(String) // navigate to a specific folder by ID
    }
    
    // NotificationCenter observer management using StateObject for lifecycle safety
    @StateObject private var notificationManager = NotificationObserverManager()

    private func applyRecordedHitResult(_ info: [String: Any]) {
        guard let hitType = info["hitType"] as? String else { 
            return 
        }
        
        #if DEBUG
        print("⚾️ Recording hit result: \(hitType) for athlete: \(selectedAthlete.name)")
        #endif
        
        Task {
            StatisticsHelpers.record(hitType: hitType, for: selectedAthlete, in: modelContext)
        }
        
        // Provide haptic feedback for successful stat recording
        Haptics.success()
    }
    
    // MARK: - Dashboard actions
    private func toggleGameLive(_ game: Game) {
        Haptics.light()
        game.isLive.toggle()
        Task { do { try modelContext.save() } catch { ErrorHandlerService.shared.handle(error, context: "MainTabView.toggleGameLive", showAlert: false) } }
    }

    // Removed toggleTournamentActive(_:) as tournaments are removed
    
    // MARK: - Tab Navigation Helpers
    
    private func navigateToTab(_ direction: SwipeDirection) {
        let maxTab = MainTab.more.rawValue
        var newTab = selectedTab

        switch direction {
        case .left:
            // Swipe left = next tab
            newTab = min(selectedTab + 1, maxTab)
        case .right:
            // Swipe right = previous tab
            newTab = max(selectedTab - 1, 0)
        }

        if newTab != selectedTab {
            Haptics.selection()
            withAnimation(.easeInOut(duration: 0.3)) {
                selectedTab = newTab
            }
        }
    }
    
    private enum SwipeDirection {
        case left, right
    }
    
    var body: some View {
        tabViewContent
            .tint(Color.brandNavy)
            .task {
                // Always restore tab and observers on appear
                restoreSelectedTab()
                setupNotificationObservers()

                // Eagerly set per-tab athlete IDs so they hold a non-nil value.
                // On subsequent athlete switches, only the active tab's ID updates;
                // inactive tabs keep the old ID until selected.
                // Uses ?? so each ID is initialized independently — safe even if
                // .onChange(of: selectedAthlete.id) fires before this .task.
                homeAthleteID = homeAthleteID ?? selectedAthlete.id
                gamesAthleteID = gamesAthleteID ?? selectedAthlete.id
                videosAthleteID = videosAthleteID ?? selectedAthlete.id
                statsAthleteID = statsAthleteID ?? selectedAthlete.id

                // Run heavy one-time setup only once per app launch
                guard !hasRunInitialSetup else { return }
                hasRunInitialSetup = true

                // Track initial screen view
                let initialScreen: String
                switch selectedTab {
                case MainTab.home.rawValue: initialScreen = "Dashboard"
                case MainTab.games.rawValue: initialScreen = "Games"
                case MainTab.videos.rawValue: initialScreen = "Videos"
                case MainTab.stats.rawValue: initialScreen = "Statistics"
                case MainTab.more.rawValue: initialScreen = "More"
                default: initialScreen = "Dashboard"
                }
                AnalyticsService.shared.trackScreenView(screenName: initialScreen, screenClass: "MainTabView")

                // Request notification permission (system dialog only shown once)
                if PushNotificationService.shared.authorizationStatus == .notDetermined {
                    _ = await PushNotificationService.shared.requestAuthorization()
                }
                // Schedule weekly summary notification with real stats for every athlete
                await WeeklySummaryScheduler.scheduleAll(for: user)

                // Show connected walkthrough for new users
                if !onboardingManager.hasSeenWelcomeTutorial {
                    showingWelcomeTutorial = true
                }

                // Evaluate athlete downgrade state
                athleteDowngradeManager.evaluate(tier: authManager.currentTier)
            }
            .onChange(of: selectedAthlete.id) { _, _ in
                // Only update the ACTIVE tab immediately; inactive tabs
                // refresh lazily via refreshStaleTab() when selected.
                refreshActiveTabAthleteID()
            }
            .onChange(of: authManager.currentTier) { _, newTier in
                athleteDowngradeManager.evaluate(tier: newTier)
            }
            .onChange(of: scenePhase) { _, phase in
                // Weekly summary body is baked in at schedule time — refresh on
                // every foreground so stats stay current across the week.
                if phase == .active {
                    Task(operation: { await WeeklySummaryScheduler.scheduleAll(for: user) })
                }
            }
            .onChange(of: selectedTab) { _, newValue in
                saveSelectedTab(newValue)
                // Rebuild the newly selected tab if its athlete is stale
                refreshStaleTab(newValue)
                // Track screen views for feature usage analytics
                let screenName: String
                switch newValue {
                case MainTab.home.rawValue: screenName = "Dashboard"
                case MainTab.games.rawValue: screenName = "Games"
                case MainTab.videos.rawValue: screenName = "Videos"
                case MainTab.stats.rawValue: screenName = "Statistics"
                case MainTab.more.rawValue: screenName = "More"
                default: screenName = "Unknown"
                }
                AnalyticsService.shared.trackScreenView(screenName: screenName, screenClass: "MainTabView")
                // Mark new-video notifications read when athlete opens Videos tab
                if newValue == MainTab.videos.rawValue, let userID = authManager.userID {
                    Task {
                        await ActivityNotificationService.shared.markNewVideoNotificationsRead(forUserID: userID)
                    }
                }
                // Reset when leaving Videos tab
                if newValue != MainTab.videos.rawValue {
                    hideFloatingRecordButton = false
                }
            }
            .sheet(isPresented: $showingSeasons) {
                NavigationStack {
                    SeasonsView(athlete: selectedAthlete)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") {
                                    showingSeasons = false
                                }
                            }
                        }
                }
            }
            .sheet(isPresented: $showingCoaches) {
                NavigationStack {
                    CoachesView(athlete: selectedAthlete)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") {
                                    showingCoaches = false
                                }
                            }
                        }
                }
            }
            .sheet(isPresented: $showingCoachVideos) {
                NavigationStack {
                    AthleteCoachVideosView(athlete: selectedAthlete)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") {
                                    showingCoachVideos = false
                                }
                            }
                        }
                }
            }
            .addKeyboardShortcuts()
            .sheet(isPresented: $showingWelcomeTutorial) {
                WelcomeTutorialView(
                    athleteName: selectedAthlete.name,
                    userEmail: authManager.userEmail ?? ""
                )
            }
            .sheet(isPresented: $showingPaywall) {
                ImprovedPaywallView(user: user)
            }
            .onReceive(NotificationCenter.default.publisher(for: .showSubscriptionPaywall)) { _ in
                showingPaywall = true
            }
    }
    
    /// Navigate to a More tab destination in a single transaction to avoid
    /// multiple NavigationRequestObserver updates per frame.
    private func navigateToMore(_ destination: MoreDestination) {
        var path = NavigationPath()
        path.append(destination)
        var transaction = Transaction()
        transaction.disablesAnimations = false
        withTransaction(transaction) {
            morePath = path
            selectedTab = MainTab.more.rawValue
        }
        Haptics.light()
    }

    // MARK: - NotificationCenter Management

    private func setupNotificationObservers() {
        // Clean up any existing observers first (safety)
        notificationManager.cleanup()

        notificationManager.observe(name: Notification.Name.switchTab) { notification in
            MainActor.assumeIsolated {
                if let index = notification.object as? Int {
                    selectedTab = index
                    Haptics.light()
                }
            }
        }

        notificationManager.observe(name: Notification.Name.switchAthlete) { notification in
            MainActor.assumeIsolated {
                if let athlete = notification.object as? Athlete {
                    #if DEBUG
                    print("🔄 Switching athlete to: \(athlete.name) (ID: \(athlete.id))")
                    #endif
                    selectedAthlete = athlete
                    Haptics.light()
                }
            }
        }

        notificationManager.observe(name: Notification.Name.presentVideoRecorder) { _ in
            MainActor.assumeIsolated {
                selectedTab = MainTab.videos.rawValue
                Haptics.light()
            }
        }

        notificationManager.observe(name: Notification.Name.recordedHitResult) { notification in
            MainActor.assumeIsolated {
                if let info = notification.object as? [String: Any] {
                    applyRecordedHitResult(info)
                }
            }
        }

        notificationManager.observe(name: Notification.Name.videosManageOwnControls) { notification in
            MainActor.assumeIsolated {
                if let flag = notification.object as? Bool {
                    hideFloatingRecordButton = flag
                }
            }
        }

        notificationManager.observe(name: Notification.Name.presentSeasons) { _ in
            MainActor.assumeIsolated {
                showingSeasons = true
                Haptics.light()
            }
        }

        notificationManager.observe(name: Notification.Name.presentCoaches) { _ in
            MainActor.assumeIsolated {
                showingCoaches = true
                Haptics.light()
            }
        }

        notificationManager.observe(name: Notification.Name.presentCoachVideos) { _ in
            MainActor.assumeIsolated {
                showingCoachVideos = true
                Haptics.light()
            }
        }

        notificationManager.observe(name: Notification.Name.navigateToMorePractice) { _ in
            MainActor.assumeIsolated { [self] in
                navigateToMore(.practice)
            }
        }

        notificationManager.observe(name: Notification.Name.navigateToMoreHighlights) { _ in
            MainActor.assumeIsolated { [self] in
                navigateToMore(.highlights)
            }
        }

        notificationManager.observe(name: Notification.Name.navigateToSharedFolder) { note in
            MainActor.assumeIsolated { [self] in
                if let folderID = note.object as? String {
                    navigateToMore(.sharedFolder(folderID))
                }
            }
        }

        // Refresh the baked-in weekly-summary body whenever the underlying
        // stats change. Each call cancel+adds the pending notification,
        // which is cheap and idempotent.
        nonisolated(unsafe) let user = user
        notificationManager.observe(name: Notification.Name.gameCreated) { _ in
            Task { @MainActor in await WeeklySummaryScheduler.scheduleAll(for: user) }
        }
        notificationManager.observe(name: Notification.Name.gameEnded) { _ in
            Task { @MainActor in await WeeklySummaryScheduler.scheduleAll(for: user) }
        }
        notificationManager.observe(name: Notification.Name.videoRecorded) { _ in
            Task { @MainActor in await WeeklySummaryScheduler.scheduleAll(for: user) }
        }
    }
    
    @ViewBuilder
    private var tabViewContent: some View {
        if #available(iOS 18.0, *), horizontalSizeClass == .regular {
            TabView(selection: $selectedTab) {
                homeTab
                gamesTab
                videosTab
                statsTab
                moreTab
            }
            .tabViewStyle(.sidebarAdaptable)
        } else {
            TabView(selection: $selectedTab) {
                homeTab
                gamesTab
                videosTab
                statsTab
                moreTab
            }
        }
    }
    
    private var homeTab: some View {
        NavigationStack {
            DashboardView(
                user: user,
                athlete: selectedAthlete,
                authManager: authManager,
                modelContext: modelContext
            )
            .id(homeAthleteID ?? selectedAthlete.id)
        }
        .modifier(InvitationBadgeModifier())
        .tabItem {
            Label("Home", systemImage: "house.fill")
        }
        .tag(MainTab.home.rawValue)
        .accessibilityLabel("Home tab")
        .accessibilityHint("View your dashboard and quick actions")
    }

    private var gamesTab: some View {
        NavigationStack {
            GamesView(athlete: selectedAthlete)
                .id(gamesAthleteID ?? selectedAthlete.id)
        }
        .tabItem {
            Label("Games", systemImage: "baseball.fill")
        }
        .tag(MainTab.games.rawValue)
        .accessibilityLabel("Games tab")
        .accessibilityHint("View and manage games")
    }

    private var statsTab: some View {
        NavigationStack {
            StatisticsView(athlete: selectedAthlete, currentTier: authManager.currentTier)
                .id(statsAthleteID ?? selectedAthlete.id)
        }
        .tabItem {
            Label("Stats", systemImage: "chart.bar.fill")
        }
        .tag(MainTab.stats.rawValue)
        .accessibilityLabel("Statistics tab")
        .accessibilityHint("View batting statistics and performance metrics")
    }

    private var videosTab: some View {
        NavigationStack {
            VideoClipsView(athlete: selectedAthlete)
                .id(videosAthleteID ?? selectedAthlete.id)
        }
        .modifier(UnreadBadgeModifier())
        .tabItem {
            Label("Videos", systemImage: "video.fill")
        }
        .tag(MainTab.videos.rawValue)
        .accessibilityLabel("Videos tab")
        .accessibilityHint("View and record video clips")
    }

    private var moreTab: some View {
        NavigationStack(path: $morePath) {
            List {
                Section { profileCard }

                // Features
                Section("Features") {
                    NavigationLink(value: MoreDestination.practice) {
                        Label("Practice", systemImage: "figure.run")
                            .foregroundColor(.primary)
                    }
                    NavigationLink(value: MoreDestination.highlights) {
                        Label {
                            HStack {
                                Text("Highlights")
                                if authManager.currentTier < .plus {
                                    Text("PLUS")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.orange)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(.orange.opacity(0.12)))
                                }
                            }
                        } icon: {
                            Image(systemName: "star.fill")
                        }
                        .foregroundColor(.primary)
                    }
                    NavigationLink(value: MoreDestination.photos) {
                        Label("Photos", systemImage: "photo.on.rectangle.angled")
                            .foregroundColor(.primary)
                    }
                    NavigationLink(value: MoreDestination.seasons) {
                        Label("Seasons", systemImage: "calendar")
                            .foregroundColor(.primary)
                    }
                    if AppFeatureFlags.isCoachEnabled {
                        NavigationLink(value: MoreDestination.coaches) {
                            Label {
                                HStack {
                                    Text("Coaches")
                                    if authManager.currentTier != .pro {
                                        Text("PRO")
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .foregroundColor(.orange)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill(.orange.opacity(0.12)))
                                    }
                                }
                            } icon: {
                                Image(systemName: "person.3.fill")
                            }
                            .foregroundColor(.primary)
                        }
                        NavigationLink(value: MoreDestination.sharedFolders) {
                            Label {
                                HStack {
                                    Text("Shared Folders")
                                    if authManager.currentTier != .pro {
                                        Text("PRO")
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .foregroundColor(.orange)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill(.orange.opacity(0.12)))
                                    }
                                    Spacer()
                                    SharedFoldersBadge()
                                }
                            } icon: {
                                Image(systemName: "folder.badge.person.crop")
                            }
                            .foregroundColor(.primary)
                        }
                    }
                }

            }
            .navigationTitle("More")
            .navigationDestination(for: MoreDestination.self) { destination in
                switch destination {
                case .practice:
                    PracticesView(athlete: selectedAthlete).id(selectedAthlete.id)
                case .highlights:
                    HighlightsView(athlete: selectedAthlete, currentTier: authManager.currentTier, hasCoachingAccess: authManager.hasCoachingAccess).id(selectedAthlete.id).plusRequired()
                case .seasons:
                    SeasonsView(athlete: selectedAthlete).id(selectedAthlete.id)
                case .photos:
                    PhotosView(athlete: selectedAthlete).id(selectedAthlete.id)
                case .coaches:
                    CoachesView(athlete: selectedAthlete).id(selectedAthlete.id).proRequired()
                case .sharedFolders:
                    AthleteFoldersListView(userID: authManager.userID, athlete: selectedAthlete).id(selectedAthlete.id).proRequired()
                case .sharedFolder(let folderID):
                    if let folder = SharedFolderManager.shared.athleteFolders.first(where: { $0.id == folderID }) {
                        AthleteFolderDetailView(folder: folder).proRequired()
                    } else {
                        AthleteFoldersListView(userID: authManager.userID, athlete: selectedAthlete).id(selectedAthlete.id).proRequired()
                    }
                }
            }
        }
        .modifier(MoreTabBadgeModifier())
        .tabItem {
            Label("More", systemImage: "ellipsis.circle.fill")
        }
        .tag(MainTab.more.rawValue)
        .accessibilityLabel("More tab")
        .accessibilityHint("Access Practice, Highlights, Photos, Seasons, Coaches, and Profile")
    }

    private var profileCard: some View {
        NavigationLink {
            ProfileView(user: user, selectedAthlete: Binding(
                get: { selectedAthlete },
                set: { selectedAthlete = $0 ?? selectedAthlete }
            ))
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.brandNavy.opacity(0.1))
                        .frame(width: 48, height: 48)
                    Text(String(user.username.prefix(1)).uppercased())
                        .font(.title3).fontWeight(.bold).foregroundColor(.brandNavy)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(user.username).font(.body).fontWeight(.semibold).foregroundColor(.primary)
                    Text(tierDisplayText).font(.caption).fontWeight(.medium).foregroundColor(tierDisplayColor)
                }
                Spacer()
            }
            .padding(.vertical, 4)
        }
    }

    private var tierDisplayText: String {
        switch authManager.currentTier {
        case .pro: return "Pro Member"
        case .plus: return "Plus Member"
        default: return "Free Plan"
        }
    }

    private var tierDisplayColor: Color {
        switch authManager.currentTier {
        case .pro, .plus: return .brandNavy
        default: return .secondary
        }
    }
    
    // MARK: - Deferred Tab Rebuild

    /// Updates only the currently visible tab's athlete ID.
    /// Inactive tabs keep their old ID and refresh lazily via refreshStaleTab().
    private func refreshActiveTabAthleteID() {
        let id = selectedAthlete.id
        switch selectedTab {
        case MainTab.home.rawValue: homeAthleteID = id
        case MainTab.games.rawValue: gamesAthleteID = id
        case MainTab.videos.rawValue: videosAthleteID = id
        case MainTab.stats.rawValue: statsAthleteID = id
        default: break // More tab uses selectedAthlete.id directly
        }
    }

    private func refreshStaleTab(_ tab: Int) {
        let id = selectedAthlete.id
        switch tab {
        case MainTab.home.rawValue where homeAthleteID != id: homeAthleteID = id
        case MainTab.games.rawValue where gamesAthleteID != id: gamesAthleteID = id
        case MainTab.videos.rawValue where videosAthleteID != id: videosAthleteID = id
        case MainTab.stats.rawValue where statsAthleteID != id: statsAthleteID = id
        default: break
        }
    }

    // MARK: - State Restoration

    private var tabDefaultsKey: String {
        "LastSelectedTab_\(user.id.uuidString)"
    }

    private func saveSelectedTab(_ tab: Int) {
        UserDefaults.standard.set(tab, forKey: tabDefaultsKey)
    }

    private func restoreSelectedTab() {
        let savedTab = UserDefaults.standard.integer(forKey: tabDefaultsKey)
        // Only restore if it's a valid tab index
        if (0...MainTab.more.rawValue).contains(savedTab) {
            selectedTab = savedTab
        } else {
            // Default to home tab if saved tab is invalid
            selectedTab = MainTab.home.rawValue
        }
    }

}

/// Isolates the badge observation so that changes to unread count
/// only invalidate this modifier's body — not the entire MainTabView.
/// Only counts newVideo notifications — coach feedback badges now
/// live on the Shared Folders list and individual video cards.
private struct UnreadBadgeModifier: ViewModifier {
    @ObservedObject private var activityNotifService = ActivityNotificationService.shared

    private var newVideoCount: Int {
        activityNotifService.recentNotifications.filter { !$0.isRead && $0.type == .newVideo }.count
    }

    func body(content: Content) -> some View {
        content
            .badge(newVideoCount > 0 ? newVideoCount : 0)
    }
}

/// Shows a badge on the Home tab when there are pending coach invitations.
private struct InvitationBadgeModifier: ViewModifier {
    private var invitationManager: AthleteInvitationManager { .shared }

    func body(content: Content) -> some View {
        content
            .badge(invitationManager.pendingCount > 0 ? invitationManager.pendingCount : 0)
    }
}

/// Shows unread coach feedback count as a badge on the More tab itself.
private struct MoreTabBadgeModifier: ViewModifier {
    @ObservedObject private var activityNotifService = ActivityNotificationService.shared

    private var totalUnread: Int {
        activityNotifService.unreadCountByFolder.values.reduce(0, +)
    }

    func body(content: Content) -> some View {
        content
            .badge(totalUnread > 0 ? totalUnread : 0)
    }
}

/// Shows total unread coach feedback count on the Shared Folders row in the More tab.
private struct SharedFoldersBadge: View {
    @ObservedObject private var activityNotifService = ActivityNotificationService.shared

    private var totalUnread: Int {
        activityNotifService.unreadCountByFolder.values.reduce(0, +)
    }

    var body: some View {
        if totalUnread > 0 {
            Text("\(totalUnread)")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.red)
                .clipShape(Capsule())
        }
    }
}
