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
    @State private var searchDebounceTask: Task<Void, Never>?

    final class ViewModelHolder: ObservableObject {
        @Published var viewModel: GamesViewModel?
    }
    
    // Game creation states
    @State private var showingGameCreation = false

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
            onSave: { opponent, date, isLive, season in
                createGame(opponent: opponent, date: date, isLive: isLive, season: season)
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

    private static let searchDateFormatter = DateFormatter.mediumDate

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
                        .tint(Color.brandNavy)
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
                    .swipeActions(edge: .leading) {
                        Button(role: .destructive) {
                            gameToDelete = game
                            showingDeleteGameConfirmation = true
                        } label: {
                            Text("Delete")
                        }
                    }
                    .onAppear {
                        if game.id == cachedCompletedGames.last?.id,
                           viewModelHolder.viewModel?.hasMoreCompleted == true {
                            viewModelHolder.viewModel?.loadMoreCompleted()
                            updateFilteredGames()
                        }
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
    
    private var seasonFilterMenu: some View {
        SeasonFilterMenu(
            selectedSeasonID: $selectedSeasonFilter,
            availableSeasons: cachedAvailableSeasons,
            showNoSeasonOption: allGames.contains(where: { $0.season == nil })
        )
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
                    Haptics.light()
                    refreshGames()
                    try? await Task.sleep(for: .milliseconds(300))
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
            .task {
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
                searchDebounceTask?.cancel()
                searchDebounceTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled else { return }
                    updateFilteredGames()
                }
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
        viewModelHolder.viewModel?.complete(game)
        refreshGames()
    }

    private func deleteGame(_ game: Game) {
        viewModelHolder.viewModel?.deleteDeep(game)
        refreshGames()
    }
    
    private func createGame(opponent: String, date: Date, isLive: Bool, season: Season? = nil) {
        viewModelHolder.viewModel?.create(
            opponent: opponent,
            date: date,
            isLive: isLive,
            season: season,
            onError: { errorMessage in
                showError(errorMessage)
            }
        )
        refreshGames()
    }
    
    private func refreshGames() {
        viewModelHolder.viewModel?.update(allGames: allGames)
    }

    private func showError(_ message: String) {
        errorMessage = message
        activeAlert = .error
    }
}

