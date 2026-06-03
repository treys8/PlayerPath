//
//  PitchMixChartView.swift
//  PlayerPath
//
//  Donut chart showing the split between fastball and off-speed pitches.
//  Mirrors the colors used by the Avg FB Speed / Avg Off-Speed StatCards
//  above it in PitchingStatsSection so the visual language carries through.
//

import SwiftUI
import Charts

struct PitchMixChartView: View {
    let fastballCount: Int
    let offspeedCount: Int

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isVisible = false

    private var hasData: Bool {
        fastballCount > 0 || offspeedCount > 0
    }

    private var chartHeight: CGFloat {
        horizontalSizeClass == .regular ? 200 : 160
    }

    private var legendItems: [LegendItem] {
        [
            LegendItem(label: "Fastball", color: .green),
            LegendItem(label: "Off-Speed", color: .orange)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            SectionHeader(title: "Pitch Mix", icon: "circle.circle")
                .opacity(isVisible ? 1 : 0)
                .offset(y: isVisible ? 0 : 10)

            VStack(spacing: 12) {
                if hasData {
                    Chart {
                        SectorMark(
                            angle: .value("Fastball", fastballCount),
                            innerRadius: .ratio(0.6),
                            angularInset: 2
                        )
                        .cornerRadius(4)
                        .foregroundStyle(.green)
                        .annotation(position: .overlay) {
                            if fastballCount > 0 {
                                Text("\(fastballCount)")
                                    .font(.labelSmall)
                                    .foregroundColor(.white)
                            }
                        }

                        SectorMark(
                            angle: .value("Off-Speed", offspeedCount),
                            innerRadius: .ratio(0.6),
                            angularInset: 2
                        )
                        .cornerRadius(4)
                        .foregroundStyle(.orange)
                        .annotation(position: .overlay) {
                            if offspeedCount > 0 {
                                Text("\(offspeedCount)")
                                    .font(.labelSmall)
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .chartLegend(.hidden)
                    .frame(height: chartHeight)

                    ChartLegend(items: legendItems)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "circle.dashed")
                            .font(.title2)
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("No pitch types tagged yet")
                            .font(.bodyMedium)
                            .foregroundColor(.secondary)
                    }
                    .frame(height: chartHeight)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, horizontalSizeClass == .regular ? 16 : 12)
            .padding(.horizontal, horizontalSizeClass == .regular ? 24 : 16)
            .background(
                RoundedRectangle(cornerRadius: .cornerXLarge, style: .continuous)
                    .fill(Theme.card)
            )
            .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 20)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.4).delay(0.35)) {
                isVisible = true
            }
        }
    }
}
