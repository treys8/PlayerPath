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
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    // More tab programmatic navigation
    @State private var morePath = NavigationPath()

    // Onboarding milestone tracking
    @ObservedObject private var onboardingManager = OnboardingManager.shared
    @State private var hasRunInitialSetup = false

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
                // Schedule weekly summary notification with real stats
                if UserDefaults.standard.object(forKey: "notif_weeklyStats") as? Bool ?? true {
                    await scheduleWeeklySummaryWithStats()
                }

                // Mark welcome tutorial complete (tutorial removed)
                if !onboardingManager.hasSeenWelcomeTutorial {
                    onboardingManager.markMilestoneComplete(.welcomeTutorial)
                }
            }
            .onChange(of: selectedAthlete.id) { _, _ in
                // Update ALL tabs immediately to prevent stale data on tab switch
                refreshAllTabAthleteIDs()
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
                // Mark activity notifications read when entering Videos tab
                if newValue == MainTab.videos.rawValue, let firebaseUID = authManager.userID {
                    Task {
                        await ActivityNotificationService.shared.markAllRead(forUserID: firebaseUID)
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
            .sheet(isPresented: $showingPaywall) {
                ImprovedPaywallView(user: user)
            }
            .onReceive(NotificationCenter.default.publisher(for: .showSubscriptionPaywall)) { _ in
                showingPaywall = true
            }
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
            MainActor.assumeIsolated {
                morePath = NavigationPath()
                selectedTab = MainTab.more.rawValue
                Haptics.light()
                // Append on the next run-loop tick so the tab switch completes first
                Task { @MainActor in
                    morePath.append(MoreDestination.practice)
                }
            }
        }

        notificationManager.observe(name: Notification.Name.navigateToMoreHighlights) { _ in
            MainActor.assumeIsolated {
                morePath = NavigationPath()
                selectedTab = MainTab.more.rawValue
                Haptics.light()
                Task { @MainActor in
                    morePath.append(MoreDestination.highlights)
                }
            }
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
                    AthleteFoldersListView(userID: authManager.userID).proRequired()
                }
            }
        }
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

    /// Updates the athlete ID for a given tab only if it's stale.
    /// This triggers .id() to change, rebuilding that tab's content.
    private func refreshAllTabAthleteIDs() {
        let id = selectedAthlete.id
        homeAthleteID = id
        gamesAthleteID = id
        videosAthleteID = id
        statsAthleteID = id
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

    /// Compute this week's stats from the athlete's data and schedule
    /// a one-shot weekly summary notification for next Sunday.
    /// Pre-extracts lightweight Date values so model objects aren't held across the await.
    private func scheduleWeeklySummaryWithStats() async {
        let athleteIdString = selectedAthlete.id.uuidString
        let gameDates = (selectedAthlete.games ?? []).compactMap(\.date)
        let videoDates = (selectedAthlete.videoClips ?? []).compactMap(\.createdAt)
        let avg = selectedAthlete.statistics?.battingAverage

        let calendar = Calendar.current
        let now = Date()
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now

        let gamesThisWeek = gameDates.filter { $0 >= startOfWeek }.count
        let videosThisWeek = videoDates.filter { $0 >= startOfWeek }.count

        await PushNotificationService.shared.scheduleWeeklySummary(
            athleteId: athleteIdString,
            gamesThisWeek: gamesThisWeek,
            videosThisWeek: videosThisWeek,
            battingAverage: avg
        )
    }
}

/// Isolates the badge observation so that changes to unreadVideoCount
/// only invalidate this modifier's body — not the entire MainTabView.
/// Only counts video-related notifications (newVideo, coachComment),
/// not invitations or access-revoked which belong on other tabs.
private struct UnreadBadgeModifier: ViewModifier {
    @ObservedObject private var activityNotifService = ActivityNotificationService.shared

    func body(content: Content) -> some View {
        content
            .badge(activityNotifService.unreadVideoCount > 0 ? activityNotifService.unreadVideoCount : 0)
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
