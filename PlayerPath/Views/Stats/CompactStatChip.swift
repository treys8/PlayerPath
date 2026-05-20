//
//  CompactStatChip.swift
//  PlayerPath
//
//  Compact colored card for a single labeled stat value. Sibling of
//  PlayResultCard — same gradient/shadow/animation aesthetic — but takes
//  a pre-formatted String so it can render counts, ratios, and percentages.
//

import SwiftUI

struct CompactStatData {
    let label: String
    let value: String
    let color: Color
}

struct CompactStatChip: View {
    let data: CompactStatData

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 6) {
            Text(data.value)
                .font(.ppStat(22))
                .monospacedDigit()
                .foregroundStyle(
                    LinearGradient(
                        colors: [data.color, data.color.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .scaleEffect(isAnimating ? 1.0 : 0.5)
                .opacity(isAnimating ? 1.0 : 0)

            Text(data.label)
                .font(.labelSmall)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .truncationMode(.tail)
                .minimumScaleFactor(0.8)
        }
        .frame(height: horizontalSizeClass == .regular ? 85 : 70)
        .frame(maxWidth: .infinity)
        .padding(horizontalSizeClass == .regular ? 12 : 8)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: .cornerLarge, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                RoundedRectangle(cornerRadius: .cornerLarge, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.clear, data.color.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        )
        .shadow(color: data.color.opacity(0.08), radius: 4, x: 0, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(data.label): \(data.value)")
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(.random(in: 0...0.2))) {
                isAnimating = true
            }
        }
    }
}
