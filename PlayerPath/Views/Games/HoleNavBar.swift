//
//  HoleNavBar.swift
//  PlayerPath
//
//  Bottom navigation bar for continuous hole-by-hole golf scoring. Pinned via
//  `.safeAreaInset(edge: .bottom)` by both scoring bodies (`QuickScoreContent`,
//  `ShotByShotContent`) so a round flows hole → hole without dismissing the
//  sheet. Layout: ‹ Prev | "Hole X of N" | primary action. The owning content
//  view supplies the primary title/disabled state and the prev/primary actions
//  (Quick saves first via its closures; shot-by-shot persists live, so it just
//  navigates).
//

import SwiftUI

struct HoleNavBar: View {
    let currentHole: Int
    let holeCount: Int
    let primaryTitle: String
    let primaryDisabled: Bool
    let onPrev: () -> Void
    let onPrimary: () -> Void

    var body: some View {
        HStack(spacing: .spacingMedium) {
            Button(action: onPrev) {
                Image(systemName: "chevron.left")
                    .font(.bodyLarge.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundColor(currentHole > 1 ? Theme.golfAccent : .secondary)
            .disabled(currentHole <= 1)
            .accessibilityLabel("Previous hole")

            Text("Hole \(currentHole) of \(holeCount)")
                .font(.labelMedium)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            Button(action: onPrimary) {
                Text(primaryTitle)
                    .font(.bodyLarge)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, .spacingLarge)
                    .frame(height: 44)
                    .background(
                        Capsule().fill(primaryDisabled ? Color.secondary.opacity(0.5) : Theme.golfAccent)
                    )
            }
            .buttonStyle(ScaleButtonStyle())
            .disabled(primaryDisabled)
        }
        .padding(.horizontal, .spacingLarge)
        .padding(.vertical, .spacingSmall)
        .background(.bar)
    }
}
