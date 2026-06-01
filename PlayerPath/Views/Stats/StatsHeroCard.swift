//
//  StatsHeroCard.swift
//  PlayerPath
//
//  Visual overhaul — "The Numbers." hero.
//  The editorial slash line (AVG / OBP / SLG) in serif-adjacent condensed
//  numerals over a small-caps label, plus a calm metric grid. Derivable stats
//  only — never RBI or runs.
//

import SwiftUI

struct StatsHeroCard: View {
    let statistics: AthleteStatistics
    var label: String = "Batting Line"

    private var svc: StatisticsService { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: .spacingLarge) {
            // Slash line
            VStack(alignment: .leading, spacing: 4) {
                Text("\(label) · \(statistics.totalGames.pluralized("Game"))")
                    .smallCapsLabel()
                HStack(alignment: .firstTextBaseline, spacing: .spacingSmall) {
                    slashValue(svc.formatBattingAverage(statistics.battingAverage))
                    slash
                    slashValue(svc.formatPercentage(statistics.onBasePercentage))
                    slash
                    slashValue(svc.formatBattingAverage(statistics.sluggingPercentage))
                }
            }

            Divider().overlay(Theme.divider)

            // Metric grid — derivable only (no RBI/runs).
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: .spacingLarge) {
                metric("Games", "\(statistics.totalGames)")
                metric("At-Bats", "\(statistics.atBats)")
                metric("Hits", "\(statistics.hits)")
                metric("Doubles", "\(statistics.doubles)")
                metric("Home Runs", "\(statistics.homeRuns)")
                metric("OPS", svc.formatOPS(statistics.ops))
            }
        }
        .padding(.spacingLarge)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ppCard()
    }

    private func slashValue(_ text: String) -> some View {
        Text(text)
            .font(.ppStat(34))
            .foregroundStyle(Theme.textPrimary)
            .monospacedDigit()
    }

    private var slash: some View {
        Text("/")
            .font(.ppTitle3)
            .foregroundStyle(Theme.textTertiary)
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.ppStatMedium)
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label).smallCapsLabel(color: Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}
