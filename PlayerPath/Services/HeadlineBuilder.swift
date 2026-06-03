//
//  HeadlineBuilder.swift
//  PlayerPath
//
//  The auto-headline rule for a journal entry / game. Priority:
//    1. A milestone linked to this game ("First home run of the season").
//    2. A standout-day line ("3-for-4 vs Tigers" / "Shot 71 (−1) at Pebble").
//    3. The plain matchup fallback ("vs Tigers" / "at Pebble Beach").
//
//  Pure and read-only. Two hard rules:
//   • Baseball NEVER invents a team/game score — no such field exists. The
//     batting standout line is the athlete's own H-for-AB only.
//   • Never reads runs/rbis (see DerivableStat).
//

import Foundation

enum HeadlineBuilder {

    /// Headline for a Journal feed entry, given the season's milestones.
    static func headline(for entry: JournalEntry, milestones: [Milestone]) -> String {
        switch entry {
        case .game(let game):
            return headline(for: game, milestones: milestones)
        case .practice, .clip, .photo:
            // Practices/standalone clips/photos don't carry batting/scoring lines.
            return entry.fallbackHeadline
        }
    }

    /// Headline for a single game (used by the feed, Stats, and clip markers).
    static func headline(for game: Game, milestones: [Milestone]) -> String {
        if let milestone = topMilestone(for: game, in: milestones) {
            return milestone.title
        }
        if let standout = standoutLine(for: game) {
            return standout
        }
        return matchupFallback(game)
    }

    // MARK: - Priority 1 — milestone

    /// The most significant milestone linked to this game, if any.
    private static func topMilestone(for game: Game, in milestones: [Milestone]) -> Milestone? {
        milestones
            .filter { $0.gameID == game.id }
            .max { rank($0.kind) < rank($1.kind) }
    }

    private static func rank(_ kind: Milestone.Kind) -> Int {
        switch kind {
        case .seasonFirst:  return 4
        case .personalBest: return 3
        case .streak:       return 2
        case .milestone:    return 1
        }
    }

    // MARK: - Priority 2 — standout day

    private static func standoutLine(for game: Game) -> String? {
        if game.isGolf {
            return golfStandout(game)
        }
        return battingStandout(game)
    }

    /// "3-for-4 vs Tigers" — only for a multi-hit game. NEVER a team score.
    private static func battingStandout(_ game: Game) -> String? {
        guard let gs = game.gameStats, gs.atBats > 0, gs.hits >= 2 else { return nil }
        let line = "\(gs.hits)-for-\(gs.atBats)"
        let opponent = game.opponent.trimmingCharacters(in: .whitespaces)
        return opponent.isEmpty ? line : "\(line) \(game.opponentLabel)"
    }

    /// "Shot 71 (−1) at Pebble" — the athlete's own round score (allowed in golf).
    private static func golfStandout(_ game: Game) -> String? {
        guard game.isGolfRoundScored, let strokes = game.effectiveTotalScore else { return nil }
        var headline = "Shot \(strokes)"
        if let par = game.effectivePar {
            headline += " (\(toPar(strokes - par)))"
        }
        let opponent = game.opponent.trimmingCharacters(in: .whitespaces)
        return opponent.isEmpty ? headline : "\(headline) \(game.opponentLabel)"
    }

    // MARK: - Priority 3 — matchup fallback

    private static func matchupFallback(_ game: Game) -> String {
        game.opponent.isEmpty ? game.eventNoun : game.opponentLabel
    }

    // MARK: - Helpers

    /// "E" for even, "+3" over, "−2" under (true minus glyph).
    private static func toPar(_ diff: Int) -> String {
        if diff == 0 { return "E" }
        if diff > 0 { return "+\(diff)" }
        return "−\(abs(diff))"
    }
}
