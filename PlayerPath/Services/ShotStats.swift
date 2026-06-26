//
//  ShotStats.swift
//  PlayerPath
//
//  Free, descriptive shot-derived golf stats (SchemaV30). Pools every
//  shot-tracked hole across a player's completed tournament rounds + practice
//  rounds and computes tee-miss bias, the regulation-approach miss pattern, and
//  greenside sand saves. Computed on demand from `HoleScore.shots` (soft-deleted
//  rows filtered) — no stored fields, no tier gate.
//
//  Strokes Gained / dispersion / cross-round trends are the Plus-gated v2 layer
//  and intentionally NOT here — this is the free descriptive payoff.
//

import Foundation

/// One pooled roll-up of shot-pattern tendencies. All counts default to zero so
/// a score-only golfer yields an all-empty value (`hasData == false`) and the UI
/// renders nothing.
struct ShotPatternStats {
    // Tee accuracy — par 4/5 driving only. Left vs right miss counts.
    var teeMissLeft = 0
    var teeMissRight = 0

    // Regulation-approach miss pattern (the stroke meant to find the green).
    // `.fringe` is intentionally NOT a miss bucket — landing on the fringe is a
    // near-hit, not an actionable miss tendency.
    var approachShort = 0
    var approachLong = 0
    var approachLeft = 0
    var approachRight = 0
    var approachBunker = 0

    // Greenside sand saves.
    var sandSaves = 0
    var sandOpportunities = 0

    var teeMisses: Int { teeMissLeft + teeMissRight }
    var approachMisses: Int {
        approachShort + approachLong + approachLeft + approachRight + approachBunker
    }

    /// Most common approach miss; nil when no approach misses logged.
    /// Tie-break order: Short, Long, Left, Right, Bunker.
    var dominantApproachMiss: String? {
        let buckets: [(String, Int)] = [
            ("Short", approachShort), ("Long", approachLong),
            ("Left", approachLeft), ("Right", approachRight),
            ("Bunker", approachBunker)
        ]
        guard let top = buckets.max(by: { $0.1 < $1.1 }), top.1 > 0 else { return nil }
        return top.0
    }

    /// Up-and-down rate from greenside sand (0–100); nil when no chances.
    var sandSavePct: Double? {
        sandOpportunities == 0 ? nil : Double(sandSaves) / Double(sandOpportunities) * 100
    }

    /// True when at least one pattern is displayable, so callers can hide the
    /// whole section for golfers with no shot data. Mirrors the chip conditions
    /// in GolfStatsSection exactly.
    var hasData: Bool {
        teeMisses > 0 || dominantApproachMiss != nil || sandSavePct != nil
    }
}

/// Pooled Est. Driving-Distance summary (SchemaV31). `hasData == false` → the UI
/// renders nothing, like `ShotPatternStats`.
struct DrivingSummary {
    let averageYards: Int
    let longestYards: Int
    let count: Int
    var hasData: Bool { count > 0 }
}

enum ShotStats {

    /// Pools shot-tracked holes from the same round sets the rest of the golf
    /// stats screen uses (completed tournament rounds + scored practice rounds),
    /// then computes the descriptive patterns.
    static func compute(for athlete: Athlete, season: Season?) -> ShotPatternStats {
        let gameHoles = GolfExportData.scoredTournamentGames(for: athlete, season: season)
            .flatMap { $0.holeScores ?? [] }
        let practicePool = season?.practices ?? athlete.practices ?? []
        let practiceHoles = practicePool
            .filter { $0.practiceType == PracticeType.practiceRound.rawValue }
            .flatMap { $0.holeScores ?? [] }
        return compute(holes: gameHoles + practiceHoles)
    }

    /// Pure roll-up over a flat hole set. Each hole's shots are filtered for
    /// soft-deletes and ordered by `shotNumber` before reading.
    static func compute(holes: [HoleScore]) -> ShotPatternStats {
        var s = ShotPatternStats()
        for hole in holes {
            // Soft-deleted rows are filtered (they outlive the local model until
            // sync tombstones them). `isPutt` is excluded to match ShotRollup's
            // non-putt contract — a forward-compat guard for the v2 per-putt
            // scaffold (never true in v1).
            let live = (hole.shots ?? [])
                .filter { !$0.isDeletedRemotely && !$0.isPutt }
                .sorted { $0.shotNumber < $1.shotNumber }
            guard !live.isEmpty else { continue }
            let par = hole.par

            // Tee accuracy — par 4/5 only (driving). A par-3 tee shot is an
            // approach, counted below, so it never lands in the tee bias.
            if par >= 4, let tee = live.first(where: { $0.lie == .tee }) {
                switch tee.outcome.missDirection {
                case .left:  s.teeMissLeft += 1
                case .right: s.teeMissRight += 1
                case nil:    break
                }
            }

            // Regulation-approach miss pattern. `.green`/`.holed` = hit (not a
            // miss); `.fringe` = near-miss (excluded). A hole reached early
            // (drivable par 4, par 5 in 2) or one where a penalty consumed the
            // regulation stroke yields no approach shot here — correctly skipped.
            if let approach = regulationApproach(in: live, par: par) {
                switch approach.outcome {
                case .short:     s.approachShort += 1
                case .long:      s.approachLong += 1
                case .missLeft:  s.approachLeft += 1
                case .missRight: s.approachRight += 1
                case .bunker:    s.approachBunker += 1
                default:         break
                }
            }

            // Greenside sand save — a hole with exactly one shot from a `.sand`
            // lie that got up and down: the sand shot holed, or reached the green
            // and the hole took ≤1 putt. Two+ sand shots means a failed escape,
            // which is an opportunity but not a save.
            let sandShots = live.filter { $0.lie == .sand }
            if !sandShots.isEmpty {
                s.sandOpportunities += 1
                if sandShots.count == 1 {
                    let shot = sandShots[0]
                    if shot.outcome == .holed {
                        s.sandSaves += 1
                    } else if shot.outcome.reachedGreen && (hole.putts ?? 99) <= 1 {
                        s.sandSaves += 1
                    }
                }
            }
        }
        return s
    }

    /// The regulation-approach shot — the stroke meant to find the green
    /// (stroke `par-2`: par-3 tee, par-4 2nd, par-5 3rd). Walks strokes so a
    /// penalty (e.g. OB / lost ball off the tee adds a stroke and a replay) can't
    /// misalign it: a hole whose regulation stroke was consumed by a penalty had
    /// no GIR chance and returns nil. Also returns nil when that stroke isn't an
    /// approach-context lie (a greenside chip after an odd edit), so a chip can
    /// never be miscounted as an approach.
    private static func regulationApproach(in live: [Shot], par: Int) -> Shot? {
        let target = par - 2
        guard target >= 1 else { return nil }
        var strokesUsed = 0
        for shot in live {
            let playedAt = strokesUsed + 1
            if playedAt == target {
                return ShotContext.forLie(shot.lie, par: par) == .approach ? shot : nil
            }
            if playedAt > target { return nil }   // a penalty pushed past the regulation stroke
            strokesUsed += 1 + shot.penaltyStrokes
        }
        return nil   // green reached before the regulation stroke (a GIR, not a miss)
    }

    // MARK: - Est. Driving Distance (SchemaV31)

    /// Estimated driving distance for one hole, in yards: the hole's length minus
    /// the lasered yards-to-pin on the regulation approach. Derivable only on a
    /// par 4/5 with a recorded hole yardage, a tee shot, and a regulation approach
    /// carrying a `distanceBefore`. nil on every other case (par 3, no yardage, no
    /// approach number, a penalty-consumed regulation stroke, a drivable green, or
    /// a non-positive result from a mis-entry / wrong tee). Card yardage is routed
    /// distance, so this systematically OVER-reads on doglegs — always present it
    /// as an ESTIMATE.
    static func driveDistance(for hole: HoleScore) -> Int? {
        driveDistance(par: hole.par, yardage: hole.yardage, shots: hole.shots ?? [])
    }

    /// Same derivation over raw inputs, so the live shot-entry view can show a
    /// running estimate from @State before the hole is persisted.
    static func driveDistance(par: Int, yardage: Int?, shots: [Shot]) -> Int? {
        guard par >= 4, let yardage else { return nil }
        let live = shots
            .filter { !$0.isDeletedRemotely && !$0.isPutt }
            .sorted { $0.shotNumber < $1.shotNumber }
        guard live.contains(where: { $0.lie == .tee }) else { return nil }
        guard let approach = regulationApproach(in: live, par: par),
              let toPin = approach.distanceBefore else { return nil }
        let drive = yardage - toPin
        return drive > 0 ? drive : nil   // guard a mis-entry / wrong-tee negative
    }

    /// All derivable Est. Driving Distances across a hole set (yards).
    static func driveDistances(in holes: [HoleScore]) -> [Int] {
        holes.compactMap { driveDistance(for: $0) }
    }

    /// Pooled Est. Driving-Distance summary (avg + longest) over the same round
    /// sets the rest of the golf stats screen uses.
    static func drivingSummary(for athlete: Athlete, season: Season?) -> DrivingSummary {
        let gameHoles = GolfExportData.scoredTournamentGames(for: athlete, season: season)
            .flatMap { $0.holeScores ?? [] }
        let practicePool = season?.practices ?? athlete.practices ?? []
        let practiceHoles = practicePool
            .filter { $0.practiceType == PracticeType.practiceRound.rawValue }
            .flatMap { $0.holeScores ?? [] }
        let dists = driveDistances(in: gameHoles + practiceHoles)
        guard !dists.isEmpty else { return DrivingSummary(averageYards: 0, longestYards: 0, count: 0) }
        return DrivingSummary(
            averageYards: Int((Double(dists.reduce(0, +)) / Double(dists.count)).rounded()),
            longestYards: dists.max() ?? 0,
            count: dists.count
        )
    }
}
