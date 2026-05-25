//
//  GolfStatsSection.swift
//  PlayerPath
//
//  Live-computed scoring summary for golf rounds. Counts only games whose
//  parent Season has sport == .golf and which have a totalScore entered.
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

    private var golfRounds: [Game] {
        let pool: [Game]
        if let season {
            pool = season.games ?? []
        } else {
            pool = athlete?.games ?? []
        }
        return pool
            .filter { $0.season?.sport == .golf && $0.totalScore != nil }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    private var totalRounds: Int { golfRounds.count }
    private var scores: [Int] { golfRounds.compactMap { $0.totalScore } }
    private var bestScore: Int? { scores.min() }
    private var worstScore: Int? { scores.max() }
    private var averageScore: Double? {
        guard !scores.isEmpty else { return nil }
        return Double(scores.reduce(0, +)) / Double(scores.count)
    }

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
            Text("Enter a score on a completed tournament to start tracking your scoring average.")
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
            if let avg = averageScore {
                statTile(label: "Avg Score", value: String(format: "%.1f", avg))
            }
            if let best = bestScore {
                statTile(label: "Best", value: "\(best)", color: .green)
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

    private var recentRoundsChart: some View {
        let recent = Array(golfRounds.prefix(10).reversed())
        return VStack(alignment: .leading, spacing: 8) {
            Text("Recent Rounds")
                .font(.headingMedium)
            if recent.count < 2 {
                Text("Play another round to see a trend.")
                    .font(.bodySmall)
                    .foregroundColor(.secondary)
            } else {
                Chart(Array(recent.enumerated()), id: \.element.id) { _, round in
                    if let score = round.totalScore, let date = round.date {
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
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: .cornerLarge, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}
