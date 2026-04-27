//
//  DetailedStatsSection.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import SwiftUI

struct DetailedStatsSection: View {
    let statistics: AthleteStatistics

    @State private var isVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            SectionHeader(title: "Detailed Statistics", icon: "list.bullet.clipboard")
                .opacity(isVisible ? 1 : 0)
                .offset(y: isVisible ? 0 : 10)

            VStack(spacing: 0) {
                DetailedStatRow(label: "At Bats", value: "\(statistics.atBats)")
                DetailedStatRow(label: "Hits", value: "\(statistics.hits)")
                DetailedStatRow(label: "Ground Outs", value: "\(statistics.groundOuts)")
                DetailedStatRow(label: "Fly Outs", value: "\(statistics.flyOuts)", isLast: true)
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
            withAnimation(.easeOut(duration: 0.4).delay(0.2)) {
                isVisible = true
            }
        }
    }
}

private struct LabelValueRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label)
                .font(.bodyMedium)
            Spacer()
            Text(value)
                .font(.ppStatSmall)
                .monospacedDigit()
                .foregroundColor(.blue)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }
}

struct DetailedStatRow: View {
    let label: String
    let value: String
    let isLast: Bool

    init(label: String, value: String, isLast: Bool = false) {
        self.label = label
        self.value = value
        self.isLast = isLast
    }

    var body: some View {
        VStack(spacing: 0) {
            LabelValueRow(label: label, value: value)
            if !isLast {
                Divider()
                    .padding(.horizontal)
            }
        }
    }
}
