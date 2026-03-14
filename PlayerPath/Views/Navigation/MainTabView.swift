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
    @Environment(\.modelContext) private var modelContext
    
    // More tab programmatic navigation
    @State private var morePath = NavigationPath()

    // Welcome tutorial — shown once after first-time setup is complete
    @StateObject private var onboardingManager = OnboardingManager.shared
    @State private var showingWelcomeTutorial = false

    // Swipe gesture tracking
    @GestureState private var dragOffset: CGFloat = 0
    @State private var tabTransition: AnyTransition = .identity

    enum MoreDestination: Hashable {
        case practice, highlights
    }
    
    // NotificationCenter observer management using StateObject for lifecycle safety
    @StateObject private var notificationManager = NotificationObserverManager()

    // Activity notification service for unread badge count
    @ObservedObject private var activityNotifService = ActivityNotificationService.shared

    private func applyRecordedHitResult(_ info: [String: Any]) {
        guard let hitType = info["hitType"] as? String else { 
            print("⚠️ Invalid hit result format")
            return 
        }
        
        #if DEBUG
        print("⚾️ Recording hit result: \(hitType) for athlete: \(selectedAthlete.name)")
        #endif
        
        StatisticsHelpers.record(hitType: hitType, for: selectedAthlete, in: modelContext)
        
        // Provide haptic feedback for successful stat recording
        Haptics.success()
    }
    
    // MARK: - Dashboard actions
    private func toggleGameLive(_ game: Game) {
        Haptics.light()
        game.isLive.toggle()
        do { try modelContext.save() } catch { print("Failed to toggle game live: \(error)") }
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
            .tint(.blue)
            .task {
                // Use task modifier which automatically handles cancellation
                restoreSelectedTab()
                setupNotificationObservers()
                // Fix AE: Request notification permission here, after the user has completed
                // onboarding and can see the app's value. The system dialog is only shown
                // once (.notDetermined). Subsequent launches are a no-op.
                if PushNotificationService.shared.authorizationStatus == .notDetermined {
                    _ = await PushNotificationService.shared.requestAuthorization()
                }
                // Show welcome tutorial once for new users after onboarding is complete.
                // Existing users have hasSeenWelcomeTutorial pre-marked in AuthenticatedFlow.loadUser().
                if !onboardingManager.hasSeenWelcomeTutorial {
                    try? await Task.sleep(for: .milliseconds(200))
                    showingWelcomeTutorial = true
                }
            }
            .sheet(isPresented: $showingWelcomeTutorial) {
                WelcomeTutorialView()
            }
            .onChange(of: selectedTab) { _, newValue in
                saveSelectedTab(newValue)
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
            .addKeyboardShortcuts()
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
        TabView(selection: $selectedTab) {
            homeTab
            gamesTab
            videosTab
            statsTab
            moreTab
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
            .id(selectedAthlete.id) // Force view to recreate when athlete changes
        }
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
                .id(selectedAthlete.id) // Force view to recreate when athlete changes
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
            StatisticsView(athlete: selectedAthlete)
                .id(selectedAthlete.id) // Force view to recreate when athlete changes
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
                .id(selectedAthlete.id) // Force view to recreate when athlete changes
        }
        .badge(activityNotifService.unreadCount > 0 ? activityNotifService.unreadCount : 0)
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
                Section {
                    NavigationLink(value: MoreDestination.practice) {
                        Label("Practice", systemImage: "figure.run")
                    }
                    NavigationLink(value: MoreDestination.highlights) {
                        Label("Highlights", systemImage: "star.fill")
                    }
                }
                Section {
                    NavigationLink {
                        ProfileView(user: user, selectedAthlete: Binding(
                            get: { selectedAthlete },
                            set: { selectedAthlete = $0 ?? selectedAthlete }
                        ))
                    } label: {
                        Label("Profile & Settings", systemImage: "person.circle.fill")
                    }
                }
            }
            .navigationTitle("More")
            .navigationDestination(for: MoreDestination.self) { destination in
                switch destination {
                case .practice:
                    PracticesView(athlete: selectedAthlete).id(selectedAthlete.id)
                case .highlights:
                    HighlightsView(athlete: selectedAthlete).id(selectedAthlete.id).plusRequired()
                }
            }
        }
        .tabItem {
            Label("More", systemImage: "ellipsis.circle.fill")
        }
        .tag(MainTab.more.rawValue)
        .accessibilityLabel("More tab")
        .accessibilityHint("Access Practice, Highlights, and Profile & Settings")
    }
    
    // MARK: - State Restoration
    
    private func saveSelectedTab(_ tab: Int) {
        UserDefaults.standard.set(tab, forKey: "LastSelectedTab")
    }
    
    private func restoreSelectedTab() {
        let savedTab = UserDefaults.standard.integer(forKey: "LastSelectedTab")
        // Only restore if it's a valid tab index
        if (0...MainTab.more.rawValue).contains(savedTab) {
            selectedTab = savedTab
        } else {
            // Default to home tab if saved tab is invalid
            selectedTab = MainTab.home.rawValue
        }
    }
}
