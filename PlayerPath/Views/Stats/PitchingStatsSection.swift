//
//  PitchingStatsSection.swift
//  PlayerPath
//
//  Created by Trey Schilling on 3/21/26.
//

import SwiftUI

// MARK: - Pitching Statistics Section

struct PitchingStatsSection: View {
    let statistics: AthleteStatistics

    @State private var isVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            SectionHeader(title: "Pitching Statistics", icon: "figure.baseball")
                .opacity(isVisible ? 1 : 0)
                .offset(y: isVisible ? 0 : 10)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 15) {
                StatCard(
                    title: "Total Pitches",
                    value: "\(statistics.totalPitches)",
                    color: .purple,
                    subtitle: nil
                )

                StatCard(
                    title: "Strike %",
                    value: String(format: "%.1f%%", statistics.strikePercentage * 100),
                    color: .green,
                    subtitle: "\(statistics.strikes)/\(statistics.totalPitches)"
                )
            }

            VStack(spacing: 0) {
                DetailedStatRow(label: "Strikes", value: "\(statistics.strikes)")
                DetailedStatRow(label: "Balls", value: "\(statistics.balls)")
                DetailedStatRow(label: "Hit By Pitch", value: "\(statistics.hitByPitches)")
                DetailedStatRow(label: "Wild Pitches", value: "\(statistics.wildPitches)", isLast: true)
            }
            .background(
                RoundedRectangle(cornerRadius: .cornerXLarge, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
            .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 20)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.4).delay(0.4)) {
                isVisible = true
            }
        }
    }
}
