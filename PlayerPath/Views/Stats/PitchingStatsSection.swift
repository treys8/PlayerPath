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
    var label: String = "Pitching Line"

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isVisible = false
    @State private var showingFastballSpeeds = false
    @State private var showingOffspeedSpeeds = false

    private var topCardColumns: [GridItem] {
        let count = horizontalSizeClass == .regular ? 3 : 2
        return Array(repeating: GridItem(.flexible()), count: count)
    }

    private var chipColumns: [GridItem] {
        let count = horizontalSizeClass == .regular ? 4 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
    }

    private var avgFBSubtitle: String {
        let count = statistics.fastballPitchCount
        guard count > 0 else { return "No fastballs yet" }
        return "\(count) fastball\(count == 1 ? "" : "s")"
    }

    private var battersFacedSubtitle: String? {
        let count = statistics.battersFaced
        guard count > 0 else { return nil }
        return "\(count) batter\(count == 1 ? "" : "s") faced"
    }

    private var avgOffspeedSubtitle: String {
        let count = statistics.offspeedPitchCount
        guard count > 0 else { return "No off-speed yet" }
        return "\(count) off-speed"
    }

    /// Same full-inning guard as PitchingHeroCard.
    private var hasIP: Bool { statistics.hasPitchingRateSample }
    private var kPer9Text: String { hasIP ? String(format: "%.1f", statistics.strikeoutsPer9) : "—" }
    private var bbPer9Text: String { hasIP ? String(format: "%.1f", statistics.walksPer9) : "—" }
    private var kbbText: String {
        guard let ratio = statistics.strikeoutToWalkRatio else { return "—" }
        return String(format: "%.2f", ratio)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            // "The Numbers." hero — mirrors the batting StatsHeroCard so the
            // Pitching tab opens with the same editorial slash line + grid.
            // Everything below adds what the hero doesn't show (pitch counts,
            // velocity, mix, rates) — never repeat a hero number here.
            PitchingHeroCard(statistics: statistics, label: label)

            SectionHeader(title: "Pitching Statistics", icon: "figure.baseball")
                .opacity(isVisible ? 1 : 0)
                .offset(y: isVisible ? 0 : 10)

            LazyVGrid(columns: topCardColumns, spacing: 15) {
                StatCard(
                    title: "Total Pitches",
                    value: "\(statistics.totalPitches)",
                    subtitle: battersFacedSubtitle
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
                        subtitle: avgOffspeedSubtitle
                    )
                }
                .buttonStyle(.plain)
                .disabled(athlete == nil)
            }

            PitchMixChartView(
                fastballCount: statistics.fastballPitchCount,
                offspeedCount: statistics.offspeedPitchCount
            )

            LazyVGrid(columns: chipColumns, spacing: 12) {
                CompactStatChip(data: CompactStatData(
                    label: "Strikes",
                    value: "\(statistics.strikes)"
                ))
                CompactStatChip(data: CompactStatData(
                    label: "Balls",
                    value: "\(statistics.balls)"
                ))
                CompactStatChip(data: CompactStatData(
                    label: "Hit By Pitch",
                    value: "\(statistics.hitByPitches)"
                ))
                CompactStatChip(data: CompactStatData(
                    label: "Wild Pitches",
                    value: "\(statistics.wildPitches)"
                ))
                CompactStatChip(data: CompactStatData(
                    label: "Strike %",
                    value: StatisticsService.shared.formatPercentage(statistics.strikePercentage)
                ))
                CompactStatChip(data: CompactStatData(
                    label: "K / 9",
                    value: kPer9Text
                ))
                CompactStatChip(data: CompactStatData(
                    label: "BB / 9",
                    value: bbPer9Text
                ))
                CompactStatChip(data: CompactStatData(
                    label: "K / BB",
                    value: kbbText
                ))
                if let oppAvg = statistics.opponentAverage {
                    CompactStatChip(data: CompactStatData(
                        label: "Opp AVG",
                        value: StatisticsService.shared.formatBattingAverage(oppAvg)
                    ))
                }
            }
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
