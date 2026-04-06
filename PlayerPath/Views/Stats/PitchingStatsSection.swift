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
    let athlete: Athlete?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isVisible = false
    @State private var showingFastballSpeeds = false
    @State private var showingOffspeedSpeeds = false

    private var columns: [GridItem] {
        let count = horizontalSizeClass == .regular ? 3 : 2
        return Array(repeating: GridItem(.flexible()), count: count)
    }

    private var avgFBSubtitle: String {
        let count = statistics.fastballPitchCount
        guard count > 0 else { return "No fastballs yet" }
        return "\(count) fastball\(count == 1 ? "" : "s")"
    }

    private var avgOffspeedSubtitle: String {
        let count = statistics.offspeedPitchCount
        guard count > 0 else { return "No off-speed yet" }
        return "\(count) off-speed"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            SectionHeader(title: "Pitching Statistics", icon: "figure.baseball")
                .opacity(isVisible ? 1 : 0)
                .offset(y: isVisible ? 0 : 10)

            LazyVGrid(columns: columns, spacing: 15) {
                StatCard(
                    title: "Total Pitches",
                    value: "\(statistics.totalPitches)",
                    color: .purple,
                    subtitle: nil
                )

                Button {
                    if athlete != nil {
                        showingFastballSpeeds = true
                    }
                } label: {
                    StatCard(
                        title: "Avg FB Speed",
                        value: statistics.fastballPitchCount > 0
                            ? String(format: "%.1f", statistics.averageFastballSpeed)
                            : "—",
                        color: .green,
                        subtitle: avgFBSubtitle
                    )
                }
                .buttonStyle(.plain)
                .disabled(athlete == nil)

                Button {
                    if athlete != nil {
                        showingOffspeedSpeeds = true
                    }
                } label: {
                    StatCard(
                        title: "Avg Off-Speed",
                        value: statistics.offspeedPitchCount > 0
                            ? String(format: "%.1f", statistics.averageOffspeedSpeed)
                            : "—",
                        color: .orange,
                        subtitle: avgOffspeedSubtitle
                    )
                }
                .buttonStyle(.plain)
                .disabled(athlete == nil)
            }

            VStack(spacing: 0) {
                DetailedStatRow(label: "Strikes", value: "\(statistics.strikes)")
                DetailedStatRow(label: "Balls", value: "\(statistics.balls)")
                DetailedStatRow(label: "Strikeouts", value: "\(statistics.pitchingStrikeouts)")
                DetailedStatRow(label: "Walks", value: "\(statistics.pitchingWalks)")
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
        .sheet(isPresented: $showingFastballSpeeds) {
            if let athlete {
                PitchSpeedsView(athlete: athlete, pitchType: "fastball")
            }
        }
        .sheet(isPresented: $showingOffspeedSpeeds) {
            if let athlete {
                PitchSpeedsView(athlete: athlete, pitchType: "offspeed")
            }
        }
    }
}
