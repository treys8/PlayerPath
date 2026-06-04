//
//  SportProfileSplitService.swift
//  PlayerPath
//
//  Migrates a LEGACY single-row multi-sport athlete (seasons in 2+ sports on one
//  `Athlete`, the old "Add a sport" model) into the modern model: one
//  `personGroupID`-linked profile per sport. The athlete's primary sport stays on
//  the original row; every OTHER sport's entire subtree — seasons, games,
//  practices, video clips, photos, golf tournaments, highlight reels (and the
//  notes / play-results / hole-scores that ride their parents) — moves onto a new
//  linked row.
//
//  Local SwiftData mutation only. Cross-device propagation rides the normal
//  dirty-flag sync: every moved entity is marked `needsSync`, and `athleteId` now
//  travels on every entity's Firestore doc (incl. clips/photos — see
//  VideoCloudManager+Metadata / Photo), so the receiving device re-homes the
//  subtree instead of losing it (SyncCoordinator+Videos/+Photos repoint).
//
//  Slot-neutral: the new rows share the original's `personGroupID`, so
//  `User.athleteSlotsUsed` is unchanged. Mirrors AddSportProfileSheet.createSpinoff
//  for the personGroupID claim + spinoff creation, but moves real data in and skips
//  priming a default season.
//

import Foundation
import SwiftData
import os

private let splitLog = Logger(subsystem: "com.playerpath.app", category: "SportProfileSplit")

@MainActor
enum SportProfileSplitService {

    /// A summary of what splitting one sport off will move — drives the dry-run preview.
    struct MovePreview: Identifiable {
        let sport: Season.SportType
        let seasons: Int
        let games: Int
        let practices: Int
        let videos: Int
        let photos: Int
        var id: String { sport.rawValue }
    }

    // MARK: - Sport partition

    /// Distinct sports present across this row's seasons (nil sport → baseball).
    static func presentSports(for athlete: Athlete) -> Set<Season.SportType> {
        Set((athlete.seasons ?? []).map { $0.sport ?? .baseball })
    }

    /// The sport that STAYS on the original row. The athlete's pinned sport when it
    /// has seasons here, otherwise the alphabetically-first present sport so the
    /// original never ends up with zero seasons.
    static func primarySport(for athlete: Athlete) -> Season.SportType {
        let present = presentSports(for: athlete)
        let pinned = athlete.sportType
        if present.contains(pinned) { return pinned }
        return present.sorted { $0.rawValue < $1.rawValue }.first ?? pinned
    }

    /// Non-primary sports that would each spin off into their own linked profile.
    static func splittableSports(for athlete: Athlete) -> [Season.SportType] {
        let primary = primarySport(for: athlete)
        return presentSports(for: athlete)
            .subtracting([primary])
            .sorted { $0.rawValue < $1.rawValue }
    }

    // MARK: - Preview

    /// Dry-run: what each non-primary sport will move. Empty when not splittable.
    static func previews(for athlete: Athlete) -> [MovePreview] {
        splittableSports(for: athlete).map { sport in
            let set = moveSet(sport: sport, from: athlete, allReels: [])
            return MovePreview(
                sport: sport,
                seasons: set.seasons.count,
                games: set.games.count,
                practices: set.practices.count,
                videos: set.clips.count,
                photos: set.photos.count
            )
        }
    }

    // MARK: - Split

    /// Performs the migration: creates one linked profile per non-primary sport and
    /// moves that sport's subtree onto it. Returns the new rows (empty if nothing to
    /// do). The whole local move is one atomic save; stats + active-season reconcile
    /// follow. The caller is responsible for kicking off `SyncCoordinator.syncAll`
    /// (athletes sync first there, so the new rows get a firestoreId before their
    /// children upload).
    @discardableResult
    static func split(athlete: Athlete, in context: ModelContext) throws -> [Athlete] {
        guard athlete.isLegacySplittable else { return [] }
        let sports = splittableSports(for: athlete)
        guard !sports.isEmpty else { return [] }

        // Claim a shared personGroupID FIRST so the new rows bill as one slot. First
        // split sets the original's group to its own id; an already-grouped row keeps
        // its group. Mirrors AddSportProfileSheet.createSpinoff.
        let groupID = athlete.personGroupID ?? athlete.id
        if athlete.personGroupID == nil {
            athlete.personGroupID = groupID
            athlete.needsSync = true
        }

        // Reels carry only a denormalized athleteID (no @Relationship), so fetch flat
        // once and re-key by hand — mirrors Athlete.delete(in:).
        let allReels = (try? context.fetch(FetchDescriptor<HighlightReel>())) ?? []

        var newRows: [(athlete: Athlete, games: [Game])] = []

        for sport in sports {
            // Bridge SportType (capitalized) → Athlete.Sport (lowercase).
            guard let mappedSport = Sport(rawValue: sport.rawValue.lowercased()) else { continue }

            let newRow = Athlete(name: athlete.name)
            newRow.user = athlete.user
            newRow.sport = mappedSport
            newRow.personGroupID = groupID
            newRow.needsSync = true
            context.insert(newRow)

            let set = moveSet(sport: sport, from: athlete, allReels: allReels)
            reassign(set, to: newRow)
            newRows.append((newRow, set.games))
            splitLog.info("Split \(sport.displayName): moved \(set.seasons.count) season(s), \(set.games.count) game(s), \(set.practices.count) practice(s), \(set.clips.count) clip(s), \(set.photos.count) photo(s), \(set.tournaments.count) tournament(s), \(set.reels.count) reel(s) for \(athlete.name)")
        }

        // (1) One atomic save of the entire move — SwiftData rolls back wholesale on
        //     failure, so a partial subtree can never persist (safe-on-failure).
        ErrorHandlerService.shared.saveContext(context, caller: "SportProfileSplit.move")

        // (2) Re-pin a single active season per row (pinned sport wins). The original
        //     may have lost its active season to a moved sport; each new row's lone
        //     moved season becomes active.
        _ = SeasonManager.reconcileActiveSeasonToPinnedSport(for: athlete, in: context)
        for row in newRows {
            _ = SeasonManager.reconcileActiveSeasonToPinnedSport(for: row.athlete, in: context)
        }

        // (3) Recompute stats now that the direct game/clip FKs moved: the original
        //     sheds the moved sports, each non-golf new row gains its own. Golf has no
        //     stored AthleteStatistics (it's derived live) — recalc would fabricate an
        //     empty batting object, so skip it. Game stats are refreshed per moved game
        //     (no-op when manually entered).
        for row in newRows {
            for game in row.games {
                try? StatisticsService.shared.recalculateGameStatistics(for: game, context: context)
            }
        }
        // Golf has no stored AthleteStatistics (derived live) — recalc would fabricate
        // an empty batting object. Guard the original too, in case its primary sport is golf.
        if athlete.sportType != .golf {
            try? StatisticsService.shared.recalculateAthleteStatistics(for: athlete, context: context, skipSave: true)
        }
        for row in newRows where row.athlete.sportType != .golf {
            try? StatisticsService.shared.recalculateAthleteStatistics(for: row.athlete, context: context, skipSave: true)
        }
        ErrorHandlerService.shared.saveContext(context, caller: "SportProfileSplit.stats")

        return newRows.map(\.athlete)
    }

    // MARK: - Move set

    private struct MoveSet {
        var seasons: [Season]
        var games: [Game]
        var practices: [Practice]
        var clips: [VideoClip]
        var photos: [Photo]
        var tournaments: [GolfTournament]
        var reels: [HighlightReel]
    }

    /// Gathers every entity belonging to `sport` under `athlete`. Children are
    /// matched by their season/game/practice membership so season-tagged standalone
    /// clips/photos (no game or practice) are caught too. Golf tournaments are
    /// golf-only by definition.
    private static func moveSet(sport: Season.SportType, from athlete: Athlete, allReels: [HighlightReel]) -> MoveSet {
        let seasons = (athlete.seasons ?? []).filter { ($0.sport ?? .baseball) == sport }
        let seasonIDs = Set(seasons.map(\.id))

        let games = (athlete.games ?? []).filter { g in
            g.season.map { seasonIDs.contains($0.id) } ?? false
        }
        let gameIDs = Set(games.map(\.id))

        let practices = (athlete.practices ?? []).filter { p in
            p.season.map { seasonIDs.contains($0.id) } ?? false
        }
        let practiceIDs = Set(practices.map(\.id))

        let clips = (athlete.videoClips ?? []).filter { c in
            (c.season.map { seasonIDs.contains($0.id) } ?? false)
                || (c.game.map { gameIDs.contains($0.id) } ?? false)
                || (c.practice.map { practiceIDs.contains($0.id) } ?? false)
        }

        let photos = (athlete.photos ?? []).filter { ph in
            (ph.season.map { seasonIDs.contains($0.id) } ?? false)
                || (ph.game.map { gameIDs.contains($0.id) } ?? false)
                || (ph.practice.map { practiceIDs.contains($0.id) } ?? false)
        }

        // Golf tournaments are golf-only; their rounds are golf games already captured above.
        let tournaments = sport == .golf ? (athlete.golfTournaments ?? []) : []

        let reels = allReels.filter { reel in
            reel.athleteID == athlete.id
                && ((reel.gameID.map { gameIDs.contains($0) } ?? false)
                    || (reel.practiceID.map { practiceIDs.contains($0) } ?? false))
        }

        return MoveSet(seasons: seasons, games: games, practices: practices,
                       clips: clips, photos: photos, tournaments: tournaments, reels: reels)
    }

    /// Re-points every DIRECT `.athlete` FK (and the reel's denormalized athleteID)
    /// to the new row + marks each `needsSync`. Child-to-parent links (game.season,
    /// clip.game, …) are invariant across the split, so they need no change.
    private static func reassign(_ set: MoveSet, to newRow: Athlete) {
        for season in set.seasons { season.athlete = newRow; season.needsSync = true }
        for game in set.games { game.athlete = newRow; game.needsSync = true }
        for practice in set.practices { practice.athlete = newRow; practice.needsSync = true }
        for clip in set.clips { clip.athlete = newRow; clip.needsSync = true }
        for photo in set.photos { photo.athlete = newRow; photo.needsSync = true }
        for tournament in set.tournaments { tournament.athlete = newRow; tournament.needsSync = true }
        for reel in set.reels { reel.athleteID = newRow.id; reel.needsSync = true }
    }
}
