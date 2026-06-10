//
//  HandicapEstimator.swift
//  PlayerPath
//
//  Lightweight estimated handicap from recent scoring. We don't collect course
//  rating / slope, so this is NOT a true WHS Handicap Index — it's an honest
//  estimate from each round's score-to-par, and the UI always labels it "Est.".
//  Uses the best 8 of the last 20 scored 18-hole rounds (the WHS shape), with a
//  soft ramp for golfers who have fewer rounds on record.
//

import Foundation

@MainActor
enum HandicapEstimator {

    /// Estimated index = mean of the best `bestCount` of the most recent (≤20)
    /// scored 18-hole rounds' to-par (`effectiveTotalScore − effectivePar`).
    /// Negative = a plus-handicap (under par). nil under a 3-round minimum.
    static func estimatedIndex(for athlete: Athlete, season: Season? = nil) -> Double? {
        // scoredTournamentGames returns newest-first, 18-hole only.
        let recent = Array(GolfExportData.scoredTournamentGames(for: athlete, season: season, holes: 18).prefix(20))
        let diffs: [Int] = recent.compactMap { game in
            guard let strokes = game.effectiveTotalScore, let par = game.effectivePar else { return nil }
            return strokes - par
        }
        guard diffs.count >= 3 else { return nil }

        let best = Array(diffs.sorted().prefix(bestCount(forRounds: diffs.count)))
        return Double(best.reduce(0, +)) / Double(best.count)
    }

    /// "Best N of last M" schedule, scaled down for small samples so a golfer
    /// with a handful of rounds still gets a reasonable estimate.
    private static func bestCount(forRounds n: Int) -> Int {
        switch n {
        case ..<5:    return n      // too few — average them all
        case 5...8:   return 2
        case 9...11:  return 3
        case 12...14: return 4
        case 15...16: return 5
        case 17...18: return 6
        case 19:      return 7
        default:      return 8      // 20+
        }
    }
}
