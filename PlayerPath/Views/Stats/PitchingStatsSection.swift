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

    private var avgOffspeedSubtitle: String {
        let count = statistics.offspeedPitchCount
        guard count > 0 else { return "No off-speed yet" }
        return "\(count) off-speed"
    }

    private var hasIP: Bool { statistics.outsRecorded > 0 }
    private var eraText: String { hasIP ? String(format: "%.2f", statistics.era) : "—" }
    private var whipText: String { hasIP ? String(format: "%.2f", statistics.whip) : "—" }
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
            PitchingHeroCard(statistics: statistics, label: label)

            SectionHeader(title: "Pitching Statistics", icon: "figure.baseball")
                .opacity(isVisible ? 1 : 0)
                .offset(y: isVisible ? 0 : 10)

            LazyVGrid(columns: topCardColumns, spacing: 15) {
                StatCard(
                    title: "ERA",
                    value: eraText,
                    color: .red,
                    subtitle: hasIP ? "\(statistics.earnedRuns) ER" : "No innings yet"
                )
                StatCard(
                    title: "WHIP",
                    value: whipText,
                    color: Theme.warning,
                    subtitle: hasIP ? nil : "No innings yet"
                )
                StatCard(
                    title: "Innings Pitched",
                    value: statistics.inningsPitchedDisplay,
                    color: .green,
                    subtitle: "\(statistics.battersFaced) batters faced"
                )

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

            PitchMixChartView(
                fastballCount: statistics.fastballPitchCount,
                offspeedCount: statistics.offspeedPitchCount
            )

            LazyVGrid(columns: chipColumns, spacing: 12) {
                CompactStatChip(data: CompactStatData(
                    label: "Strikes",
                    value: "\(statistics.strikes)",
                    color: .green
                ))
                CompactStatChip(data: CompactStatData(
                    label: "Balls",
                    value: "\(statistics.balls)",
                    color: .orange
                ))
                CompactStatChip(data: CompactStatData(
                    label: "Strikeouts",
                    value: "\(statistics.pitchingStrikeouts)",
                    color: .red
                ))
                CompactStatChip(data: CompactStatData(
                    label: "Walks",
                    value: "\(statistics.pitchingWalks)",
                    color: .cyan
                ))
                CompactStatChip(data: CompactStatData(
                    label: "Hit By Pitch",
                    value: "\(statistics.hitByPitches)",
                    color: .pink
                ))
                CompactStatChip(data: CompactStatData(
                    label: "Wild Pitches",
                    value: "\(statistics.wildPitches)",
                    color: .yellow
                ))
                CompactStatChip(data: CompactStatData(
                    label: "Strike %",
                    value: StatisticsService.shared.formatPercentage(statistics.strikePercentage),
                    color: .purple
                ))
                CompactStatChip(data: CompactStatData(
                    label: "Hits Allowed",
                    value: "\(statistics.hitsAllowed)",
                    color: .red
                ))
                CompactStatChip(data: CompactStatData(
                    label: "HR Allowed",
                    value: "\(statistics.homeRunsAllowed)",
                    color: .red
                ))
                CompactStatChip(data: CompactStatData(
                    label: "Earned Runs",
                    value: "\(statistics.earnedRuns)",
                    color: Theme.warning
                ))
                CompactStatChip(data: CompactStatData(
                    label: "K / 9",
                    value: kPer9Text,
                    color: .green
                ))
                CompactStatChip(data: CompactStatData(
                    label: "BB / 9",
                    value: bbPer9Text,
                    color: .cyan
                ))
                CompactStatChip(data: CompactStatData(
                    label: "K / BB",
                    value: kbbText,
                    color: .brandNavy
                ))
                if let oppAvg = statistics.opponentAverage {
                    CompactStatChip(data: CompactStatData(
                        label: "Opp AVG",
                        value: StatisticsService.shared.formatBattingAverage(oppAvg),
                        color: .pink
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
