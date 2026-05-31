//
//  MilestoneEngine.swift
//  PlayerPath
//
//  Pure, read-only computation of a season's milestones from existing data —
//  Games, per-game GameStatistics, and golf HoleScores. No Firestore reads, no
//  schema changes, no persistence. One engine feeds the Journal headline rule,
//  the Stats milestones list, and the clip/row star marker.
//
//  Hard rule: NEVER reads `runs` or `rbis`. Baseball milestones derive only
//  from hits / extra-base hits / at-bats; golf from strokes vs par.
//

import Foundation

enum MilestoneEngine {

    /// All milestones for a season, most-recent first. Returns an empty array
    /// for seasons with no qualifying activity. Pure function of the passed-in
    /// SwiftData graph — safe to call from a view body.
    static func milestones(for season: Season) -> [Milestone] {
        let games = season.games ?? []
        let result: [Milestone]
        if season.sport == .golf {
            result = golfMilestones(games)
        } else {
            result = battingMilestones(games)
        }
        return result.sorted { $0.date > $1.date }
    }

    // MARK: - Baseball / softball

    /// Count thresholds at which an extra-base-hit tally earns a milestone.
    private static let countStep = 5

    private static func battingMilestones(_ games: [Game]) -> [Milestone] {
        // Chronological, stat-bearing games only.
        let ordered = games
            .filter { $0.countsTowardStats }
            .sorted { date($0) < date($1) }

        var milestones: [Milestone] = []

        // First home run of the season.
        if let firstHR = ordered.first(where: { ($0.gameStats?.homeRuns ?? 0) > 0 }) {
            milestones.append(Milestone(
                id: "bb-first-hr-\(firstHR.id.uuidString)",
                kind: .seasonFirst,
                title: "First home run of the season",
                detail: detail(for: firstHR),
                date: date(firstHR),
                gameID: firstHR.id
            ))
        }

        // Cumulative count milestones (every `countStep`) for HR and doubles.
        milestones += countMilestones(ordered, noun: "home run", idTag: "hr") { $0.gameStats?.homeRuns ?? 0 }
        milestones += countMilestones(ordered, noun: "double", idTag: "2b") { $0.gameStats?.doubles ?? 0 }

        // Season-high hits in a single game (only notable multi-hit games).
        if let best = ordered.max(by: { ($0.gameStats?.hits ?? 0) < ($1.gameStats?.hits ?? 0) }),
           let bestHits = best.gameStats?.hits, bestHits >= 3 {
            // Earliest game that reached the season-high, so the marker lands on
            // the first time it happened rather than a later tie.
            let achiever = ordered.first { ($0.gameStats?.hits ?? 0) == bestHits } ?? best
            milestones.append(Milestone(
                id: "bb-high-hits-\(achiever.id.uuidString)",
                kind: .personalBest,
                title: "Season-high \(bestHits) hits in a game",
                detail: detail(for: achiever),
                date: date(achiever),
                gameID: achiever.id
            ))
        }

        // Longest hit streak (consecutive games with a hit; games with no plate
        // appearance neither extend nor break the streak).
        if let streak = longestHitStreak(ordered), streak.length >= 3 {
            milestones.append(Milestone(
                id: "bb-hit-streak-\(streak.endGame.id.uuidString)",
                kind: .streak,
                title: "\(streak.length)-game hit streak",
                detail: detail(for: streak.endGame),
                date: date(streak.endGame),
                gameID: streak.endGame.id
            ))
        }

        return milestones
    }

    /// Emits a milestone each time a running tally crosses a `countStep`
    /// boundary (5th, 10th, …). A single big game can cross several at once.
    private static func countMilestones(
        _ ordered: [Game],
        noun: String,
        idTag: String,
        count: (Game) -> Int
    ) -> [Milestone] {
        var milestones: [Milestone] = []
        var running = 0
        for game in ordered {
            let added = count(game)
            guard added > 0 else { continue }
            let before = running
            running += added
            var threshold = ((before / countStep) + 1) * countStep
            while threshold <= running {
                milestones.append(Milestone(
                    // Game-qualified so the same threshold reached in two
                    // different seasons (career view flattens both) stays unique.
                    id: "bb-\(idTag)-count-\(threshold)-\(game.id.uuidString)",
                    kind: .milestone,
                    title: "\(ordinal(threshold)) \(noun) of the season",
                    detail: detail(for: game),
                    date: date(game),
                    gameID: game.id
                ))
                threshold += countStep
            }
        }
        return milestones
    }

    private struct HitStreak { let length: Int; let endGame: Game }

    /// Longest run of consecutive batting games (a game with at least one plate
    /// appearance) that each recorded a hit. Games with no plate appearance are
    /// skipped so a defensive-only game doesn't snap a streak.
    private static func longestHitStreak(_ ordered: [Game]) -> HitStreak? {
        var best: HitStreak?
        var current = 0
        var currentEnd: Game?
        for game in ordered {
            guard let gs = game.gameStats else { continue }
            let plateAppearances = gs.atBats + gs.walks + gs.hitByPitches
            guard plateAppearances > 0 else { continue } // no AB → neutral
            if gs.hits > 0 {
                current += 1
                currentEnd = game
                if let end = currentEnd, best == nil || current > best!.length {
                    best = HitStreak(length: current, endGame: end)
                }
            } else {
                current = 0
                currentEnd = nil
            }
        }
        return best
    }

    // MARK: - Golf

    private static func golfMilestones(_ games: [Game]) -> [Milestone] {
        let scored = games
            .filter { $0.isGolfRoundScored }
            .sorted { date($0) < date($1) }

        var milestones: [Milestone] = []

        // First eagle-or-better hole of the season (aces included via diffLabel).
        for round in scored {
            let holes = (round.holeScores ?? []).sorted { $0.holeNumber < $1.holeNumber }
            if let gem = holes.first(where: { $0.score > 0 && $0.diff <= -2 }) {
                milestones.append(Milestone(
                    id: "golf-first-gem-\(round.id.uuidString)-\(gem.holeNumber)",
                    kind: .seasonFirst,
                    title: "First \(gem.diffLabel.lowercased()) of the season",
                    detail: "\(round.opponentLabel) · hole \(gem.holeNumber)",
                    date: date(round),
                    gameID: round.id
                ))
                break
            }
        }

        // Personal-low round of the season (needs at least two scored rounds for
        // "low" to mean anything).
        if scored.count >= 2,
           let low = scored.min(by: { ($0.effectiveTotalScore ?? .max) < ($1.effectiveTotalScore ?? .max) }),
           let strokes = low.effectiveTotalScore {
            milestones.append(Milestone(
                id: "golf-low-round-\(low.id.uuidString)",
                kind: .personalBest,
                title: "Personal-low round: \(strokes)",
                detail: toParDetail(for: low),
                date: date(low),
                gameID: low.id
            ))
        }

        return milestones
    }

    // MARK: - Helpers

    private static func date(_ game: Game) -> Date {
        game.date ?? game.createdAt ?? .distantPast
    }

    /// "vs Tigers · May 12" (baseball) / "at Pebble Beach · May 12" (golf).
    private static func detail(for game: Game) -> String {
        let when = date(game).formatted(.dateTime.month(.abbreviated).day())
        let opponent = game.opponent.trimmingCharacters(in: .whitespaces)
        return opponent.isEmpty ? when : "\(game.opponentLabel) · \(when)"
    }

    /// "−3 · at Pebble Beach" for a golf round's score relative to par.
    private static func toParDetail(for round: Game) -> String? {
        guard let strokes = round.effectiveTotalScore, let par = round.effectivePar else {
            return detail(for: round)
        }
        let diff = strokes - par
        let toPar: String
        if diff == 0 { toPar = "Even par" }
        else if diff > 0 { toPar = "+\(diff)" }
        else { toPar = "\(diff)" } // already carries the minus sign
        return "\(toPar) · \(round.opponentLabel)"
    }

    /// 1 → "1st", 2 → "2nd", 3 → "3rd", 11 → "11th", 22 → "22nd".
    private static func ordinal(_ n: Int) -> String {
        let ones = n % 10
        let tens = (n / 10) % 10
        let suffix: String
        if tens == 1 { suffix = "th" }
        else {
            switch ones {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(n)\(suffix)"
    }
}
