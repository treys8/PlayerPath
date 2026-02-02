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

    @State private var viewModel: GamesDashboardViewModel?
    @State private var pulseAnimation = false
    @State private var showCoachesPremiumAlert = false
    @State private var showingPaywall = false
    @State private var showingDirectCamera = false
    @State private var selectedVideoForPlayback: VideoClip?

    // Dynamic live games query configured via init to safely capture athleteID
    private let athleteID: UUID
    @Query private var liveGames: [Game]

    init(user: User, athlete: Athlete, authManager: ComprehensiveAuthManager) {
        self.user = user
        self.athlete = athlete
        self.authManager = authManager
        self._viewModel = State(initialValue: nil)
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

    // MARK: - Body

    var body: some View {
        Group {
            if let viewModel = viewModel {
                dashboardContent(viewModel: viewModel)
            } else {
                ProgressView("Loading...")
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
            // Initialize ViewModel with environment modelContext once
            if viewModel == nil {
                viewModel = GamesDashboardViewModel(
                    athlete: athlete,
                    modelContext: modelContext
                )
            }
            pulseAnimation = true
            #if DEBUG
            print("🔍 DashboardView liveGames count: \(liveGames.count) for athlete: \(athlete.name)")
            // Debug: Check all games for this athlete
            let allAthleteGames = try? modelContext.fetch(FetchDescriptor<Game>())
            let athleteGames = allAthleteGames?.filter { $0.athlete?.id == athlete.id } ?? []
            print("   Total games for athlete: \(athleteGames.count)")
            let liveCount = athleteGames.filter { $0.isLive }.count
            print("   Live games (manual filter): \(liveCount)")
            if liveCount > 0 {
                for game in athleteGames.filter({ $0.isLive }) {
                    print("   - Live game: \(game.opponent), isLive=\(game.isLive), athlete.id=\(game.athlete?.id.uuidString ?? "nil")")
                }
            }
            #endif
        }
        .alert("Premium Feature", isPresented: $showCoachesPremiumAlert) {
            Button("Upgrade to Premium") {
                Haptics.success()
                showingPaywall = true
            }
            Button("Not Now", role: .cancel) { }
        } message: {
            Text("The Coaches feature is available exclusively to Premium members. Upgrade now to share videos and collaborate with your coaching team!")
        }
        .sheet(isPresented: $showingPaywall) {
            ImprovedPaywallView(user: user)
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

    private func toggleGameLive(_ game: Game) {
        Haptics.light()
        game.isLive.toggle()
        do {
            try modelContext.save()
            NotificationCenter.default.post(name: Notification.Name("GameBecameLive"), object: game)
        } catch {
            print("❌ Failed to toggle game live: \(error)")
        }
    }

    private func endLiveGame(_ game: Game) {
        Haptics.light()
        game.isLive = false
        game.isComplete = true

        if let athlete = game.athlete {
            // Create athlete statistics if they don't exist
            if athlete.statistics == nil {
                let newStats = AthleteStatistics()
                newStats.athlete = athlete
                athlete.statistics = newStats
                modelContext.insert(newStats)
            }

            // Aggregate game statistics into athlete's overall statistics
            if let athleteStats = athlete.statistics, let gameStats = game.gameStats {
                athleteStats.atBats += gameStats.atBats
                athleteStats.hits += gameStats.hits
                athleteStats.singles += gameStats.singles
                athleteStats.doubles += gameStats.doubles
                athleteStats.triples += gameStats.triples
                athleteStats.homeRuns += gameStats.homeRuns
                athleteStats.runs += gameStats.runs
                athleteStats.rbis += gameStats.rbis
                athleteStats.strikeouts += gameStats.strikeouts
                athleteStats.walks += gameStats.walks
                athleteStats.updatedAt = Date()
            }

            // Increment total games
            if let athleteStats = athlete.statistics {
                athleteStats.addCompletedGame()
            }
        }

        do {
            try modelContext.save()
            print("✅ Game ended successfully")
        } catch {
            print("❌ Error ending game: \(error)")
        }
    }


    @ViewBuilder
    private func dashboardContent(viewModel: GamesDashboardViewModel) -> some View {
        ScrollView {
            LazyVStack(spacing: 32) {

                // SEASON RECOMMENDATION BANNER - Shows when athlete needs a season
                let seasonRecommendation = SeasonManager.checkSeasonStatus(for: athlete)
                if seasonRecommendation.message != nil {
                    SeasonRecommendationBanner(athlete: athlete, recommendation: seasonRecommendation)
                        .padding(.horizontal)
                }

                // LIVE GAMES SECTION - Shows when games are live
                if !liveGames.isEmpty {
                    #if DEBUG
                    let _ = print("🔴 DashboardView: Showing \(liveGames.count) live game(s)")
                    let _ = liveGames.enumerated().forEach { index, game in
                        print("   [\(index)] \(game.opponent) | isLive: \(game.isLive) | date: \(game.date?.description ?? "nil")")
                    }
                    #endif

                    VStack(spacing: 12) {
                        // Header with pulsing indicator
                        HStack {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 8, height: 8)
                                    .opacity(pulseAnimation ? 0.4 : 1.0)
                                    .shadow(color: .red.opacity(0.8), radius: pulseAnimation ? 4 : 2)
                                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulseAnimation)

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
                                LiveGameCard(game: game) {
                                    endLiveGame(game)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }

                // Quick Actions Section
                VStack(spacing: 16) {
                    DashboardSectionHeader(title: "Quick Actions", icon: "bolt.fill", color: .orange)

                    HStack(spacing: 12) {
                        QuickActionButton(
                            icon: "plus.circle.fill",
                            title: "New Game",
                            color: .blue
                        ) {
                            Task { @MainActor in
                                // Switch to Games tab
                                postSwitchTab(.games)
                                #if DEBUG
                                print("🎮 New Game quick action - switching to Games tab")
                                #endif

                                // Removed tournament context usage, always nil
                                // Ask the Games module to present its Add Game UI
                                NotificationCenter.default.post(name: Notification.Name.presentAddGame, object: nil)
                                #if DEBUG
                                print("📣 Posted .presentAddGame notification with no tournament context")
                                #endif
                                Haptics.light()
                            }
                        }
                        QuickActionButton(
                            icon: hasLiveGame ? "record.circle" : "video.badge.plus",
                            title: hasLiveGame ? "Record Live" : "Quick Record",
                            color: .red
                        ) {
                            Task { @MainActor in
                                #if DEBUG
                                print("🎬 Quick Record tapped - Has live game: \(hasLiveGame)")
                                #endif

                                // Check permissions first
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
                                } else {
                                    print("🎬 Opening camera for quick record")
                                }
                                #endif

                                // Open camera directly - NEW STREAMLINED FLOW
                                showingDirectCamera = true
                                Haptics.medium()
                            }
                        }
                    }
                }
                .padding(.horizontal)

                // Management Section
                VStack(spacing: 16) {
                    DashboardSectionHeader(title: "Management", icon: "square.grid.2x2.fill", color: .blue)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        // 1. Games
                        DashboardFeatureCard(
                            icon: "sportscourt.fill",
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
                            color: .purple
                        ) {
                            postSwitchTab(.videos)
                        }

                        // 3. Statistics
                        DashboardFeatureCard(
                            icon: "chart.bar.fill",
                            title: "Statistics",
                            subtitle: (athlete.statistics.map { String(format: "%.3f AVG", $0.battingAverage) }) ?? "0.000 AVG",
                            color: .blue
                        ) {
                            postSwitchTab(.stats)
                        }

                        // 4. Highlights
                        DashboardFeatureCard(
                            icon: "star.fill",
                            title: "Highlights",
                            subtitle: "\(viewModel.totalHighlights) Highlights",
                            color: .yellow
                        ) {
                            postSwitchTab(.highlights)
                        }

                        // 5. Practice
                        DashboardFeatureCard(
                            icon: "figure.run",
                            title: "Practice",
                            subtitle: "0 Sessions",
                            color: .green
                        ) {
                            postSwitchTab(.practice)
                        }

                        // 6. Coaches (Premium Only)
                        DashboardPremiumFeatureCard(
                            icon: "person.3.fill",
                            title: "Coaches",
                            subtitle: "0 Coaches",
                            color: .indigo,
                            isPremium: authManager.isPremiumUser
                        ) {
                            if authManager.isPremiumUser {
                                postSwitchTab(.home)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    NotificationCenter.default.post(name: Notification.Name.presentCoaches, object: athlete)
                                }
                            } else {
                                Haptics.warning()
                                showCoachesPremiumAlert = true
                            }
                        }

                        // 7. Seasons
                        DashboardFeatureCard(
                            icon: "calendar",
                            title: "Seasons",
                            subtitle: "\((athlete.seasons ?? []).count) Total",
                            color: .teal
                        ) {
                            postSwitchTab(.more)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                NotificationCenter.default.post(name: Notification.Name.presentSeasons, object: athlete)
                            }
                        }
                    }
                }
                .padding(.horizontal)

                // Quick Stats Section
                VStack(spacing: 16) {
                    DashboardSectionHeader(title: "Quick Stats", icon: "chart.bar.fill", color: .purple)

                    HStack(spacing: 12) {
                        DashboardStatCard(
                            title: "AVG",
                            value: athlete.statistics.map { String(format: "%.3f", $0.battingAverage) } ?? "0.000",
                            icon: "square.grid.2x2.fill",
                            color: .blue
                        )
                        DashboardStatCard(
                            title: "SLG",
                            value: athlete.statistics.map { String(format: "%.3f", $0.sluggingPercentage) } ?? "0.000",
                            icon: "chart.bar.fill",
                            color: .purple
                        )
                        DashboardStatCard(
                            title: "Hits",
                            value: athlete.statistics.map { String($0.hits) } ?? "0",
                            icon: "hand.tap.fill",
                            color: .green
                        )
                    }
                }
                .padding(.horizontal)

                // Recent Videos Section
                if !viewModel.recentVideos.isEmpty {
                    VStack(spacing: 16) {
                        HStack {
                            DashboardSectionHeader(title: "Recent Videos", icon: "video", color: .red)
                            Spacer()
                            NavigationLink {
                                VideoClipsView(athlete: athlete)
                            } label: {
                                HStack(spacing: 4) {
                                    Text("See All")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                }
                                .foregroundColor(.blue)
                            }
                            .simultaneousGesture(TapGesture().onEnded { Haptics.light() })
                        }
                        .padding(.horizontal)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(viewModel.recentVideos, id: \.id) { video in
                                    DashboardVideoCard(video: video)
                                        .onTapGesture {
                                            Haptics.light()
                                            NotificationCenter.default.post(name: Notification.Name.presentFullscreenVideo, object: video)
                                        }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.25), value: viewModel.recentVideos.count)
                }
            }
            .padding(.vertical)
        }
        .refreshable {
            await viewModel.forceRefresh()
        }
        .onAppear {
            // Start auto-refresh timer when view appears
            viewModel.startAutoRefresh()
        }
        .onDisappear {
            // Stop auto-refresh timer when view disappears
            viewModel.stopAutoRefresh()
        }
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
                .foregroundColor(.primary)

            Spacer()
        }
    }
}
