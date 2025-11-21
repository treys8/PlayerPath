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
    @Query private var allGames: [Game]
    @StateObject private var viewModelHolder = ViewModelHolder()
    
    // Error handling
    @State private var showingError = false
    @State private var errorMessage = ""
    
    // Loading states
    @State private var isLoading = false

    final class ViewModelHolder: ObservableObject {
        @Published var viewModel: GamesViewModel?
    }
    
    // Game creation states
    @State private var showingGameCreation = false
    @State private var newGameOpponent = ""
    @State private var newGameDate = Date()
    @State private var selectedTournament: Tournament?
    @State private var makeGameLive = false
    
    // Computed properties for cleaner code
    private var hasGames: Bool {
        guard let vm = viewModelHolder.viewModel else { return false }
        return !vm.liveGames.isEmpty || !vm.upcomingGames.isEmpty || 
               !vm.pastGames.isEmpty || !vm.completedGames.isEmpty
    }
    
    private var liveGames: [Game] { viewModelHolder.viewModel?.liveGames ?? [] }
    private var upcomingGames: [Game] { viewModelHolder.viewModel?.upcomingGames ?? [] }
    private var pastGames: [Game] { viewModelHolder.viewModel?.pastGames ?? [] }
    private var completedGames: [Game] { viewModelHolder.viewModel?.completedGames ?? [] }
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading games...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !hasGames {
                EmptyGamesView {
                    showingGameCreation = true
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
            }
        }
        .standardNavigationBar(title: "Games", displayMode: .large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingGameCreation = true }) {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add new game")
            }
            
            if hasGames {
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }
            }
        }
        .onAppear {
            if viewModelHolder.viewModel == nil {
                viewModelHolder.viewModel = GamesViewModel(modelContext: modelContext, athlete: athlete, allGames: allGames)
            } else {
                viewModelHolder.viewModel?.update(allGames: allGames)
            }
        }
        .onChange(of: allGames) { _, newValue in
            viewModelHolder.viewModel?.update(allGames: newValue)
        }
        .sheet(isPresented: $showingGameCreation) {
            GameCreationView(
                athlete: athlete,
                availableTournaments: viewModelHolder.viewModel?.availableTournaments ?? [],
                onSave: { opponent, date, tournament, isLive in
                    createGame(opponent: opponent, date: date, tournament: tournament, isLive: isLive)
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
    
    private func createGame(opponent: String, date: Date, tournament: Tournament?, isLive: Bool) {
        viewModelHolder.viewModel?.create(opponent: opponent, date: date, tournament: tournament, isLive: isLive)
        refreshGames()
    }
    
    private func refreshGames() {
        viewModelHolder.viewModel?.update(allGames: allGames)
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
                
                // Date and status
                HStack(spacing: 8) {
                    if let date = game.date {
                        Text(date, style: .date)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let tournament = game.tournament {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(tournament.name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
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
            
            Text("Create your first game to start recording and tracking performance")
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
        game.videoClips.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
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
                    
                    if let tournament = game.tournament {
                        HStack {
                            Text("Tournament")
                                .fontWeight(.semibold)
                            Spacer()
                            Text(tournament.name)
                                .foregroundColor(.secondary)
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
                            .foregroundColor(.blue)
                    }
                    
                    if game.isLive {
                        Button("End Game") {
                            showingEndGame = true
                        }
                        .foregroundColor(.red)
                    } else {
                        Button("Start Game") {
                            startGame()
                        }
                        .foregroundColor(.green)
                    }
                } else {
                    Button("Mark as Incomplete") {
                        game.isComplete = false
                        try? modelContext.save()
                    }
                    .foregroundColor(.orange)
                }
                
                // Manual Statistics Entry
                Button(action: { showingManualStats = true }) {
                    Label("Enter Statistics", systemImage: "chart.bar.doc.horizontal")
                        .foregroundColor(.purple)
                }
                
                // Additional quick actions
                if !game.isComplete && !game.isLive {
                    Button("Delete Game") {
                        showingDeleteConfirmation = true
                    }
                    .foregroundColor(.red)
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
        .childNavigationBar(title: "vs \(game.opponent)")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
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
    let tournament: Tournament?
    
    @State private var opponent = ""
    @State private var date = Date()
    @State private var selectedTournament: Tournament?
    @State private var startAsLive = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    init(athlete: Athlete? = nil, tournament: Tournament? = nil) {
        self.athlete = athlete
        self.tournament = tournament
        self._selectedTournament = State(initialValue: tournament)
    }
    
    var availableTournaments: [Tournament] {
        athlete?.tournaments.filter { $0.isActive } ?? []
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
                
                if tournament == nil && !availableTournaments.isEmpty {
                    Section("Tournament") {
                        Picker("Select Tournament", selection: $selectedTournament) {
                            Text("Standalone Game")
                                .tag(nil as Tournament?)
                            
                            ForEach(availableTournaments) { tournament in
                                Text(tournament.name)
                                    .tag(tournament as Tournament?)
                            }
                        }
                    }
                }
                
                Section {
                    Toggle("Start as Live Game", isOn: $startAsLive)
                }
            }
            .navigationTitle("New Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveGame()
                    }
                    .disabled(!isValidOpponent)
                }
            }
            .onAppear {
                if selectedTournament == nil {
                    selectedTournament = availableTournaments.first(where: { $0.isActive })
                }
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
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
        
        // Check for existing game with same opponent and date
        let existingGame = athlete.games.first { game in
            if let gameDate = game.date {
                return game.opponent.lowercased() == trimmedOpponent.lowercased() && 
                       Calendar.current.isDate(gameDate, inSameDayAs: date)
            }
            return false
        }
        
        if existingGame != nil {
            errorMessage = "A game against \(trimmedOpponent) already exists on this date"
            showingError = true
            return
        }
        
        print("Creating new game via AddGameView: \(trimmedOpponent) for athlete: \(athlete.name)")
        
        // If starting as live, end any other live games
        if startAsLive {
            athlete.games.forEach { $0.isLive = false }
        }
        
        let game = Game(date: date, opponent: trimmedOpponent)
        game.isLive = startAsLive
        game.athlete = athlete
        
        // Create and link game statistics
        let gameStats = GameStatistics()
        game.gameStats = gameStats
        gameStats.game = game
        modelContext.insert(gameStats)
        
        // Link to active season
        if let activeSeason = athlete.activeSeason {
            game.season = activeSeason
            activeSeason.games.append(game)
            print("✅ Linked game to active season: \(activeSeason.displayName)")
        } else {
            print("⚠️ Warning: No active season found for game")
        }
        
        // Set tournament relationship
        if let tournament = selectedTournament ?? tournament {
            game.tournament = tournament
            tournament.games.append(game)
            // Also link tournament to active season if not already linked
            if let activeSeason = athlete.activeSeason, tournament.season == nil {
                tournament.season = activeSeason
                activeSeason.tournaments.append(tournament)
                print("✅ Linked tournament to active season: \(activeSeason.displayName)")
            }
        } else if let activeTournament = athlete.tournaments.first(where: { $0.isActive }) {
            game.tournament = activeTournament
            activeTournament.games.append(game)
            // Also link tournament to active season if not already linked
            if let activeSeason = athlete.activeSeason, activeTournament.season == nil {
                activeTournament.season = activeSeason
                activeSeason.tournaments.append(activeTournament)
                print("✅ Linked tournament to active season: \(activeSeason.displayName)")
            }
        }
        
        athlete.games.append(game)
        modelContext.insert(game)
        
        do {
            try modelContext.save()
            print("Successfully saved game via AddGameView: \(trimmedOpponent)")
            dismiss()
        } catch {
            print("Failed to save game: \(error)")
            errorMessage = "Failed to save game: \(error.localizedDescription)"
            showingError = true
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
    let availableTournaments: [Tournament]
    let onSave: (String, Date, Tournament?, Bool) -> Void
    
    @State private var opponent = ""
    @State private var date = Date()
    @State private var selectedTournament: Tournament?
    @State private var makeGameLive = false
    @State private var showingValidationError = false
    @State private var validationMessage = ""
    
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
                
                if !availableTournaments.isEmpty {
                    Section("Tournament (Optional)") {
                        Picker("Select Tournament", selection: $selectedTournament) {
                            Text("Standalone Game")
                                .tag(nil as Tournament?)
                            
                            ForEach(availableTournaments) { tournament in
                                Text(tournament.name)
                                    .tag(tournament as Tournament?)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                
                Section("Game Options") {
                    Toggle("Start as Live Game", isOn: $makeGameLive)
                    
                    if makeGameLive {
                        Label {
                            Text("This game will become the active game for recording videos")
                                .font(.caption)
                        } icon: {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                // Quick tips section
                Section {
                    Label {
                        Text("You can add statistics and videos after creating the game")
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
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveGame()
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                if selectedTournament == nil {
                    selectedTournament = availableTournaments.first(where: { $0.isActive })
                }
            }
        }
        .alert("Invalid Input", isPresented: $showingValidationError) {
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
        
        onSave(opponent.trimmingCharacters(in: .whitespacesAndNewlines), date, selectedTournament, makeGameLive)
        dismiss()
    }
}

// Helper extension for time formatting
extension DateFormatter {
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
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveStatistics()
                    }
                    .disabled(!hasAnyInput)
                }
            }
        }
        .alert("Invalid Input", isPresented: $showingValidationAlert) {
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
                .textFieldStyle(RoundedBorderTextFieldStyle())
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

