//
//  BattingChartSection.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import SwiftUI
import Charts

struct BattingChartSection: View {
    let statistics: AthleteStatistics

    @State private var isVisible = false

    private var chartData: [PlayTypeData] {
        [
            PlayTypeData(type: "Singles", count: statistics.singles, color: .green),
            PlayTypeData(type: "Doubles", count: statistics.doubles, color: .blue),
            PlayTypeData(type: "Triples", count: statistics.triples, color: .orange),
            PlayTypeData(type: "Home Runs", count: statistics.homeRuns, color: .gold)
        ].filter { $0.count > 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            SectionHeader(title: "Hit Distribution", icon: "chart.bar.xaxis")
                .opacity(isVisible ? 1 : 0)
                .offset(y: isVisible ? 0 : 10)

            if !chartData.isEmpty {
                Chart(chartData, id: \.type) { data in
                    BarMark(
                        x: .value("Count", data.count),
                        y: .value("Type", data.type)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [data.color, data.color.opacity(0.7)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(4)
                    .annotation(position: .trailing) {
                        Text("\(data.count)")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                    }
                    .accessibilityLabel("\(data.type): \(data.count)")
                }
                .chartXScale(domain: 0...max(1, chartData.map(\.count).max() ?? 1))
                .chartXAxis(.hidden)
                .frame(height: 140)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: .cornerXLarge, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )
                .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
                .opacity(isVisible ? 1 : 0)
                .offset(y: isVisible ? 0 : 20)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "chart.bar")
                        .font(.title2)
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No hits recorded yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(height: 100)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: .cornerXLarge, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.4).delay(0.1)) {
                isVisible = true
            }
        }
    }
}

struct PlayTypeData {
    let type: String
    let count: Int
    let color: Color
}
