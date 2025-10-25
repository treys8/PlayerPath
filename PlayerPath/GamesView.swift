//
//  GamesView.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import SwiftUI
import SwiftData

struct GamesView: View {
    let athlete: Athlete?
    @Environment(\.modelContext) private var modelContext
    @Query private var allGames: [Game]
    
    // Game creation states
    @State private var showingGameCreation = false
    @State private var newGameOpponent = ""
    @State private var newGameDate = Date()
    @State private var selectedTournament: Tournament?
    @State private var makeGameLive = false
    
    var games: [Game] {
        guard let athlete = athlete else { return [] }
        
        // Get games from both the athlete's games array AND by querying for games that belong to this athlete
        let relationshipGames = Set(athlete.games)
        let queryGames = Set(allGames.filter { $0.athlete?.id == athlete.id })
        
        // Combine both sets to catch any inconsistencies
        let allAthleteGames = relationshipGames.union(queryGames)
        
        return Array(allAthleteGames).sorted { $0.date > $1.date }
    }
    
    var liveGames: [Game] {
        games.filter { $0.isLive }
    }
    
    var completedGames: [Game] {
        games.filter { $0.isComplete }
    }
    
    var upcomingGames: [Game] {
        games.filter { !$0.isComplete && !$0.isLive && $0.date > Date() }
    }
    
    var pastGames: [Game] {
        games.filter { !$0.isComplete && !$0.isLive && $0.date <= Date() }
    }
    
    var availableTournaments: [Tournament] {
        athlete?.tournaments.filter { $0.isActive } ?? []
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if games.isEmpty {
                    EmptyGamesView {
                        showingGameCreation = true
                    }
                } else {
                    List {
                        // Live Games Section
                        if !liveGames.isEmpty {
                            Section("Live Games") {
                                ForEach(liveGames) { game in
                                    NavigationLink(destination: GameDetailView(game: game)) {
                                        GameRow(game: game)
                                    }
                                    .swipeActions(edge: .trailing) {
                                        Button("End") {
                                            endGameFromList(game)
                                        }
                                        .tint(.red)
                                    }
                                }
                                .onDelete { indexSet in
                                    deleteLiveGames(offsets: indexSet)
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
                                            startGameFromList(game)
                                        }
                                        .tint(.green)
                                    }
                                    .swipeActions(edge: .leading) {
                                        Button("Delete") {
                                            deleteGameFromList(game)
                                        }
                                        .tint(.red)
                                    }
                                }
                                .onDelete { indexSet in
                                    deleteUpcomingGames(offsets: indexSet)
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
                                            markGameComplete(game)
                                        }
                                        .tint(.blue)
                                    }
                                    .swipeActions(edge: .leading) {
                                        Button("Delete") {
                                            deleteGameFromList(game)
                                        }
                                        .tint(.red)
                                    }
                                }
                                .onDelete { indexSet in
                                    deletePastGames(offsets: indexSet)
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
                                .onDelete(perform: deleteCompletedGames)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Games")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingGameCreation = true }) {
                        Image(systemName: "plus")
                    }
                }
                
                if !games.isEmpty {
                    ToolbarItem(placement: .navigationBarLeading) {
                        EditButton()
                    }
                }
            }
            .onAppear {
                repairDataConsistency()
            }
        }
        .sheet(isPresented: $showingGameCreation) {
            GameCreationView(
                athlete: athlete,
                availableTournaments: availableTournaments,
                onSave: { opponent, date, tournament, isLive in
                    createGame(opponent: opponent, date: date, tournament: tournament, isLive: isLive)
                }
            )
        }
    }
    
    private func repairDataConsistency() {
        guard let athlete = athlete else { return }
        
        print("Repairing data consistency for athlete: \(athlete.name)")
        
        let relationshipGames = Set(athlete.games)
        let queryGames = Set(allGames.filter { $0.athlete?.id == athlete.id })
        
        // Find games that are in the query but not in the relationship
        let orphanedGames = queryGames.subtracting(relationshipGames)
        
        if !orphanedGames.isEmpty {
            print("Found \(orphanedGames.count) orphaned games, adding to athlete's games array")
            
            for game in orphanedGames {
                if !athlete.games.contains(game) {
                    athlete.games.append(game)
                    print("Added orphaned game: \(game.opponent)")
                }
            }
            
            do {
                try modelContext.save()
                print("Successfully repaired data consistency")
            } catch {
                print("Failed to repair data consistency: \(error)")
            }
        }
        
        // Also check for games in the relationship that don't have proper athlete reference
        for game in relationshipGames {
            if game.athlete?.id != athlete.id {
                print("Fixing game with incorrect athlete reference: \(game.opponent)")
                game.athlete = athlete
            }
        }
        
        do {
            try modelContext.save()
        } catch {
            print("Failed to save athlete reference fixes: \(error)")
        }
    }
    
    private func createGame(opponent: String, date: Date, tournament: Tournament?, isLive: Bool) {
        guard let athlete = athlete else { return }
        
        // Check for existing game with same opponent and date
        let existingGame = athlete.games.first { game in
            game.opponent == opponent && Calendar.current.isDate(game.date, inSameDayAs: date)
        }
        
        if existingGame != nil {
            print("Game already exists: \(opponent) on \(date)")
            return
        }
        
        print("Creating new game: \(opponent) for athlete: \(athlete.name)")
        
        // If making live, end any other live games
        if isLive {
            athlete.games.forEach { $0.isLive = false }
        }
        
        let game = Game(date: date, opponent: opponent)
        game.isLive = isLive
        game.athlete = athlete
        
        // Create and link game statistics
        let gameStats = GameStatistics()
        game.gameStats = gameStats
        gameStats.game = game
        modelContext.insert(gameStats)
        
        // Set tournament relationship
        if let tournament = tournament {
            game.tournament = tournament
            tournament.games.append(game)
        }
        
        athlete.games.append(game)
        modelContext.insert(game)
        
        do {
            try modelContext.save()
            print("Successfully saved game: \(opponent)")
        } catch {
            print("Failed to save game: \(error)")
        }
    }
    
    private func deleteCompletedGames(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                let game = completedGames[index]
                
                print("Deleting completed game: \(game.opponent)")
                
                // Remove from athlete's games array
                if let athlete = game.athlete,
                   let gameIndex = athlete.games.firstIndex(of: game) {
                    athlete.games.remove(at: gameIndex)
                    print("Removed game from athlete's array")
                }
                
                // Remove from tournament's games array if applicable
                if let tournament = game.tournament,
                   let gameIndex = tournament.games.firstIndex(of: game) {
                    tournament.games.remove(at: gameIndex)
                    print("Removed game from tournament's array")
                }
                
                // Delete associated video clips
                for videoClip in game.videoClips {
                    // Remove from athlete's video clips array
                    if let athlete = videoClip.athlete,
                       let clipIndex = athlete.videoClips.firstIndex(of: videoClip) {
                        athlete.videoClips.remove(at: clipIndex)
                    }
                    
                    // Delete any associated play results
                    if let playResult = videoClip.playResult {
                        modelContext.delete(playResult)
                    }
                    
                    modelContext.delete(videoClip)
                    print("Deleted associated video clip: \(videoClip.fileName)")
                }
                
                // Delete associated game statistics
                if let gameStats = game.gameStats {
                    modelContext.delete(gameStats)
                    print("Deleted game statistics")
                }
                
                // Delete the game itself
                modelContext.delete(game)
                print("Deleted game from context")
            }
            
            do {
                try modelContext.save()
                print("Successfully saved game deletions")
            } catch {
                print("Failed to delete games: \(error)")
            }
        }
    }
    
    private func deleteLiveGames(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                let game = liveGames[index]
                deleteGameCompletely(game)
            }
        }
    }
    
    private func deleteUpcomingGames(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                let game = upcomingGames[index]
                deleteGameCompletely(game)
            }
        }
    }
    
    private func deletePastGames(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                let game = pastGames[index]
                deleteGameCompletely(game)
            }
        }
    }
    
    private func deleteGameCompletely(_ game: Game) {
        print("Deleting game: \(game.opponent)")
        
        // Remove from athlete's games array
        if let athlete = game.athlete,
           let gameIndex = athlete.games.firstIndex(of: game) {
            athlete.games.remove(at: gameIndex)
            print("Removed game from athlete's array")
        }
        
        // Remove from tournament's games array if applicable
        if let tournament = game.tournament,
           let gameIndex = tournament.games.firstIndex(of: game) {
            tournament.games.remove(at: gameIndex)
            print("Removed game from tournament's array")
        }
        
        // Delete associated video clips
        for videoClip in game.videoClips {
            // Remove from athlete's video clips array
            if let athlete = videoClip.athlete,
               let clipIndex = athlete.videoClips.firstIndex(of: videoClip) {
                athlete.videoClips.remove(at: clipIndex)
            }
            
            // Delete any associated play results
            if let playResult = videoClip.playResult {
                modelContext.delete(playResult)
            }
            
            modelContext.delete(videoClip)
            print("Deleted associated video clip: \(videoClip.fileName)")
        }
        
        // Delete associated game statistics
        if let gameStats = game.gameStats {
            modelContext.delete(gameStats)
            print("Deleted game statistics")
        }
        
        // Delete the game from context
        modelContext.delete(game)
        print("Deleted game from context")
        
        do {
            try modelContext.save()
            print("Successfully saved game deletion")
        } catch {
            print("Failed to delete game: \(error)")
        }
    }
    
    private func startGameFromList(_ game: Game) {
        // End any other live games for this athlete
        athlete?.games.forEach { $0.isLive = false }
        
        // Start this game
        game.isLive = true
        
        do {
            try modelContext.save()
        } catch {
            print("Failed to start game: \(error)")
        }
    }
    
    private func endGameFromList(_ game: Game) {
        game.isLive = false
        game.isComplete = true
        
        do {
            try modelContext.save()
        } catch {
            print("Failed to end game: \(error)")
        }
    }
    
    private func markGameComplete(_ game: Game) {
        game.isComplete = true
        
        do {
            try modelContext.save()
        } catch {
            print("Failed to mark game as complete: \(error)")
        }
    }
    
    private func deleteGameFromList(_ game: Game) {
        print("Deleting game from list: \(game.opponent)")
        
        // Remove from athlete's games array
        if let athlete = game.athlete,
           let index = athlete.games.firstIndex(of: game) {
            athlete.games.remove(at: index)
            print("Removed game from athlete's array")
        }
        
        // Remove from tournament's games array if applicable
        if let tournament = game.tournament,
           let index = tournament.games.firstIndex(of: game) {
            tournament.games.remove(at: index)
            print("Removed game from tournament's array")
        }
        
        // Delete associated video clips
        for videoClip in game.videoClips {
            // Remove from athlete's video clips array
            if let athlete = videoClip.athlete,
               let clipIndex = athlete.videoClips.firstIndex(of: videoClip) {
                athlete.videoClips.remove(at: clipIndex)
            }
            
            // Delete any associated play results
            if let playResult = videoClip.playResult {
                modelContext.delete(playResult)
            }
            
            modelContext.delete(videoClip)
            print("Deleted associated video clip: \(videoClip.fileName)")
        }
        
        // Delete associated game statistics
        if let gameStats = game.gameStats {
            modelContext.delete(gameStats)
            print("Deleted game statistics")
        }
        
        // Delete the game from context
        modelContext.delete(game)
        print("Deleted game from context")
        
        do {
            try modelContext.save()
            print("Successfully saved game deletion")
        } catch {
            print("Failed to delete game: \(error)")
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
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
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
    
    var videoClips: [VideoClip] {
        game.videoClips.sorted { $0.createdAt > $1.createdAt }
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
                        Text(game.date, formatter: DateFormatter.shortDateTime)
                            .foregroundColor(.secondary)
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
        .navigationTitle("vs \(game.opponent)")
        .navigationBarTitleDisplayMode(.inline)
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
            VideoRecorderView(athlete: game.athlete, game: game)
        }
        .sheet(isPresented: $showingManualStats) {
            ManualStatisticsEntryView(game: game)
        }
    }
    
    private func startGame() {
        // End any other live games for this athlete
        game.athlete?.games.forEach { $0.isLive = false }
        
        // Start this game
        game.isLive = true
        
        do {
            try modelContext.save()
        } catch {
            print("Failed to start game: \(error)")
        }
    }
    
    private func endGame() {
        game.isLive = false
        game.isComplete = true
        
        do {
            try modelContext.save()
        } catch {
            print("Failed to end game: \(error)")
        }
    }
    
    private func deleteGame() {
        print("Deleting game from detail view: \(game.opponent)")
        
        // Remove from athlete's games array
        if let athlete = game.athlete,
           let index = athlete.games.firstIndex(of: game) {
            athlete.games.remove(at: index)
            print("Removed game from athlete's array")
        }
        
        // Remove from tournament's games array if applicable
        if let tournament = game.tournament,
           let index = tournament.games.firstIndex(of: game) {
            tournament.games.remove(at: index)
            print("Removed game from tournament's array")
        }
        
        // Delete associated video clips
        for videoClip in game.videoClips {
            // Remove from athlete's video clips array
            if let athlete = videoClip.athlete,
               let clipIndex = athlete.videoClips.firstIndex(of: videoClip) {
                athlete.videoClips.remove(at: clipIndex)
            }
            
            // Delete any associated play results
            if let playResult = videoClip.playResult {
                modelContext.delete(playResult)
            }
            
            modelContext.delete(videoClip)
            print("Deleted associated video clip: \(videoClip.fileName)")
        }
        
        // Delete associated game statistics
        if let gameStats = game.gameStats {
            modelContext.delete(gameStats)
            print("Deleted game statistics")
        }
        
        // Delete the game from context
        modelContext.delete(game)
        print("Deleted game from context")
        
        do {
            try modelContext.save()
            print("Successfully saved game deletion")
            // Dismiss the view after successful deletion
            dismiss()
        } catch {
            print("Failed to delete game: \(error)")
        }
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
    
    init(athlete: Athlete? = nil, tournament: Tournament? = nil) {
        self.athlete = athlete
        self.tournament = tournament
        self._selectedTournament = State(initialValue: tournament)
    }
    
    var availableTournaments: [Tournament] {
        athlete?.tournaments.filter { $0.isActive } ?? []
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Game Details") {
                    TextField("Opponent", text: $opponent)
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
                    .disabled(opponent.isEmpty)
                }
            }
        }
    }
    
    private func saveGame() {
        guard let athlete = athlete else { return }
        
        // Check for existing game with same opponent and date
        let existingGame = athlete.games.first { game in
            game.opponent == opponent && Calendar.current.isDate(game.date, inSameDayAs: date)
        }
        
        if existingGame != nil {
            print("Game already exists: \(opponent) on \(date)")
            dismiss()
            return
        }
        
        print("Creating new game via AddGameView: \(opponent) for athlete: \(athlete.name)")
        
        // If starting as live, end any other live games
        if startAsLive {
            athlete.games.forEach { $0.isLive = false }
        }
        
        let game = Game(date: date, opponent: opponent)
        game.isLive = startAsLive
        game.athlete = athlete
        
        // Create and link game statistics
        let gameStats = GameStatistics()
        game.gameStats = gameStats
        gameStats.game = game
        modelContext.insert(gameStats)
        
        // Set tournament relationship
        if let tournament = selectedTournament ?? tournament {
            game.tournament = tournament
            tournament.games.append(game)
        }
        
        athlete.games.append(game)
        modelContext.insert(game)
        
        do {
            try modelContext.save()
            print("Successfully saved game via AddGameView: \(opponent)")
            dismiss()
        } catch {
            print("Failed to save game: \(error)")
        }
    }
}

struct VideoClipRow: View {
    let clip: VideoClip
    
    var body: some View {
        HStack {
            // Enhanced thumbnail with overlay
            ZStack(alignment: .bottomLeading) {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 50, height: 35)
                    .cornerRadius(6)
                    .overlay(
                        Image(systemName: "play.fill")
                            .foregroundColor(.white)
                            .font(.caption)
                            .shadow(color: .black.opacity(0.3), radius: 1)
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
                        .font(.system(size: 10))
                        .background(Circle().fill(Color.black.opacity(0.6)).frame(width: 14, height: 14))
                        .offset(x: -2, y: 2)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                if let playResult = clip.playResult {
                    Text(playResult.type.rawValue)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                } else {
                    Text("Unrecorded Play")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Text(clip.createdAt, formatter: DateFormatter.shortTime)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if clip.isHighlight {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
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
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Game Details") {
                    TextField("Opponent", text: $opponent)
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
                        Text("This game will become the active game for recording videos")
                            .font(.caption)
                            .foregroundColor(.secondary)
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
                        onSave(opponent, date, selectedTournament, makeGameLive)
                        dismiss()
                    }
                    .disabled(opponent.isEmpty)
                }
            }
        }
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
                        Text(game.date, formatter: DateFormatter.shortDate)
                            .foregroundColor(.secondary)
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