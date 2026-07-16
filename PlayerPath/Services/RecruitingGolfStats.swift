//
//  RecruitingGolfStats.swift
//  PlayerPath
//
//  The single source for a golf recruiting profile's stat band — used by BOTH
//  the in-app band (RecruitingGolfStatBand) and the publish snapshot
//  (RecruitingProfileService). One computation, one set of labels, one set of
//  formatters, so the public web page can never disagree with what the athlete
//  previewed in the app.
//
//  Derived live from the same sources as the in-app Stats screen
//  (GolfExportData + HandicapEstimator) — never stored on the Athlete blob.
//

import Foundation

/// One scored tournament round, shaped for display.
nonisolated struct RecruitingGolfRound: Equatable {
    let date: Date?
    let course: String
    let score: Int
    let toPar: Int?

    /// "4/22/26" — empty when the round has no date.
    var dateString: String {
        guard let date else { return "" }
        return DateFormatter.compactDate.string(from: date)
    }

    /// "E" / "+3" / "-2" / "—" (mirrors GolfRoundRow.toParString).
    var toParString: String {
        guard let toPar else { return "—" }
        if toPar == 0 { return "E" }
        return toPar > 0 ? "+\(toPar)" : "\(toPar)"
    }
}

nonisolated struct RecruitingGolfStats: Equatable {
    // MARK: Raw values

    let estHandicap: Double?
    let roundAvg: Double?
    let bestScore: Int?
    let roundCount: Int
    let girPct: Double?
    let firPct: Double?
    let puttsPerRound: Double?
    let scramblingPct: Double?

    /// Copied from `GolfAdvancedStats.hasDetailed` rather than re-derived, so the
    /// detailed grid appears under exactly the same condition as the Stats screen.
    let hasDetailed: Bool

    /// Most recent scored tournament rounds, newest first (capped).
    let recentRounds: [RecruitingGolfRound]

    /// False when the athlete has no scored tournament rounds — callers show an
    /// empty state instead of a band of dashes.
    var hasScores: Bool { roundCount > 0 }

    /// Scoring is tournament-only, but GIR/fairways/putts/scrambling come from
    /// GolfExportData.advancedStats, which pools tournament AND practice rounds.
    /// This wording is deliberately narrow — do not broaden it to claim the whole
    /// band is tournament-only.
    static let footnote = "Scoring (avg / best / rounds) from tournament rounds only."

    // MARK: Display items (single source for band chips and page)

    var leadStats: [RecruitingStatItem] {
        var items: [RecruitingStatItem] = []
        if let estHandicap {
            items.append(.init(kind: .handicap, label: "Est. Handicap", value: Self.handicapString(estHandicap)))
        }
        if let roundAvg {
            items.append(.init(kind: .roundAvg, label: "Round Avg", value: Self.oneDecimal(roundAvg)))
        }
        if let bestScore {
            items.append(.init(kind: .best, label: "Best", value: "\(bestScore)"))
        }
        items.append(.init(kind: .rounds, label: "Rounds", value: "\(roundCount)"))
        return items
    }

    var detailedStats: [RecruitingStatItem] {
        var items: [RecruitingStatItem] = []
        if let girPct {
            items.append(.init(kind: .gir, label: "GIR", value: Self.pctString(girPct)))
        }
        if let firPct {
            items.append(.init(kind: .fairways, label: "Fairways", value: Self.pctString(firPct)))
        }
        if let puttsPerRound {
            items.append(.init(kind: .putts, label: "Putts / Rnd", value: Self.oneDecimal(puttsPerRound)))
        }
        if let scramblingPct {
            items.append(.init(kind: .scrambling, label: "Scrambling", value: Self.pctString(scramblingPct)))
        }
        return items
    }

    // MARK: Formatting (matches GolfStatsSection so values agree app-wide)

    /// Golf convention: a plus-handicap (better than scratch) renders "+2.4".
    static func handicapString(_ v: Double) -> String {
        let r = (v * 10).rounded() / 10
        return r < 0 ? "+\(String(format: "%.1f", -r))" : String(format: "%.1f", r)
    }

    static func pctString(_ v: Double) -> String { "\(Int(v.rounded()))%" }
    static func oneDecimal(_ v: Double) -> String { String(format: "%.1f", v) }

    // MARK: Compute

    /// Career-scope roll-up (`season: nil`) over the athlete's golf data.
    /// Call once per render / per publish — this walks the game + hole graph.
    @MainActor
    static func compute(for athlete: Athlete, recentLimit: Int = 5) -> RecruitingGolfStats {
        // Tournament rounds only for scoring: practice scores carry no recruiting
        // credibility, and `tournamentAverage` averages exactly this same set (see
        // GolfExportData.summary), so avg / best / rounds all agree.
        let tRounds = GolfExportData.tournamentRounds(for: athlete, season: nil)
        let tScores = tRounds.compactMap { $0.score }
        let advanced = GolfExportData.advancedStats(for: athlete, season: nil)

        return RecruitingGolfStats(
            estHandicap: HandicapEstimator.estimatedIndex(for: athlete, season: nil),
            roundAvg: GolfExportData.summary(for: athlete, season: nil).tournamentAverage,
            bestScore: tScores.min(),
            roundCount: tScores.count,
            girPct: advanced.girPct,
            firPct: advanced.firPct,
            puttsPerRound: advanced.puttsPerRound,
            scramblingPct: advanced.scramblingPct,
            hasDetailed: advanced.hasDetailed,
            recentRounds: tRounds.prefix(recentLimit).compactMap { row in
                guard let score = row.score else { return nil }
                return RecruitingGolfRound(
                    date: row.date, course: row.course, score: score, toPar: row.toPar
                )
            }
        )
    }
}
