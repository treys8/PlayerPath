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

    // MARK: - Body

    var body: some View {
        VStack(spacing: 16) {
            SectionHeader(title: season?.displayName ?? "Career Scoring", icon: "figure.golf")

            if totalRounds == 0 {
                emptyState
            } else {
                summaryGrid
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

    private var summaryGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            statTile(label: "Rounds", value: "\(totalRounds)")
            if let best = bestScore {
                statTile(label: "Best", value: "\(best)", color: .green)
            }
            if let avg = tournamentAverage {
                statTile(label: "Round Avg", value: String(format: "%.1f", avg))
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
