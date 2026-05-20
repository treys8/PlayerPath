//
//  ChartLegend.swift
//  PlayerPath
//
//  Reusable inline legend for the stats charts. Renders a row of colored
//  dots + labels using the app's `.labelSmall` typography.
//

import SwiftUI

struct LegendItem {
    let label: String
    let color: Color
}

struct ChartLegend: View {
    let items: [LegendItem]

    var body: some View {
        HStack(spacing: 14) {
            ForEach(items, id: \.label) { item in
                HStack(spacing: 6) {
                    Circle()
                        .fill(item.color)
                        .frame(width: 8, height: 8)
                    Text(item.label)
                        .font(.labelSmall)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
