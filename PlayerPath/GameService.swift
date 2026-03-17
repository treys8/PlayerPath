import Foundation
import SwiftUI
import SwiftData
import os.log

@MainActor
class GameService {

    private let modelContext: ModelContext
    private let logger = Logger(subsystem: "PlayerPath", category: "GameService")

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Deep Game Deletion

    func deleteGameDeep(_ game: Game) async {
        // Capture primitive values before SwiftData deletion removes access
        let firestoreId = game.firestoreId
        let userId = game.athlete?.user?.firebaseAuthUid
        let gameAthlete = game.athlete
        let gameIdString = game.id.uuidString

        // Cancel any pending push notification for this game
        PushNotificationService.shared.cancelNotifications(
            withIdentifiers: ["game_reminder_\(gameIdString)"]
        )
        GameAlertService.shared.cancelEndGameReminder(for: game)

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
            // Save the deletion first so recalculation operates on committed state
            try modelContext.save()
        } catch {
            logger.error("Failed to save game deletion: \(error.localizedDescription)")
            return
        }

        // Recalculate athlete statistics to reflect the removed game
        if let athlete = gameAthlete {
            do {
                try StatisticsService.shared.recalculateAthleteStatistics(for: athlete, context: modelContext, skipSave: true)
                try modelContext.save()
            } catch {
                logger.error("Failed to recalculate statistics after game deletion: \(error.localizedDescription)")
            }
        }

        logger.info("Deleted game and related data successfully")

        // Soft-delete from Firestore if the game was previously synced
        if let firestoreId, let userId {
            Task {
                for attempt in 1...3 {
                    do {
                        try await FirestoreManager.shared.deleteGame(userId: userId, gameId: firestoreId)
                        return
                    } catch {
                        self.logger.error("Failed to delete game from Firestore (attempt \(attempt)/3): \(error.localizedDescription)")
                        if attempt < 3 {
                            try? await Task.sleep(for: .seconds(2))
                        }
                    }
                }
            }
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
        let trimmedOpponent = opponent.trimmingCharacters(in: .whitespaces)
        let isDuplicate = (athlete.games ?? []).contains { existingGame in
            existingGame.opponent.localizedCaseInsensitiveCompare(trimmedOpponent) == .orderedSame &&
            existingGame.date.map { calendar.isDate($0, inSameDayAs: date) } == true
        }

        guard !isDuplicate else {
            return .failure(.duplicateGame)
        }

        // End all other live games if this game is going live
        if isLive {
            (athlete.games ?? []).filter { $0.isLive }.forEach {
                $0.isLive = false
                GameAlertService.shared.cancelEndGameReminder(for: $0)
            }
        }

        // Create game with relationships
        let game = Game(date: date, opponent: opponent)
        game.isLive = isLive
        if isLive { game.liveStartDate = Date() }
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
                } catch {
                    self.logger.error("Sync after game creation failed: \(error.localizedDescription)")
                }
            }

            #if DEBUG
            let seasonInfo = game.season?.name ?? "year \(game.year ?? 0)"
            print("✅ Game created: \(opponent) (live: \(isLive), tracking: \(seasonInfo))")
            #endif

            NotificationCenter.default.post(name: .gameCreated, object: game)

            if game.isLive {
                NotificationCenter.default.post(name: .gameBecameLive, object: game)
                await GameAlertService.shared.requestPermissionIfNeeded()
                await GameAlertService.shared.scheduleEndGameReminder(for: game)
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
            return
        }
        
        // End other live games of this athlete
        for otherGame in athlete.games ?? [] where otherGame.isLive && otherGame != game {
            otherGame.isLive = false
            GameAlertService.shared.cancelEndGameReminder(for: otherGame)
        }
        
        // Start this game
        game.isLive = true
        game.liveStartDate = Date()

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
                } catch {
                    self.logger.error("Sync after game start failed: \(error.localizedDescription)")
                }
            }

            NotificationCenter.default.post(name: .gameBecameLive, object: game)
            await GameAlertService.shared.requestPermissionIfNeeded()
            await GameAlertService.shared.scheduleEndGameReminder(for: game)
        } catch {
            logger.error("Failed to save game start: \(error.localizedDescription)")
        }
    }

    func end(_ game: Game) async {
        game.isLive = false
        game.isComplete = true
        game.liveStartDate = nil
        GameAlertService.shared.cancelEndGameReminder(for: game)

        // Mark for Firestore sync (Phase 2)
        game.needsSync = true

        if let athlete = game.athlete {
            // Recalculate all athlete statistics from source of truth.
            // Resetting and recomputing (rather than adding incrementally) prevents
            // double-counting if end() is ever called more than once on the same game.
            // Use skipSave to consolidate into a single save below.
            do {
                try StatisticsService.shared.recalculateAthleteStatistics(for: athlete, context: modelContext, skipSave: true)
            } catch {
                logger.error("Failed to recalculate statistics on game end: \(error.localizedDescription)")
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
                } catch {
                    self.logger.error("Sync after game end failed: \(error.localizedDescription)")
                }
            }

            // Track completed game for review prompt eligibility
            ReviewPromptManager.shared.recordCompletedGame()
        } catch {
            logger.error("Failed to save game end: \(error.localizedDescription)")
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
        
        // Set the owning side only — SwiftData manages the inverse relationship
        for game in orphanedGames {
            game.athlete = athlete
        }

        for game in gamesWithWrongAthlete {
            game.athlete = athlete
        }

        if !orphanedGames.isEmpty || !gamesWithWrongAthlete.isEmpty {
            do {
                try modelContext.save()
                logger.info("Repaired \(orphanedGames.count) orphaned and \(gamesWithWrongAthlete.count) misassigned games")
            } catch {
                logger.error("Failed to save consistency repairs: \(error.localizedDescription)")
            }
        }
    }
}

