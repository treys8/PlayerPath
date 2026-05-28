//
//  ScoreHoleControls.swift
//  PlayerPath
//
//  Presentational building blocks for the modern ScoreHoleSheet (Option A —
//  hero + tap-grid). Kept separate so ScoreHoleSheet stays focused on state and
//  save logic. All views here are stateless and driven by values/closures.
//

import SwiftUI

/// Large color-coded score readout — the focal point of the scoring sheet.
/// Term ("BIRDIE"), the score itself, and a plain-language relative line, all
/// tinted by the modern par convention (green under / red over / neutral).
struct ScoreHeroCard: View {
    let score: Int
    let par: Int

    private var diff: Int { score - par }
    private var tint: Color { .parRelative(diff) }

    /// "1 under par" / "Even par" / "2 over par". The headline term above
    /// already celebrates the name ("BIRDIE", "HOLE-IN-ONE"), so this stays
    /// purely informational.
    private var relativeLine: String {
        if diff == 0 { return "Even par" }
        let magnitude = abs(diff)
        return diff < 0 ? "\(magnitude) under par" : "\(magnitude) over par"
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(HoleScore.diffLabel(score: score, par: par).uppercased())
                .font(.headingSmall)
                .foregroundColor(tint)

            Text("\(score)")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(tint)

            Text(relativeLine)
                .font(.bodySmall)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, .spacingLarge)
        .background(
            RoundedRectangle(cornerRadius: .cornerXLarge)
                .fill(tint.opacity(0.10))
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: score)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: par)
    }
}

/// A single tappable number pill. Mirrors InlineSpeedControl's selected/idle
/// styling (navy fill when chosen). `isPar` faintly rings the chip equal to par
/// so the score grid orients the golfer toward the expected number.
private struct NumberChip: View {
    let value: Int
    let isSelected: Bool
    let isPar: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            Haptics.selection()
            onTap()
        } label: {
            Text("\(value)")
                .font(.headingMedium)
                .monospacedDigit()
                .fontWeight(isSelected ? .bold : .medium)
                .foregroundColor(isSelected ? .white : .primary)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: .cornerLarge)
                        .fill(isSelected ? Color.brandNavy : Color(.secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: .cornerLarge)
                        .stroke(
                            isPar && !isSelected ? Color.brandNavy.opacity(0.4) : Color.clear,
                            lineWidth: 1.5
                        )
                )
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel("\(value)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Wrapping grid of NumberChips. Reused for score (with `par` highlighted) and
/// putts (`par: nil`). One tap commits the value through `onSelect`.
struct NumberChipGrid: View {
    let range: ClosedRange<Int>
    let selected: Int
    /// When non-nil, the chip matching this value is ringed as the par hint.
    let par: Int?
    let onSelect: (Int) -> Void

    private let columns = [GridItem(.adaptive(minimum: 52), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Array(range), id: \.self) { value in
                NumberChip(
                    value: value,
                    isSelected: value == selected,
                    isPar: par == value,
                    onTap: { onSelect(value) }
                )
            }
        }
    }
}
