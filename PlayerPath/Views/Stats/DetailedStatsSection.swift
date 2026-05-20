//
//  DetailedStatsSection.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import SwiftUI

struct DetailedStatsSection: View {
    let statistics: AthleteStatistics

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isVisible = false

    private var columns: [GridItem] {
        let count = horizontalSizeClass == .regular ? 3 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            SectionHeader(title: "Detailed Statistics", icon: "list.bullet.clipboard")
                .opacity(isVisible ? 1 : 0)
                .offset(y: isVisible ? 0 : 10)

            LazyVGrid(columns: columns, spacing: 12) {
                CompactStatChip(data: CompactStatData(
                    label: "At Bats",
                    value: "\(statistics.atBats)",
                    color: .blue
                ))
                CompactStatChip(data: CompactStatData(
                    label: "Hits",
                    value: "\(statistics.hits)",
                    color: .green
                ))
                CompactStatChip(data: CompactStatData(
                    label: "Ground Outs",
                    value: "\(statistics.groundOuts)",
                    color: .brown
                ))
                CompactStatChip(data: CompactStatData(
                    label: "Fly Outs",
                    value: "\(statistics.flyOuts)",
                    color: .cyan
                ))
                CompactStatChip(data: CompactStatData(
                    label: "ISO",
                    value: StatisticsService.shared.formatPercentage(statistics.isolatedPower),
                    color: .gold
                ))
                CompactStatChip(data: CompactStatData(
                    label: "Contact %",
                    value: StatisticsService.shared.formatPercentage(statistics.contactPercentage),
                    color: .mint
                ))
            }
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 20)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.4).delay(0.2)) {
                isVisible = true
            }
        }
    }
}
