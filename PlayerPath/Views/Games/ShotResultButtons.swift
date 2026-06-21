//
//  ShotResultButtons.swift
//  PlayerPath
//
//  Presentational result-button set for one shot, driven by its `ShotContext`
//  (tee / approach / around-green). Keeps ShotEntryView thin: it just hands over
//  the context and a tap handler. Stateless — tint + label come from the
//  outcome.
//

import SwiftUI

struct ShotResultButtons: View {
    let context: ShotContext
    let onTap: (ShotOutcome) -> Void

    private let columns = [GridItem(.adaptive(minimum: 84), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(context.outcomes, id: \.self) { outcome in
                ResultButton(outcome: outcome) { onTap(outcome) }
            }
        }
    }
}

private struct ResultButton: View {
    let outcome: ShotOutcome
    let onTap: () -> Void

    var body: some View {
        Button {
            Haptics.selection()
            onTap()
        } label: {
            Text(outcome.displayName)
                .font(.bodyLarge)
                .fontWeight(.semibold)
                .foregroundColor(tint)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: .cornerLarge)
                        .fill(tint.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: .cornerLarge)
                        .stroke(tint.opacity(0.5), lineWidth: 1.5)
                )
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel(outcome.displayName)
    }

    /// Good outcomes read green, misses amber, fringe neutral, bunker sandy.
    private var tint: Color {
        switch outcome {
        case .fairway, .green, .holed, .close, .on: return Theme.golfAccent
        case .missLeft, .missRight, .short, .long:  return Theme.warning
        case .fringe:                                return .secondary
        case .bunker:                                return .brandGold
        }
    }
}
