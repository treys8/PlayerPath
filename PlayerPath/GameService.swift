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
                await retryAsync {
                    try await FirestoreManager.shared.deleteGame(userId: userId, gameId: firestoreId)
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

    func createGame(for athlete: Athlete, opponent: String, date: Date, isLive: Bool, season: Season? = nil, allowWithoutSeason: Bool = false) async -> Result<Game, GameCreationError> {
        // Resolve target season: caller-supplied override wins, otherwise active.
        let resolvedSeason = season ?? athlete.activeSeason
        let hasSeason = resolvedSeason != nil

        logger.debug("createGame() called — athlete: \(athlete.name, privacy: .private), hasSeason: \(hasSeason), resolvedSeason: \(resolvedSeason?.name ?? "none"), allowWithoutSeason: \(allowWithoutSeason)")

        // If no season could be resolved and not explicitly allowed to create without season, return error
        if !hasSeason && !allowWithoutSeason {
            logger.debug("Returning .noActiveSeason error")
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

        // End all other live games if this game is going live — but only when
        // the new game is on the active season. A historical game filed onto a
        // past season should never interrupt the current live game.
        if isLive && (resolvedSeason?.isActive ?? true) {
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
        game.season = resolvedSeason // Will be nil if no season available and allowWithoutSeason

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

            let seasonInfo = game.season?.name ?? "year \(game.year ?? 0)"
            logger.info("Game created: \(opponent, privacy: .private) (live: \(isLive), tracking: \(seasonInfo))")

            NotificationCenter.default.post(name: .gameCreated, object: game)

            await scheduleReminderIfNeeded(for: game)

            if game.isLive {
                NotificationCenter.default.post(name: .gameBecameLive, object: game)
                await GameAlertService.shared.requestPermissionIfNeeded()
                await GameAlertService.shared.scheduleEndGameReminder(for: game)
            }

            return .success(game)
        } catch {
            logger.error("Game save failed: \(error.localizedDescription)")
            return .failure(.saveFailed)
        }
    }

    /// Schedule a local reminder for the game if user preferences allow and
    /// the game is far enough in the future. Centralizes what used to be
    /// duplicated across AddGameView, GamesView, and GameCreationView callers.
    func scheduleReminderIfNeeded(for game: Game) async {
        let prefs = try? modelContext.fetch(FetchDescriptor<UserPreferences>()).first
        guard prefs?.enableGameReminders ?? true else { return }
        let minutes = prefs?.gameReminderMinutes ?? 30
        guard let gameDate = game.date,
              gameDate > Date().addingTimeInterval(TimeInterval(minutes * 60)) else { return }
        await PushNotificationService.shared.scheduleGameReminder(
            gameId: game.id.uuidString,
            opponent: game.opponent,
            scheduledTime: gameDate,
            reminderMinutes: minutes
        )
    }

    // MARK: - Game Lifecycle Management
    
    func start(_ game: Game) async {
        guard let athlete = game.athlete else {
            logger.warning("start() called but game.athlete is nil — no action taken")
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

            NotificationCenter.default.post(name: .gameEnded, object: game)
        } catch {
            logger.error("Failed to save game end: \(error.localizedDescription)")
        }
    }

    func restart(_ game: Game) async {
        guard let athlete = game.athlete else {
            logger.warning("restart() called but game.athlete is nil — no action taken")
            return
        }

        // End other live games of this athlete
        for otherGame in athlete.games ?? [] where otherGame.isLive && otherGame != game {
            otherGame.isLive = false
            GameAlertService.shared.cancelEndGameReminder(for: otherGame)
        }

        // Restart this game
        game.isComplete = false
        game.isLive = true
        game.liveStartDate = Date()
        game.needsSync = true

        do {
            try modelContext.save()

            AnalyticsService.shared.trackGameStarted(gameID: game.id.uuidString)

            let userForSync = athlete.user
            Task {
                guard let user = userForSync else { return }
                do {
                    try await SyncCoordinator.shared.syncGames(for: user)
                } catch {
                    self.logger.error("Sync after game restart failed: \(error.localizedDescription)")
                }
            }

            NotificationCenter.default.post(name: .gameBecameLive, object: game)
            await GameAlertService.shared.requestPermissionIfNeeded()
            await GameAlertService.shared.scheduleEndGameReminder(for: game)
        } catch {
            logger.error("Failed to save game restart: \(error.localizedDescription)")
        }
    }

    func complete(_ game: Game) async {
        game.isComplete = true
        game.needsSync = true

        // Recalculate game stats first (they feed into athlete stats)
        do {
            try StatisticsService.shared.recalculateGameStatistics(for: game, context: modelContext)
        } catch {
            logger.error("Failed to recalculate game statistics on complete: \(error.localizedDescription)")
        }

        if let athlete = game.athlete {
            do {
                try StatisticsService.shared.recalculateAthleteStatistics(for: athlete, context: modelContext, skipSave: true)
            } catch {
                logger.error("Failed to recalculate athlete statistics on complete: \(error.localizedDescription)")
            }
        }

        do {
            try modelContext.save()

            let userForSync = game.athlete?.user
            Task {
                guard let user = userForSync else { return }
                do {
                    try await SyncCoordinator.shared.syncGames(for: user)
                } catch {
                    self.logger.error("Sync after game complete failed: \(error.localizedDescription)")
                }
            }

            ReviewPromptManager.shared.recordCompletedGame()
        } catch {
            logger.error("Failed to save game completion: \(error.localizedDescription)")
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

