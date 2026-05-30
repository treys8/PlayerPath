//
//  GolfScoreDistributionSection.swift
//  PlayerPath
//
//  Scoring-mix bar chart (Eagle+/Birdie/Par/Bogey/Double+) for the golf charts
//  screen. Per-hole, so it pools 9- and 18-hole rounds safely — buckets come
//  from GolfExportData.scoreDistribution.
//

import SwiftUI
import Charts

struct GolfScoreDistributionSection: View {
    let holeScores: [HoleScore]

    private var buckets: [GolfScoreBucket] { GolfExportData.scoreDistribution(holeScores) }
    private var total: Int { buckets.reduce(0) { $0 + $1.count } }

    // y-axis domain bottom→top: putting Eagle+ at the top reads like a leaderboard.
    private var orderedLabels: [String] { buckets.reversed().map { $0.label } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scoring Breakdown")
                .font(.headingLarge)

            if total == 0 {
                Text("Score some holes to see your scoring mix.")
                    .font(.bodyMedium)
                    .foregroundStyle(.secondary)
                    .frame(height: 160)
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
            } else {
                Chart(buckets) { bucket in
                    BarMark(
                        x: .value("Holes", bucket.count),
                        y: .value("Result", bucket.label)
                    )
                    .foregroundStyle(color(for: bucket.order))
                    .annotation(position: .trailing) {
                        if bucket.count > 0 {
                            Text("\(bucket.count)")
                                .font(.labelSmall)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .chartYScale(domain: orderedLabels)
                .chartXAxis(.hidden)
                .frame(height: CGFloat(buckets.count) * 34 + 16)

                Text("\(total) holes scored")
                    .font(.bodySmall)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .statCardBackground()
    }

    private func color(for order: Int) -> Color {
        switch order {
        case 0:  return .green      // Eagle or better
        case 1:  return .mint       // Birdie
        case 2:  return .brandNavy  // Par
        case 3:  return .orange     // Bogey
        default: return .red        // Double bogey or worse
        }
    }
}
