//
//  GolfStatsSection.swift
//  PlayerPath
//
//  Live-computed scoring summary for golf rounds. v6.1 PR3: splits the
//  single "Avg Score" tile into Tournament Avg and Practice Avg so range
//  sessions and practice rounds don't pollute the tournament-only number.
//  No fields are added to AthleteStatistics — golf scoring is summarised on
//  the fly so it stays simple and migration-free.
//

import SwiftUI
import SwiftData
import Charts

struct GolfStatsSection: View {
    let athlete: Athlete?
    /// When non-nil, only rounds in this season are counted. nil = all golf rounds.
    let season: Season?

    // MARK: - Source pools

    private var tournamentRounds: [Game] {
        let pool: [Game]
        if let season {
            pool = season.games ?? []
        } else {
            pool = athlete?.games ?? []
        }
        // Exclude in-progress (live) rounds and partially-scored rounds from
        // averages — only complete rounds count (isGolfRoundScored), so a round
        // ended after 3 of 18 holes doesn't show up as a "best" of 12. The
        // value displayed for a counted round still comes from effectiveTotalScore.
        // Broken into an explicit closure so the type-checker doesn't time out
        // on the chained filter/sorted with optional unwraps.
        let scored = pool.filter { (game: Game) -> Bool in
            guard game.season?.sport == .golf else { return false }
            guard !game.isLive else { return false }
            return game.isGolfRoundScored
        }
        return scored.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    /// Golf practice rounds with at least one scored hole. Season filter
    /// matches the tournament path: when `season` is set, only practice
    /// rounds tied to that season are counted; otherwise all of the athlete's
    /// practice rounds qualify. Practices without per-hole entries are
    /// excluded — they don't contribute a meaningful average.
    private var practiceRounds: [Practice] {
        let pool: [Practice]
        if let season {
            pool = season.practices ?? []
        } else {
            pool = athlete?.practices ?? []
        }
        return pool.filter { practice in
            practice.practiceType == PracticeType.practiceRound.rawValue
                && !(practice.holeScores ?? []).isEmpty
        }
    }

    // MARK: - Derived metrics

    private var tournamentScores: [Int] { tournamentRounds.compactMap { $0.effectiveTotalScore } }
    private var practiceScores: [Int] {
        practiceRounds.map { practice in
            (practice.holeScores ?? []).reduce(0) { $0 + $1.score }
        }
    }

    private var totalRounds: Int { tournamentScores.count + practiceScores.count }
    private var bestScore: Int? { (tournamentScores + practiceScores).min() }
    private var worstScore: Int? { (tournamentScores + practiceScores).max() }

    private var tournamentAverage: Double? {
        guard !tournamentScores.isEmpty else { return nil }
        return Double(tournamentScores.reduce(0, +)) / Double(tournamentScores.count)
    }
    private var practiceAverage: Double? {
        guard !practiceScores.isEmpty else { return nil }
        return Double(practiceScores.reduce(0, +)) / Double(practiceScores.count)
    }

    /// Average to-par over tournament rounds ONLY, so it reflects the same round
    /// set as the adjacent "Round Avg" tile. (The detailed grid's pooled metrics
    /// still come from `advanced`, which intentionally includes practice rounds.)
    private var tournamentAvgToPar: Double? {
        let diffs: [Int] = tournamentRounds.compactMap { game in
            guard let s = game.effectiveTotalScore, let p = game.effectivePar else { return nil }
            return s - p
        }
        guard !diffs.isEmpty else { return nil }
        return Double(diffs.reduce(0, +)) / Double(diffs.count)
    }

    /// Detailed game-improvement metrics. nil when no athlete; `hasDetailed`
    /// gates the detailed grid so a score-only golfer sees the simple view.
    private var advanced: GolfAdvancedStats? {
        guard let athlete else { return nil }
        return GolfExportData.advancedStats(for: athlete, season: season)
    }

    /// Free shot-derived patterns (tee miss bias, approach miss, sand saves).
    /// `hasData` gates the section so a golfer with no shot tracking sees
    /// nothing new. No subscription check — this is the free descriptive payoff.
    private var shotPatterns: ShotPatternStats? {
        guard let athlete else { return nil }
        return ShotStats.compute(for: athlete, season: season)
    }

    private func toParString(_ v: Double) -> String {
        if abs(v) < 0.05 { return "E" }
        let r = (v * 10).rounded() / 10
        let body = r == r.rounded() ? "\(Int(r))" : String(format: "%.1f", r)
        return r > 0 ? "+\(body)" : body
    }
    private func pctString(_ v: Double) -> String { "\(Int(v.rounded()))%" }
    private func oneDecimal(_ v: Double) -> String { String(format: "%.1f", v) }

    /// Handicap-style display: a plus-handicap (under-par estimate) shows as
    /// "+2.3"; everyone else shows the over-par estimate, e.g. "11.4".
    private func handicapString(_ v: Double) -> String {
        let r = (v * 10).rounded() / 10
        if r < 0 { return "+\(String(format: "%.1f", -r))" }
        return String(format: "%.1f", r)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 16) {
            SectionHeader(title: season?.displayName ?? "Career Scoring", icon: "figure.golf")

            if totalRounds == 0 {
                emptyState
            } else {
                handicapHeader
                summaryGrid
                if let advanced, advanced.hasDetailed {
                    detailedGrid(advanced)
                }
                if let sp = shotPatterns, sp.hasData {
                    shotPatternGrid(sp)
                }
                parSplitRow
                recentRoundsChart
            }
        }
        .padding(.vertical, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.golf")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("No completed rounds yet")
                .font(.bodyMedium)
                .foregroundColor(.secondary)
            Text("Enter a score on a completed tournament or score holes on a practice round to start tracking your averages.")
                .font(.bodySmall)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .statCardBackground()
    }

    /// Prominent estimated-handicap card above the summary grid. Hidden until
    /// the athlete has enough scored 18-hole rounds (HandicapEstimator minimum).
    @ViewBuilder
    private var handicapHeader: some View {
        if let athlete, let idx = HandicapEstimator.estimatedIndex(for: athlete, season: season) {
            HStack(spacing: 12) {
                Image(systemName: "figure.golf")
                    .font(.title2)
                    .foregroundColor(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Est. Handicap")
                        .font(.labelMedium)
                        .foregroundColor(.secondary)
                    Text(handicapString(idx))
                        .font(.ppStatLarge)
                        .monospacedDigit()
                }
                Spacer()
            }
            .padding(.spacingMedium)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: .cornerLarge, style: .continuous)
                    .fill(Theme.card)
            )
        }
    }

    private var summaryGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            statTile(label: "Rounds", value: "\(totalRounds)")
            if let best = bestScore {
                statTile(label: "Best", value: "\(best)", color: .green)
            }
            if let avg = tournamentAverage {
                statTile(label: "Round Avg", value: String(format: "%.1f", avg))
            }
            if let atp = tournamentAvgToPar {
                statTile(label: "Avg To Par", value: toParString(atp),
                         color: .parRelative(atp < 0 ? -1 : (atp > 0 ? 1 : 0)))
            }
            // Practice avg hides when zero practice rounds exist so a
            // tournament-only golfer doesn't see a stranded "—".
            if let avg = practiceAverage {
                statTile(label: "Practice Avg", value: String(format: "%.1f", avg))
            }
            if let worst = worstScore {
                statTile(label: "Worst", value: "\(worst)", color: .secondary)
            }
        }
    }

    private func statTile(label: String, value: String, color: Color = .primary) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.ppStatLarge)
                .monospacedDigit()
                .foregroundColor(color)
            Text(label)
                .font(.labelSmall)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .statCardBackground()
    }

    // MARK: - Detailed (FIR / GIR / scrambling / putts / penalties)

    private func detailedGrid(_ s: GolfAdvancedStats) -> some View {
        var chips: [CompactStatData] = []
        if let g = s.girPct { chips.append(.init(label: "GIR", value: pctString(g), color: .green)) }
        if let f = s.firPct { chips.append(.init(label: "Fairways", value: pctString(f), color: .brandNavy)) }
        if let p = s.puttsPerRound { chips.append(.init(label: "Putts / Rnd", value: oneDecimal(p), color: .brandNavy)) }
        if let sc = s.scramblingPct { chips.append(.init(label: "Scrambling", value: pctString(sc), color: .mint)) }
        if let pen = s.penaltiesPerRound { chips.append(.init(label: "Penalties / Rnd", value: oneDecimal(pen), color: Theme.warning)) }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Detailed")
                .font(.headingMedium)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                    CompactStatChip(data: chip)
                }
            }
        }
    }

    // MARK: - Shot patterns (free, shot-tracking only)

    /// Free descriptive shot patterns — tee miss bias, dominant approach miss,
    /// and greenside sand saves. Only the chips with data render; the whole
    /// section is gated on `ShotPatternStats.hasData` by the caller.
    @ViewBuilder
    private func shotPatternGrid(_ s: ShotPatternStats) -> some View {
        let chips = shotPatternChips(s)
        if !chips.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Shot Patterns")
                    .font(.headingMedium)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                        CompactStatChip(data: chip)
                    }
                }
            }
        }
    }

    private func shotPatternChips(_ s: ShotPatternStats) -> [CompactStatData] {
        var chips: [CompactStatData] = []
        if s.teeMisses > 0 {
            chips.append(.init(label: "Tee Miss",
                               value: "L\(s.teeMissLeft) · R\(s.teeMissRight)",
                               color: Theme.warning))
        }
        if let dir = s.dominantApproachMiss {
            chips.append(.init(label: "Approach Miss", value: dir, color: Theme.warning))
        }
        if let ss = s.sandSavePct {
            chips.append(.init(label: "Sand Saves", value: pctString(ss), color: Theme.golfAccent))
        }
        return chips
    }

    // MARK: - Scoring by par

    @ViewBuilder
    private var parSplitRow: some View {
        if let s = advanced, s.par3Avg != nil || s.par4Avg != nil || s.par5Avg != nil {
            VStack(alignment: .leading, spacing: 8) {
                Text("Scoring by Par")
                    .font(.headingMedium)
                HStack(spacing: 12) {
                    parTile("Par 3", s.par3Avg)
                    parTile("Par 4", s.par4Avg)
                    parTile("Par 5", s.par5Avg)
                }
            }
        }
    }

    private func parTile(_ label: String, _ avg: Double?) -> some View {
        VStack(spacing: 4) {
            Text(avg.map { String(format: "%.2f", $0) } ?? "—")
                .font(.ppStatLarge)
                .monospacedDigit()
            Text(label)
                .font(.labelSmall)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .statCardBackground()
    }

    /// Recent-rounds chart is tournament-only — practice rounds vary in length
    /// (9 vs 18 holes) so plotting them on the same axis would mislead.
    private var recentRoundsChart: some View {
        let recent = Array(tournamentRounds.prefix(10).reversed())
        return VStack(alignment: .leading, spacing: 8) {
            Text("Recent Tournaments")
                .font(.headingMedium)
            if recent.count < 2 {
                Text("Play another round to see a trend.")
                    .font(.bodySmall)
                    .foregroundColor(.secondary)
            } else {
                Chart(Array(recent.enumerated()), id: \.element.id) { _, round in
                    if let score = round.effectiveTotalScore, let date = round.date {
                        LineMark(
                            x: .value("Date", date),
                            y: .value("Score", score)
                        )
                        .foregroundStyle(Color.brandNavy)
                        PointMark(
                            x: .value("Date", date),
                            y: .value("Score", score)
                        )
                        .foregroundStyle(Color.brandNavy)
                    }
                }
                .frame(height: 160)
            }
            if !practiceScores.isEmpty {
                Text("Practice rounds shown in totals only.")
                    .font(.bodySmall)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: .cornerLarge, style: .continuous)
                .fill(Theme.card)
        )
    }
}
