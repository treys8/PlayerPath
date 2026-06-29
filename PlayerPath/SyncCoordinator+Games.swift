import Foundation
import SwiftData
import FirebaseAuth
import os

private let syncLog = Logger(subsystem: "com.playerpath.app", category: "Sync")

extension SyncCoordinator {
    // MARK: - Games Sync

    /// Syncs all games for a user bidirectionally (upload + download + resolve)
    /// - Parameter user: The SwiftData User to sync games for
    func syncGames(for user: User) async throws {
        guard let context = modelContext else {
            return
        }


        do {
            try await uploadLocalGames(user, context: context)
            try await downloadRemoteGames(user, context: context)
            try await resolveGameConflicts(user: user, context: context)
        } catch {
            appendSyncError(SyncError(
                type: .syncFailed,
                entityId: (user.firebaseAuthUid ?? user.id.uuidString),
                message: "Game sync failed: \(error.localizedDescription)"
            ))
            throw error
        }
    }

    func uploadLocalGames(_ user: User, context: ModelContext) async throws {
        // Collect games from both athlete.games and season.games, then deduplicate by ID.
        // A game can appear in both collections if it has both athlete + season relationships.
        let athletes = user.athletes ?? []
        let allGamesRaw = athletes.flatMap { athlete in
            (athlete.seasons?.flatMap { $0.games ?? [] } ?? []) + (athlete.games ?? [])
        }
        var seenGameIDs = Set<UUID>()
        let allGames = allGamesRaw.filter { seenGameIDs.insert($0.id).inserted }
        // Only upload games whose parent athlete has already synced (has a firestoreId).
        let dirtyGames = allGames.filter { $0.needsSync && !$0.isDeletedRemotely && $0.athlete?.firestoreId != nil }

        guard !dirtyGames.isEmpty else {
            return
        }

        // See uploadLocalAthletes for the rollback rationale.
        var rollback: [(game: Game, needsSync: Bool, version: Int, lastSyncDate: Date?)] = []

        for game in dirtyGames {
            let priorNeedsSync = game.needsSync
            let priorVersion = game.version
            let priorLastSync = game.lastSyncDate
            do {
                // Bump version BEFORE serialization so the written doc carries it.
                game.version += 1
                if let firestoreId = game.firestoreId {
                    // Update existing game in Firestore
                    try await FirestoreManager.shared.updateGame(
                        userId: (user.firebaseAuthUid ?? user.id.uuidString),
                        gameId: firestoreId,
                        data: game.toFirestoreData()
                    )

                } else {
                    // Create new game in Firestore
                    let docId = try await FirestoreManager.shared.createGame(
                        userId: (user.firebaseAuthUid ?? user.id.uuidString),
                        data: game.toFirestoreData()
                    )
                    game.firestoreId = docId
                    ErrorHandlerService.shared.saveContext(context, caller: "SyncCoordinator.syncGames.firestoreId")
                }

                // Mark as synced
                game.needsSync = false
                game.lastSyncDate = Date()
                rollback.append((game, priorNeedsSync, priorVersion, priorLastSync))

            } catch {
                game.version = priorVersion
                appendSyncError(SyncError(
                    type: .uploadFailed,
                    entityId: game.id.uuidString,
                    message: "Failed to upload game: \(error.localizedDescription)"
                ))
            }
        }

        // Save all changes to SwiftData — on failure restore every mutated sync field.
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                for entry in rollback {
                    entry.game.needsSync = true
                    entry.game.version = entry.version
                    entry.game.lastSyncDate = entry.lastSyncDate
                }
                throw error
            }
        }
    }

    func downloadRemoteGames(_ user: User, context: ModelContext) async throws {
        let remoteGames = try await FirestoreManager.shared.fetchGames(userId: (user.firebaseAuthUid ?? user.id.uuidString))

        guard !remoteGames.isEmpty else {
            return
        }


        // Get all local games and athletes/seasons
        let athletes = user.athletes ?? []
        let allLocalGames = athletes.flatMap { athlete in
            (athlete.seasons?.flatMap { $0.games ?? [] } ?? []) + (athlete.games ?? [])
        }
        let allLocalSeasons = athletes.flatMap { $0.seasons ?? [] }
        let allLocalTournaments = athletes.flatMap { $0.golfTournaments ?? [] }

        // Detect games deleted on another device. Cascade matches GameService.deleteGameDeep:
        // videoClips, photos, and gameStats are removed locally. Firestore deletion is not
        // needed (remote already gone). Safety: skip deletion pass if remote count is
        // suspiciously low compared to local synced games (transient fetch failure).
        // Dedup by UUID because a game may appear in both athlete.games and season.games.
        let remoteGameIds = Set(remoteGames.compactMap { $0.id })
        var seenDeleteIDs = Set<UUID>()
        let syncedLocalGames = allLocalGames.filter {
            $0.firestoreId != nil && seenDeleteIDs.insert($0.id).inserted
        }
        /// Athletes whose stats need recalculation because games were deleted remotely.
        /// The deleted games take their clips' play results with them, so athlete
        /// totals shift — game-level stats aren't needed because the games are gone.
        var athletesAffectedByGameDeletion: Set<PersistentIdentifier> = []
        // Gate destructive reconciliation on connectivity (see +HoleScores): an
        // offline/partial cached fetch can return a stale set without throwing, and
        // the game cascade hard-deletes clips/photos/gameStats — unrecoverable.
        if !ConnectivityMonitor.shared.isConnected {
            syncLog.warning("Skipping game deletion pass — offline (would risk wiping synced games)")
        } else {
            for localGame in syncedLocalGames {
                guard let fsId = localGame.firestoreId, !remoteGameIds.contains(fsId) else { continue }
                // Capture athlete identity before the cascade — accessing SwiftData
                // properties after `context.delete` is undefined behavior.
                if let athlete = localGame.athlete {
                    athletesAffectedByGameDeletion.insert(athlete.persistentModelID)
                }
                // cleanupReels: false — the originating device already stripped
                // these clips from their reels and synced that edit; re-running
                // cleanup here would re-dirty the same reel and race the tombstone.
                for clip in localGame.videoClips ?? [] { clip.delete(in: context, cleanupReels: false) }
                for photo in localGame.photos ?? [] { photo.delete(in: context) }
                if let gameStats = localGame.gameStats { context.delete(gameStats) }
                context.delete(localGame)
            }
        }

        // Games created from remote docs within this loop. Included in the
        // multi-device dedup search so a fresh device downloading two duplicate
        // Firestore docs doesn't create both locally.
        var newGamesThisPass: [Game] = []

        for remoteGame in remoteGames {
            // Find local game by firestoreId (search includes games just inserted
            // in this loop so a second remote with the same firestoreId can't fire,
            // which shouldn't happen but is defensive).
            var localGame = (allLocalGames + newGamesThisPass).first {
                $0.firestoreId == remoteGame.id
            }

            // Find parent athlete by athleteId (matches local UUID or firestoreId).
            // Falls back to sole athlete for legacy data with stale local UUIDs.
            let parentAthlete: Athlete? = athletes.first {
                $0.id.uuidString == remoteGame.athleteId || $0.firestoreId == remoteGame.athleteId
            } ?? (athletes.count == 1 ? athletes.first : nil)

            if parentAthlete == nil && athletes.count > 1 {
                syncLog.error("Orphaned remote game '\(remoteGame.opponent)' (athleteId=\(remoteGame.athleteId)) — no matching local athlete among \(athletes.count) profiles.")
            }

            // Find parent season by seasonId (optional)
            let parentSeason = allLocalSeasons.first {
                if let seasonId = remoteGame.seasonId {
                    return $0.id.uuidString == seasonId || $0.firestoreId == seasonId
                }
                return false
            }

            // Find parent golf tournament by tournamentId (optional, SchemaV27).
            // Resolves like parentSeason — by local UUID or firestoreId.
            let parentTournament = allLocalTournaments.first {
                if let tournamentId = remoteGame.tournamentId {
                    return $0.id.uuidString == tournamentId || $0.firestoreId == tournamentId
                }
                return false
            }

            // Multi-device dedup: when two devices on the same account create the same
            // game simultaneously (parents both adding "vs Tigers" at a tournament), the
            // firestoreId-only match above misses the local twin and the other device's
            // upload gets inserted as a brand-new game. Fall back to natural key
            // (athlete + opponent + same day) — mirrors GameService creation-time dedup.
            //
            // Golf is EXEMPT: `opponent` is the course name and same-course/same-day
            // rounds are legitimate (36-hole tournament days, replays — see the matching
            // exemption in GameService.createGame). Collapsing them here would silently
            // drop the second round on a second device / after reinstall, defeating that
            // fix. Golf still dedups reliably by firestoreId above. Detect golf from the
            // season OR the golf-only fields on the remote doc (season may be nil/unsynced).
            let remoteIsGolf = parentSeason?.sport == .golf
                || remoteGame.holes != nil
                || remoteGame.tournamentId != nil
            if localGame == nil,
               !remoteIsGolf,
               let athlete = parentAthlete,
               let remoteDate = remoteGame.date,
               !remoteGame.opponent.trimmingCharacters(in: .whitespaces).isEmpty {
                let calendar = Calendar.current
                let remoteSport = parentSeason?.sport
                let matchesNaturalKey: (Game) -> Bool = { game in
                    // Sport-aware dedup: a golf "at Pebble Beach" round and a
                    // baseball "vs Pebble Beach" game on the same day must
                    // NOT collapse into one. When either side has no season
                    // yet, fall through and use opponent + date alone — the
                    // common case where dedup actually fires.
                    if let localSport = game.season?.sport,
                       let remoteSport,
                       localSport != remoteSport {
                        return false
                    }
                    return game.athlete?.id == athlete.id
                        && game.opponent.localizedCaseInsensitiveCompare(remoteGame.opponent) == .orderedSame
                        && (game.date.map { calendar.isDate($0, inSameDayAs: remoteDate) } ?? false)
                }
                let candidates = allLocalGames + newGamesThisPass
                if let unsynced = candidates.first(where: { $0.firestoreId == nil && matchesNaturalKey($0) }) {
                    // Link by firestoreId only — don't rewrite local UUID. Any video clip
                    // already uploaded with this game's local UUID as gameId would orphan
                    // if we changed it (see SyncCoordinator+Videos.swift:108).
                    unsynced.firestoreId = remoteGame.id
                    localGame = unsynced
                    syncLog.info("Multi-device dedup: linked local game vs '\(remoteGame.opponent)' to remote \(remoteGame.id ?? "nil")")
                } else if candidates.contains(where: { $0.firestoreId != nil && $0.firestoreId != remoteGame.id && matchesNaturalKey($0) }) {
                    syncLog.info("Multi-device dedup: skipped duplicate remote game vs '\(remoteGame.opponent)' (id: \(remoteGame.id ?? "nil"))")
                    continue
                }
            }

            if let local = localGame {
                let remoteIsNewer = (remoteGame.updatedAt ?? Date.distantPast) > (local.lastSyncDate ?? Date.distantPast)

                if remoteIsNewer && local.needsSync {
                    syncLog.warning("Sync conflict on game vs '\(local.opponent)': local has pending changes, skipping remote update")
                    appendSyncError(SyncError(
                        type: .conflictResolution,
                        entityId: local.id.uuidString,
                        message: "Game vs '\(local.opponent)' modified on both devices — local changes kept"
                    ))
                } else if remoteIsNewer {
                    // Only write properties that actually changed to avoid
                    // dirtying the object and triggering unnecessary @Query updates.
                    var changed = false
                    if local.opponent != remoteGame.opponent { local.opponent = remoteGame.opponent; changed = true }
                    if local.date != remoteGame.date { local.date = remoteGame.date; changed = true }
                    if local.isLive != remoteGame.isLive { local.isLive = remoteGame.isLive; changed = true }
                    if local.isComplete != remoteGame.isComplete { local.isComplete = remoteGame.isComplete; changed = true }
                    if local.year != remoteGame.year { local.year = remoteGame.year; changed = true }
                    if local.location != remoteGame.location { local.location = remoteGame.location; changed = true }
                    if local.notes != remoteGame.notes { local.notes = remoteGame.notes; changed = true }
                    if local.holes != remoteGame.holes { local.holes = remoteGame.holes; changed = true }
                    if local.par != remoteGame.par { local.par = remoteGame.par; changed = true }
                    if local.totalScore != remoteGame.totalScore { local.totalScore = remoteGame.totalScore; changed = true }
                    if local.roundNumber != remoteGame.roundNumber { local.roundNumber = remoteGame.roundNumber; changed = true }
                    if local.tracksShotByShot != (remoteGame.tracksShotByShot ?? false) { local.tracksShotByShot = remoteGame.tracksShotByShot ?? false; changed = true }
                    if local.selectedTee != remoteGame.selectedTee { local.selectedTee = remoteGame.selectedTee; changed = true }
                    if local.scorecardData != remoteGame.scorecardData { local.scorecardData = remoteGame.scorecardData; changed = true }
                    // Re-link tournament (SchemaV27): attach when the parent is
                    // resolved locally, detach only when the remote explicitly
                    // cleared it. If the remote points at a tournament not yet
                    // downloaded, leave local untouched — GolfTournaments sync
                    // runs before Games, so the next pass resolves it.
                    let localTournamentId = local.tournament?.firestoreId ?? local.tournament?.id.uuidString
                    if remoteGame.tournamentId != localTournamentId {
                        if let parentTournament {
                            local.tournament = parentTournament; changed = true
                        } else if remoteGame.tournamentId == nil {
                            local.tournament = nil; changed = true
                        }
                    }
                    if local.version != remoteGame.version { local.version = remoteGame.version; changed = true }
                    // Re-home (legacy-split migration): re-bind the parent athlete when a
                    // remote athleteId change moved this game to another profile. The
                    // season id is invariant across a split (the whole subtree moves
                    // together), so local.season stays valid. Only repoint when the parent
                    // resolves locally — never null it out on a not-yet-synced parent.
                    if let newParent = parentAthlete, local.athlete?.id != newParent.id {
                        local.athlete = newParent
                        changed = true
                    }
                    applyRemoteStats(remoteGame, to: local, context: context)
                    if changed {
                        // Anchor to remote write time, not Date() — see uploadLocalAthletes.
                        local.lastSyncDate = remoteGame.updatedAt ?? Date()
                    }
                }
            } else if let athlete = parentAthlete {
                // Create new local game from remote
                let newGame = Game(
                    date: remoteGame.date ?? Date.distantPast,
                    opponent: remoteGame.opponent
                )
                newGame.id = UUID(uuidString: remoteGame.swiftDataId) ?? UUID()
                newGame.firestoreId = remoteGame.id
                newGame.isLive = remoteGame.isLive
                newGame.isComplete = remoteGame.isComplete
                newGame.year = remoteGame.year
                newGame.location = remoteGame.location
                newGame.notes = remoteGame.notes
                newGame.holes = remoteGame.holes
                newGame.par = remoteGame.par
                newGame.totalScore = remoteGame.totalScore
                newGame.roundNumber = remoteGame.roundNumber
                newGame.tracksShotByShot = remoteGame.tracksShotByShot ?? false
                newGame.selectedTee = remoteGame.selectedTee
                newGame.scorecardData = remoteGame.scorecardData
                newGame.createdAt = remoteGame.createdAt
                newGame.lastSyncDate = Date()
                newGame.needsSync = false
                newGame.version = remoteGame.version
                newGame.athlete = athlete
                newGame.season = parentSeason
                newGame.tournament = parentTournament
                context.insert(newGame)
                newGamesThisPass.append(newGame)
                applyRemoteStats(remoteGame, to: newGame, context: context)
            } else {
                syncLog.warning("Dropped remote game '\(remoteGame.opponent)' (id: \(remoteGame.id ?? "nil")) — no matching athlete found for athleteId '\(remoteGame.athleteId)'")
            }
        }

        if context.hasChanges { try context.save() }

        // Recalculate athlete stats for any athlete whose games were deleted
        // remotely. Game-level stats aren't needed — the games themselves are
        // gone — but athlete totals aggregate across all remaining games.
        for athleteID in athletesAffectedByGameDeletion {
            guard let athlete = athletes.first(where: { $0.persistentModelID == athleteID }) else { continue }
            do {
                try StatisticsService.shared.recalculateAthleteStatistics(for: athlete, context: context)
            } catch {
                syncLog.error("Failed to recalculate athlete stats after remote game deletion for '\(athlete.name)': \(error.localizedDescription)")
            }
        }
        if context.hasChanges { try context.save() }
    }

    func resolveGameConflicts(user: User, context: ModelContext) async throws {
        // For now, local changes win (already marked needsSync)
    }

    /// Applies GameStatistics counter fields from a remote game doc to the local
    /// Game. Only fires for manual-entry games — video-derived stats are
    /// re-derivable locally from synced VideoClips and shouldn't be crossed
    /// over Firestore (would race with fresh local video data).
    private func applyRemoteStats(_ remote: FirestoreGame, to local: Game, context: ModelContext) {
        // Only apply when remote explicitly says these counters came from manual
        // entry. Pre-V20 docs (nil) and video-derived docs (false) are ignored —
        // local device will derive from its own VideoClips.
        guard remote.statsHasManualEntry == true else { return }

        // Ensure a local GameStatistics exists to receive the fields.
        let stats: GameStatistics
        if let existing = local.gameStats {
            stats = existing
        } else {
            let fresh = GameStatistics()
            fresh.game = local
            local.gameStats = fresh
            context.insert(fresh)
            stats = fresh
        }

        // hasManualEntry is sticky: once true on either side, stays true.
        stats.hasManualEntry = true

        stats.atBats = remote.statsAtBats ?? stats.atBats
        stats.hits = remote.statsHits ?? stats.hits
        stats.runs = remote.statsRuns ?? stats.runs
        stats.singles = remote.statsSingles ?? stats.singles
        stats.doubles = remote.statsDoubles ?? stats.doubles
        stats.triples = remote.statsTriples ?? stats.triples
        stats.homeRuns = remote.statsHomeRuns ?? stats.homeRuns
        stats.rbis = remote.statsRbis ?? stats.rbis
        stats.strikeouts = remote.statsStrikeouts ?? stats.strikeouts
        stats.walks = remote.statsWalks ?? stats.walks
        stats.groundOuts = remote.statsGroundOuts ?? stats.groundOuts
        stats.flyOuts = remote.statsFlyOuts ?? stats.flyOuts
        stats.hitByPitches = remote.statsHitByPitches ?? stats.hitByPitches
        stats.totalPitches = remote.statsTotalPitches ?? stats.totalPitches
        stats.balls = remote.statsBalls ?? stats.balls
        stats.strikes = remote.statsStrikes ?? stats.strikes
        stats.wildPitches = remote.statsWildPitches ?? stats.wildPitches
        stats.pitchingStrikeouts = remote.statsPitchingStrikeouts ?? stats.pitchingStrikeouts
        stats.pitchingWalks = remote.statsPitchingWalks ?? stats.pitchingWalks
        stats.fastballPitchCount = remote.statsFastballPitchCount ?? stats.fastballPitchCount
        stats.fastballSpeedTotal = remote.statsFastballSpeedTotal ?? stats.fastballSpeedTotal
        stats.offspeedPitchCount = remote.statsOffspeedPitchCount ?? stats.offspeedPitchCount
        stats.offspeedSpeedTotal = remote.statsOffspeedSpeedTotal ?? stats.offspeedSpeedTotal
        stats.outsRecorded = remote.statsOutsRecorded ?? stats.outsRecorded
        stats.earnedRuns = remote.statsEarnedRuns ?? stats.earnedRuns
        stats.runsAllowed = remote.statsRunsAllowed ?? stats.runsAllowed
        stats.hitsAllowed = remote.statsHitsAllowed ?? stats.hitsAllowed
        stats.homeRunsAllowed = remote.statsHomeRunsAllowed ?? stats.homeRunsAllowed
        stats.battersFaced = remote.statsBattersFaced ?? stats.battersFaced
    }
}
