//
//  GolfExportData.swift
//  PlayerPath
//
//  Single source of golf scoring rows + summary for the CSV/PDF export
//  stacks. Mirrors GolfStatsSection's round pools and Stream A's derived
//  totals so an exported document never disagrees with the in-app Stats
//  screen. No rendering here — the CSV/PDF services format these values.
//

import Foundation

/// One golf round's exportable scoring line. Greens-in-regulation and
/// fairways-hit are not tracked yet (no model fields); when they land they
/// become two more stored properties here and two more rendered columns —
/// callers don't change shape. That's the reason this is a struct, not a
/// pile of parallel arrays.
struct GolfRoundRow {
    let date: Date?
    let course: String
    let holes: Int
    let par: Int?
    let score: Int?
    let putts: Int?
    /// Per-round greens- and fairways-in-regulation %, nil when the round
    /// carries no detailed tracking (SchemaV29). 0–100.
    let girPct: Double?
    let firPct: Double?

    /// Est. Strokes Gained for this round vs the PGA Tour baseline (Broadie),
    /// computed live from per-hole yardage; nil unless every scored hole has a
    /// known yardage. Signed (positive = gained). Plus-gated at the UI layer.
    let strokesGained: Double?

    /// Signed strokes relative to par; nil when either side is unknown.
    var toPar: Int? {
        guard let score, let par else { return nil }
        return score - par
    }

    /// "E" / "+3" / "-2" / "—" for display.
    var toParString: String {
        guard let toPar else { return "—" }
        if toPar == 0 { return "E" }
        return toPar > 0 ? "+\(toPar)" : "\(toPar)"
    }
}

/// Career/season scoring roll-up — same five numbers GolfStatsSection shows.
struct GolfExportSummary {
    let totalRounds: Int
    let bestScore: Int?
    let worstScore: Int?
    let tournamentAverage: Double?
    let practiceAverage: Double?
}

/// Per-season golf roll-up for the season-comparison view. Computed over
/// 18-hole tournament rounds only: comparing a 9-hole average against an
/// 18-hole one is meaningless, and practice rounds aren't competitive scores.
/// Every value is nil when the season has no qualifying rounds so the UI can
/// show an empty state rather than a misleading zero.
struct GolfSeasonSummary {
    let rounds: Int
    let bestScore: Int?
    let avgScore: Double?
    let avgToPar: Double?
    let avgPutts: Double?
    let birdiesPerRound: Double?
    // Detailed (SchemaV29) — nil when the season carries no tracked data.
    let girPct: Double?
    let firPct: Double?
    let scramblingPct: Double?
}

/// Game-improvement roll-up over all scored rounds (tournament + practice) in a
/// pool. Every value is nil when its inputs are absent so the UI hides the tile
/// rather than showing a misleading zero. Percentages are 0–100.
struct GolfAdvancedStats {
    let avgToPar: Double?
    let girPct: Double?
    let firPct: Double?
    let puttsPerRound: Double?
    let puttsPerGIR: Double?
    let scramblingPct: Double?
    let penaltiesPerRound: Double?
    let par3Avg: Double?
    let par4Avg: Double?
    let par5Avg: Double?

    /// True when at least one detailed (FIR / GIR / penalty) datapoint exists,
    /// so callers can hide the whole detailed grid for score-only golfers.
    var hasDetailed: Bool {
        girPct != nil || firPct != nil || penaltiesPerRound != nil
    }
}

/// One scoring-distribution bucket for the per-hole chart. `order` drives both
/// the x-axis sort and Identifiable so two equal labels can't collide.
struct GolfScoreBucket: Identifiable {
    let order: Int
    let label: String
    let count: Int
    var id: Int { order }
}

enum GolfExportData {
    /// Scored tournament rounds (golf-season `Game`s), newest first. Matches
    /// GolfStatsSection.tournamentRounds: golf season, not live, fully scored.
    /// When `season` is non-nil only that season's games count.
    static func tournamentRounds(for athlete: Athlete, season: Season?) -> [GolfRoundRow] {
        let pool: [Game] = season?.games ?? athlete.games ?? []
        let scored = pool.filter { (g: Game) -> Bool in
            guard g.season?.sport == .golf else { return false }
            guard !g.isLive else { return false }
            return g.isGolfRoundScored
        }
        let sorted = scored.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        // Explicit typed closure + a holeScores local so the type-checker stays
        // fast (this chained map otherwise times out — same reason the filter is
        // an annotated closure).
        return sorted.map { (game: Game) -> GolfRoundRow in
            let holeScores = game.holeScores ?? []
            return GolfRoundRow(
                date: game.date,
                course: game.opponent.isEmpty ? "Unknown Course" : game.opponent,
                holes: game.holes ?? holeScores.count,
                par: game.effectivePar,
                score: game.effectiveTotalScore,
                putts: puttsTotal(game.holeScores),
                girPct: girRate(holeScores),
                firPct: firRate(holeScores),
                strokesGained: ShotStrokesGained.roundSGTotal(holes: holeScores)
            )
        }
    }

    /// Golf practice rounds with ≥1 scored hole, newest first. Mirrors
    /// GolfStatsSection.practiceRounds. Practice has no course-par field, so
    /// par is derived from the per-hole pars.
    static func practiceRounds(for athlete: Athlete, season: Season?) -> [GolfRoundRow] {
        let pool: [Practice] = season?.practices ?? athlete.practices ?? []
        let scored = pool.filter { (p: Practice) -> Bool in
            p.practiceType == PracticeType.practiceRound.rawValue
                && !(p.holeScores ?? []).isEmpty
        }
        let sorted = scored.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        // Explicit typed closure keeps the type-checker fast (see tournamentRounds).
        return sorted.map { (practice: Practice) -> GolfRoundRow in
            let holes = practice.holeScores ?? []
            return GolfRoundRow(
                date: practice.date,
                course: practice.course ?? "Practice Round",
                holes: practice.holes ?? holes.count,
                par: parTotal(practice.holeScores),
                score: holes.reduce(0) { $0 + $1.score },
                putts: puttsTotal(practice.holeScores),
                girPct: girRate(holes),
                firPct: firRate(holes),
                strokesGained: ShotStrokesGained.roundSGTotal(holes: holes)
            )
        }
    }

    /// Five-number scoring summary across both pools (matches GolfStatsSection).
    static func summary(for athlete: Athlete, season: Season?) -> GolfExportSummary {
        let tScores = tournamentRounds(for: athlete, season: season).compactMap { $0.score }
        let pScores = practiceRounds(for: athlete, season: season).compactMap { $0.score }
        let all = tScores + pScores
        return GolfExportSummary(
            totalRounds: all.count,
            bestScore: all.min(),
            worstScore: all.max(),
            tournamentAverage: tScores.isEmpty ? nil
                : Double(tScores.reduce(0, +)) / Double(tScores.count),
            practiceAverage: pScores.isEmpty ? nil
                : Double(pScores.reduce(0, +)) / Double(pScores.count)
        )
    }

    // MARK: - Charts & comparison support (golf Plus parity)

    /// Scored, non-live tournament `Game`s for the pool, newest first — the
    /// same membership test as `tournamentRounds`, but returning the models so
    /// callers can reach per-hole `holeScores`. Pass `holes: 18` to drop
    /// 9-hole rounds when an average must stay on one scale.
    static func scoredTournamentGames(for athlete: Athlete, season: Season?, holes: Int? = nil) -> [Game] {
        let pool: [Game] = season?.games ?? athlete.games ?? []
        let scored = pool.filter { (g: Game) -> Bool in
            guard g.season?.sport == .golf else { return false }
            guard !g.isLive else { return false }
            guard g.isGolfRoundScored else { return false }
            guard let holes else { return true }
            return holeCount(of: g) == holes
        }
        return scored.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    /// Hole count for a round: the declared `holes`, else the number of scored
    /// holes. Pulled out so `scoredTournamentGames`' filter type-checks fast.
    private static func holeCount(of game: Game) -> Int {
        if let holes = game.holes { return holes }
        return (game.holeScores ?? []).count
    }

    /// Comparison roll-up for one season, over 18-hole tournament rounds only.
    static func seasonSummary(for athlete: Athlete, season: Season?) -> GolfSeasonSummary {
        let games = scoredTournamentGames(for: athlete, season: season, holes: 18)
        let scores = games.compactMap { $0.effectiveTotalScore }
        let toPars: [Int] = games.compactMap { g in
            guard let s = g.effectiveTotalScore, let p = g.effectivePar else { return nil }
            return s - p
        }
        let puttRounds = games.compactMap { puttsTotal($0.holeScores) }
        let birdieCounts = games.map { g in (g.holeScores ?? []).filter { $0.isBirdieOrBetter }.count }

        func avg(_ xs: [Int]) -> Double? {
            xs.isEmpty ? nil : Double(xs.reduce(0, +)) / Double(xs.count)
        }

        let seasonHoles = games.flatMap { $0.holeScores ?? [] }
        return GolfSeasonSummary(
            rounds: games.count,
            bestScore: scores.min(),
            avgScore: avg(scores),
            avgToPar: avg(toPars),
            avgPutts: avg(puttRounds),
            birdiesPerRound: birdieCounts.isEmpty ? nil
                : Double(birdieCounts.reduce(0, +)) / Double(birdieCounts.count),
            girPct: girRate(seasonHoles),
            firPct: firRate(seasonHoles),
            scramblingPct: scramblingRate(seasonHoles)
        )
    }

    /// Game-improvement roll-up over every scored round (tournament + practice)
    /// in the pool. Mirrors the membership tests in `tournamentRounds` /
    /// `practiceRounds`, but works at the hole level for the rate metrics.
    static func advancedStats(for athlete: Athlete, season: Season?) -> GolfAdvancedStats {
        // Per-round hole sets (each inner array is one round's holes).
        let gameRounds = scoredTournamentGames(for: athlete, season: season).map { $0.holeScores ?? [] }
        let rounds: [[HoleScore]] = gameRounds + practiceRoundHoleSets(for: athlete, season: season)
        let flattened: [HoleScore] = rounds.flatMap { $0 }
        let allHoles = flattened.filter { $0.score > 0 }

        // Per-round to-par (split out so the type-checker stays fast).
        var toPars: [Int] = []
        for holes in rounds where !holes.isEmpty {
            let s = holes.reduce(0) { $0 + $1.score }
            let p = holes.reduce(0) { $0 + $1.par }
            toPars.append(s - p)
        }

        // Putts per round (only rounds that recorded putts).
        var puttRounds: [Int] = []
        for holes in rounds {
            let recorded = holes.compactMap { $0.putts }
            if !recorded.isEmpty { puttRounds.append(recorded.reduce(0, +)) }
        }

        // Penalties per detailed round (a round with any tracked detail).
        let detailedRounds = rounds.filter { holes in
            holes.contains { $0.fairwayHit != nil || $0.greenInRegulation != nil || $0.penalties != nil }
        }
        let penaltyTotals = detailedRounds.map { holes in holes.compactMap { $0.penalties }.reduce(0, +) }

        // Putts on GIR holes.
        let girHoles = allHoles.filter { $0.greenInRegulation == true }
        let girPutts = girHoles.compactMap { $0.putts }

        func avg(_ xs: [Int]) -> Double? {
            xs.isEmpty ? nil : Double(xs.reduce(0, +)) / Double(xs.count)
        }

        return GolfAdvancedStats(
            avgToPar: avg(toPars),
            girPct: girRate(allHoles),
            firPct: firRate(allHoles),
            puttsPerRound: avg(puttRounds),
            puttsPerGIR: girPutts.isEmpty ? nil : Double(girPutts.reduce(0, +)) / Double(girPutts.count),
            scramblingPct: scramblingRate(allHoles),
            penaltiesPerRound: detailedRounds.isEmpty ? nil : avg(penaltyTotals),
            par3Avg: parScoringAvg(allHoles, par: 3),
            par4Avg: parScoringAvg(allHoles, par: 4),
            par5Avg: parScoringAvg(allHoles, par: 5)
        )
    }

    /// Practice-round hole sets with ≥1 scored hole (mirrors `practiceRounds`).
    private static func practiceRoundHoleSets(for athlete: Athlete, season: Season?) -> [[HoleScore]] {
        let pool: [Practice] = season?.practices ?? athlete.practices ?? []
        return pool
            .filter { $0.practiceType == PracticeType.practiceRound.rawValue && !($0.holeScores ?? []).isEmpty }
            .map { $0.holeScores ?? [] }
    }

    /// Buckets every scored hole into Eagle+/Birdie/Par/Bogey/Double+ for the
    /// distribution chart. Per-hole, so 9- and 18-hole rounds pool safely.
    static func scoreDistribution(_ holeScores: [HoleScore]) -> [GolfScoreBucket] {
        var counts = [0, 0, 0, 0, 0] // eagle+, birdie, par, bogey, double+
        for h in holeScores where h.score > 0 {
            switch h.diff {
            case ...(-2): counts[0] += 1
            case -1:      counts[1] += 1
            case 0:       counts[2] += 1
            case 1:       counts[3] += 1
            default:      counts[4] += 1
            }
        }
        let labels = ["Eagle+", "Birdie", "Par", "Bogey", "Double+"]
        return labels.enumerated().map {
            GolfScoreBucket(order: $0.offset, label: $0.element, count: counts[$0.offset])
        }
    }

    private static func parTotal(_ holeScores: [HoleScore]?) -> Int? {
        let holes = holeScores ?? []
        return holes.isEmpty ? nil : holes.reduce(0) { $0 + $1.par }
    }

    /// Greens-in-regulation % over holes that tracked GIR (0–100); nil if none.
    static func girRate(_ holes: [HoleScore]) -> Double? {
        let tracked = holes.filter { $0.greenInRegulation != nil }
        guard !tracked.isEmpty else { return nil }
        let hit = tracked.filter { $0.greenInRegulation == true }.count
        return Double(hit) / Double(tracked.count) * 100
    }

    /// Fairways-in-regulation % over holes that tracked fairway (par 4+); nil if none.
    static func firRate(_ holes: [HoleScore]) -> Double? {
        let tracked = holes.filter { $0.fairwayHit != nil }
        guard !tracked.isEmpty else { return nil }
        let hit = tracked.filter { $0.fairwayHit == true }.count
        return Double(hit) / Double(tracked.count) * 100
    }

    /// Scrambling %: of holes where GIR was missed, the share saved to par or
    /// better. nil when no missed-GIR holes were tracked.
    static func scramblingRate(_ holes: [HoleScore]) -> Double? {
        let missed = holes.filter { $0.greenInRegulation == false && $0.score > 0 }
        guard !missed.isEmpty else { return nil }
        let saved = missed.filter { $0.diff <= 0 }.count
        return Double(saved) / Double(missed.count) * 100
    }

    /// Average score on holes of a given par; nil when none were played.
    private static func parScoringAvg(_ holes: [HoleScore], par: Int) -> Double? {
        let hs = holes.filter { $0.par == par && $0.score > 0 }
        guard !hs.isEmpty else { return nil }
        return Double(hs.reduce(0) { $0 + $1.score }) / Double(hs.count)
    }

    private static func puttsTotal(_ holeScores: [HoleScore]?) -> Int? {
        let recorded = (holeScores ?? []).compactMap { $0.putts }
        return recorded.isEmpty ? nil : recorded.reduce(0, +)
    }
}
