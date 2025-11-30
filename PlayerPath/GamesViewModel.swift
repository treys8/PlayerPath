import Foundation
import SwiftUI
import SwiftData
import Combine

@MainActor
final class GamesViewModel: ObservableObject {
    let athlete: Athlete?
    
    @Published private(set) var liveGames: [Game] = []
    @Published private(set) var completedGames: [Game] = []
    @Published private(set) var upcomingGames: [Game] = []
    @Published private(set) var pastGames: [Game] = []

    private let modelContext: ModelContext
    private let gameService: GameService

    init(modelContext: ModelContext, athlete: Athlete?, allGames: [Game]) {
        self.modelContext = modelContext
        self.athlete = athlete
        self.gameService = GameService(modelContext: modelContext)
        recomputeSections(allGames: allGames)
    }
    
    func update(allGames: [Game]) {
        #if DEBUG
        print("📊 GamesViewModel: Updating with \(allGames.count) total games")
        #endif
        recomputeSections(allGames: allGames)
    }
    
    private func recomputeSections(allGames: [Game]) {
        guard let athlete = athlete else {
            liveGames = []
            completedGames = []
            upcomingGames = []
            pastGames = []
            #if DEBUG
            print("📊 GamesViewModel: No athlete, cleared all sections")
            #endif
            return
        }
        
        let athleteGamesSet = Set(athlete.games ?? [])
        let filteredGamesSet = Set(allGames.filter { $0.athlete?.id == athlete.id })
        let combinedGames = Array(athleteGamesSet.union(filteredGamesSet))
        
        #if DEBUG
        print("📊 GamesViewModel: Athlete '\(athlete.name)'")
        print("   - Games from relationship: \(athleteGamesSet.count)")
        print("   - Games from query filter: \(filteredGamesSet.count)")
        print("   - Combined unique games: \(combinedGames.count)")
        #endif
        
        let sortedGames = combinedGames.sorted { a, b in
            switch (a.date, b.date) {
            case let (ad?, bd?):
                if ad == bd { return a.id.uuidString < b.id.uuidString }
                return ad > bd
            case (nil, nil):
                return a.id.uuidString < b.id.uuidString
            case (nil, _?):
                return false // b has a date, a doesn't -> b comes first
            case (_?, nil):
                return true  // a has a date, b doesn't -> a comes first
            }
        }
        
        let now = Date()
        liveGames = sortedGames.filter { $0.isLive }
        completedGames = sortedGames.filter { $0.isComplete }
        upcomingGames = sortedGames.filter { game in
            guard !game.isLive, !game.isComplete else { return false }
            if let d = game.date { return d > now }
            return false
        }
        pastGames = sortedGames.filter { game in
            guard !game.isLive, !game.isComplete else { return false }
            if let d = game.date { return d <= now }
            return false
        }
        
        #if DEBUG
        print("📊 GamesViewModel: Sections updated")
        print("   - Live: \(liveGames.count)")
        print("   - Completed: \(completedGames.count)")
        print("   - Upcoming: \(upcomingGames.count)")
        print("   - Past: \(pastGames.count)")
        #endif
    }
    
    func repair(allGames: [Game]) {
        Task { @MainActor in
            if let athlete = self.athlete {
                await gameService.repairConsistency(for: athlete, allGames: allGames)
            }
            recomputeSections(allGames: allGames)
        }
    }
    
    func create(opponent: String, date: Date, isLive: Bool, onError: @escaping (String) -> Void) {
        guard let athlete = self.athlete else { return }

        // Check for duplicate
        let calendar = Calendar.current
        for existingGame in athlete.games ?? [] {
            if existingGame.opponent == opponent,
               let gameDate = existingGame.date,
               calendar.isDate(gameDate, inSameDayAs: date) {
                print("❌ Duplicate game found")
                onError("A game against this opponent already exists on the same day.")
                return
            }
        }

        // End other live games if needed
        if isLive {
            for game in athlete.games ?? [] where game.isLive {
                game.isLive = false
            }
        }

        // Create on MAIN context
        let game = Game(date: date, opponent: opponent)
        game.isLive = isLive
        game.athlete = athlete

        let stats = GameStatistics()
        game.gameStats = stats
        stats.game = game
        modelContext.insert(stats)
        modelContext.insert(game)

        // Append to athlete
        var athleteGames = athlete.games ?? []
        athleteGames.append(game)
        athlete.games = athleteGames

        do {
            try modelContext.save()
            print("✅ Game created on main context")
        } catch {
            print("❌ Error: \(error)")
            onError("Failed to save game. Please try again.")
        }
    }
    
    func start(_ game: Game) {
        guard let athlete = game.athlete else {
            print("Cannot start game: no athlete found.")
            return
        }

        // End other live games of this athlete
        for otherGame in athlete.games ?? [] where otherGame.isLive && otherGame != game {
            otherGame.isLive = false
        }

        // Start this game
        game.isLive = true

        do {
            try modelContext.save()
            print("Started game for athlete \(athlete.name).")
            NotificationCenter.default.post(name: Notification.Name("GameBecameLive"), object: game)
        } catch {
            print("Error saving context after starting game: \(error.localizedDescription)")
        }
    }

    func end(_ game: Game) {
        game.isLive = false
        game.isComplete = true

        if let athlete = game.athlete {
            // Create athlete statistics if they don't exist
            if athlete.statistics == nil {
                let newStats = AthleteStatistics()
                newStats.athlete = athlete
                athlete.statistics = newStats
                modelContext.insert(newStats)
                print("Created new AthleteStatistics for athlete.")
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

                print("Aggregated game stats into athlete stats:")
                print("  - Added \(gameStats.hits) hits, \(gameStats.atBats) at-bats")
                print("  - New totals: \(athleteStats.hits) hits, \(athleteStats.atBats) at-bats")
                print("  - Batting Average: \(athleteStats.battingAverage)")
            }

            // Increment total games
            if let athleteStats = athlete.statistics {
                athleteStats.addCompletedGame()
                print("Added completed game to athlete's statistics.")
            }
        }

        do {
            try modelContext.save()
            print("Ended game and saved changes.")
        } catch {
            print("Error saving context after ending game: \(error.localizedDescription)")
        }
    }
    
    func deleteDeep(_ game: Game) {
        Task { @MainActor in
            await gameService.deleteGameDeep(game)
        }
    }
}

