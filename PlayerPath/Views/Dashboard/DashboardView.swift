//
//  DashboardView.swift
//  PlayerPath
//
//  Extracted from MainAppView.swift
//

import SwiftUI
import SwiftData
import UIKit

struct DashboardView: View {
    let user: User
    let athlete: Athlete
    let authManager: ComprehensiveAuthManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @StateObject private var viewModel: GamesDashboardViewModel
    @State private var pulseAnimation = false
    @State private var showingPaywall = false
    @State private var showingDirectCamera = false
    @State private var selectedVideoForPlayback: VideoClip?
    @State private var showingSeasons = false
    @State private var showingPhotos = false
    @State private var isCheckingPermissions = false
    @State private var isEndingGame: Set<UUID> = []
    @State private var errorMessage: String?

    // Cached computed values to avoid recalculation during body evaluation
    @State private var seasonRecommendation: SeasonManager.SeasonRecommendation = .ok
    @State private var cachedBA: String = ".000"
    @State private var cachedSLG: String = ".000"
    @State private var cachedHits: String = "0"

    // Dynamic live games query configured via init to safely capture athleteID
    private let athleteID: UUID
    @Query private var liveGames: [Game]

    init(user: User, athlete: Athlete, authManager: ComprehensiveAuthManager, modelContext: ModelContext) {
        self.user = user
        self.athlete = athlete
        self.authManager = authManager
        self._viewModel = StateObject(wrappedValue: GamesDashboardViewModel(athlete: athlete, modelContext: modelContext))
        self._pulseAnimation = State(initialValue: false)
        self.athleteID = athlete.id
        // Configure the query with a predicate bound to a stable value (athleteID)
        self._liveGames = Query(filter: #Predicate<Game> { game in
            game.isLive == true && game.athlete?.id == athleteID
        }, sort: [SortDescriptor(\Game.date, order: .reverse)])
    }

    private var hasLiveGame: Bool {
        !liveGames.isEmpty
    }

    private var firstLiveGame: Game? {
        liveGames.first
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
            ToolbarItem(placement: .principal) {
                Menu {
                    // Show all athletes with checkmark for current
                    ForEach((user.athletes ?? []).sorted(by: { $0.name < $1.name })) { ath in
                        Button {
                            // Switch to this athlete
                            NotificationCenter.default.post(
                                name: Notification.Name.switchAthlete,
                                object: ath
                            )
                            Haptics.light()
                        } label: {
                            HStack {
                                Text(ath.name)
                                if ath.id == athlete.id {
                                    Image(systemName: "checkmark")
                                }
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
                    HStack(spacing: 6) {
                        Text(athlete.name)
                            .fontWeight(.semibold)
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
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
        .sheet(isPresented: $showingPaywall) {
            ImprovedPaywallView(user: user)
        }
        .sheet(isPresented: $showingSeasons) {
            NavigationStack {
                SeasonsView(athlete: athlete)
            }
        }
        .sheet(isPresented: $showingPhotos) {
            NavigationStack {
                PhotosView(athlete: athlete)
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
        .alert("Error", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Content

    private func endLiveGame(_ game: Game) {
        guard !isEndingGame.contains(game.id) else { return }
        isEndingGame.insert(game.id)

        // Capture original state for revert on save failure
        let prevLiveStartDate = game.liveStartDate
        let prevNeedsSync = game.needsSync

        Haptics.light()
        game.isLive = false
        game.isComplete = true
        game.liveStartDate = nil
        game.needsSync = true
        GameAlertService.shared.cancelEndGameReminder(for: game)

        Task { @MainActor in
            defer { isEndingGame.remove(game.id) }

            // Recalculate from scratch to avoid double-counting
            if let athlete = game.athlete {
                do {
                    try StatisticsService.shared.recalculateAthleteStatistics(for: athlete, context: modelContext)
                } catch {
                    // Stats failed but game state can still be saved
                }
            }

            do {
                try modelContext.save()
            } catch {
                // Revert in-memory mutations since save failed
                game.isLive = true
                game.isComplete = false
                game.liveStartDate = prevLiveStartDate
                game.needsSync = prevNeedsSync
                ErrorHandlerService.shared.handle(error, context: "DashboardView.endGame", showAlert: false)
                errorMessage = "Failed to end game: \(error.localizedDescription)"
                return
            }

            // Track game end analytics
            let gameStats = game.gameStats
            AnalyticsService.shared.trackGameEnded(
                gameID: game.id.uuidString,
                atBats: gameStats?.atBats ?? 0,
                hits: gameStats?.hits ?? 0
            )

            // Trigger Firestore sync
            if let userForSync = game.athlete?.user {
                do {
                    try await SyncCoordinator.shared.syncGames(for: userForSync)
                } catch {
                    // Game is saved locally with needsSync=true; sync will retry later
                }
            }
        }
    }


    @ViewBuilder
    private func dashboardContent(viewModel: GamesDashboardViewModel) -> some View {
        ScrollView {
            LazyVStack(spacing: 32) {

                // COACH INVITATIONS BANNER - Shows pending invitations from coaches
                AthleteInvitationsBanner()
                    .padding(.horizontal, dashboardHorizontalPadding)

                // SEASON RECOMMENDATION BANNER - Shows when athlete needs a season
                if seasonRecommendation.message != nil {
                    SeasonRecommendationBanner(athlete: athlete, recommendation: seasonRecommendation)
                        .padding(.horizontal, dashboardHorizontalPadding)
                }

                // NEXT STEP CARD - Guides new users through first actions
                DashboardNextStepCard(athlete: athlete)
                    .padding(.horizontal, dashboardHorizontalPadding)

                // LIVE GAMES SECTION - Shows when games are live
                if !liveGames.isEmpty {
                    VStack(spacing: 12) {
                        // Header with pulsing indicator
                        HStack {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 8, height: 8)
                                    .opacity(pulseAnimation ? 0.4 : 1.0)
                                    .shadow(color: .red.opacity(0.8), radius: pulseAnimation ? 4 : 2)
                                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulseAnimation)

                                Text("Live Now")
                                    .font(.title3)
                                    .fontWeight(.bold)
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
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(.systemGray5))
                                .clipShape(Capsule())
                        }

                        // Live Games
                        ForEach(liveGames) { game in
                            NavigationLink {
                                GameDetailView(game: game)
                            } label: {
                                LiveGameCard(game: game, isEnding: isEndingGame.contains(game.id), onEnd: nil)
                            }
                            .buttonStyle(.plain)
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    endLiveGame(game)
                                } label: {
                                    Group {
                                        if isEndingGame.contains(game.id) {
                                            ProgressView().tint(.white)
                                        } else {
                                            Text("End")
                                        }
                                    }
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(
                                        LinearGradient(colors: [.red, .red.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                    )
                                    .clipShape(Capsule())
                                }
                                .disabled(isEndingGame.contains(game.id))
                                .padding(12)
                            }
                        }
                    }
                    .padding(.horizontal, dashboardHorizontalPadding)
                }

                // Quick Actions Section — only shown when a game is live
                if hasLiveGame {
                    VStack(spacing: 16) {
                        DashboardSectionHeader(title: "Quick Actions", icon: "bolt.fill", color: .blue)

                        HStack(spacing: 12) {
                            QuickActionButton(
                                icon: "plus.circle.fill",
                                title: "New Game",
                                color: .blue
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

                                    #if DEBUG
                                    print("🎬 Record Live tapped")
                                    #endif

                                    let status = await RecorderPermissions.ensureCapturePermissions(context: "QuickRecord")
                                    guard status == .granted else {
                                        #if DEBUG
                                        print("🛑 Permissions not granted for recording")
                                        #endif
                                        return
                                    }

                                    #if DEBUG
                                    if let game = firstLiveGame {
                                        print("🎮 Opening camera for live game: \(game.opponent)")
                                    }
                                    #endif

                                    showingDirectCamera = true
                                    Haptics.medium()
                                }
                            }
                            .disabled(isCheckingPermissions)
                        }
                    }
                    .padding(.horizontal, dashboardHorizontalPadding)
                }

                // Management Section
                VStack(spacing: 16) {
                    HStack {
                        DashboardSectionHeader(title: "Management", icon: "square.grid.2x2.fill", color: .blue)

                        Button {
                            createNewGame()
                        } label: {
                            Text("+ New Game")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.blue)
                        }
                    }

                    LazyVGrid(columns: managementColumns, spacing: 16) {
                        // 1. Games
                        DashboardFeatureCard(
                            icon: "baseball.diamond.bases",
                            title: "Games",
                            subtitle: "\(viewModel.totalGames) Total",
                            color: .blue
                        ) {
                            postSwitchTab(.games)
                        }

                        // 2. Video Clips
                        DashboardFeatureCard(
                            icon: "video",
                            title: "Video Clips",
                            subtitle: "\(viewModel.totalVideos) Recorded",
                            color: .blue
                        ) {
                            postSwitchTab(.videos)
                        }

                        // 3. Statistics
                        DashboardFeatureCard(
                            icon: "chart.bar.fill",
                            title: "Statistics",
                            subtitle: cachedBA + " AVG",
                            color: .blue
                        ) {
                            postSwitchTab(.stats)
                        }

                        // 4. Seasons
                        DashboardFeatureCard(
                            icon: "calendar",
                            title: "Seasons",
                            subtitle: "\((athlete.seasons ?? []).count) Total",
                            color: .blue
                        ) {
                            showingSeasons = true
                        }

                        // 5. Practice
                        DashboardFeatureCard(
                            icon: "figure.run",
                            title: "Practice",
                            subtitle: "\((athlete.practices ?? []).count) Sessions",
                            color: .blue
                        ) {
                            NotificationCenter.default.post(name: .navigateToMorePractice, object: nil)
                        }

                        // 6. Photos
                        DashboardFeatureCard(
                            icon: "photo.on.rectangle.angled",
                            title: "Photos",
                            subtitle: "\((athlete.photos ?? []).count) Photos",
                            color: .blue
                        ) {
                            showingPhotos = true
                        }

                        // 7. Highlights (Plus+)
                        DashboardPremiumFeatureCard(
                            icon: "star.fill",
                            title: "Highlights",
                            subtitle: "\(viewModel.totalHighlights) Highlights",
                            color: .blue,
                            isPremium: authManager.currentTier >= .plus,
                            badgeLabel: "PLUS"
                        ) {
                            if authManager.currentTier >= .plus {
                                NotificationCenter.default.post(name: .navigateToMoreHighlights, object: nil)
                            } else {
                                Haptics.warning()
                                showingPaywall = true
                            }
                        }

                        // 8. Coaches (Pro Only)
                        DashboardPremiumFeatureCard(
                            icon: "person.3.fill",
                            title: "Coaches",
                            subtitle: "\((athlete.coaches ?? []).count) Coaches",
                            color: .blue,
                            isPremium: authManager.currentTier >= .pro
                        ) {
                            if authManager.currentTier >= .pro {
                                postSwitchTab(.home)
                                Task { @MainActor in
                                    NotificationCenter.default.post(name: Notification.Name.presentCoaches, object: athlete)
                                }
                            } else {
                                Haptics.warning()
                                showingPaywall = true
                            }
                        }
                    }
                }
                .padding(.horizontal, dashboardHorizontalPadding)

                // Quick Stats Section
                VStack(spacing: 16) {
                    DashboardSectionHeader(title: "Quick Stats", icon: "chart.bar.fill", color: .blue)

                    HStack(spacing: 12) {
                        DashboardStatCard(
                            title: "AVG",
                            value: cachedBA,
                            icon: "square.grid.2x2.fill",
                            color: .blue
                        )
                        DashboardStatCard(
                            title: "SLG",
                            value: cachedSLG,
                            icon: "chart.bar.fill",
                            color: .blue
                        )
                        DashboardStatCard(
                            title: "Hits",
                            value: cachedHits,
                            icon: "hand.tap.fill",
                            color: .blue
                        )
                    }
                }
                .padding(.horizontal, dashboardHorizontalPadding)

            }
            .padding(.vertical)
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    // MARK: - Helper Functions

    private func createNewGame() {
        Task { @MainActor in
            postSwitchTab(.games)
            #if DEBUG
            print("🎮 New Game quick action - switching to Games tab")
            #endif
            NotificationCenter.default.post(name: Notification.Name.presentAddGame, object: nil)
            #if DEBUG
            print("📣 Posted .presentAddGame notification with no tournament context")
            #endif
            Haptics.light()
        }
    }

    private func updateCachedStats() {
        seasonRecommendation = SeasonManager.checkSeasonStatus(for: athlete)
        if let stats = athlete.statistics {
            cachedBA = formatBattingAverage(stats.battingAverage)
            cachedSLG = formatBattingAverage(stats.sluggingPercentage)
            cachedHits = String(stats.hits)
        } else {
            cachedBA = ".000"
            cachedSLG = ".000"
            cachedHits = "0"
        }
    }

    /// Formats a rate stat in baseball style: ".325" for values < 1.0, "1.400" for SLG/OPS >= 1.0
    private func formatBattingAverage(_ value: Double) -> String {
        guard !value.isNaN, !value.isInfinite else { return ".000" }
        // SLG can exceed 1.0; show full decimal in that case
        if value >= 1.0 { return String(format: "%.3f", value) }
        let thousandths = Int((value * 1000).rounded())
        guard thousandths > 0 else { return ".000" }
        return String(format: ".%03d", thousandths)
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
                .foregroundStyle(
                    LinearGradient(
                        colors: [color, color.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text(title)
                .font(.title3)
                .fontWeight(.bold)
                .fontDesign(.rounded)
                .foregroundColor(.primary)

            Spacer()
        }
    }
}
