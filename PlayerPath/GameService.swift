import Foundation
import SwiftUI
import SwiftData

@MainActor
class GameService {

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
                    // Remove from cache (ThumbnailCache is an actor)
                    ThumbnailCache.shared.removeThumbnail(at: thumbnailPath)
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
        for clip in game.videoClips ?? [] {
            if let clipAthlete = clip.athlete,
               var athleteClips = clipAthlete.videoClips,
               let clipIndex = athleteClips.firstIndex(of: clip) {
                athleteClips.remove(at: clipIndex)
                clipAthlete.videoClips = athleteClips
            }
            if let playResult = clip.playResult {
                modelContext.delete(playResult)
            }
            await deleteFiles(for: clip)
            modelContext.delete(clip)
        }
        
        // Remove game from athlete's games
        if var athleteGames = athlete.games,
           let index = athleteGames.firstIndex(of: game) {
            athleteGames.remove(at: index)
            athlete.games = athleteGames
        }
        
        // Delete gameStats if exists
        if let gameStats = game.gameStats {
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

    enum GameCreationError: Error {
        case noActiveSeason
        case duplicateGame
        case saveFailed

        var localizedDescription: String {
            switch self {
            case .noActiveSeason:
                return "No active season found. Please create a season before adding games."
            case .duplicateGame:
                return "A game against this opponent already exists on the same day."
            case .saveFailed:
                return "Failed to save game. Please try again."
            }
        }
    }

    func createGame(for athlete: Athlete, opponent: String, date: Date, isLive: Bool, allowWithoutSeason: Bool = false) async -> Result<Game, GameCreationError> {
        // Check if athlete has an active season
        let hasActiveSeason = athlete.activeSeason != nil

        #if DEBUG
        print("🎮 GameService.createGame() called")
        print("   Athlete: \(athlete.name)")
        print("   Has active season: \(hasActiveSeason)")
        if let season = athlete.activeSeason {
            print("   Active season: \(season.name)")
        }
        print("   Allow without season: \(allowWithoutSeason)")
        #endif

        // If no active season and not explicitly allowed to create without season, return error
        if !hasActiveSeason && !allowWithoutSeason {
            #if DEBUG
            print("   ❌ Returning .noActiveSeason error")
            #endif
            return .failure(.noActiveSeason)
        }

        // Check for duplicate game with same opponent on same day
        let calendar = Calendar.current
        let isDuplicate = (athlete.games ?? []).contains { existingGame in
            existingGame.opponent == opponent &&
            existingGame.date.map { calendar.isDate($0, inSameDayAs: date) } == true
        }

        guard !isDuplicate else {
            return .failure(.duplicateGame)
        }

        // End all other live games if this game is going live
        if isLive {
            (athlete.games ?? []).filter { $0.isLive }.forEach { $0.isLive = false }
        }

        // Create game with relationships
        let game = Game(date: date, opponent: opponent)
        game.isLive = isLive
        game.athlete = athlete
        game.season = athlete.activeSeason // Will be nil if no active season

        // Create and link statistics
        let stats = GameStatistics()
        stats.game = game
        game.gameStats = stats

        // Mark for Firestore sync (Phase 2)
        game.needsSync = true

        modelContext.insert(game)
        modelContext.insert(stats)

        // Save and notify
        do {
            try modelContext.save()

            // Track game creation analytics
            AnalyticsService.shared.trackGameCreated(
                gameID: game.id.uuidString,
                opponent: opponent,
                isLive: isLive
            )

            // Trigger immediate sync to Firestore
            Task {
                guard let user = athlete.user else { return }
                do {
                    try await SyncCoordinator.shared.syncGames(for: user)
                    print("✅ Game synced to Firestore successfully")
                } catch {
                    print("⚠️ Failed to sync game to Firestore: \(error)")
                    // Don't block game creation on sync failure
                }
            }

            #if DEBUG
            let seasonInfo = game.season?.name ?? "year \(game.year ?? 0)"
            print("✅ Game created: \(opponent) (live: \(isLive), tracking: \(seasonInfo))")
            #endif

            NotificationCenter.default.post(name: Notification.Name("GameCreated"), object: game)

            if game.isLive {
                NotificationCenter.default.post(name: Notification.Name("GameBecameLive"), object: game)
            }

            return .success(game)
        } catch {
            #if DEBUG
            print("❌ Game save failed: \(error.localizedDescription)")
            #endif
            return .failure(.saveFailed)
        }
    }
    
    // MARK: - Game Lifecycle Management
    
    func start(_ game: Game) async {
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

        // Mark for Firestore sync (Phase 2)
        game.needsSync = true

        do {
            try modelContext.save()

            // Track game start analytics
            AnalyticsService.shared.trackGameStarted(gameID: game.id.uuidString)

            // Trigger immediate sync to Firestore
            Task {
                guard let user = athlete.user else { return }
                do {
                    try await SyncCoordinator.shared.syncGames(for: user)
                    print("✅ Game start synced to Firestore successfully")
                } catch {
                    print("⚠️ Failed to sync game start to Firestore: \(error)")
                }
            }

            print("Started game for athlete \(athlete.name).")
            NotificationCenter.default.post(name: Notification.Name("GameBecameLive"), object: game)
        } catch {
            print("Error saving context after starting game: \(error.localizedDescription)")
        }
    }
    
    func end(_ game: Game) async {
        game.isLive = false
        game.isComplete = true

        // Mark for Firestore sync (Phase 2)
        game.needsSync = true

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

            // Track game end analytics
            let gameStats = game.gameStats
            AnalyticsService.shared.trackGameEnded(
                gameID: game.id.uuidString,
                atBats: gameStats?.atBats ?? 0,
                hits: gameStats?.hits ?? 0
            )

            // Trigger immediate sync to Firestore
            Task {
                if let athlete = game.athlete, let user = athlete.user {
                    do {
                        try await SyncCoordinator.shared.syncGames(for: user)
                        print("✅ Game end synced to Firestore successfully")
                    } catch {
                        print("⚠️ Failed to sync game end to Firestore: \(error)")
                    }
                }
            }

            print("Ended game and saved changes.")
        } catch {
            print("Error saving context after ending game: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Data Consistency Repair
    
    func repairConsistency(for athlete: Athlete, allGames: [Game]) async {
        // Set of games that athlete currently references
        let relationshipSet = Set(athlete.games ?? [])
        // Set of games that query found for this athlete
        let querySet = Set(allGames.filter { $0.athlete?.id == athlete.id })
        
        let orphanedGames = querySet.subtracting(relationshipSet)
        let gamesWithWrongAthlete = (athlete.games ?? []).filter { $0.athlete != athlete }
        
        if !orphanedGames.isEmpty {
            var athleteGames = athlete.games ?? []
            for game in orphanedGames {
                athleteGames.append(game)
                game.athlete = athlete
            }
            athlete.games = athleteGames
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

