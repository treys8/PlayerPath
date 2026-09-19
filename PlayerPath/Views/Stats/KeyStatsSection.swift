//
//  KeyStatsSection.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import SwiftUI

struct KeyStatsSection: View {
    let statistics: AthleteStatistics
    var seasonLabel: String? = nil

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isVisible = false

    private var columns: [GridItem] {
        let count = horizontalSizeClass == .regular ? 4 : 2
        return Array(repeating: GridItem(.flexible()), count: count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            SectionHeader(title: "Key Statistics", icon: "chart.bar.fill")
                .opacity(isVisible ? 1 : 0)
                .offset(y: isVisible ? 0 : 10)

            LazyVGrid(columns: columns, spacing: 15) {
                StatCard(
                    title: "Batting Average",
                    value: StatisticsService.shared.formatBattingAverage(statistics.battingAverage),
                    subtitle: "\(statistics.hits)/\(statistics.atBats)"
                )

                StatCard(
                    title: "On-Base %",
                    value: StatisticsService.shared.formatPercentage(statistics.onBasePercentage),
                    subtitle: "Walks: \(statistics.walks)"
                )

                StatCard(
                    title: "Slugging %",
                    value: StatisticsService.shared.formatBattingAverage(statistics.sluggingPercentage),
                    subtitle: "Total Bases"
                )

                StatCard(
                    title: "Games Played",
                    value: "\(statistics.totalGames)",
                    subtitle: seasonLabel ?? "Career"
                )
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) {
                isVisible = true
            }
        }
    }
}

/// One labeled stat in a calm card: neutral value, small-caps label, the
/// standard `ppCard` surface. No per-stat hue — the overhaul rule is one
/// accent app-wide, and a colored value implies good/bad (a red 0.00 ERA read
/// as bad when it's perfect).
struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    init(title: String, value: String, subtitle: String? = nil) {
        self.title = title
        self.value = value
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .smallCapsLabel(color: Theme.textTertiary)
                .multilineTextAlignment(.center)

            Text(value)
                .font(.ppStatMedium)
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.7)

            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.ppCaption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(height: horizontalSizeClass == .regular ? 120 : 100)
        .frame(maxWidth: .infinity)
        .padding(horizontalSizeClass == .regular ? 16 : 12)
        .ppCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value)\(subtitle.map { ", \($0)" } ?? "")")
    }
}
