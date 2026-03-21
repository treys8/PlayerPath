//
//  CareerSeasonComparisonSection.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import SwiftUI

// MARK: - Career vs Season Comparison Section
struct CareerSeasonComparisonSection: View {
    let careerStats: AthleteStatistics
    let seasonStats: AthleteStatistics
    let seasonName: String

    @State private var isVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            SectionHeader(title: "Statistics Comparison", icon: "arrow.left.arrow.right")
                .opacity(isVisible ? 1 : 0)
                .offset(y: isVisible ? 0 : 10)

            // Batting Average Comparison
            ComparisonStatCard(
                title: "Batting Average",
                careerValue: StatisticsService.shared.formatBattingAverage(careerStats.battingAverage),
                seasonValue: StatisticsService.shared.formatBattingAverage(seasonStats.battingAverage),
                careerSubtitle: "Career: \(careerStats.hits)/\(careerStats.atBats)",
                seasonSubtitle: "\(seasonName): \(seasonStats.hits)/\(seasonStats.atBats)",
                color: .blue
            )

            // On-Base Percentage Comparison
            ComparisonStatCard(
                title: "On-Base Percentage",
                careerValue: StatisticsService.shared.formatPercentage(careerStats.onBasePercentage),
                seasonValue: StatisticsService.shared.formatPercentage(seasonStats.onBasePercentage),
                careerSubtitle: "Career Walks: \(careerStats.walks)",
                seasonSubtitle: "\(seasonName) Walks: \(seasonStats.walks)",
                color: .green
            )

            // Slugging Percentage Comparison
            ComparisonStatCard(
                title: "Slugging Percentage",
                careerValue: StatisticsService.shared.formatBattingAverage(careerStats.sluggingPercentage),
                seasonValue: StatisticsService.shared.formatBattingAverage(seasonStats.sluggingPercentage),
                careerSubtitle: "Career Total Bases",
                seasonSubtitle: "\(seasonName) Total Bases",
                color: .orange
            )

            // Games Played Comparison
            ComparisonStatCard(
                title: "Games Played",
                careerValue: "\(careerStats.totalGames)",
                seasonValue: "\(seasonStats.totalGames)",
                careerSubtitle: "All Time",
                seasonSubtitle: seasonName,
                color: .purple
            )
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) {
                isVisible = true
            }
        }
    }
}

struct ComparisonStatCard: View {
    let title: String
    let careerValue: String
    let seasonValue: String
    let careerSubtitle: String
    let seasonSubtitle: String
    let color: Color

    @State private var isAnimating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            HStack(spacing: 16) {
                // Career Stats
                VStack(alignment: .leading, spacing: 4) {
                    Text("Career")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    Text(careerValue)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [color.opacity(0.7), color.opacity(0.5)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .scaleEffect(isAnimating ? 1.0 : 0.8)
                        .opacity(isAnimating ? 1.0 : 0)
                    Text(careerSubtitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // VS indicator
                ZStack {
                    Circle()
                        .fill(color.opacity(0.1))
                        .frame(width: 32, height: 32)
                    Text("vs")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(color)
                }

                // Season Stats
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 8))
                        Text("This Season")
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.blue)
                    Text(seasonValue)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [color, color.opacity(0.7)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .scaleEffect(isAnimating ? 1.0 : 0.8)
                        .opacity(isAnimating ? 1.0 : 0)
                    Text(seasonSubtitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(16)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: .cornerXLarge, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))

                // Subtle gradient accent
                RoundedRectangle(cornerRadius: .cornerXLarge, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.05), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        )
        .shadow(color: color.opacity(0.08), radius: 8, x: 0, y: 4)
        .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1)) {
                isAnimating = true
            }
        }
    }
}
