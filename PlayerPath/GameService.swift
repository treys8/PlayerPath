import Foundation
import SwiftUI
import SwiftData

actor GameService {
    
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - File Deletion
    
    func deleteFiles(for clip: VideoClip) async {
        let fileManager = FileManager.default
        
        // Delete video file
        let fileURL = URL(fileURLWithPath: clip.filePath)
        if fileManager.fileExists(atPath: fileURL.path) {
            do {
                try fileManager.removeItem(at: fileURL)
                print("Deleted video file at \(fileURL.path)")
            } catch {
                print("Error deleting video file at \(fileURL.path): \(error.localizedDescription)")
            }
        } else {
            print("Video file does not exist at \(fileURL.path)")
        }
        
        // Delete thumbnail file
        if let thumbnailPath = clip.thumbnailPath {
            let thumbnailURL = URL(fileURLWithPath: thumbnailPath)
            if fileManager.fileExists(atPath: thumbnailURL.path) {
                do {
                    try fileManager.removeItem(at: thumbnailURL)
                    print("Deleted thumbnail file at \(thumbnailURL.path)")
                    await MainActor.run {
                        ThumbnailCache.shared.removeThumbnail(at: thumbnailPath)
                    }
                } catch {
                    print("Error deleting thumbnail file at \(thumbnailURL.path): \(error.localizedDescription)")
                }
            } else {
                print("Thumbnail file does not exist at \(thumbnailURL.path)")
            }
        }
    }
    
    // MARK: - Deep Game Deletion
    
    func deleteGameDeep(_ game: Game) async {
        guard let athlete = game.athlete else {
            print("Game has no athlete; cannot delete deeply.")
            return
        }
        
        // Delete all video clips and their files
        for clip in game.videoClips {
            await deleteFiles(for: clip)
            modelContext.delete(clip)
        }
        
        // Remove game from athlete's games
        if let index = athlete.games.firstIndex(of: game) {
            athlete.games.remove(at: index)
        }
        
        // Remove game from tournament's games if applicable
        if let tournament = game.tournament {
            if let index = tournament.games.firstIndex(of: game) {
                tournament.games.remove(at: index)
            }
        }
        
        // Delete playResult if exists
        if let playResult = game.playResult {
            modelContext.delete(playResult)
        }
        
        // Delete gameStats if exists
        if let gameStats = game.statistics {
            modelContext.delete(gameStats)
        }
        
        // Delete the game itself
        modelContext.delete(game)
        
        do {
            try modelContext.save()
            print("Deleted game and related data successfully.")
        } catch {
            print("Error saving context after deleting game deeply: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Game Creation
    
    func createGame(for athlete: Athlete, opponent: String, date: Date, tournament: Tournament?, isLive: Bool) async {
        // Check for duplicate game with same opponent and same day
        let calendar = Calendar.current
        for existingGame in athlete.games {
            if existingGame.opponent == opponent,
               calendar.isDate(existingGame.date, inSameDayAs: date) {
                print("Duplicate game found for opponent \(opponent) on the same day.")
                return
            }
        }
        
        if isLive {
            // End all other live games for athlete
            for game in athlete.games where game.isLive {
                game.isLive = false
            }
        }
        
        // Create new game
        let game = Game()
        game.opponent = opponent
        game.date = date
        game.isLive = isLive
        
        // Create GameStatistics and assign
        let stats = GameStatistics()
        game.statistics = stats
        
        // Insert into context
        modelContext.insert(game)
        modelContext.insert(stats)
        
        // Assign tournament
        if let providedTournament = tournament {
            game.tournament = providedTournament
            providedTournament.games.append(game)
        } else {
            if let activeTournament = athlete.tournaments.first(where: { $0.isActive }) {
                game.tournament = activeTournament
                activeTournament.games.append(game)
            }
        }
        
        // Append game to athlete.games
        athlete.games.append(game)
        game.athlete = athlete
        
        do {
            try modelContext.save()
            print("Created new game successfully.")
        } catch {
            print("Error saving context after creating game: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Game Lifecycle Management
    
    func start(_ game: Game) async {
        guard let athlete = game.athlete else {
            print("Cannot start game: no athlete found.")
            return
        }
        
        // End other live games of this athlete
        for otherGame in athlete.games where otherGame.isLive && otherGame != game {
            otherGame.isLive = false
        }
        
        // Start this game
        game.isLive = true
        
        do {
            try modelContext.save()
            print("Started game for athlete \(athlete.name).")
        } catch {
            print("Error saving context after starting game: \(error.localizedDescription)")
        }
    }
    
    func end(_ game: Game) async {
        game.isLive = false
        game.isComplete = true
        
        if let athlete = game.athlete, let statistics = athlete.statistics {
            statistics.addCompletedGame()
            print("Added completed game to athlete's statistics.")
        }
        
        do {
            try modelContext.save()
            print("Ended game and saved changes.")
        } catch {
            print("Error saving context after ending game: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Data Consistency Repair
    
    func repairConsistency(for athlete: Athlete, allGames: [Game]) async {
        // Set of games that athlete currently references
        let relationshipSet = Set(athlete.games)
        // Set of games that query found for this athlete
        let querySet = Set(allGames.filter { $0.athlete == athlete })
        
        let orphanedGames = querySet.subtracting(relationshipSet)
        let gamesWithWrongAthlete = athlete.games.filter { $0.athlete != athlete }
        
        if !orphanedGames.isEmpty {
            for game in orphanedGames {
                athlete.games.append(game)
                game.athlete = athlete
            }
            print("Re-added \(orphanedGames.count) orphaned games to athlete's games.")
        }
        
        if !gamesWithWrongAthlete.isEmpty {
            for game in gamesWithWrongAthlete {
                game.athlete = athlete
            }
            print("Corrected athlete reference in \(gamesWithWrongAthlete.count) games.")
        }
        
        if !orphanedGames.isEmpty || !gamesWithWrongAthlete.isEmpty {
            do {
                try modelContext.save()
                print("Data consistency repaired and saved.")
            } catch {
                print("Error saving context after repairing consistency: \(error.localizedDescription)")
            }
        } else {
            print("No data consistency issues found.")
        }
    }
}
