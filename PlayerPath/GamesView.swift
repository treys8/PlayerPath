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
    private var activeSport: Season.SportType { athlete?.sportType ?? .baseball }

    private var isGolf: Bool { activeSport == .golf }
    private var unitNoun: String { isGolf ? "round" : "game" }
    private var unitNounPlural: String { isGolf ? "rounds" : "games" }
    private var navigationTitle: String { isGolf ? "Rounds" : "Games" }
    private var searchPrompt: String { isGolf ? "Search by course or date" : "Search by opponent or date" }
    private var addAccessibilityLabel: String { isGolf ? "Add new round" : "Add new game" }

    // Query games for the current athlete only — avoids loading all games across athletes
    private let athleteID: UUID?
    @Query private var allGames: [Game]
    /// Golf tournaments for this athlete (SchemaV27). Rendered as cards above the
    /// standalone rounds when the athlete is in golf mode.
    @Query private var golfTournaments: [GolfTournament]

    init(athlete: Athlete?) {
        self.athlete = athlete
        let id = athlete?.id
        self.athleteID = id
        if let id {
            self._allGames = Query(
                filter: #Predicate<Game> { $0.athlete?.id == id },
                sort: [SortDescriptor(\Game.date, order: .reverse)]
            )
            self._golfTournaments = Query(
                filter: #Predicate<GolfTournament> { $0.athlete?.id == id },
                sort: [SortDescriptor(\GolfTournament.startDate, order: .reverse)]
            )
        } else {
            self._allGames = Query(sort: [SortDescriptor(\Game.date, order: .reverse)])
            self._golfTournaments = Query(sort: [SortDescriptor(\GolfTournament.startDate, order: .reverse)])
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
    @State private var listEditMode: EditMode = .inactive

    final class ViewModelHolder: ObservableObject {
        @Published var viewModel: GamesViewModel?
    }
    
    // Game creation states
    @State private var showingGameCreation = false
    /// Presents the multi-round tournament creation sheet (golf only, SchemaV27).
    @State private var showingTournamentCreation = false

    // Season check states
    @State private var showingSeasonCreation = false

    // Delete confirmation
    @State private var gameToDelete: Game?
    @State private var showingDeleteGameConfirmation = false

    // Row tap → push game detail. Driving the push with navigationDestination(item:)
    // means the rows are plain Buttons, not NavigationLinks, so the List never adds
    // a system disclosure chevron beside GameRow's own in-card chevron.
    @State private var selectedGame: Game?

    // Alert state
    private enum AlertType: Identifiable {
        case error
        case noSeason
        case duplicateConfirm
        var id: Self { self }
    }
    @State private var activeAlert: AlertType?

    // Captured game-creation parameters held while the duplicate (doubleheader)
    // confirmation alert is shown, so "Add Game" can re-create with allowDuplicate.
    private struct PendingGameCreation {
        let opponent: String
        let date: Date
        let isLive: Bool
        let season: Season?
        let golf: GolfRoundDetails?
        let location: String?
        let tournament: GolfTournament?
    }
    @State private var pendingDuplicate: PendingGameCreation?
    
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
               !vm.pastGames.isEmpty || !vm.completedGames.isEmpty ||
               (isGolf && !golfTournaments.isEmpty)
    }

    // Check if filters are active
    private var hasActiveFilters: Bool {
        selectedSeasonFilter != nil ||
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // Check if we have any filtered results. Golf tournaments count too — a
    // golf athlete whose only content is a tournament (no standalone rounds)
    // must still see the list (with its tournament cards), not the empty state.
    private var hasFilteredResults: Bool {
        (isGolf && !visibleTournaments.isEmpty) ||
        !cachedLiveGames.isEmpty || !cachedUpcomingGames.isEmpty || !cachedPastGames.isEmpty || !cachedCompletedGames.isEmpty
    }

    /// Tournaments shown in the list — the @Query set narrowed by the search box
    /// so a search that matches no tournament/round correctly reaches the
    /// "no results" state. Season filter is intentionally not applied:
    /// tournaments are a season-agnostic grouping (SchemaV27).
    private var visibleTournaments: [GolfTournament] {
        guard isGolf else { return [] }
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return golfTournaments }
        let query = trimmed.lowercased()
        return golfTournaments.filter { tournament in
            tournament.name.lowercased().contains(query) ||
            (tournament.location?.lowercased().contains(query) ?? false)
        }
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
            onSave: { opponent, date, isLive, season, golf, location, tournament in
                createGame(opponent: opponent, date: date, isLive: isLive, season: season, golf: golf, location: location, tournament: tournament)
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
        // Filter by active sport context. A game with no season falls back to
        // the athlete's primary sport hint so legacy baseball games still appear
        // when the athlete is multi-sport and toggled to baseball.
        var filtered = games.filter { game in
            if let seasonSport = game.season?.sport {
                return seasonSport == activeSport
            }
            // No-season games match when active sport equals the athlete's hint.
            let hint = Season.SportType(rawValue: (game.athlete?.sport ?? .baseball).rawValue.capitalized) ?? .baseball
            return hint == activeSport
        }

        // Golf rounds that belong to a tournament are shown under their
        // tournament card (TournamentDetailView), not in the flat round list —
        // exclude them here so they don't double-appear (SchemaV27). A LIVE
        // tournament round is exempt: it still surfaces in the Live section so
        // it can be resumed from the most discoverable place (it also remains
        // reachable inside its tournament card).
        if isGolf {
            filtered = filtered.filter { $0.tournament == nil || $0.isLive }
        }

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

    private static let monthLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    private var completedSections: [(label: String, games: [Game])] {
        let games = cachedCompletedGames
        guard games.count >= 10 else { return [("Completed", games)] }

        let calendar = Calendar.current
        var bucketsByKey: [String: [Game]] = [:]
        var keyOrder: [String] = []
        for game in games {
            let key: String
            if let date = game.date,
               let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) {
                key = Self.monthLabelFormatter.string(from: monthStart)
            } else {
                key = "Undated"
            }
            if bucketsByKey[key] == nil {
                bucketsByKey[key] = []
                keyOrder.append(key)
            }
            bucketsByKey[key]?.append(game)
        }
        return keyOrder.map { ($0, bucketsByKey[$0] ?? []) }
    }

    // MARK: - Sub-views
    
    @ViewBuilder
    private var gamesListContent: some View {
        // Tournaments Section (golf only) — multi-round containers above the
        // standalone rounds. Sorted newest-first by the @Query (SchemaV27).
        if isGolf && !visibleTournaments.isEmpty {
            Section("Tournaments") {
                ForEach(visibleTournaments) { tournament in
                    NavigationLink(destination: TournamentDetailView(tournament: tournament)) {
                        TournamentRow(tournament: tournament)
                    }
                }
            }
        }

        // Live Games Section
        if !cachedLiveGames.isEmpty {
            Section("Live") {
                ForEach(cachedLiveGames) { game in
                    gameNavigationRow(game)
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
                    gameNavigationRow(game)
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
            Section(isGolf ? "Past Rounds" : "Past Games") {
                ForEach(cachedPastGames) { game in
                    gameNavigationRow(game)
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
        
        // Completed Games — single section under threshold, per-month sections at scale
        if !cachedCompletedGames.isEmpty {
            ForEach(completedSections, id: \.label) { bucket in
                Section(bucket.label) {
                    ForEach(bucket.games) { game in
                        gameNavigationRow(game)
                        .onAppear {
                            if game.id == cachedCompletedGames.last?.id,
                               viewModelHolder.viewModel?.hasMoreCompleted == true {
                                viewModelHolder.viewModel?.loadMoreCompleted()
                                updateFilteredGames()
                            }
                        }
                    }
                    .onDelete { indexSet in
                        if let index = indexSet.first, index < bucket.games.count {
                            gameToDelete = bucket.games[index]
                            showingDeleteGameConfirmation = true
                        }
                    }
                }
            }
        }
    }
    
    /// A games-list row whose entire card pushes the game detail. Uses a plain
    /// `Button` (driving `navigationDestination(item:)`) rather than a
    /// `NavigationLink`, because a List decorates every NavigationLink row with a
    /// system disclosure chevron — which would sit beside GameRow's own in-card
    /// chevron (the double-chevron bug). A Button gets no such chevron, and the
    /// whole card stays one actionable, well-labeled element for VoiceOver (GameRow
    /// already combines its children).
    private func gameNavigationRow(_ game: Game) -> some View {
        Button {
            selectedGame = game
        } label: {
            GameRow(game: game, isSeasonFiltered: selectedSeasonFilter != nil)
        }
        .buttonStyle(.plain)
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
                    EmptyGamesView(isGolf: isGolf) {
                        handleAddGame()
                    }
                }
            } else {
                List {
                    gamesListContent
                        .listRowBackground(Theme.surface)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 5, leading: 18, bottom: 5, trailing: 18))
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Theme.surface)
                .environment(\.editMode, $listEditMode)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.surface)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(item: $selectedGame) { game in
                GameDetailView(game: game)
            }
            .searchable(text: $searchText, prompt: searchPrompt)
            .toolbar {
                if let athlete = athlete {
                    ToolbarItem(placement: .principal) {
                        PPAthleteSwitcher(athlete: athlete)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    if isGolf {
                        // Golf now has two creatable things: a standalone round
                        // or a multi-round tournament (SchemaV27).
                        Menu {
                            Button {
                                handleAddGame()
                            } label: {
                                Label("New Round", systemImage: "flag")
                            }
                            Button {
                                showingTournamentCreation = true
                            } label: {
                                Label("New Tournament", systemImage: "trophy")
                            }
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Add new round or tournament")
                    } else {
                    Button(action: { handleAddGame() }) {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(addAccessibilityLabel)
                    }
                }

                if hasGames {
                    ToolbarItem(placement: .topBarTrailing) {
                        seasonFilterMenu
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                withAnimation {
                                    listEditMode = (listEditMode == .active) ? .inactive : .active
                                }
                            } label: {
                                Label(listEditMode == .active ? "Done" : "Edit", systemImage: "pencil")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("More options")
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
            .onChange(of: activeSport) { _, _ in
                updateFilteredGames()
            }
            .sheet(isPresented: $showingGameCreation) {
                gameCreationSheet
            }
            .sheet(isPresented: $showingSeasonCreation) {
                seasonCreationSheet
            }
            .sheet(isPresented: $showingTournamentCreation) {
                TournamentCreationView(athlete: athlete)
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
                        message: Text("\(unitNounPlural.capitalized) belong to a season. Create a season to start tracking \(unitNounPlural)."),
                        primaryButton: .default(Text("Create Season")) {
                            showingSeasonCreation = true
                        },
                        secondaryButton: .cancel()
                    )
                case .duplicateConfirm:
                    Alert(
                        title: Text("\(unitNoun.capitalized) Already Exists"),
                        message: Text(duplicateConfirmMessage),
                        primaryButton: .default(Text("Add \(unitNoun.capitalized)")) {
                            if let pending = pendingDuplicate {
                                confirmDuplicateGame(pending)
                            }
                            pendingDuplicate = nil
                        },
                        secondaryButton: .cancel {
                            pendingDuplicate = nil
                        }
                    )
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .presentAddGame)) { _ in
                handleAddGame()
            }
            .confirmationDialog(
                isGolf ? "Delete Round" : "Delete Game",
                isPresented: $showingDeleteGameConfirmation,
                presenting: gameToDelete
            ) { game in
                Button("Delete \"\(game.opponent)\"", role: .destructive) {
                    deleteGame(game)
                }
            } message: { _ in
                Text("This will permanently delete this \(unitNoun) and all its video clips, photos, and statistics.")
            }
    }

    // MARK: - Helper Methods
    
    private func startGame(_ game: Game) {
        // Check if game has a season
        guard game.season != nil else {
            errorMessage = "This \(unitNoun) needs a season before it can be started. Please assign a season to the \(unitNoun) first."
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
    
    private func createGame(opponent: String, date: Date, isLive: Bool, season: Season? = nil, golf: GolfRoundDetails? = nil, location: String? = nil, tournament: GolfTournament? = nil) {
        viewModelHolder.viewModel?.create(
            opponent: opponent,
            date: date,
            isLive: isLive,
            season: season,
            golfDetails: golf,
            location: location,
            tournament: tournament,
            onDuplicate: {
                // Same opponent on the same day — likely a doubleheader. Confirm
                // before creating a second game rather than hard-blocking it.
                pendingDuplicate = PendingGameCreation(
                    opponent: opponent,
                    date: date,
                    isLive: isLive,
                    season: season,
                    golf: golf,
                    location: location,
                    tournament: tournament
                )
                activeAlert = .duplicateConfirm
            },
            onError: { errorMessage in
                showError(errorMessage)
            }
        )
        refreshGames()
    }

    /// Re-run creation for a confirmed doubleheader, bypassing the same-day
    /// duplicate guard. Only reached after the user taps "Add" on the
    /// duplicate-confirmation alert.
    private func confirmDuplicateGame(_ pending: PendingGameCreation) {
        viewModelHolder.viewModel?.create(
            opponent: pending.opponent,
            date: pending.date,
            isLive: pending.isLive,
            season: pending.season,
            golfDetails: pending.golf,
            location: pending.location,
            tournament: pending.tournament,
            allowDuplicate: true,
            onError: { errorMessage in
                showError(errorMessage)
            }
        )
        refreshGames()
    }

    private var duplicateConfirmMessage: String {
        guard let pending = pendingDuplicate else { return "" }
        let dateStr = DateFormatter.mediumDate.string(from: pending.date)
        return "You already have a \(unitNoun) against \(pending.opponent) on \(dateStr). Add another \(unitNoun) (e.g. a doubleheader)?"
    }
    
    private func refreshGames() {
        viewModelHolder.viewModel?.update(allGames: allGames)
    }

    private func showError(_ message: String) {
        errorMessage = message
        activeAlert = .error
    }
}

