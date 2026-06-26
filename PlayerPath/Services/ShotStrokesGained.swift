//
//  ShotStrokesGained.swift
//  PlayerPath
//
//  Live-computed "Est. Strokes Gained" for golf (Plus-gated v2 analytics layer).
//  Compute-on-read only — mirrors ShotStats/GolfExportData pooling, adds NO
//  stored fields, NO schema, NO sync. Two fidelity layers, both derived from
//  data already collected (HoleScore.yardage + score; Shot.lie/distanceBefore):
//
//   • Layer 1 (round-level, no shots): Broadie's telescoping identity
//     SG_hole = E(.tee, yardage) − score, summed over a round, averaged across
//     full-coverage rounds. Also split by par-type. This is the headline.
//   • Layer 2 (category from shots): walk the hole's non-putt shots and apply
//     E(before) − E(after) − 1 − penalty, bucketed OTT / APP / ARG. Putting SG
//     is deferred (no putt distance in feet captured). The terminal approach to
//     the green has unknown proximity → that shot is dropped and the category
//     sums are flagged partial.
//
//  Layer-1 total and Layer-2 category sums are COMPLEMENTARY, not equal:
//  Layer 2 omits putting + dropped terminal proximity, so (Layer1 − Layer2) ≈
//  putting SG. Do not try to reconcile them to equality.
//
//  Synchronous + @MainActor (like ShotStats) — no awaits, so the
//  @Model-snapshot-before-await rule doesn't apply.
//

import Foundation

/// Pooled Est. Strokes Gained for an athlete/season. Every value is nil when its
/// inputs are absent so the UI hides the tile rather than showing a misleading
/// zero. SG is signed: positive = gained vs the PGA Tour baseline.
struct ShotStrokesGainedStats {
    /// Average per-round SG total over full-yardage rounds (Layer 1). The headline.
    let sgTotalPerRound: Double?
    /// Average per-round SG split by par-type (Layer 1). Each nil when no
    /// full-coverage round contained that par.
    let sgByPar: (par3: Double?, par4: Double?, par5: Double?)
    /// Average per-round category SG from logged shots (Layer 2). nil when no
    /// shot data exists at all.
    let sgByCategory: (ott: Double?, app: Double?, arg: Double?)?
    /// false when any logged shot was dropped for unknown distance (the terminal
    /// approach-to-green, or an un-ranged shot) — category sums then read partial.
    let completeCategorySG: Bool
    /// Number of full-coverage rounds behind `sgTotalPerRound`.
    let roundCount: Int

    /// True when Layer 1 produced a headline number (≥1 full-coverage round).
    var hasData: Bool { sgTotalPerRound != nil }
}

@MainActor
enum ShotStrokesGained {

    #if DEBUG
    private static var didSelfCheck = false
    #endif

    // MARK: - Public API

    /// Pool the same tournament + practice rounds the free golf stats use, and
    /// compute both SG layers. Rounds are kept whole (never flattened across
    /// rounds) so per-round integrity is preserved and tournament/practice
    /// pools can't contaminate each other's per-round averages.
    static func compute(for athlete: Athlete, season: Season?) -> ShotStrokesGainedStats {
        #if DEBUG
        if !didSelfCheck { didSelfCheck = true; BroadieBaseline.runSelfCheck() }
        #endif

        let rounds = roundHoleSets(for: athlete, season: season)

        // ---- Layer 1: round-level SG over full-coverage (all-yardage) rounds.
        let roundSGs = rounds.compactMap { layer1(round: $0) }
        let sgTotal = average(roundSGs.map { $0.total })
        let par3 = average(roundSGs.compactMap { $0.par3 })
        let par4 = average(roundSGs.compactMap { $0.par4 })
        let par5 = average(roundSGs.compactMap { $0.par5 })

        // ---- Layer 2: category SG from logged shots.
        var cats: [CategorySG] = []
        var anyShots = false
        var complete = true
        for round in rounds {
            let r = layer2(round: round)
            if r.hadShots { anyShots = true }
            if !r.complete { complete = false }
            if r.ott != nil || r.app != nil || r.arg != nil { cats.append(r) }
        }
        let byCategory: (ott: Double?, app: Double?, arg: Double?)? = anyShots
            ? (ott: average(cats.compactMap { $0.ott }),
               app: average(cats.compactMap { $0.app }),
               arg: average(cats.compactMap { $0.arg }))
            : nil

        return ShotStrokesGainedStats(
            sgTotalPerRound: sgTotal,
            sgByPar: (par3: par3, par4: par4, par5: par5),
            sgByCategory: byCategory,
            completeCategorySG: complete,
            roundCount: roundSGs.count
        )
    }

    /// Per-round SG total for a single round's holes — Layer 1, full-coverage
    /// only (nil when any scored hole lacks yardage, or no scored hole has it).
    /// Used by the charts trend so partial-yardage rounds drop out rather than
    /// plotting a deflated total.
    static func roundSGTotal(holes: [HoleScore]) -> Double? {
        layer1(round: holes)?.total
    }

    // MARK: - Pooling (mirrors GolfExportData.advancedStats round sets)

    private static func roundHoleSets(for athlete: Athlete, season: Season?) -> [[HoleScore]] {
        // Restrict to 18-hole, non-live rounds. SG total / by-par / category are
        // per-round SUMS, so a 9-hole round would contribute ~half the magnitude
        // and deflate the "per round" average — the same reason HandicapEstimator,
        // GolfChartsView, and the season-comparison roll-up all use 18-hole rounds.
        let gameRounds: [[HoleScore]] = GolfExportData.scoredTournamentGames(for: athlete, season: season, holes: 18)
            .map { $0.holeScores ?? [] }
        let practicePool: [Practice] = season?.practices ?? athlete.practices ?? []
        // Explicit typed closure keeps the type-checker fast (the chained
        // filter/map with optional unwraps otherwise times out — same reason
        // GolfStatsSection breaks its pools into annotated closures).
        let practiceRounds: [[HoleScore]] = practicePool.compactMap { (p: Practice) -> [HoleScore]? in
            guard p.practiceType == PracticeType.practiceRound.rawValue, !p.isLive else { return nil }
            let holes = p.holeScores ?? []
            guard !holes.isEmpty, (p.holes ?? holes.count) == 18 else { return nil }
            return holes
        }
        return gameRounds + practiceRounds
    }

    // MARK: - Layer 1

    private struct RoundSG {
        let total: Double
        let par3: Double?
        let par4: Double?
        let par5: Double?
    }

    /// Round-level SG via the telescoping identity. Returns nil unless the round
    /// is full-coverage: at least one scored hole, and every scored hole has a
    /// known yardage (apples-to-apples, like HandicapEstimator's 18-hole rule).
    private static func layer1(round holes: [HoleScore]) -> RoundSG? {
        let scored = holes.filter { $0.score > 0 }
        guard !scored.isEmpty, scored.allSatisfy({ $0.yardage != nil }) else { return nil }

        var total = 0.0
        var byPar: [Int: Double] = [:]
        for h in scored {
            guard let y = h.yardage,
                  let e = BroadieBaseline.expectedStrokes(lie: .tee, distanceYards: y) else { continue }
            let sg = e - Double(h.score)
            total += sg
            byPar[h.par, default: 0] += sg
        }
        return RoundSG(total: total, par3: byPar[3], par4: byPar[4], par5: byPar[5])
    }

    // MARK: - Layer 2

    private struct CategorySG {
        var ott: Double?
        var app: Double?
        var arg: Double?
        var hadShots: Bool
        var complete: Bool
    }

    /// Per-round category SG from logged shots. Sums are nil for a category with
    /// no computable shot; `complete` is false when any logged shot was dropped
    /// for unknown distance (terminal approach proximity, or an un-ranged shot).
    private static func layer2(round holes: [HoleScore]) -> CategorySG {
        var ott = 0.0, app = 0.0, arg = 0.0
        var ottN = 0, appN = 0, argN = 0
        var hadShots = false
        var complete = true

        for hole in holes {
            // Same filter contract as ShotStats: drop soft-deletes + putts, sort
            // by shot order. isPutt is never true in v1 (forward-compat guard).
            let live = (hole.shots ?? [])
                .filter { !$0.isDeletedRemotely && !$0.isPutt }
                .sorted { $0.shotNumber < $1.shotNumber }
            guard !live.isEmpty else { continue }
            hadShots = true
            let par = hole.par

            for (i, shot) in live.enumerated() {
                guard let ctx = ShotContext.forLie(shot.lie, par: par) else { continue } // green = putting

                // Distance before this shot. A par-4/5 tee shot isn't ranged
                // (distanceBefore nil) — fall back to the hole's yardage.
                let distBefore: Int?
                if shot.lie == .tee && shot.distanceBefore == nil {
                    distBefore = hole.yardage
                } else {
                    distBefore = shot.distanceBefore
                }
                guard let db = distBefore,
                      let eBefore = BroadieBaseline.expectedStrokes(lie: shot.lie, distanceYards: db) else {
                    complete = false
                    continue
                }

                // Expected strokes after this shot: 0 if holed, else the next
                // logged shot's pre-shot baseline. The terminal approach to the
                // green has no next shot (putts aren't logged) → unknown.
                let eAfter: Double?
                if shot.outcome.isHoled {
                    eAfter = 0
                } else if i + 1 < live.count,
                          let nd = live[i + 1].distanceBefore,
                          let ea = BroadieBaseline.expectedStrokes(lie: live[i + 1].lie, distanceYards: nd) {
                    eAfter = ea
                } else {
                    eAfter = nil
                }
                guard let ea = eAfter else { complete = false; continue }

                // Subtract the shot (−1) and any penalty exactly once.
                let sg = eBefore - ea - 1 - Double(shot.penaltyStrokes)
                switch ctx {
                case .teeFull:     ott += sg; ottN += 1
                case .approach:    app += sg; appN += 1
                case .aroundGreen: arg += sg; argN += 1
                }
            }
        }

        return CategorySG(
            ott: ottN > 0 ? ott : nil,
            app: appN > 0 ? app : nil,
            arg: argN > 0 ? arg : nil,
            hadShots: hadShots,
            complete: complete
        )
    }

    // MARK: - Helpers

    private static func average(_ xs: [Double]) -> Double? {
        xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count)
    }
}
