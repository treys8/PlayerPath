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
    
    // Query all games with sorting - SwiftData will automatically observe changes
    @Query(sort: \Game.date, order: .reverse) private var allGames: [Game]
    
    @StateObject private var viewModelHolder = ViewModelHolder()
    
    // Error handling
    @State private var showingError = false
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
    
    // Computed properties for cleaner code
    private var hasGames: Bool {
        guard let vm = viewModelHolder.viewModel else { return false }
        return !vm.liveGames.isEmpty || !vm.upcomingGames.isEmpty || 
               !vm.pastGames.isEmpty || !vm.completedGames.isEmpty
    }
    
    private var liveGames: [Game] {
        filterGames(viewModelHolder.viewModel?.liveGames ?? [])
    }
    private var upcomingGames: [Game] {
        filterGames(viewModelHolder.viewModel?.upcomingGames ?? [])
    }
    private var pastGames: [Game] {
        filterGames(viewModelHolder.viewModel?.pastGames ?? [])
    }
    private var completedGames: [Game] {
        filterGames(viewModelHolder.viewModel?.completedGames ?? [])
    }

    // Get all unique seasons from games
    private var availableSeasons: [Season] {
        let seasons = allGames.compactMap { $0.season }
        let uniqueSeasons = Array(Set(seasons))
        return uniqueSeasons.sorted { ($0.startDate ?? Date.distantPast) > ($1.startDate ?? Date.distantPast) }
    }

    // Check if filters are active
    private var hasActiveFilters: Bool {
        selectedSeasonFilter != nil ||
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // Check if we have any filtered results
    private var hasFilteredResults: Bool {
        !liveGames.isEmpty || !upcomingGames.isEmpty || !pastGames.isEmpty || !completedGames.isEmpty
    }

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
                (game.date?.formatted(date: .abbreviated, time: .omitted).lowercased().contains(query) ?? false)
            }
        }

        return filtered
    }

    private var filterDescription: String {
        var parts: [String] = []

        if let seasonID = selectedSeasonFilter {
            if seasonID == "no_season" {
                parts.append("season: None")
            } else if let season = availableSeasons.first(where: { $0.id.uuidString == seasonID }) {
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
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading games...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !hasFilteredResults {
                if hasActiveFilters && hasGames {
                    // Filtered empty state
                    FilteredEmptyStateView(
                        filterDescription: filterDescription,
                        onClearFilters: clearAllFilters
                    )
                } else {
                    // True empty state
                    EmptyGamesView {
                        showingGameCreation = true
                    }
                }
            } else {
                List {
                    // Live Games Section
                    if !liveGames.isEmpty {
                        Section("Live") {
                            ForEach(liveGames) { game in
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
                                deleteGames(from: liveGames, at: indexSet)
                            }
                        }
                    }
                    
                    // Upcoming Games Section
                    if !upcomingGames.isEmpty {
                        Section("Upcoming") {
                            ForEach(upcomingGames) { game in
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
                                        deleteGame(game)
                                    } label: {
                                        Text("Delete")
                                    }
                                }
                            }
                            .onDelete { indexSet in
                                deleteGames(from: upcomingGames, at: indexSet)
                            }
                        }
                    }
                    
                    // Past Games Section (games that happened but weren't marked as complete)
                    if !pastGames.isEmpty {
                        Section("Past Games") {
                            ForEach(pastGames) { game in
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
                                        deleteGame(game)
                                    } label: {
                                        Text("Delete")
                                    }
                                }
                            }
                            .onDelete { indexSet in
                                deleteGames(from: pastGames, at: indexSet)
                            }
                        }
                    }
                    
                    // Completed Games Section
                    if !completedGames.isEmpty {
                        Section("Completed") {
                            ForEach(completedGames) { game in
                                NavigationLink(destination: GameDetailView(game: game)) {
                                    GameRow(game: game)
                                }
                            }
                            .onDelete { indexSet in
                                deleteGames(from: completedGames, at: indexSet)
                            }
                        }
                    }
                }
                .refreshable {
                    await refreshGames()
                }
            }
        }
        .navigationTitle("Games")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search by opponent or date")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingGameCreation = true }) {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add new game")
            }

            if hasGames {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }

                // Season filter menu
                ToolbarItem(placement: .topBarTrailing) {
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

                        ForEach(availableSeasons) { season in
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
        }
        .onChange(of: athlete?.id) { oldValue, newValue in
            #if DEBUG
            print("🎮 GamesView: Athlete changed from \(oldValue?.uuidString ?? "nil") to \(newValue?.uuidString ?? "nil")")
            #endif
            // Recreate ViewModel when athlete changes
            viewModelHolder.viewModel = GamesViewModel(modelContext: modelContext, athlete: athlete, allGames: allGames)
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
        }
        .sheet(isPresented: $showingGameCreation) {
            GameCreationView(
                athlete: athlete,
                onSave: { opponent, date, isLive in
                    createGame(opponent: opponent, date: date, isLive: isLive)
                }
            )
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .onReceive(NotificationCenter.default.publisher(for: .presentAddGame)) { _ in
            showingGameCreation = true
        }
    }
    
    // MARK: - Helper Methods
    
    private func startGame(_ game: Game) {
        viewModelHolder.viewModel?.start(game)
        refreshGames()
    }
    
    private func endGame(_ game: Game) {
        viewModelHolder.viewModel?.end(game)
        refreshGames()
    }
    
    private func completeGame(_ game: Game) {
        game.isComplete = true
        do {
            try modelContext.save()
            refreshGames()
        } catch {
            showError("Failed to mark game as complete: \(error.localizedDescription)")
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
        showingError = true
    }
}

// MARK: - Game Row View
struct GameRow: View {
    let game: Game
    
    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            VStack(alignment: .leading, spacing: 4) {
                // Opponent name
                Text("vs \(game.opponent)")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                // Date and season
                HStack(spacing: 8) {
                    if let date = game.date {
                        Text(date, style: .date)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Season badge
                    if let season = game.season {
                        Text(season.displayName)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(season.isActive ? Color.blue : Color.gray)
                            .cornerRadius(4)
                    } else if let year = game.year {
                        Text(String(year))
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.6))
                            .cornerRadius(4)
                    }
                }
            }
            
            Spacer()
            
            // Status badge
            if game.isLive {
                Text("LIVE")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red)
                    .cornerRadius(4)
            } else if game.isComplete {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
            
            // Stats summary (if available)
            if let stats = game.gameStats, stats.atBats > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(stats.hits)-\(stats.atBats)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                    Text(String(format: "%.3f", Double(stats.hits) / Double(stats.atBats)))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
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
}

struct EmptyGamesView: View {
    let onAddGame: () -> Void
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "sportscourt")
                .font(.system(size: 80))
                .foregroundColor(.green)
            
            Text("No Games Yet")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Create your first game to record and track performance")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: onAddGame) {
                Text("Add Game")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
        .padding()
    }
}

struct GameDetailView: View {
    let game: Game
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showingEndGame = false
    @State private var showingVideoRecorder = false
    @State private var showingDeleteConfirmation = false
    @State private var showingManualStats = false
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
                    
                    // Removed tournament display here as per instructions
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
                        try? modelContext.save()
                    } label: {
                        Label("Mark as Incomplete", systemImage: "arrow.counterclockwise")
                    }
                }
                
                // Manual Statistics Entry
                Button(action: { showingManualStats = true }) {
                    Label("Enter Statistics", systemImage: "chart.bar.doc.horizontal")
                }
                
                if !game.isComplete && !game.isLive {
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
                        VideoClipRow(clip: clip)
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
                            try? modelContext.save()
                        }) {
                            Label("Mark as Incomplete", systemImage: "arrow.counterclockwise")
                        }
                    }
                    
                    Divider()
                    
                    // Statistics Action
                    Button(action: { showingManualStats = true }) {
                        Label("Enter Statistics", systemImage: "chart.bar.doc.horizontal")
                    }
                    
                    Divider()
                    
                    // Destructive Actions
                    if !game.isComplete && !game.isLive {
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
            Text("Are you sure you want to delete this game? This action cannot be undone.")
        }
        .sheet(isPresented: $showingVideoRecorder) {
            VideoRecorderView_Refactored(athlete: game.athlete, game: game)
        }
        .sheet(isPresented: $showingManualStats) {
            ManualStatisticsEntryView(game: game)
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
        print("Deleting game from detail view: \(game.opponent)")
        Task { await gameService?.deleteGameDeep(game) }
        // Dismiss the view after deletion attempt
        dismiss()
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
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
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
                case .success:
                    #if DEBUG
                    print("   ✅ Game created successfully")
                    #endif
                    // Dismiss on successful creation
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
                case .success(let game):
                    // Success - dismiss
                    let calendar = Calendar.current
                    let year = calendar.component(.year, from: date)
                    print("✅ Game added to year \(year): \(trimmedOpponent)")
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
    @State private var showingVideoPlayer = false
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
                                            Image(systemName: "video")
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
        .task {
            await loadThumbnail()
        }
        .sheet(isPresented: $showingVideoPlayer) {
            VideoPlayerView(clip: clip)
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
            let image = try await ThumbnailCache.shared.loadThumbnail(at: thumbnailPath)
            thumbnailImage = image
        } catch {
            print("Failed to load thumbnail in VideoClipRow: \(error)")
            // Try to regenerate thumbnail
            await generateMissingThumbnail()
        }
        
        isLoadingThumbnail = false
    }
    
    private func generateMissingThumbnail() async {
        print("Generating missing thumbnail for clip in game: \(clip.fileName)")
        
        let videoURL = URL(fileURLWithPath: clip.filePath)
        let result = await VideoFileManager.generateThumbnail(from: videoURL)
        
        await MainActor.run {
            switch result {
            case .success(let thumbnailPath):
                clip.thumbnailPath = thumbnailPath
                // Save the thumbnail path to model context
                do {
                    try modelContext.save()
                } catch {
                    print("Failed to save thumbnail path: \(error)")
                }
                Task {
                    await loadThumbnail()
                }
            case .failure(let error):
                print("Failed to generate thumbnail in VideoClipRow: \(error)")
                isLoadingThumbnail = false
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
        }
    }
    
    private func playResultColor(for type: PlayResultType) -> Color {
        switch type {
        case .single: return .green
        case .double: return .blue
        case .triple: return .orange
        case .homeRun: return .red
        case .walk: return .cyan
        case .strikeout: return .red.opacity(0.8)
        case .groundOut, .flyOut: return .gray
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
    @State private var showingValidationAlert = false
    @State private var alertMessage = ""
    
    var gameStats: GameStatistics {
        game.gameStats ?? GameStatistics()
    }
    
    // Calculate totals for preview
    var newSingles: Int { Int(singles) ?? 0 }
    var newDoubles: Int { Int(doubles) ?? 0 }
    var newTriples: Int { Int(triples) ?? 0 }
    var newHomeRuns: Int { Int(homeRuns) ?? 0 }
    var newRuns: Int { Int(runs) ?? 0 }
    var newRbis: Int { Int(rbis) ?? 0 }
    var newStrikeouts: Int { Int(strikeouts) ?? 0 }
    var newWalks: Int { Int(walks) ?? 0 }
    
    var newHits: Int { newSingles + newDoubles + newTriples + newHomeRuns }
    var newAtBats: Int { newHits + newStrikeouts }
    
    var totalHits: Int { gameStats.hits + newHits }
    var totalAtBats: Int { gameStats.atBats + newAtBats }
    var totalRuns: Int { gameStats.runs + newRuns }
    var totalRbis: Int { gameStats.rbis + newRbis }
    var totalStrikeouts: Int { gameStats.strikeouts + newStrikeouts }
    var totalWalks: Int { gameStats.walks + newWalks }
    
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
                    StatEntryRow(title: "Singles", value: $singles, icon: "1.circle.fill", color: .green)
                    StatEntryRow(title: "Doubles", value: $doubles, icon: "2.circle.fill", color: .blue)
                    StatEntryRow(title: "Triples", value: $triples, icon: "3.circle.fill", color: .orange)
                    StatEntryRow(title: "Home Runs", value: $homeRuns, icon: "4.circle.fill", color: .red)
                }
                
                Section("Offensive Statistics") {
                    StatEntryRow(title: "Runs", value: $runs, icon: "figure.run", color: .purple)
                    StatEntryRow(title: "RBIs", value: $rbis, icon: "arrow.up.right.circle.fill", color: .pink)
                }
                
                Section("Plate Appearance Outcomes") {
                    StatEntryRow(title: "Strikeouts (K's)", value: $strikeouts, icon: "k.circle.fill", color: .red)
                    StatEntryRow(title: "Walks (BB's)", value: $walks, icon: "figure.walk", color: .cyan)
                }
                
                Section("Current Game Statistics") {
                    CurrentStatRow(title: "Hits", current: gameStats.hits, color: .blue)
                    CurrentStatRow(title: "At Bats", current: gameStats.atBats, color: .blue)
                    CurrentStatRow(title: "Runs", current: gameStats.runs, color: .purple)
                    CurrentStatRow(title: "RBIs", current: gameStats.rbis, color: .pink)
                    CurrentStatRow(title: "Strikeouts", current: gameStats.strikeouts, color: .red)
                    CurrentStatRow(title: "Walks", current: gameStats.walks, color: .cyan)
                    
                    if gameStats.atBats > 0 {
                        HStack {
                            Text("Current Batting Average")
                                .fontWeight(.medium)
                            Spacer()
                            Text(String(format: "%.3f", Double(gameStats.hits) / Double(gameStats.atBats)))
                                .fontWeight(.semibold)
                                .foregroundColor(.green)
                        }
                    }
                }
                
                if hasAnyInput {
                    Section("Preview New Totals") {
                        PreviewStatRow(title: "Total Hits", current: gameStats.hits, new: newHits, total: totalHits)
                        PreviewStatRow(title: "Total At Bats", current: gameStats.atBats, new: newAtBats, total: totalAtBats)
                        PreviewStatRow(title: "Total Runs", current: gameStats.runs, new: newRuns, total: totalRuns)
                        PreviewStatRow(title: "Total RBIs", current: gameStats.rbis, new: newRbis, total: totalRbis)
                        PreviewStatRow(title: "Total Strikeouts", current: gameStats.strikeouts, new: newStrikeouts, total: totalStrikeouts)
                        PreviewStatRow(title: "Total Walks", current: gameStats.walks, new: newWalks, total: totalWalks)
                        
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
                            .cornerRadius(8)
                        }
                    }
                }
            }
            .navigationTitle("Enter Statistics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
        !runs.isEmpty || !rbis.isEmpty || !strikeouts.isEmpty || !walks.isEmpty
    }
    
    private func saveStatistics() {
        // Validation
        if newAtBats < 0 || newHits < 0 || newRuns < 0 || newRbis < 0 || newStrikeouts < 0 || newWalks < 0 {
            alertMessage = "Statistics cannot be negative numbers."
            showingValidationAlert = true
            return
        }
        
        // Create game stats if they don't exist
        var stats = game.gameStats
        if stats == nil {
            stats = GameStatistics()
            game.gameStats = stats
            stats?.game = game
            modelContext.insert(stats!)
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
                walks: newWalks
            )
            
            print("Updated game statistics: \(gameStats.hits) hits in \(gameStats.atBats) at bats, \(gameStats.runs) runs, \(gameStats.rbis) RBIs")
            
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
                    walks: newWalks
                )
                
                print("Updated athlete overall statistics: \(athleteStats.hits) total hits in \(athleteStats.atBats) total at bats")
            }
        }
        
        do {
            try modelContext.save()
            print("Successfully saved comprehensive manual statistics")
            dismiss()
        } catch {
            print("Failed to save statistics: \(error)")
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
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 25)
            
            Text(title)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            TextField("0", text: $value)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
                .multilineTextAlignment(.center)
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

extension GameService {
    func createGame(
        for athlete: Athlete,
        opponent: String,
        date: Date,
        isLive: Bool,
        allowWithoutSeason: Bool = false
    ) async -> Result<Game, GameService.GameCreationError> {
        return await createGame(
            for: athlete,
            opponent: opponent,
            date: date,
            tournament: nil,
            isLive: isLive,
            allowWithoutSeason: allowWithoutSeason
        )
    }
}
