//
//  KeyStatsSection.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import SwiftUI

struct KeyStatsSection: View {
    let statistics: AthleteStatistics

    @State private var isVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            SectionHeader(title: "Key Statistics", icon: "chart.bar.fill")
                .opacity(isVisible ? 1 : 0)
                .offset(y: isVisible ? 0 : 10)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 15) {
                StatCard(
                    title: "Batting Average",
                    value: StatisticsService.shared.formatBattingAverage(statistics.battingAverage),
                    color: .blue,
                    subtitle: "\(statistics.hits)/\(statistics.atBats)"
                )

                StatCard(
                    title: "On-Base %",
                    value: StatisticsService.shared.formatPercentage(statistics.onBasePercentage),
                    color: .green,
                    subtitle: "Walks: \(statistics.walks)"
                )

                StatCard(
                    title: "Slugging %",
                    value: StatisticsService.shared.formatBattingAverage(statistics.sluggingPercentage),
                    color: .orange,
                    subtitle: "Total Bases"
                )

                StatCard(
                    title: "Games Played",
                    value: "\(statistics.totalGames)",
                    color: .purple,
                    subtitle: "Career"
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

struct StatCard: View {
    let title: String
    let value: String
    let color: Color
    let subtitle: String?

    @State private var isAnimating = false

    init(title: String, value: String, color: Color, subtitle: String? = nil) {
        self.title = title
        self.value = value
        self.color = color
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .textCase(.uppercase)
                .tracking(0.5)

            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [color, color.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.7)
                .scaleEffect(isAnimating ? 1.0 : 0.8)
                .opacity(isAnimating ? 1.0 : 0)

            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(height: 100)
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(
            ZStack {
                // Base background
                RoundedRectangle(cornerRadius: .cornerXLarge, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))

                // Subtle top gradient accent
                RoundedRectangle(cornerRadius: .cornerXLarge, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.1), .clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )

                // Top accent line
                VStack {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [color, color.opacity(0.5)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 3)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    Spacer()
                }
            }
        )
        .shadow(color: color.opacity(0.1), radius: 8, x: 0, y: 4)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value)\(subtitle.map { ", \($0)" } ?? "")")
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1)) {
                isAnimating = true
            }
        }
    }
}
