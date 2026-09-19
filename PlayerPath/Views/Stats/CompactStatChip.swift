//
//  CompactStatChip.swift
//  PlayerPath
//
//  Compact card for a single labeled stat value. Takes a pre-formatted String
//  so it can render counts, ratios, and percentages. Neutral value on the
//  standard card surface — same calm treatment as StatCard.
//

import SwiftUI

struct CompactStatData {
    let label: String
    let value: String
}

struct CompactStatChip: View {
    let data: CompactStatData

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        VStack(spacing: 6) {
            Text(data.value)
                .font(.ppStat(22))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(data.label)
                .font(.ppCaption)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .truncationMode(.tail)
                .minimumScaleFactor(0.8)
        }
        .frame(height: horizontalSizeClass == .regular ? 85 : 70)
        .frame(maxWidth: .infinity)
        .padding(horizontalSizeClass == .regular ? 12 : 8)
        .ppCard(cornerRadius: .cornerLarge)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(data.label): \(data.value)")
    }
}
