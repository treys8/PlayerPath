//
//  PitchingHeroCard.swift
//  PlayerPath
//
//  "The Numbers." hero for pitching — the sibling of StatsHeroCard so the
//  Pitching tab opens with the same editorial slash line + calm metric grid
//  instead of jumping straight into colored stat cards. The pitching slash
//  line is ERA / WHIP / K-9 (the rate-stat analog of AVG / OBP / SLG).
//

import SwiftUI

struct PitchingHeroCard: View {
    let statistics: AthleteStatistics
    var label: String = "Pitching Line"

    /// Rates are only meaningful once at least one out is recorded; otherwise
    /// they read as "—" rather than a misleading 0.00 / ∞ (matches the guard
    /// in PitchingStatsSection).
    private var hasIP: Bool { statistics.outsRecorded > 0 }
    private var eraText: String { hasIP ? String(format: "%.2f", statistics.era) : "—" }
    private var whipText: String { hasIP ? String(format: "%.2f", statistics.whip) : "—" }
    private var kPer9Text: String { hasIP ? String(format: "%.1f", statistics.strikeoutsPer9) : "—" }

    var body: some View {
        VStack(alignment: .leading, spacing: .spacingLarge) {
            // Slash line — ERA / WHIP / K-9.
            VStack(alignment: .leading, spacing: 4) {
                Text("\(label) · \(statistics.inningsPitchedDisplay) IP")
                    .smallCapsLabel()
                HStack(alignment: .firstTextBaseline, spacing: .spacingSmall) {
                    slashValue(eraText, label: "ERA")
                    slash
                    slashValue(whipText, label: "WHIP")
                    slash
                    slashValue(kPer9Text, label: "K-9")
                }
            }

            Divider().overlay(Theme.divider)

            // Metric grid — pitching counting line.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: .spacingLarge) {
                metric("Innings", statistics.inningsPitchedDisplay)
                metric("Strikeouts", "\(statistics.pitchingStrikeouts)")
                metric("Walks", "\(statistics.pitchingWalks)")
                metric("Hits", "\(statistics.hitsAllowed)")
                metric("Home Runs", "\(statistics.homeRunsAllowed)")
                metric("Earned Runs", "\(statistics.earnedRuns)")
            }
        }
        .padding(.spacingLarge)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ppCard()
    }

    private func slashValue(_ text: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text)
                .font(.ppStat(34))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
            Text(label).smallCapsLabel(color: Theme.textTertiary)
        }
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
