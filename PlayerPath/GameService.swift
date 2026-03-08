import Foundation
import SwiftUI
import SwiftData

@MainActor
class GameService {

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Deep Game Deletion

    func deleteGameDeep(_ game: Game) async {
        // Capture primitive values before SwiftData deletion removes access
        let firestoreId = game.firestoreId
        let userId = game.athlete?.user?.firebaseAuthUid

        // Delete all video clips — VideoClip.delete handles local files, thumbnails,
        // cloud storage, and play results. SwiftData handles inverse relationship cleanup.
        for clip in game.videoClips ?? [] {
            clip.delete(in: modelContext)
        }

        // Delete all photos associated with this game — Photo.delete handles local files
        // and cloud storage.
        for photo in game.photos ?? [] {
            photo.delete(in: modelContext)
        }

        // Delete game stats
        if let gameStats = game.gameStats {
            modelContext.delete(gameStats)
        }

        modelContext.delete(game)

        do {
            try modelContext.save()
            #if DEBUG
            print("Deleted game and related data successfully.")
            #endif

            // Soft-delete from Firestore if the game was previously synced
            if let firestoreId, let userId {
                Task {
                    do {
                        try await FirestoreManager.shared.deleteGame(userId: userId, gameId: firestoreId)
                    } catch {
                        #if DEBUG
                        print("⚠️ Failed to delete game from Firestore: \(error)")
                        #endif
                    }
                }
            }
        } catch {
            print("Error saving context after deleting game: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Game Creation

    enum GameCreationError: LocalizedError {
        case noActiveSeason
        case duplicateGame
        case saveFailed

        var errorDescription: String? {
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

            // Trigger immediate sync to Firestore.
            // Capture user before the Task to avoid accessing a SwiftData model across
            // an async boundary after the context may have changed.
            let userForSync = athlete.user
            Task {
                guard let user = userForSync else { return }
                do {
                    try await SyncCoordinator.shared.syncGames(for: user)
                    print("✅ Game synced to Firestore successfully")
                } catch {
                    print("⚠️ Failed to sync game to Firestore: \(error)")
                }
            }

            #if DEBUG
            let seasonInfo = game.season?.name ?? "year \(game.year ?? 0)"
            print("✅ Game created: \(opponent) (live: \(isLive), tracking: \(seasonInfo))")
            #endif

            NotificationCenter.default.post(name: .gameCreated, object: game)

            if game.isLive {
                NotificationCenter.default.post(name: .gameBecameLive, object: game)
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

            // Capture user before the Task to avoid accessing a SwiftData model across
            // an async boundary after the context may have changed.
            let userForSync = athlete.user
            Task {
                guard let user = userForSync else { return }
                do {
                    try await SyncCoordinator.shared.syncGames(for: user)
                    print("✅ Game start synced to Firestore successfully")
                } catch {
                    print("⚠️ Failed to sync game start to Firestore: \(error)")
                }
            }

            print("Started game for athlete \(athlete.name).")
            NotificationCenter.default.post(name: .gameBecameLive, object: game)
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
            // Recalculate all athlete statistics from source of truth.
            // Resetting and recomputing (rather than adding incrementally) prevents
            // double-counting if end() is ever called more than once on the same game.
            do {
                try StatisticsService.shared.recalculateAthleteStatistics(for: athlete, context: modelContext)
            } catch {
                print("⚠️ Failed to recalculate athlete statistics after ending game: \(error.localizedDescription)")
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

            // Capture user before the Task to avoid accessing a SwiftData model across
            // an async boundary after the context may have changed.
            let userForSync = game.athlete?.user
            Task {
                guard let user = userForSync else { return }
                do {
                    try await SyncCoordinator.shared.syncGames(for: user)
                    print("✅ Game end synced to Firestore successfully")
                } catch {
                    print("⚠️ Failed to sync game end to Firestore: \(error)")
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

