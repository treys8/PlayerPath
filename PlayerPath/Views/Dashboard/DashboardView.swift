//
//  DashboardView.swift
//  PlayerPath
//
//  Extracted from MainAppView.swift
//

import SwiftUI
import SwiftData
import TipKit
import os

private let dashboardLog = Logger(subsystem: "com.playerpath.app", category: "DashboardView")

enum HomeDestination: Hashable {
    case photos
}

struct DashboardView: View {
    let user: User
    let athlete: Athlete
    let authManager: ComprehensiveAuthManager
    @Binding var homePath: NavigationPath
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var activeSport: Season.SportType { athlete.sportType }

    @StateObject private var viewModel: GamesDashboardViewModel
    @ObservedObject private var activityNotifService = ActivityNotificationService.shared
    @State private var pulseAnimation = false
    @State private var showingDirectCamera = false
    @State private var selectedVideoForPlayback: VideoClip?
    @State private var showingSeasons = false
    @State private var isCheckingPermissions = false
    @State private var isEndingGame: Set<UUID> = []
    private let athletePickerTip = AthletePickerTip()

    // Cached computed values to avoid recalculation during body evaluation
    @State private var seasonRecommendation: SeasonManager.SeasonRecommendation = .ok
    @State private var cachedBA: String = ".000"
    @State private var cachedSLG: String = ".000"
    @State private var cachedHits: String = "0"
    @State private var cachedSeasonCount: Int = 0
    @State private var cachedPracticeCount: Int = 0
    @State private var cachedPhotoCount: Int = 0

    // Dynamic live games query configured via init to safely capture athleteID
    private let athleteID: UUID
    @Query private var liveGames: [Game]

    init(user: User, athlete: Athlete, authManager: ComprehensiveAuthManager, modelContext: ModelContext, homePath: Binding<NavigationPath>) {
        self.user = user
        self.athlete = athlete
        self.authManager = authManager
        self._homePath = homePath
        self._viewModel = StateObject(wrappedValue: GamesDashboardViewModel(athlete: athlete, modelContext: modelContext))
        self.athleteID = athlete.id
        // Configure the query with a predicate bound to a stable value (athleteID)
        self._liveGames = Query(filter: #Predicate<Game> { game in
            game.isLive == true && game.athlete?.id == athleteID
        }, sort: [SortDescriptor(\Game.date, order: .reverse)])
    }

    /// Live games scoped to the athlete's active sport. The @Query above keys
    /// by athleteID (a stable capture); sport-filtering happens here so a stale
    /// cross-sport live game (e.g. baseball game left running after the athlete
    /// activated a golf season) doesn't leak into the dashboard's Live Now
    /// section. Mirrors GamesView.filterGames: season-sport match, seasonless
    /// passes through.
    private var liveGamesForActiveSport: [Game] {
        liveGames.filter { game in
            guard let seasonSport = game.season?.sport else { return true }
            return seasonSport == activeSport
        }
    }

    private var hasLiveGame: Bool {
        !liveGamesForActiveSport.isEmpty
    }

    private var firstLiveGame: Game? {
        liveGamesForActiveSport.first
    }

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    private var managementColumns: [GridItem] {
        if isRegularWidth {
            return Array(repeating: GridItem(.flexible()), count: 4)
        } else {
            return [GridItem(.flexible()), GridItem(.flexible())]
        }
    }

    private var dashboardHorizontalPadding: CGFloat {
        isRegularWidth ? 32 : 16
    }

    private var athleteInitials: String {
        athlete.name.split(separator: " ").compactMap({ $0.first.map(String.init) }).prefix(2).joined()
    }

    private var seasonSectionTitle: String {
        "\(athlete.name)'s Season"
    }

    private var coachCardSubtitle: String {
        let unread = activityNotifService.unreadFolderVideoCount
        if unread > 0 {
            return "\(unread) new video\(unread == 1 ? "" : "s")"
        }
        return "\((athlete.coaches ?? []).count) Coaches"
    }

    // Golf scoring summary computed inline. SwiftData observes property reads
    // in body, so this re-evaluates when a score is entered or a round is added.
    private var golfRoundsWithScores: [Game] {
        (athlete.games ?? []).filter { $0.season?.sport == .golf && $0.totalScore != nil }
    }

    private var golfRoundCount: Int { golfRoundsWithScores.count }

    private var golfAverageScoreText: String {
        let scores = golfRoundsWithScores.compactMap { $0.totalScore }
        guard !scores.isEmpty else { return "—" }
        let avg = Double(scores.reduce(0, +)) / Double(scores.count)
        return String(format: "%.1f", avg)
    }

    private var golfBestScoreText: String {
        let scores = golfRoundsWithScores.compactMap { $0.totalScore }
        return scores.min().map(String.init) ?? "—"
    }

    private var statisticsCardSubtitle: String {
        activeSport == .golf ? "\(golfRoundCount) Rounds" : cachedBA + " AVG"
    }

    // MARK: - Body

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.totalGames == 0 && viewModel.totalVideos == 0 {
                DashboardSkeletonView()
            } else {
                dashboardContent(viewModel: viewModel)
            }
        }
        .navigationTitle(athlete.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                SportContextChip(athlete: athlete)
            }
            ToolbarItem(placement: .principal) {
                Menu {
                    // Show all athletes with checkmark for current. Each entry
                    // carries a sport icon so same-named spinoffs (e.g. two
                    // "Zain" profiles in different sports) are distinguishable.
                    ForEach((user.athletes ?? []).sorted(by: { $0.name < $1.name })) { ath in
                        Button {
                            // Switch to this athlete
                            NotificationCenter.default.post(
                                name: Notification.Name.switchAthlete,
                                object: ath
                            )
                            Haptics.light()
                            athletePickerTip.invalidate(reason: .actionPerformed)
                        } label: {
                            Label {
                                HStack(spacing: 6) {
                                    Text(ath.name)
                                    Text("·")
                                        .foregroundStyle(.secondary)
                                    Text(ath.sportType.displayName)
                                        .foregroundStyle(.secondary)
                                    if ath.id == athlete.id {
                                        Spacer(minLength: 8)
                                        Image(systemName: "checkmark")
                                    }
                                }
                            } icon: {
                                Image(systemName: ath.sportType.icon)
                            }
                        }
                    }

                    Divider()

                    Button {
                        NotificationCenter.default.post(name: Notification.Name.showAthleteSelection, object: nil)
                        Haptics.light()
                    } label: {
                        Label("Manage Athletes", systemImage: "person.2.fill")
                    }
                } label: {
                    AthletePickerLabel(name: athlete.name, initials: athleteInitials)
                }
                .onboardingTip(athletePickerTip, arrowEdge: .top, also: (user.athletes?.count ?? 0) > 1)
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                NotificationBellToolbarButton()
            }
        }
        .task {
            await viewModel.refresh()
        }
        .onAppear {
            if !reduceMotion {
                pulseAnimation = true
            }
            updateCachedStats()
        }
        .onChange(of: athlete.statistics?.updatedAt) { _, _ in
            updateCachedStats()
        }
        .onChange(of: athlete.seasons?.count) { _, _ in
            updateCachedStats()
        }
        .onChange(of: athlete.practices?.count) { _, _ in
            updateCachedStats()
        }
        .onChange(of: athlete.photos?.count) { _, _ in
            updateCachedStats()
        }
        .sheet(isPresented: $showingSeasons) {
            NavigationStack {
                SeasonsView(athlete: athlete)
            }
        }
        .navigationDestination(for: HomeDestination.self) { destination in
            switch destination {
            case .photos:
                PhotosView(athlete: athlete).id(athlete.id)
            }
        }
        .fullScreenCover(isPresented: $showingDirectCamera) {
            DirectCameraRecorderView(athlete: athlete, game: firstLiveGame)
        }
        .fullScreenCover(item: $selectedVideoForPlayback) { video in
            VideoPlayerView(clip: video)
        }
        .onReceive(NotificationCenter.default.publisher(for: .presentFullscreenVideo)) { notification in
            if let video = notification.object as? VideoClip {
                selectedVideoForPlayback = video
            }
        }
    }

    // MARK: - Content

    private func endLiveGame(_ game: Game) {
        guard !isEndingGame.contains(game.id) else { return }
        isEndingGame.insert(game.id)
        Haptics.light()

        Task { @MainActor in
            defer { isEndingGame.remove(game.id) }
            await GameService(modelContext: modelContext).end(game)
        }
    }


    @ViewBuilder
    private func dashboardContent(viewModel: GamesDashboardViewModel) -> some View {
        ScrollView {
            LazyVStack(spacing: 32) {
                AthleteInvitationsBanner()
                    .padding(.horizontal, dashboardHorizontalPadding)

                if seasonRecommendation.message != nil {
                    SeasonRecommendationBanner(athlete: athlete, recommendation: seasonRecommendation)
                        .padding(.horizontal, dashboardHorizontalPadding)
                }

                DashboardNextStepCard(athlete: athlete)
                    .padding(.horizontal, dashboardHorizontalPadding)

                liveGamesSection
                quickActionsSection
                managementGridSection(viewModel: viewModel)
                quickStatsSection
            }
            .padding(.vertical)
        }
        .refreshable {
            if user.firebaseAuthUid != nil {
                do {
                    try await SyncCoordinator.shared.syncAll(for: user)
                } catch {
                    ErrorHandlerService.shared.handle(error, context: "DashboardView.refreshable", showAlert: false)
                }
            }
            await viewModel.refresh()
        }
    }

    // MARK: - Dashboard Sections

    @ViewBuilder
    private var liveGamesSection: some View {
        let liveGames = liveGamesForActiveSport
        if !liveGames.isEmpty {
            VStack(spacing: 12) {
                HStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                            .opacity(pulseAnimation ? 0.4 : 1.0)
                            .shadow(color: .red.opacity(0.8), radius: pulseAnimation ? 4 : 2)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulseAnimation)

                        Text("Live Now")
                            .font(.headingLarge)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.red, .red.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }

                    Spacer()

                    Text("\(liveGames.count)")
                        .font(.labelMedium)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray5))
                        .clipShape(Capsule())
                }

                ForEach(liveGames) { game in
                    NavigationLink {
                        GameDetailView(game: game)
                    } label: {
                        LiveGameCard(game: game, isEnding: isEndingGame.contains(game.id)) {
                            endLiveGame(game)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, dashboardHorizontalPadding)
        }
    }

    @ViewBuilder
    private var quickActionsSection: some View {
        if hasLiveGame {
            VStack(spacing: 16) {
                DashboardSectionHeader(title: "Quick Actions", icon: "bolt.fill", color: .brandNavy)

                HStack(spacing: 12) {
                    QuickActionButton(
                        icon: "plus.circle.fill",
                        title: "New Game",
                        color: .brandNavy
                    ) {
                        createNewGame()
                    }

                    QuickActionButton(
                        icon: "record.circle",
                        title: "Record Live",
                        color: .red
                    ) {
                        Task { @MainActor in
                            guard !isCheckingPermissions else { return }
                            isCheckingPermissions = true
                            defer { isCheckingPermissions = false }

                            let status = await RecorderPermissions.ensureCapturePermissions(context: "QuickRecord")
                            guard status == .granted else { return }

                            showingDirectCamera = true
                            Haptics.medium()
                        }
                    }
                    .disabled(isCheckingPermissions)
                }
            }
            .padding(.horizontal, dashboardHorizontalPadding)
        }
    }

    @ViewBuilder
    private func managementGridSection(viewModel: GamesDashboardViewModel) -> some View {
        VStack(spacing: 16) {
            HStack {
                DashboardSectionHeader(title: seasonSectionTitle, icon: "square.grid.2x2.fill", color: .brandNavy)

                Button {
                    createNewGame()
                } label: {
                    Text(activeSport == .golf ? "+ New Tournament" : "+ New Game")
                        .font(.headingSmall)
                        .foregroundColor(.brandGold)
                }
            }

            LazyVGrid(columns: managementColumns, spacing: 16) {
                DashboardFeatureCard(
                    icon: activeSport == .golf ? "figure.golf" : "baseball.diamond.bases",
                    title: activeSport == .golf ? "Tournaments" : "Games",
                    subtitle: "\(viewModel.totalGames) Total",
                    color: .brandNavy
                ) {
                    postSwitchTab(.games)
                }
                DashboardFeatureCard(icon: "video", title: "Video Clips", subtitle: "\(viewModel.totalVideos) Recorded", color: .brandNavy) {
                    postSwitchTab(.videos)
                }
                DashboardFeatureCard(icon: "chart.bar.fill", title: "Statistics", subtitle: statisticsCardSubtitle, color: .brandNavy) {
                    postSwitchTab(.stats)
                }
                DashboardFeatureCard(icon: "calendar", title: "Seasons", subtitle: "\(cachedSeasonCount) Total", color: .brandNavy) {
                    showingSeasons = true
                }
                DashboardFeatureCard(icon: "figure.run", title: "Practice", subtitle: "\(cachedPracticeCount) Sessions", color: .brandNavy) {
                    NotificationCenter.default.post(name: .navigateToMorePractice, object: nil)
                }
                DashboardFeatureCard(icon: "photo.on.rectangle.angled", title: "Photos", subtitle: "\(cachedPhotoCount) Photos", color: .brandNavy) {
                    homePath.append(HomeDestination.photos)
                }
                DashboardPremiumFeatureCard(icon: "star.fill", title: "Highlights", subtitle: "\(viewModel.totalHighlights) Highlights", color: .brandGold, isPremium: authManager.currentTier >= .plus, badgeLabel: "PLUS") {
                    if authManager.currentTier >= .plus {
                        NotificationCenter.default.post(name: .navigateToMoreHighlights, object: nil)
                    } else {
                        Haptics.warning()
                        NotificationCenter.default.post(name: .showSubscriptionPaywall, object: nil)
                    }
                }
                DashboardPremiumFeatureCard(
                    icon: "person.3.fill",
                    title: "Coaches",
                    subtitle: coachCardSubtitle,
                    color: .brandGold,
                    isPremium: authManager.currentTier >= .pro,
                    notificationCount: activityNotifService.unreadFolderVideoCount
                ) {
                    if authManager.currentTier >= .pro {
                        Task { @MainActor in
                            postSwitchTab(.home)
                            try? await Task.sleep(for: .milliseconds(150))
                            NotificationCenter.default.post(name: .presentCoachVideos, object: athlete)
                        }
                    } else {
                        Haptics.warning()
                        NotificationCenter.default.post(name: .showSubscriptionPaywall, object: nil)
                    }
                }
            }
        }
        .padding(.horizontal, dashboardHorizontalPadding)
    }

    @ViewBuilder
    private var quickStatsSection: some View {
        VStack(spacing: 16) {
            DashboardSectionHeader(title: "Quick Stats", icon: "chart.bar.fill", color: .brandNavy)

            HStack(spacing: 12) {
                if activeSport == .golf {
                    DashboardStatCard(title: "Rounds", value: "\(golfRoundCount)", icon: "figure.golf", color: .brandGold)
                    DashboardStatCard(title: "Avg Score", value: golfAverageScoreText, icon: "chart.bar.fill", color: .brandGold)
                    DashboardStatCard(title: "Best", value: golfBestScoreText, icon: "trophy.fill", color: .brandGold)
                } else {
                    DashboardStatCard(title: "AVG", value: cachedBA, icon: "square.grid.2x2.fill", color: .brandGold)
                    DashboardStatCard(title: "SLG", value: cachedSLG, icon: "chart.bar.fill", color: .brandGold)
                    DashboardStatCard(title: "Hits", value: cachedHits, icon: "hand.tap.fill", color: .brandGold)
                }
            }
        }
        .padding(.horizontal, dashboardHorizontalPadding)
    }

    // MARK: - Helper Functions

    private func createNewGame() {
        Task { @MainActor in
            postSwitchTab(.games)
            dashboardLog.debug("New Game quick action — switching to Games tab")
            try? await Task.sleep(for: .milliseconds(150))
            NotificationCenter.default.post(name: Notification.Name.presentAddGame, object: nil)
            dashboardLog.debug("Posted .presentAddGame notification with no tournament context")
            Haptics.light()
        }
    }

    private func updateCachedStats() {
        seasonRecommendation = SeasonManager.checkSeasonStatus(for: athlete, sport: activeSport)
        if let stats = athlete.statistics {
            cachedBA = StatisticsService.shared.formatBattingAverage(stats.battingAverage)
            cachedSLG = StatisticsService.shared.formatBattingAverage(stats.sluggingPercentage)
            cachedHits = String(stats.hits)
        } else {
            cachedBA = ".000"
            cachedSLG = ".000"
            cachedHits = "0"
        }
        // Sport-scope cached counts so management card subtitles match the
        // sport-filtered lists the user lands on. Seasons are filtered strictly
        // by sport (a season has exactly one sport). Practices and photos pass
        // seasonless items through under both sports — same rule as the lists.
        cachedSeasonCount = (athlete.seasons ?? []).filter { $0.sport == activeSport }.count
        cachedPracticeCount = (athlete.practices ?? []).filter { practice in
            guard let season = practice.season else { return true }
            return season.sport == activeSport
        }.count
        cachedPhotoCount = (athlete.photos ?? []).filter { photo in
            guard let season = photo.season else { return true }
            return season.sport == activeSport
        }.count
    }

}

// MARK: - Athlete Picker Label

struct AthletePickerLabel: View {
    let name: String
    let initials: String

    var body: some View {
        HStack(spacing: 8) {
            Text(initials)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(Color.brandNavy)
                )
                .clipShape(Circle())

            Text(name)
                .font(.headingMedium)
                .foregroundColor(.primary)
            Image(systemName: "chevron.down")
                .font(.caption2)
                .foregroundColor(.brandGold)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.brandNavy.opacity(0.08))
        )
    }
}

// MARK: - Dashboard Section Header

struct DashboardSectionHeader: View {
    let title: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            // Icon with gradient
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(color)

            Text(title)
                .font(.headingLarge)
                .foregroundColor(.primary)

            Spacer()
        }
    }
}
