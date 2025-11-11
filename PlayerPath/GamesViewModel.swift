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
    @Published private(set) var availableTournaments: [Tournament] = []
    
    private let modelContext: ModelContext
    private let gameService: GameService
    
    init(modelContext: ModelContext, athlete: Athlete?, allGames: [Game]) {
        self.modelContext = modelContext
        self.athlete = athlete
        self.gameService = GameService(modelContext: modelContext)
        if let athlete = athlete {
            self.availableTournaments = athlete.tournaments.sorted { lhs, rhs in
                if lhs.name == rhs.name {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.name < rhs.name
            }
        } else {
            self.availableTournaments = []
        }
        recomputeSections(allGames: allGames)
    }
    
    func update(allGames: [Game]) {
        recomputeSections(allGames: allGames)
    }
    
    private func recomputeSections(allGames: [Game]) {
        guard let athlete = athlete else {
            liveGames = []
            completedGames = []
            upcomingGames = []
            pastGames = []
            return
        }
        
        let athleteGamesSet = Set(athlete.games)
        let filteredGamesSet = Set(allGames.filter { $0.athlete?.id == athlete.id })
        let combinedGames = Array(athleteGamesSet.union(filteredGamesSet))
        
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
    }
    
    func repair(allGames: [Game]) {
        Task {
            if let athlete = self.athlete {
                await gameService.repairConsistency(for: athlete, allGames: allGames)
            }
            await MainActor.run {
                recomputeSections(allGames: allGames)
            }
        }
    }
    
    func create(opponent: String, date: Date, tournament: Tournament?, isLive: Bool) {
        Task {
            guard let athlete = self.athlete else { return }
            await gameService.createGame(for: athlete, opponent: opponent, date: date, tournament: tournament, isLive: isLive)
        }
    }
    
    func start(_ game: Game) {
        Task {
            await gameService.start(game)
        }
    }
    
    func end(_ game: Game) {
        Task {
            await gameService.end(game)
        }
    }
    
    func deleteDeep(_ game: Game) {
        Task {
            await gameService.deleteGameDeep(game)
        }
    }
}

