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
        let gameID = game.id
        // Capture hole numbers BEFORE deletion so we can soft-delete the
        // matching Firestore subcollection docs after the local save commits.
        let holeNumbers = (game.holeScores ?? []).map(\.holeNumber)

        // v6.1 PR2: collect HighlightReel doc IDs for this game so we can
        // soft-delete the Firestore docs after local delete + save. Reels
        // aren't a SwiftData child of Game (only denormalized `gameID`), so
        // we have to fetch flat.
        var reelDocIDsToSoftDelete: [String] = []
        do {
            let allReels = try modelContext.fetch(FetchDescriptor<HighlightReel>())
            let matchingReels = allReels.filter { $0.gameID == gameID }
            reelDocIDsToSoftDelete = matchingReels.compactMap(\.firestoreId)
            for reel in matchingReels {
                modelContext.delete(reel)
            }
        } catch {
            logger.error("Failed to fetch HighlightReels for cascade delete: \(error.localizedDescription)")
        }

        // Delete all video clips — VideoClip.delete handles local files, thumbnails,
        // cloud storage, and play results. SwiftData handles inverse relationship cleanup.
        for clip in game.videoClips ?? [] {
            clip.delete(in: modelContext, cleanupReels: false)
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

        // Delete per-hole scoring rows. SwiftData inverse nullifies the
        // game pointer on cascade, but we want hard removal so a re-created
        // game with the same UUID can't inherit ghost holes.
        for hole in game.holeScores ?? [] {
            modelContext.delete(hole)
        }

        modelContext.delete(game)

        do {
            // Save the deletion first so recalculation operates on committed state
            try modelContext.save()
        } catch {
            logger.error("Failed to save game deletion: \(error.localizedDescription)")
            return
        }

        // Cancel pending notifications only AFTER the delete is committed to disk.
        // If the save above fails we return early, leaving the game — and its
        // reminders — intact. All identifiers come from primitives captured at
        // entry, so nothing here touches the now-deleted `game` model.
        PushNotificationService.shared.cancelNotifications(
            withIdentifiers: ["game_reminder_\(gameIdString)"]
        )
        GameAlertService.shared.cancelEndGameReminder(forGameID: gameID)
        // Drop any pending clip-tagging nudge so it can't fire for a deleted game.
        ClipTaggingReminderService.shared.cancelNudge(eventID: gameID)

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
                // Soft-delete each hole subcollection doc so cross-device sync
                // doesn't resurrect them. Fire-and-forget per hole — failures
                // are caught by the daily server-side cleanup.
                for holeNumber in holeNumbers {
                    await retryAsync {
                        try await FirestoreManager.shared.deleteGameHoleScore(
                            userId: userId,
                            gameFirestoreId: firestoreId,
                            holeNumber: holeNumber
                        )
                    }
                }
            }
        }

        // Soft-delete each reel doc independently of the game firestoreId —
        // reels live at the user-scoped collection, not under the game doc,
        // so a game with no firestoreId (created offline, never synced) still
        // needs to surface any synced reels for cleanup.
        if let userId, !reelDocIDsToSoftDelete.isEmpty {
            Task {
                for reelId in reelDocIDsToSoftDelete {
                    await retryAsync {
                        try await FirestoreManager.shared.deleteHighlightReel(
                            userId: userId,
                            reelId: reelId
                        )
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

    func createGame(for athlete: Athlete, opponent: String, date: Date, isLive: Bool, season: Season? = nil, allowWithoutSeason: Bool = false, allowDuplicate: Bool = false, golfDetails: GolfRoundDetails? = nil, location: String? = nil, tournament: GolfTournament? = nil) async -> Result<Game, GameCreationError> {
        // Resolve target season: caller-supplied override wins, otherwise active.
        let resolvedSeason = season ?? athlete.activeSeason
        let hasSeason = resolvedSeason != nil

        logger.debug("createGame() called — athlete: \(athlete.name, privacy: .private), hasSeason: \(hasSeason), resolvedSeason: \(resolvedSeason?.name ?? "none"), allowWithoutSeason: \(allowWithoutSeason)")

        // If no season could be resolved and not explicitly allowed to create without season, return error
        if !hasSeason && !allowWithoutSeason {
            logger.debug("Returning .noActiveSeason error")
            return .failure(.noActiveSeason)
        }

        // Check for duplicate game with same opponent on same day — but only
        // for ball sports. In golf `opponent` is the course name, and playing
        // the same course twice in a day is legitimate (36-hole tournament days,
        // same-course replays), so course+day can't distinguish an intentional
        // round from an accidental double-tap. Golf gets no auto-dedupe.
        // A round created via allowWithoutSeason may have a nil season, so also
        // treat the presence of golfDetails as a golf signal.
        //
        // For ball sports this is a soft guard, not a hard rule: a same-opponent,
        // same-day game is a legitimate doubleheader, so callers surface a
        // confirmation and re-call with `allowDuplicate: true` to proceed.
        let isGolf = (resolvedSeason?.sport == .golf) || (golfDetails != nil)
        if !isGolf && !allowDuplicate {
            let calendar = Calendar.current
            let trimmedOpponent = opponent.trimmingCharacters(in: .whitespaces)
            let isDuplicate = (athlete.games ?? []).contains { existingGame in
                existingGame.opponent.localizedCaseInsensitiveCompare(trimmedOpponent) == .orderedSame &&
                existingGame.date.map { calendar.isDate($0, inSameDayAs: date) } == true
            }

            guard !isDuplicate else {
                return .failure(.duplicateGame)
            }
        }

        // End all other live games if this game is going live — but only when
        // the new game is on the active season. A historical game filed onto a
        // past season should never interrupt the current live game.
        if isLive && (resolvedSeason?.isActive ?? true) {
            (athlete.games ?? []).filter { $0.isLive }.forEach {
                $0.isLive = false
                $0.needsSync = true
                GameAlertService.shared.cancelEndGameReminder(for: $0)
            }
            // v6.1 golf single-live spans practices: a new live tournament also
            // ends any live practice round / range session for this athlete.
            if resolvedSeason?.sport == .golf {
                endLivePractices(for: athlete)
            }
        }

        // Create game with relationships
        let game = Game(date: date, opponent: opponent)
        game.isLive = isLive
        if isLive { game.liveStartDate = Date() }
        game.athlete = athlete
        game.season = resolvedSeason // Will be nil if no season available and allowWithoutSeason

        // Apply golf/location fields up front so they land in the same save as
        // the rest of the game. Persisting them here (rather than in a second
        // save by the caller) ensures the sync Task spawned below serializes a
        // complete doc — otherwise par/score could be missing on the first push
        // and only reach Firestore on a later unrelated sync trigger.
        if let golf = golfDetails {
            game.holes = golf.holes
            game.par = golf.par
            game.totalScore = golf.totalScore
            game.tracksShotByShot = golf.tracksShotByShot
            // Scorecard scan (SchemaV32): now that the round exists, persist the
            // confirmed card (blob + tee + summed par). No rows are materialized —
            // each hole seeds lazily from the blob when it's scored.
            if let scanned = golf.scannedHoles, !scanned.isEmpty {
                GolfScoreWriter.applyScannedCard(scanned, tee: golf.selectedTee, to: .game(game), context: modelContext)
            }
        }
        if let location {
            game.location = location
        }

        // Multi-round tournament link (SchemaV27) — routed through the shared
        // helper so the round-numbering rule lives in one place (also used by
        // EditGameSheet's "Move to Tournament").
        if let tournament {
            GameService.linkRound(game, to: tournament)
        }

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

    /// Links (or unlinks) a golf round to/from a tournament, assigning the next
    /// round number (max existing + 1) and dirtying the round plus any affected
    /// tournament so the change syncs. Shared by `createGame` and EditGameSheet's
    /// "Move to Tournament". Pass `nil` to unlink (the round becomes standalone).
    /// No-op when membership is unchanged.
    @MainActor
    static func linkRound(_ game: Game, to tournament: GolfTournament?) {
        let old = game.tournament
        guard old !== tournament else { return }

        // Dirty the previous tournament so its inverse-relation change re-syncs.
        old?.needsSync = true

        if let tournament {
            game.tournament = tournament
            let maxRound = (tournament.rounds ?? [])
                .filter { $0.id != game.id }
                .compactMap { $0.roundNumber }.max() ?? 0
            game.roundNumber = maxRound + 1
            tournament.needsSync = true
        } else {
            game.tournament = nil
            game.roundNumber = nil
        }
        game.needsSync = true
    }

    /// Schedule a local reminder for the game if user preferences allow and
    /// the game is far enough in the future. Centralizes what used to be
    /// duplicated across AddGameView, GamesView, and GameCreationView callers.
    func scheduleReminderIfNeeded(for game: Game) async {
        // Prompt for permission on first game creation — first concrete
        // moment the user has a reason to receive a notification.
        await PushNotificationService.shared.requestAuthorizationIfNeeded()

        let prefs = try? modelContext.fetch(FetchDescriptor<UserPreferences>()).first
        guard prefs?.enableGameReminders ?? true else { return }
        let minutes = prefs?.gameReminderMinutes ?? 30
        guard let gameDate = game.date,
              gameDate > Date().addingTimeInterval(TimeInterval(minutes * 60)) else { return }
        await PushNotificationService.shared.scheduleGameReminder(
            gameId: game.id.uuidString,
            opponent: game.opponent,
            scheduledTime: gameDate,
            reminderMinutes: minutes,
            isGolf: game.season?.sport == .golf
        )
    }

    /// Cancels all pending `game_reminder_*` notifications and re-schedules them
    /// for every future game. Call when the gameReminders toggle is flipped ON
    /// or when `gameReminderMinutes` changes — both require a full refresh so
    /// existing games reflect the new preference.
    func rescheduleAllGameReminders() async {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let gameReminderIds = pending
            .filter { $0.identifier.hasPrefix("game_reminder_") }
            .map { $0.identifier }
        if !gameReminderIds.isEmpty {
            PushNotificationService.shared.cancelNotifications(withIdentifiers: gameReminderIds)
        }

        // Fetch all games, filter in memory — SwiftData #Predicate support for
        // optional dates is inconsistent. Future games are a small set.
        let descriptor = FetchDescriptor<Game>()
        guard let allGames = try? modelContext.fetch(descriptor) else { return }
        let now = Date()
        let futureGames = allGames.filter { game in
            guard let date = game.date else { return false }
            return date > now
        }
        for game in futureGames {
            await scheduleReminderIfNeeded(for: game)
        }
    }

    // MARK: - Game Lifecycle Management

    /// End any live golf practices for the athlete. Used by the golf start
    /// paths so the single-live invariant spans games and practices.
    private func endLivePractices(for athlete: Athlete) {
        for practice in (athlete.practices ?? []) where practice.isLive {
            practice.isLive = false
            practice.liveStartDate = nil
            practice.needsSync = true
        }
    }

    func start(_ game: Game) async {
        guard let athlete = game.athlete else {
            logger.warning("start() called but game.athlete is nil — no action taken")
            return
        }

        // End other live games of this athlete
        for otherGame in athlete.games ?? [] where otherGame.isLive && otherGame != game {
            otherGame.isLive = false
            otherGame.needsSync = true
            GameAlertService.shared.cancelEndGameReminder(for: otherGame)
        }
        // v6.1: golf tournaments also end live practices (single-live invariant).
        if game.season?.sport == .golf {
            endLivePractices(for: athlete)
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

            // Behavioral re-engagement nudges (local-only, opt-out). Snapshot
            // model values to plain types BEFORE any await so a concurrent delete
            // can't invalidate the model mid-flight. The stale-game reminder was
            // already cancelled above, preserving cancel-before-nudge ordering.
            // This is the shared "game completed" extension hook (Feature 6 reuses
            // it) — keep each side-effect a small, well-ordered call.
            let endedGameID = game.id
            let isGolfRound = game.season?.sport == .golf
            let untaggedClipCount = (game.videoClips ?? []).filter {
                !$0.isTagged && !$0.isDeletedRemotely && $0.sourceCoachVideoID == nil
            }.count
            let endedSeason = game.season

            // Milestone diff first: its only model read (milestones(for:)) runs
            // synchronously at the top of processGameEnd, before any suspension.
            await MilestoneReminderService.shared.processGameEnd(season: endedSeason)
            await ClipTaggingReminderService.shared.scheduleIfNeeded(
                eventID: endedGameID,
                untaggedCount: untaggedClipCount,
                eventNoun: isGolfRound ? "round" : "game"
            )
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
            otherGame.needsSync = true
            GameAlertService.shared.cancelEndGameReminder(for: otherGame)
        }
        // v6.1: golf tournaments also end live practices (single-live invariant).
        if game.season?.sport == .golf {
            endLivePractices(for: athlete)
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

