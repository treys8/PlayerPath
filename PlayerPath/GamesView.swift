//
//  GamesView.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import SwiftUI
import SwiftData
import Foundation
import Combine

struct GamesView: View {
    let athlete: Athlete?
    @Environment(\.modelContext) private var modelContext

    // Query games for the current athlete only — avoids loading all games across athletes
    private let athleteID: UUID?
    @Query private var allGames: [Game]

    init(athlete: Athlete?) {
        self.athlete = athlete
        let id = athlete?.id
        self.athleteID = id
        if let id {
            self._allGames = Query(
                filter: #Predicate<Game> { $0.athlete?.id == id },
                sort: [SortDescriptor(\Game.date, order: .reverse)]
            )
        } else {
            self._allGames = Query(sort: [SortDescriptor(\Game.date, order: .reverse)])
        }
    }
    
    @StateObject private var viewModelHolder = ViewModelHolder()
    
    // Error handling
    @State private var errorMessage = ""

    // Loading states
    @State private var isLoading = false

    // Search
    @State private var searchText = ""

    // Season filter
    @State private var selectedSeasonFilter: String? = nil // nil = All Seasons

    final class ViewModelHolder: ObservableObject {
        @Published var viewModel: GamesViewModel?
    }
    
    // Game creation states
    @State private var showingGameCreation = false
    @State private var newGameOpponent = ""
    @State private var newGameDate = Date()
    @State private var makeGameLive = false

    // Season check states
    @State private var showingSeasonCreation = false

    // Delete confirmation
    @State private var gameToDelete: Game?
    @State private var showingDeleteGameConfirmation = false

    // Alert state
    private enum AlertType: Identifiable {
        case error
        case noSeason
        var id: Self { self }
    }
    @State private var activeAlert: AlertType?
    
    // Cached filtered game arrays (updated via updateFilteredGames)
    @State private var cachedLiveGames: [Game] = []
    @State private var cachedUpcomingGames: [Game] = []
    @State private var cachedPastGames: [Game] = []
    @State private var cachedCompletedGames: [Game] = []
    @State private var cachedAvailableSeasons: [Season] = []

    // Computed properties for cleaner code
    private var hasGames: Bool {
        guard let vm = viewModelHolder.viewModel else { return false }
        return !vm.liveGames.isEmpty || !vm.upcomingGames.isEmpty ||
               !vm.pastGames.isEmpty || !vm.completedGames.isEmpty
    }

    // Check if filters are active
    private var hasActiveFilters: Bool {
        selectedSeasonFilter != nil ||
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // Check if we have any filtered results
    private var hasFilteredResults: Bool {
        !cachedLiveGames.isEmpty || !cachedUpcomingGames.isEmpty || !cachedPastGames.isEmpty || !cachedCompletedGames.isEmpty
    }

    private func updateFilteredGames() {
        cachedLiveGames = filterGames(viewModelHolder.viewModel?.liveGames ?? [])
        cachedUpcomingGames = filterGames(viewModelHolder.viewModel?.upcomingGames ?? [])
        cachedPastGames = filterGames(viewModelHolder.viewModel?.pastGames ?? [])
        cachedCompletedGames = filterGames(viewModelHolder.viewModel?.completedGames ?? [])
        let seasons = allGames.compactMap { $0.season }
        let uniqueSeasons = Array(Set(seasons))
        cachedAvailableSeasons = uniqueSeasons.sorted { ($0.startDate ?? Date.distantPast) > ($1.startDate ?? Date.distantPast) }
    }

    // Check if athlete has any seasons
    private var hasSeasons: Bool {
        guard let athlete = athlete else { return false }
        return !(athlete.seasons?.isEmpty ?? true)
    }

    // Handle add game action with season check
    private func handleAddGame() {
        if hasSeasons {
            showingGameCreation = true
        } else {
            activeAlert = .noSeason
        }
    }

    // Game creation sheet content
    @ViewBuilder
    private var gameCreationSheet: some View {
        GameCreationView(
            athlete: athlete,
            onSave: { opponent, date, isLive in
                createGame(opponent: opponent, date: date, isLive: isLive)
            }
        )
    }

    // Season creation sheet content
    @ViewBuilder
    private var seasonCreationSheet: some View {
        if let athlete = athlete {
            CreateSeasonView(athlete: athlete)
        }
    }

    private static let searchDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private func filterGames(_ games: [Game]) -> [Game] {
        var filtered = games

        // Filter by season
        if let seasonFilter = selectedSeasonFilter {
            filtered = filtered.filter { game in
                if seasonFilter == "no_season" {
                    return game.season == nil
                } else {
                    return game.season?.id.uuidString == seasonFilter
                }
            }
        }

        // Filter by search text
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            filtered = filtered.filter { game in
                game.opponent.lowercased().contains(query) ||
                (game.location?.lowercased().contains(query) ?? false) ||
                (game.notes?.lowercased().contains(query) ?? false) ||
                (game.season?.displayName.lowercased().contains(query) ?? false) ||
                (game.date.map { Self.searchDateFormatter.string(from: $0).lowercased().contains(query) } ?? false)
            }
        }

        return filtered
    }

    private var filterDescription: String {
        var parts: [String] = []

        if let seasonID = selectedSeasonFilter {
            if seasonID == "no_season" {
                parts.append("season: None")
            } else if let season = cachedAvailableSeasons.first(where: { $0.id.uuidString == seasonID }) {
                parts.append("season: \(season.displayName)")
            }
        }

        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("search: \"\(searchText)\"")
        }

        return parts.isEmpty ? "your filters" : parts.joined(separator: ", ")
    }

    private func clearAllFilters() {
        Haptics.light()
        withAnimation {
            selectedSeasonFilter = nil
            searchText = ""
        }
    }
    
    // MARK: - Sub-views
    
    @ViewBuilder
    private var gamesListContent: some View {
        // Live Games Section
        if !cachedLiveGames.isEmpty {
            Section("Live") {
                ForEach(cachedLiveGames) { game in
                    NavigationLink(destination: GameDetailView(game: game)) {
                        GameRow(game: game)
                    }
                    .swipeActions(edge: .trailing) {
                        Button("End") {
                            endGame(game)
                        }
                        .tint(.red)
                    }
                }
                .onDelete { indexSet in
                    if let index = indexSet.first, index < cachedLiveGames.count {
                        gameToDelete = cachedLiveGames[index]
                        showingDeleteGameConfirmation = true
                    }
                }
            }
        }
        
        // Upcoming Games Section
        if !cachedUpcomingGames.isEmpty {
            Section("Upcoming") {
                ForEach(cachedUpcomingGames) { game in
                    NavigationLink(destination: GameDetailView(game: game)) {
                        GameRow(game: game)
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Start") {
                            startGame(game)
                        }
                        .tint(.green)
                    }
                    .swipeActions(edge: .leading) {
                        Button(role: .destructive) {
                            gameToDelete = game
                            showingDeleteGameConfirmation = true
                        } label: {
                            Text("Delete")
                        }
                    }
                }
                .onDelete { indexSet in
                    if let index = indexSet.first, index < cachedUpcomingGames.count {
                        gameToDelete = cachedUpcomingGames[index]
                        showingDeleteGameConfirmation = true
                    }
                }
            }
        }

        // Past Games Section (games that happened but weren't marked as complete)
        if !cachedPastGames.isEmpty {
            Section("Past Games") {
                ForEach(cachedPastGames) { game in
                    NavigationLink(destination: GameDetailView(game: game)) {
                        GameRow(game: game)
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Complete") {
                            completeGame(game)
                        }
                        .tint(.blue)
                    }
                    .swipeActions(edge: .leading) {
                        Button(role: .destructive) {
                            gameToDelete = game
                            showingDeleteGameConfirmation = true
                        } label: {
                            Text("Delete")
                        }
                    }
                }
                .onDelete { indexSet in
                    if let index = indexSet.first, index < cachedPastGames.count {
                        gameToDelete = cachedPastGames[index]
                        showingDeleteGameConfirmation = true
                    }
                }
            }
        }
        
        // Completed Games Section
        if !cachedCompletedGames.isEmpty {
            Section("Completed") {
                ForEach(cachedCompletedGames) { game in
                    NavigationLink(destination: GameDetailView(game: game)) {
                        GameRow(game: game)
                    }
                }
                .onDelete { indexSet in
                    if let index = indexSet.first, index < cachedCompletedGames.count {
                        gameToDelete = cachedCompletedGames[index]
                        showingDeleteGameConfirmation = true
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var seasonFilterMenu: some View {
        Menu {
            Button {
                selectedSeasonFilter = nil
            } label: {
                HStack {
                    Text("All Seasons")
                    if selectedSeasonFilter == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }

            Divider()

            ForEach(cachedAvailableSeasons) { season in
                Button {
                    selectedSeasonFilter = season.id.uuidString
                } label: {
                    HStack {
                        Text(season.displayName)
                        if selectedSeasonFilter == season.id.uuidString {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            // Show "No Season" option if there are games without a season
            if allGames.contains(where: { $0.season == nil }) {
                Divider()
                Button {
                    selectedSeasonFilter = "no_season"
                } label: {
                    HStack {
                        Text("No Season")
                        if selectedSeasonFilter == "no_season" {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                if selectedSeasonFilter != nil {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundColor(.blue)
                }
            }
        }
        .accessibilityLabel("Filter by season")
    }

    @ViewBuilder
    private var mainContent: some View {
        Group {
            if isLoading {
                ListSkeletonView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !hasFilteredResults {
                if hasActiveFilters && hasGames {
                    FilteredEmptyStateView(
                        filterDescription: filterDescription,
                        onClearFilters: clearAllFilters
                    )
                } else {
                    EmptyGamesView {
                        handleAddGame()
                    }
                }
            } else {
                List {
                    gamesListContent
                }
                .refreshable {
                    await refreshGames()
                }
            }
        }
    }

    var body: some View {
        mainContent
            .navigationTitle("Games")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Search by opponent or date")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { handleAddGame() }) {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add new game")
                }

                if hasGames {
                    ToolbarItem(placement: .topBarLeading) {
                        EditButton()
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        seasonFilterMenu
                    }
                }
            }
            .onAppear {
                if viewModelHolder.viewModel == nil {
                    viewModelHolder.viewModel = GamesViewModel(modelContext: modelContext, athlete: athlete, allGames: allGames)
                    #if DEBUG
                    print("🎮 GamesView: Initialized ViewModel with \(allGames.count) games")
                    #endif
                } else {
                    viewModelHolder.viewModel?.update(allGames: allGames)
                    #if DEBUG
                    print("🎮 GamesView: Updated ViewModel with \(allGames.count) games")
                    #endif
                }
                updateFilteredGames()
            }
            .onChange(of: athlete?.id) { oldValue, newValue in
                #if DEBUG
                print("🎮 GamesView: Athlete changed from \(oldValue?.uuidString ?? "nil") to \(newValue?.uuidString ?? "nil")")
                #endif
                viewModelHolder.viewModel = GamesViewModel(modelContext: modelContext, athlete: athlete, allGames: allGames)
                updateFilteredGames()
            }
            .onChange(of: allGames) { oldValue, newValue in
                #if DEBUG
                print("🎮 GamesView: Games changed from \(oldValue.count) to \(newValue.count)")
                if let athlete = athlete {
                    let athleteGames = newValue.filter { $0.athlete?.id == athlete.id }
                    print("🎮 GamesView: Athlete '\(athlete.name)' has \(athleteGames.count) games")
                }
                #endif
                viewModelHolder.viewModel?.update(allGames: newValue)
                updateFilteredGames()
            }
            .onChange(of: searchText) { _, _ in
                updateFilteredGames()
            }
            .onChange(of: selectedSeasonFilter) { _, _ in
                updateFilteredGames()
            }
            .sheet(isPresented: $showingGameCreation) {
                gameCreationSheet
            }
            .sheet(isPresented: $showingSeasonCreation) {
                seasonCreationSheet
            }
            .alert(item: $activeAlert) { alertType in
                switch alertType {
                case .error:
                    Alert(
                        title: Text("Error"),
                        message: Text(errorMessage),
                        dismissButton: .default(Text("OK"))
                    )
                case .noSeason:
                    Alert(
                        title: Text("Create a Season First"),
                        message: Text("Games belong to a season. Create a season to start tracking games."),
                        primaryButton: .default(Text("Create Season")) {
                            showingSeasonCreation = true
                        },
                        secondaryButton: .cancel()
                    )
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .presentAddGame)) { _ in
                handleAddGame()
            }
            .confirmationDialog(
                "Delete Game",
                isPresented: $showingDeleteGameConfirmation,
                presenting: gameToDelete
            ) { game in
                Button("Delete \"\(game.opponent)\"", role: .destructive) {
                    deleteGame(game)
                }
            } message: { game in
                Text("This will permanently delete this game and all its video clips, photos, and statistics.")
            }
    }

    // MARK: - Helper Methods
    
    private func startGame(_ game: Game) {
        // Check if game has a season
        guard game.season != nil else {
            errorMessage = "This game needs a season before it can be started. Please assign a season to the game first."
            activeAlert = .error
            return
        }
        viewModelHolder.viewModel?.start(game)
        refreshGames()
    }
    
    private func endGame(_ game: Game) {
        viewModelHolder.viewModel?.end(game)
        refreshGames()
    }
    
    private func completeGame(_ game: Game) {
        game.isComplete = true
        Task {
            // Recalculate game stats first (they feed into athlete stats)
            try? StatisticsService.shared.recalculateGameStatistics(for: game, context: modelContext)
            if let athlete = game.athlete {
                try? StatisticsService.shared.recalculateAthleteStatistics(for: athlete, context: modelContext)
            }
            do {
                try modelContext.save()
                refreshGames()
                // Track completed game for review prompt eligibility
                ReviewPromptManager.shared.recordCompletedGame()
            } catch {
                showError("Failed to mark game as complete: \(error.localizedDescription)")
            }
        }
    }

    private func deleteGame(_ game: Game) {
        viewModelHolder.viewModel?.deleteDeep(game)
        refreshGames()
    }
    
    private func deleteGames(from games: [Game], at indexSet: IndexSet) {
        for index in indexSet {
            guard index < games.count else { continue }
            viewModelHolder.viewModel?.deleteDeep(games[index])
        }
        refreshGames()
    }
    
    private func createGame(opponent: String, date: Date, isLive: Bool) {
        viewModelHolder.viewModel?.create(
            opponent: opponent,
            date: date,
            isLive: isLive,
            onError: { errorMessage in
                showError(errorMessage)
            },
            onSuccess: { createdGame in
                guard UserDefaults.standard.bool(forKey: "notif_gameReminders"),
                      let gameDate = createdGame.date,
                      gameDate > Date().addingTimeInterval(60 * 60) else { return }
                Task {
                    await PushNotificationService.shared.scheduleGameReminder(
                        gameId: createdGame.id.uuidString,
                        opponent: opponent,
                        scheduledTime: gameDate
                    )
                }
            }
        )
        refreshGames()
    }
    
    private func refreshGames() {
        viewModelHolder.viewModel?.update(allGames: allGames)
    }

    @MainActor
    private func refreshGames() async {
        Haptics.light()
        viewModelHolder.viewModel?.update(allGames: allGames)
        // Small delay for haptic feedback
        try? await Task.sleep(nanoseconds: 300_000_000)
    }

    private func showError(_ message: String) {
        errorMessage = message
        activeAlert = .error
    }
}

// MARK: - Game Row View
struct GameRow: View {
    let game: Game
    @State private var isPressed = false
    @State private var livePulse = false

    var body: some View {
        HStack(spacing: 0) {
            // Accent bar
            RoundedRectangle(cornerRadius: 2)
                .fill(statusColor)
                .frame(width: 4)
                .padding(.vertical, 4)

            HStack(spacing: 12) {
                GameInfoView(game: game, showSeason: !game.isLive)
                Spacer()
                RightStatusView(game: game)
            }
            .padding(.leading, 12)
            .padding(.trailing, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: .cornerLarge, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Game against \(game.opponent)")
        .accessibilityValue(game.isLive ? "Live" : game.isComplete ? "Completed" : "Scheduled")
    }

    private var statusColor: Color {
        if game.isLive {
            return .red
        } else if game.isComplete {
            return .green
        } else if let date = game.date, date < Date() {
            return .orange
        } else {
            return .blue
        }
    }
    
    private struct RightStatusView: View {
        let game: Game

        var body: some View {
            HStack(spacing: 12) {
                // Stats summary (if available)
                if let stats = game.gameStats, stats.atBats > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(stats.hits)-\(stats.atBats)")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        Text(String(format: ".%03d", Int(Double(stats.hits) / Double(stats.atBats) * 1000)))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                // Status badge
                Group {
                    if game.isLive {
                        LiveBadge()
                    } else if game.isComplete {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.green, .green.opacity(0.7)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private struct GameInfoView: View {
        let game: Game
        var showSeason: Bool = true

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                // Opponent name
                Text("vs \(game.opponent)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                // Date and season
                HStack(spacing: 8) {
                    if let date = game.date {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.caption2)
                            Text(date, format: .dateTime.month(.abbreviated).day().year())
                                .font(.caption)
                                .lineLimit(1)
                        }
                        .foregroundColor(.secondary)
                    }

                    if showSeason, let season = game.season {
                        Text(season.displayName)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(season.isActive ? Color.blue : Color.gray)
                            )
                    }
                }
            }
        }
    }
}

// Pulsing live badge
struct LiveBadge: View {
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            // Glow
            Capsule()
                .fill(Color.red.opacity(0.3))
                .frame(width: 52, height: 26)
                .scaleEffect(isPulsing ? 1.3 : 1.0)
                .opacity(isPulsing ? 0 : 0.6)

            // Badge
            HStack(spacing: 4) {
                Circle()
                    .fill(.white)
                    .frame(width: 6, height: 6)

                Text("LIVE")
                    .font(.caption2)
                    .fontWeight(.bold)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.red, .red.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .shadow(color: .red.opacity(0.4), radius: 4, x: 0, y: 2)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                isPulsing = true
            }
        }
    }
}

struct EmptyGamesView: View {
    let onAddGame: () -> Void

    @State private var isAnimating = false
    @State private var floatOffset: CGFloat = 0

    var body: some View {
        ZStack {
            // Subtle background decoration
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.green.opacity(0.08), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 200
                    )
                )
                .frame(width: 400, height: 400)
                .blur(radius: 60)
                .offset(y: -50)

            VStack(spacing: 28) {
                // Floating icon with glow
                ZStack {
                    // Glow effect
                    Image(systemName: "baseball.diamond.bases")
                        .font(.system(size: 72, weight: .light))
                        .foregroundStyle(.green.opacity(0.3))
                        .blur(radius: 20)

                    Image(systemName: "baseball.diamond.bases")
                        .font(.system(size: 72, weight: .light))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.green, .green.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .symbolRenderingMode(.hierarchical)
                }
                .offset(y: floatOffset)
                .scaleEffect(isAnimating ? 1.0 : 0.8)
                .opacity(isAnimating ? 1.0 : 0.0)

                VStack(spacing: 10) {
                    Text("No Games Yet")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)

                    Text("Create your first game to record\nand track performance")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(2)
                }
                .opacity(isAnimating ? 1.0 : 0.0)
                .offset(y: isAnimating ? 0 : 10)

                Button {
                    Haptics.medium()
                    onAddGame()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.body)
                        Text("Add Game")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: 200)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [.green, .green.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(Capsule())
                    .shadow(color: .green.opacity(0.3), radius: 12, x: 0, y: 6)
                }
                .buttonStyle(PremiumButtonStyle())
                .opacity(isAnimating ? 1.0 : 0.0)
                .offset(y: isAnimating ? 0 : 20)
            }
            .padding(.horizontal, 40)
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                isAnimating = true
            }
            // Floating animation
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                floatOffset = -8
            }
        }
    }
}

struct GameDetailView: View {
    let game: Game
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @State private var showingEndGame = false
    @State private var showingVideoRecorder = false
    @State private var showingUploadRecorder = false
    @State private var showingDeleteConfirmation = false
    @State private var showingManualStats = false
    @State private var showingEditGame = false
    @State private var gameService: GameService? = nil
    
    var videoClips: [VideoClip] {
        (game.videoClips ?? []).sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }
    
    var body: some View {
        List {
            // Game Info Section
            Section("Game Details") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Opponent")
                            .fontWeight(.semibold)
                        Spacer()
                        Text(game.opponent)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Date")
                            .fontWeight(.semibold)
                        Spacer()
                        if let date = game.date {
                            Text(date, format: .dateTime.month().day().hour().minute())
                                .foregroundColor(.secondary)
                        } else {
                            Text("Unknown Date")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if let location = game.location, !location.isEmpty {
                        HStack {
                            Text("Location")
                                .fontWeight(.semibold)
                            Spacer()
                            Text(location)
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack {
                        Text("Status")
                            .fontWeight(.semibold)
                        Spacer()

                        Group {
                            if game.isLive {
                                Text("LIVE")
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.red)
                                    .cornerRadius(4)
                            } else if game.isComplete {
                                Text("COMPLETED")
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.gray)
                                    .cornerRadius(4)
                            } else {
                                Text("SCHEDULED")
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue)
                                    .cornerRadius(4)
                            }
                        }
                        .font(.caption)
                        .fontWeight(.bold)
                    }

                    if let notes = game.notes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notes")
                                .fontWeight(.semibold)
                            Text(notes)
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                        }
                    }
                }
                .padding(.vertical, 5)
            }
            
            // Quick Actions Section
            Section("Actions") {
                if !game.isComplete {
                    Button(action: { showingVideoRecorder = true }) {
                        Label("Record Video", systemImage: "video.badge.plus")
                    }

                    if game.isLive {
                        Button(role: .destructive) {
                            showingEndGame = true
                        } label: {
                            Label("End Game", systemImage: "stop.circle")
                        }
                    } else {
                        Button {
                            startGame()
                        } label: {
                            Label("Start Game", systemImage: "play.circle")
                        }
                    }
                } else {
                    Button {
                        game.isComplete = false
                        game.isLive = true
                        try? modelContext.save()
                    } label: {
                        Label("Restart Game", systemImage: "arrow.counterclockwise")
                    }

                    Button(action: { showingUploadRecorder = true }) {
                        Label("Upload from Camera Roll", systemImage: "photo.badge.plus")
                    }
                }

                // Edit Game Details - available for all games
                Button(action: { showingEditGame = true }) {
                    Label("Edit Game", systemImage: "pencil")
                }

                // Manual Statistics Entry
                Button(action: { showingManualStats = true }) {
                    Label("Enter Statistics", systemImage: "chart.bar.doc.horizontal")
                }
                
                if !game.isLive {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete Game", systemImage: "trash")
                    }
                }
            }

            // Video Clips Section
            Section("Video Clips (\(videoClips.count))") {
                if videoClips.isEmpty {
                    Text("No videos recorded yet")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(videoClips) { clip in
                        VideoClipRow(clip: clip, hasCoachingAccess: authManager.hasCoachingAccess)
                    }
                }
            }
            
            // Game Statistics
            if let stats = game.gameStats {
                Section("Game Statistics") {
                    HStack {
                        Text("At Bats")
                        Spacer()
                        Text("\(stats.atBats)")
                            .fontWeight(.semibold)
                    }
                    HStack {
                        Text("Hits")
                        Spacer()
                        Text("\(stats.hits)")
                            .fontWeight(.semibold)
                    }
                    HStack {
                        Text("Runs")
                        Spacer()
                        Text("\(stats.runs)")
                            .fontWeight(.semibold)
                    }
                    HStack {
                        Text("RBIs")
                        Spacer()
                        Text("\(stats.rbis)")
                            .fontWeight(.semibold)
                    }
                    HStack {
                        Text("Strikeouts")
                        Spacer()
                        Text("\(stats.strikeouts)")
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                    }
                    HStack {
                        Text("Ground Outs")
                        Spacer()
                        Text("\(stats.groundOuts)")
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                    }
                    HStack {
                        Text("Fly Outs")
                        Spacer()
                        Text("\(stats.flyOuts)")
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                    }
                    HStack {
                        Text("Walks")
                        Spacer()
                        Text("\(stats.walks)")
                            .fontWeight(.semibold)
                    }
                    
                    // Calculate and show batting average for this game
                    if stats.atBats > 0 {
                        HStack {
                            Text("Batting Average")
                            Spacer()
                            Text(String(format: "%.3f", Double(stats.hits) / Double(stats.atBats)))
                                .fontWeight(.semibold)
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
        }
        .navigationTitle("vs \(game.opponent)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    // Video Actions
                    if !game.isComplete {
                        Button(action: { showingVideoRecorder = true }) {
                            Label("Record Video", systemImage: "video.badge.plus")
                        }
                    }
                    
                    // Game State Actions
                    if !game.isComplete {
                        if game.isLive {
                            Button(action: { showingEndGame = true }) {
                                Label("End Game", systemImage: "stop.circle")
                            }
                        } else {
                            Button(action: { startGame() }) {
                                Label("Start Game", systemImage: "play.circle")
                            }
                        }
                    } else {
                        Button(action: {
                            game.isComplete = false
                            game.isLive = true
                            try? modelContext.save()
                        }) {
                            Label("Restart Game", systemImage: "arrow.counterclockwise")
                        }

                        Button(action: { showingUploadRecorder = true }) {
                            Label("Upload from Camera Roll", systemImage: "photo.badge.plus")
                        }
                    }

                    Divider()
                    
                    // Edit Game Details
                    Button(action: { showingEditGame = true }) {
                        Label("Edit Game", systemImage: "pencil")
                    }

                    // Statistics Action
                    Button(action: { showingManualStats = true }) {
                        Label("Enter Statistics", systemImage: "chart.bar.doc.horizontal")
                    }

                    Divider()
                    
                    // Destructive Actions
                    if !game.isLive {
                        Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                            Label("Delete Game", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
            }
        }
        .alert("End Game", isPresented: $showingEndGame) {
            Button("Cancel", role: .cancel) { }
            Button("End", role: .destructive) {
                endGame()
            }
        } message: {
            Text("Are you sure you want to end this game? You won't be able to record more videos for it.")
        }
        .alert("Delete Game", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteGame()
            }
        } message: {
            if game.isComplete, !videoClips.isEmpty || game.gameStats != nil {
                let clipCount = videoClips.count
                let hasStats = game.gameStats != nil
                if clipCount > 0 && hasStats {
                    Text("This game has \(clipCount) video clip\(clipCount == 1 ? "" : "s") and recorded statistics. Deleting it will permanently remove all data and recalculate career stats.")
                } else if clipCount > 0 {
                    Text("This game has \(clipCount) video clip\(clipCount == 1 ? "" : "s"). Deleting it will permanently remove all data.")
                } else {
                    Text("This game has recorded statistics. Deleting it will permanently remove all data and recalculate career stats.")
                }
            } else {
                Text("Are you sure you want to delete this game? This action cannot be undone.")
            }
        }
        .fullScreenCover(isPresented: $showingVideoRecorder) {
            DirectCameraRecorderView(athlete: game.athlete, game: game)
        }
        .fullScreenCover(isPresented: $showingUploadRecorder) {
            VideoRecorderView_Refactored(athlete: game.athlete, game: game)
        }
        .sheet(isPresented: $showingManualStats) {
            ManualStatisticsEntryView(game: game)
        }
        .sheet(isPresented: $showingEditGame) {
            EditGameSheet(game: game)
        }
        .onAppear {
            if gameService == nil { gameService = GameService(modelContext: modelContext) }
        }
    }
    
    @MainActor
    private func startGame() {
        Task { await gameService?.start(game) }
    }
    
    @MainActor
    private func endGame() {
        Task { await gameService?.end(game) }
    }
    
    @MainActor
    private func deleteGame() {
        Task {
            await gameService?.deleteGameDeep(game)
            dismiss()
        }
    }
}

// MARK: - Edit Game Sheet

struct EditGameSheet: View {
    @Bindable var game: Game
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var opponent: String = ""
    @State private var date: Date = Date()
    @State private var location: String = ""
    @State private var notes: String = ""

    enum Field: Hashable { case opponent, location, notes }
    @FocusState private var focusedField: Field?
    @State private var showingSaveError = false

    private var isValidOpponent: Bool {
        let trimmed = opponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 2 && trimmed.count <= 50
    }

    private var hasChanges: Bool {
        opponent != game.opponent ||
        date != (game.date ?? Date()) ||
        location != (game.location ?? "") ||
        notes != (game.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Game Details") {
                    TextField("Opponent", text: $opponent)
                        .focused($focusedField, equals: .opponent)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .location }
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()

                    if !opponent.isEmpty && !isValidOpponent {
                        Label("Opponent name must be 2-50 characters", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }

                    DatePicker("Date & Time", selection: $date)
                }

                Section("Location (Optional)") {
                    TextField("Location", text: $location)
                        .focused($focusedField, equals: .location)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .notes }
                        .textInputAutocapitalization(.words)
                }

                Section("Notes (Optional)") {
                    TextField("Game notes", text: $notes, axis: .vertical)
                        .focused($focusedField, equals: .notes)
                        .submitLabel(.done)
                        .lineLimit(3...6)
                }

                if game.isLive {
                    Section {
                        Label("This game is currently live", systemImage: "circle.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                } else if game.isComplete {
                    Section {
                        Label("This game has been completed", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Edit Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                        .fontWeight(.semibold)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                    .disabled(!isValidOpponent || !hasChanges)
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                // Initialize with current values
                opponent = game.opponent
                date = game.date ?? Date()
                location = game.location ?? ""
                notes = game.notes ?? ""
            }
            .alert("Save Error", isPresented: $showingSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Failed to save changes. Please try again.")
            }
        }
    }

    private func saveChanges() {
        let dateChanged = date != (game.date ?? Date())
        let gameId = game.id.uuidString
        let newOpponent = opponent.trimmingCharacters(in: .whitespacesAndNewlines)

        game.opponent = newOpponent
        game.date = date
        game.location = location.isEmpty ? nil : location.trimmingCharacters(in: .whitespacesAndNewlines)
        game.notes = notes.isEmpty ? nil : notes.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                try modelContext.save()

                // Reschedule game reminder if date changed
                if dateChanged && UserDefaults.standard.bool(forKey: "notif_gameReminders") {
                    PushNotificationService.shared.cancelNotifications(withIdentifiers: ["game_reminder_\(gameId)"])
                    if date > Date().addingTimeInterval(60 * 60) {
                        await PushNotificationService.shared.scheduleGameReminder(
                            gameId: gameId,
                            opponent: newOpponent,
                            scheduledTime: date
                        )
                    }
                }

                Haptics.success()
                dismiss()
            } catch {
                showingSaveError = true
                Haptics.error()
            }
        }
    }
}

struct AddGameView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let athlete: Athlete?

    @State private var opponent = ""
    @State private var date = Date()
    @State private var startAsLive = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isSeasonError = false

    init(athlete: Athlete? = nil) {
        self.athlete = athlete
    }
    
    private var isValidOpponent: Bool {
        let trimmed = opponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 2 && trimmed.count <= 50
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Game Details") {
                    TextField("Opponent", text: $opponent)
                        .submitLabel(.done)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Opponent name")

                    if !opponent.isEmpty && !isValidOpponent {
                        Label {
                            Text("Opponent name must be 2-50 characters")
                                .font(.caption)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                        }
                    }
                    
                    DatePicker("Date & Time", selection: $date)
                }
                
                // Removed tournament selection section
                
                Section {
                    Toggle("Start as Live Game", isOn: $startAsLive)
                }
            }
            .navigationTitle("New Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveGame()
                    }
                    .disabled(!isValidOpponent)
                }
            }
            // Removed onAppear that sets selectedTournament
        }
        .alert(isSeasonError ? "No Active Season" : "Error", isPresented: $showingError) {
            if isSeasonError {
                Button("Create Season") {
                    dismiss()
                    // Post notification to open seasons view
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms for dismiss animation
                        NotificationCenter.default.post(name: Notification.Name.presentSeasons, object: athlete)
                    }
                }
                Button("Add to Year Only") {
                    saveGameWithoutSeason()
                }
                Button("Cancel", role: .cancel) { }
            } else {
                Button("OK") { }
            }
        } message: {
            if isSeasonError {
                let calendar = Calendar.current
                let year = calendar.component(.year, from: date)
                Text("You don't have an active season. Create a season to organize your games, or add this game to year \(year) for basic tracking.")
            } else {
                Text(errorMessage)
            }
        }
    }

    private func saveGame() {
        guard let athlete = athlete else {
            errorMessage = "No athlete selected"
            showingError = true
            return
        }

        guard isValidOpponent else {
            errorMessage = "Please enter a valid opponent name (2-50 characters)"
            showingError = true
            return
        }

        let trimmedOpponent = opponent.trimmingCharacters(in: .whitespacesAndNewlines)

        #if DEBUG
        print("📱 AddGameView.saveGame() called")
        print("   Athlete: \(athlete.name)")
        print("   Active season: \(athlete.activeSeason?.name ?? "none")")
        print("   Seasons count: \(athlete.seasons?.count ?? 0)")
        #endif

        // Use GameService for consistent game creation
        let gameService = GameService(modelContext: modelContext)
        // Removed tournament parameter from call

        Task {
            let result = await gameService.createGame(
                for: athlete,
                opponent: trimmedOpponent,
                date: date,
                isLive: startAsLive
            )

            await MainActor.run {
                switch result {
                case .success(let createdGame):
                    #if DEBUG
                    print("   ✅ Game created successfully")
                    #endif
                    // Schedule a reminder if the game is in the future and reminders are enabled
                    if UserDefaults.standard.bool(forKey: "notif_gameReminders"),
                       let gameDate = createdGame.date,
                       gameDate > Date().addingTimeInterval(60 * 60) {
                        Task {
                            await PushNotificationService.shared.scheduleGameReminder(
                                gameId: createdGame.id.uuidString,
                                opponent: trimmedOpponent,
                                scheduledTime: gameDate
                            )
                        }
                    }
                    dismiss()
                case .failure(let error):
                    #if DEBUG
                    print("   ❌ Game creation failed: \(error)")
                    print("   Is season error: \(error == .noActiveSeason)")
                    #endif
                    // Show error alert
                    errorMessage = error.localizedDescription
                    isSeasonError = (error == .noActiveSeason)
                    showingError = true
                }
            }
        }
    }

    private func saveGameWithoutSeason() {
        guard let athlete = athlete else {
            errorMessage = "No athlete selected"
            showingError = true
            return
        }

        guard isValidOpponent else {
            errorMessage = "Please enter a valid opponent name (2-50 characters)"
            showingError = true
            return
        }

        let trimmedOpponent = opponent.trimmingCharacters(in: .whitespacesAndNewlines)

        // Use GameService with allowWithoutSeason flag
        let gameService = GameService(modelContext: modelContext)

        Task {
            let result = await gameService.createGame(
                for: athlete,
                opponent: trimmedOpponent,
                date: date,
                isLive: startAsLive,
                allowWithoutSeason: true
            )

            await MainActor.run {
                switch result {
                case .success(let createdGame):
                    // Success - dismiss
                    // Schedule a reminder if the game is in the future and reminders are enabled
                    if UserDefaults.standard.bool(forKey: "notif_gameReminders"),
                       let gameDate = createdGame.date,
                       gameDate > Date().addingTimeInterval(60 * 60) {
                        Task {
                            await PushNotificationService.shared.scheduleGameReminder(
                                gameId: createdGame.id.uuidString,
                                opponent: trimmedOpponent,
                                scheduledTime: gameDate
                            )
                        }
                    }
                    dismiss()
                case .failure(let error):
                    // Show error alert
                    errorMessage = error.localizedDescription
                    isSeasonError = false
                    showingError = true
                }
            }
        }
    }
}

struct VideoClipRow: View {
    let clip: VideoClip
    let hasCoachingAccess: Bool
    @State private var showingVideoPlayer = false
    @State private var showingShareToFolder = false
    @State private var thumbnailImage: UIImage?
    @State private var isLoadingThumbnail = false
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        Button(action: { showingVideoPlayer = true }) {
            HStack {
                // Enhanced thumbnail with overlay - using the same logic as VideoClipListItem
                ZStack(alignment: .bottomLeading) {
                    // Thumbnail Image
                    Group {
                        if let thumbnail = thumbnailImage {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 50, height: 35)
                                .clipped()
                        } else {
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 50, height: 35)
                                .overlay(
                                    VStack(spacing: 2) {
                                        if isLoadingThumbnail {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                                .scaleEffect(0.5)
                                        } else {
                                            Image(systemName: "video.fill")
                                                .foregroundColor(.white)
                                                .font(.caption)
                                        }
                                        
                                        if !isLoadingThumbnail {
                                            Text("No Preview")
                                                .font(.system(size: 8))
                                                .foregroundColor(.white)
                                        }
                                    }
                                )
                        }
                    }
                    .cornerRadius(6)
                    .overlay(
                        // Play button overlay
                        Circle()
                            .fill(Color.black.opacity(0.6))
                            .frame(width: 16, height: 16)
                            .overlay(
                                Image(systemName: "play.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: 8))
                            )
                    )
                    
                    // Play result badge
                    if let playResult = clip.playResult {
                        Text(playResultAbbreviation(for: playResult.type))
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(playResultColor(for: playResult.type))
                            .cornerRadius(3)
                            .offset(x: 2, y: -2)
                    } else {
                        Text("?")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .frame(width: 12, height: 12)
                            .background(Color.gray)
                            .clipShape(Circle())
                            .offset(x: 2, y: -2)
                    }
                    
                    // Highlight indicator
                    if clip.isHighlight {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                            .font(.system(size: 8))
                            .background(Circle().fill(Color.black.opacity(0.6)).frame(width: 12, height: 12))
                            .offset(x: -2, y: 2)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    if let playResult = clip.playResult {
                        Text(String(describing: playResult.type))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    } else {
                        Text("Unrecorded Play")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    if let createdAt = clip.createdAt {
                        Text(createdAt, formatter: DateFormatter.shortTime)
                    } else {
                        Text("Unknown Time")
                    }
                }
                
                Spacer()
                
                if clip.isHighlight {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                        .font(.caption)
                }
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .font(.caption)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(clip.playResult?.type.displayName ?? "Unrecorded Play")
        .accessibilityHint("Opens the video")
        .contextMenu {
            if hasCoachingAccess {
                Button {
                    showingShareToFolder = true
                } label: {
                    Label("Share to Coach Folder", systemImage: "folder.badge.person.fill")
                }
            }
        }
        .task {
            await loadThumbnail()
        }
        .fullScreenCover(isPresented: $showingVideoPlayer) {
            VideoPlayerView(clip: clip)
        }
        .sheet(isPresented: $showingShareToFolder) {
            ShareToCoachFolderView(clip: clip)
        }
    }
    
    @MainActor
    private func loadThumbnail() async {
        // Skip if already loading or already have image
        guard !isLoadingThumbnail, thumbnailImage == nil else { return }
        
        // Check if we have a thumbnail path
        guard let thumbnailPath = clip.thumbnailPath else {
            // Generate thumbnail if none exists
            await generateMissingThumbnail()
            return
        }
        
        isLoadingThumbnail = true
        
        do {
            // Load thumbnail asynchronously using the same cache system
            let size = CGSize(width: 160, height: 90)
            let image = try await ThumbnailCache.shared.loadThumbnail(at: thumbnailPath, targetSize: size)
            thumbnailImage = image
        } catch {
            // Try to regenerate thumbnail
            await generateMissingThumbnail()
        }
        
        isLoadingThumbnail = false
    }
    
    private func generateMissingThumbnail() async {
        
        let videoURL = clip.resolvedFileURL
        let result = await VideoFileManager.generateThumbnail(from: videoURL)

        await MainActor.run {
            switch result {
            case .success(let thumbnailPath):
                clip.thumbnailPath = thumbnailPath
                do {
                    try modelContext.save()
                } catch {
                }
                isLoadingThumbnail = false
            case .failure(_):
                isLoadingThumbnail = false
            }
        }
        // Load through the cache (off main thread) after saving the path
        if case .success(let thumbnailPath) = result {
            let size = CGSize(width: 160, height: 90)
            if let image = try? await ThumbnailCache.shared.loadThumbnail(at: thumbnailPath, targetSize: size) {
                await MainActor.run { thumbnailImage = image }
            }
        }
    }
    
    // Helper functions for styling
    private func playResultAbbreviation(for type: PlayResultType) -> String {
        switch type {
        case .single: return "1B"
        case .double: return "2B"
        case .triple: return "3B"
        case .homeRun: return "HR"
        case .walk: return "BB"
        case .strikeout: return "K"
        case .groundOut: return "GO"
        case .flyOut: return "FO"
        case .ball: return "B"
        case .strike: return "S"
        case .hitByPitch: return "HBP"
        case .wildPitch: return "WP"
        }
    }

    private func playResultColor(for type: PlayResultType) -> Color {
        switch type {
        case .single: return .green
        case .double: return .blue
        case .triple: return .orange
        case .homeRun: return .gold
        case .walk: return .cyan
        case .strikeout: return .red
        case .groundOut, .flyOut: return .red
        case .ball: return .orange
        case .strike: return .green
        case .hitByPitch: return .purple
        case .wildPitch: return .red
        }
    }
}

struct GameCreationView: View {
    @Environment(\.dismiss) private var dismiss
    let athlete: Athlete?
    let onSave: (String, Date, Bool) -> Void

    @State private var opponent = ""
    @State private var date = Date()
    @State private var makeGameLive = false
    @State private var showingValidationError = false
    @State private var validationMessage = ""

    // Get previous opponents for autocomplete
    private var previousOpponents: [String] {
        guard let athlete = athlete else { return [] }
        let opponents = (athlete.games ?? [])
            .map { $0.opponent }
            .filter { !$0.isEmpty }
        // Deduplicate and sort by frequency
        let frequency = opponents.reduce(into: [:]) { counts, name in
            counts[name, default: 0] += 1
        }
        return Array(Set(opponents))
            .sorted { frequency[$0, default: 0] > frequency[$1, default: 0] }
    }

    // Filter opponents by current input
    private var filteredOpponents: [String] {
        guard !opponent.isEmpty else { return previousOpponents.prefix(5).map { $0 } }
        return previousOpponents.filter {
            $0.localizedCaseInsensitiveContains(opponent)
        }.prefix(5).map { $0 }
    }

    // Validation
    private var isValidOpponent: Bool {
        let trimmed = opponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 2 && trimmed.count <= 50
    }

    private var canSave: Bool {
        isValidOpponent
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Game Details") {
                    TextField("Opponent", text: $opponent)
                        .submitLabel(.done)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()

                    // Show validation feedback
                    if !opponent.isEmpty && !isValidOpponent {
                        Label {
                            Text("Opponent name must be 2-50 characters")
                                .font(.caption)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                        }
                    }

                    DatePicker("Date & Time", selection: $date)
                }

                // Opponent Suggestions
                if !filteredOpponents.isEmpty && opponent.count < 3 || !filteredOpponents.filter({ $0.localizedCaseInsensitiveContains(opponent) && $0 != opponent }).isEmpty {
                    Section("Recent Opponents") {
                        ForEach(filteredOpponents, id: \.self) { suggestion in
                            Button {
                                opponent = suggestion
                            } label: {
                                HStack {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .foregroundColor(.blue)
                                        .font(.caption)
                                    Text(suggestion)
                                        .foregroundColor(.primary)
                                    Spacer()
                                }
                            }
                        }
                    }
                }

                Section("Game Options") {
                    Toggle("Start as Live Game", isOn: $makeGameLive)
                    
                    if makeGameLive {
                        Label {
                            Text("Game becomes active for recording")
                                .font(.caption)
                        } icon: {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                Section {
                    Label {
                        Text("Add stats and videos after creating the game")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } icon: {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.yellow)
                    }
                }
            }
            .navigationTitle("New Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveGame()
                    }
                    .disabled(!canSave)
                }
            }
            // Removed onAppear that sets selectedTournament
        }
        .alert("Validation Error", isPresented: $showingValidationError) {
            Button("OK") { }
        } message: {
            Text(validationMessage)
        }
    }
    
    private func saveGame() {
        // Final validation
        guard isValidOpponent else {
            validationMessage = "Please enter a valid opponent name (2-50 characters)"
            showingValidationError = true
            return
        }
        
        // Check for reasonable date (not too far in past/future)
        let yearFromNow = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
        let yearAgo = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
        
        if date > yearFromNow {
            validationMessage = "Game date cannot be more than 1 year in the future"
            showingValidationError = true
            return
        }
        
        if date < yearAgo {
            validationMessage = "Game date cannot be more than 1 year in the past"
            showingValidationError = true
            return
        }
        
        #if DEBUG
        print("🎮 GameCreationView: Saving game | Opponent: '\(opponent.trimmingCharacters(in: .whitespacesAndNewlines))' | makeGameLive: \(makeGameLive)")
        #endif

        onSave(opponent.trimmingCharacters(in: .whitespacesAndNewlines), date, makeGameLive)
        dismiss()
    }
}

// Helper extension for time formatting
extension DateFormatter {
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter
    }()

    static let shortTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
}

// MARK: - Manual Statistics Entry View
struct ManualStatisticsEntryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let game: Game
    
    @State private var singles: String = ""
    @State private var doubles: String = ""
    @State private var triples: String = ""
    @State private var homeRuns: String = ""
    @State private var runs: String = ""
    @State private var rbis: String = ""
    @State private var strikeouts: String = ""
    @State private var walks: String = ""
    @State private var groundOuts: String = ""
    @State private var flyOuts: String = ""
    @State private var showingValidationAlert = false
    @State private var alertMessage = ""

    enum StatField: Int, Hashable, CaseIterable {
        case singles, doubles, triples, homeRuns, runs, rbis, strikeouts, groundOuts, flyOuts, walks
    }
    @FocusState private var focusedStatField: StatField?

    // Use game.gameStats directly — never create a throwaway GameStatistics()
    // which would be an uninserted @Model object with misleading zero values.
    private var existingGameStats: GameStatistics? { game.gameStats }

    // Calculate totals for preview
    var newSingles: Int { Int(singles) ?? 0 }
    var newDoubles: Int { Int(doubles) ?? 0 }
    var newTriples: Int { Int(triples) ?? 0 }
    var newHomeRuns: Int { Int(homeRuns) ?? 0 }
    var newRuns: Int { Int(runs) ?? 0 }
    var newRbis: Int { Int(rbis) ?? 0 }
    var newStrikeouts: Int { Int(strikeouts) ?? 0 }
    var newWalks: Int { Int(walks) ?? 0 }
    var newGroundOuts: Int { Int(groundOuts) ?? 0 }
    var newFlyOuts: Int { Int(flyOuts) ?? 0 }

    var newHits: Int { newSingles + newDoubles + newTriples + newHomeRuns }
    var newAtBats: Int { newHits + newStrikeouts + newGroundOuts + newFlyOuts }

    var totalHits: Int { (existingGameStats?.hits ?? 0) + newHits }
    var totalAtBats: Int { (existingGameStats?.atBats ?? 0) + newAtBats }
    var totalRuns: Int { (existingGameStats?.runs ?? 0) + newRuns }
    var totalRbis: Int { (existingGameStats?.rbis ?? 0) + newRbis }
    var totalStrikeouts: Int { (existingGameStats?.strikeouts ?? 0) + newStrikeouts }
    var totalWalks: Int { (existingGameStats?.walks ?? 0) + newWalks }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Game Information") {
                    HStack {
                        Text("Opponent:")
                            .fontWeight(.semibold)
                        Spacer()
                        Text(game.opponent)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Date:")
                            .fontWeight(.semibold)
                        Spacer()
                        if let date = game.date {
                            Text(date, style: .date)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Unknown Date")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section("Batting Statistics") {
                    StatEntryRow(title: "Singles", value: $singles, icon: "1.circle.fill", color: .green, field: .singles, focusedField: $focusedStatField)
                    StatEntryRow(title: "Doubles", value: $doubles, icon: "2.circle.fill", color: .blue, field: .doubles, focusedField: $focusedStatField)
                    StatEntryRow(title: "Triples", value: $triples, icon: "3.circle.fill", color: .orange, field: .triples, focusedField: $focusedStatField)
                    StatEntryRow(title: "Home Runs", value: $homeRuns, icon: "4.circle.fill", color: .gold, field: .homeRuns, focusedField: $focusedStatField)
                }

                Section("Offensive Statistics") {
                    StatEntryRow(title: "Runs", value: $runs, icon: "figure.run", color: .purple, field: .runs, focusedField: $focusedStatField)
                    StatEntryRow(title: "RBIs", value: $rbis, icon: "arrow.up.right.circle.fill", color: .pink, field: .rbis, focusedField: $focusedStatField)
                }

                Section("Plate Appearance Outcomes") {
                    StatEntryRow(title: "Strikeouts (K's)", value: $strikeouts, icon: "k.circle.fill", color: .red, field: .strikeouts, focusedField: $focusedStatField)
                    StatEntryRow(title: "Ground Outs", value: $groundOuts, icon: "arrow.down.circle.fill", color: .red, field: .groundOuts, focusedField: $focusedStatField)
                    StatEntryRow(title: "Fly Outs", value: $flyOuts, icon: "arrow.up.circle.fill", color: .red, field: .flyOuts, focusedField: $focusedStatField)
                    StatEntryRow(title: "Walks (BB's)", value: $walks, icon: "figure.walk", color: .cyan, field: .walks, focusedField: $focusedStatField)
                }
                
                Section("Current Game Statistics") {
                    CurrentStatRow(title: "Hits", current: existingGameStats?.hits ?? 0, color: .blue)
                    CurrentStatRow(title: "At Bats", current: existingGameStats?.atBats ?? 0, color: .blue)
                    CurrentStatRow(title: "Runs", current: existingGameStats?.runs ?? 0, color: .purple)
                    CurrentStatRow(title: "RBIs", current: existingGameStats?.rbis ?? 0, color: .pink)
                    CurrentStatRow(title: "Strikeouts", current: existingGameStats?.strikeouts ?? 0, color: .red)
                    CurrentStatRow(title: "Walks", current: existingGameStats?.walks ?? 0, color: .cyan)

                    if let stats = existingGameStats, stats.atBats > 0 {
                        HStack {
                            Text("Current Batting Average")
                                .fontWeight(.medium)
                            Spacer()
                            Text(String(format: "%.3f", Double(stats.hits) / Double(stats.atBats)))
                                .fontWeight(.semibold)
                                .foregroundColor(.green)
                        }
                    }
                }

                if hasAnyInput {
                    Section("Preview New Totals") {
                        PreviewStatRow(title: "Total Hits", current: existingGameStats?.hits ?? 0, new: newHits, total: totalHits)
                        PreviewStatRow(title: "Total At Bats", current: existingGameStats?.atBats ?? 0, new: newAtBats, total: totalAtBats)
                        PreviewStatRow(title: "Total Runs", current: existingGameStats?.runs ?? 0, new: newRuns, total: totalRuns)
                        PreviewStatRow(title: "Total RBIs", current: existingGameStats?.rbis ?? 0, new: newRbis, total: totalRbis)
                        PreviewStatRow(title: "Total Strikeouts", current: existingGameStats?.strikeouts ?? 0, new: newStrikeouts, total: totalStrikeouts)
                        PreviewStatRow(title: "Total Walks", current: existingGameStats?.walks ?? 0, new: newWalks, total: totalWalks)
                        
                        if totalAtBats > 0 {
                            HStack {
                                Text("New Batting Average")
                                    .fontWeight(.semibold)
                                Spacer()
                                Text(String(format: "%.3f", Double(totalHits) / Double(totalAtBats)))
                                    .fontWeight(.bold)
                                    .foregroundColor(.green)
                                    .font(.headline)
                            }
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(.cornerMedium)
                        }
                    }
                }
            }
            .navigationTitle("Enter Statistics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    if let current = focusedStatField,
                       let nextField = StatField(rawValue: current.rawValue + 1) {
                        Button("Next") { focusedStatField = nextField }
                    }
                    Spacer()
                    Button("Done") { focusedStatField = nil }
                        .fontWeight(.semibold)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveStatistics()
                    }
                    .disabled(!hasAnyInput)
                }
            }
        }
        .alert("Error", isPresented: $showingValidationAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
    }
    
    private var hasAnyInput: Bool {
        !singles.isEmpty || !doubles.isEmpty || !triples.isEmpty || !homeRuns.isEmpty ||
        !runs.isEmpty || !rbis.isEmpty || !strikeouts.isEmpty || !walks.isEmpty ||
        !groundOuts.isEmpty || !flyOuts.isEmpty
    }
    
    private func saveStatistics() {
        // Validation
        if newAtBats < 0 || newHits < 0 || newRuns < 0 || newRbis < 0 || newStrikeouts < 0 || newWalks < 0 || newGroundOuts < 0 || newFlyOuts < 0 {
            alertMessage = "Statistics cannot be negative numbers."
            showingValidationAlert = true
            return
        }
        
        // Create game stats if they don't exist
        var stats = game.gameStats
        if stats == nil {
            let newStats = GameStatistics()
            game.gameStats = newStats
            newStats.game = game
            modelContext.insert(newStats)
            stats = newStats
        }
        
        // Add the new statistics
        if let gameStats = stats {
            gameStats.addManualStatistic(
                singles: newSingles,
                doubles: newDoubles,
                triples: newTriples,
                homeRuns: newHomeRuns,
                runs: newRuns,
                rbis: newRbis,
                strikeouts: newStrikeouts,
                walks: newWalks,
                groundOuts: newGroundOuts,
                flyOuts: newFlyOuts
            )


            // Also update athlete's overall statistics if they exist
            if let athlete = game.athlete,
               let athleteStats = athlete.statistics {

                athleteStats.addManualStatistic(
                    singles: newSingles,
                    doubles: newDoubles,
                    triples: newTriples,
                    homeRuns: newHomeRuns,
                    runs: newRuns,
                    rbis: newRbis,
                    strikeouts: newStrikeouts,
                    walks: newWalks,
                    groundOuts: newGroundOuts,
                    flyOuts: newFlyOuts
                )
                
            }
        }
        
        do {
            try modelContext.save()
            dismiss()
        } catch {
            alertMessage = "Failed to save statistics. Please try again."
            showingValidationAlert = true
        }
    }
}

// Helper Views for Manual Statistics Entry
struct StatEntryRow: View {
    let title: String
    @Binding var value: String
    let icon: String
    let color: Color
    var field: ManualStatisticsEntryView.StatField? = nil
    var focusedField: FocusState<ManualStatisticsEntryView.StatField?>.Binding? = nil

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 25)

            Text(title)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let field, let focusedField {
                TextField("0", text: $value)
                    .focused(focusedField, equals: field)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .multilineTextAlignment(.center)
            } else {
                TextField("0", text: $value)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

struct CurrentStatRow: View {
    let title: String
    let current: Int
    let color: Color
    
    var body: some View {
        HStack {
            Text(title)
                .fontWeight(.medium)
            Spacer()
            Text("\(current)")
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
    }
}

struct PreviewStatRow: View {
    let title: String
    let current: Int
    let new: Int
    let total: Int
    
    var body: some View {
        HStack {
            Text(title)
                .fontWeight(.medium)
            
            Spacer()
            
            if new > 0 {
                Text("\(current) + \(new) = ")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("\(total)")
                    .fontWeight(.bold)
                    .foregroundColor(.green)
            } else {
                Text("\(current)")
                    .foregroundColor(.secondary)
            }
        }
    }
}

