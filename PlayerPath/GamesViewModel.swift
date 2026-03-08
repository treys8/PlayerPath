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
            guard let d = game.date else { return true } // nil date → treat as upcoming
            return d > now
        }
        pastGames = sortedGames.filter { game in
            guard !game.isLive, !game.isComplete else { return false }
            guard let d = game.date else { return false }
            return d <= now
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
    
    func create(opponent: String, date: Date, isLive: Bool, onError: @escaping (String) -> Void, onSuccess: ((Game) -> Void)? = nil) {
        guard let athlete = self.athlete else { return }
        Task {
            let result = await gameService.createGame(for: athlete, opponent: opponent, date: date, isLive: isLive)
            switch result {
            case .success(let game):
                onSuccess?(game)
            case .failure(let error):
                onError(error.localizedDescription)
            }
        }
    }
    
    func start(_ game: Game) {
        Task { await gameService.start(game) }
    }

    func end(_ game: Game) {
        Task { await gameService.end(game) }
    }
    
    func deleteDeep(_ game: Game) {
        Task { @MainActor in
            await gameService.deleteGameDeep(game)
        }
    }
}

