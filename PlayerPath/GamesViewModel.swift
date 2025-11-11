import Foundation
import SwiftUI
import SwiftData

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
            if a.date == b.date {
                return a.id.uuidString < b.id.uuidString
            }
            return a.date > b.date
        }
        
        liveGames = sortedGames.filter { $0.isLive }
        completedGames = sortedGames.filter { $0.isCompleted }
        upcomingGames = sortedGames.filter { $0.isUpcoming }
        pastGames = sortedGames.filter { $0.isPast }
    }
    
    func repair(allGames: [Game]) {
        Task {
            await gameService.repair()
            await MainActor.run {
                recomputeSections(allGames: allGames)
            }
        }
    }
    
    func create(opponent: String, date: Date, tournament: Tournament?, isLive: Bool) {
        Task {
            await gameService.createGame(opponent: opponent, date: date, tournament: tournament, isLive: isLive, athlete: athlete)
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
            await gameService.deleteDeep(game)
        }
    }
}
