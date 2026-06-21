//
//  ShotLogRow.swift
//  PlayerPath
//
//  One logged-shot row in the shot-by-shot timeline (Direction B). Shows the
//  shot number, club, lie → outcome, and optional distance. Tapping the row
//  opens it for editing in `ShotByShotContent` (the active card becomes its
//  editor); a ring marks the row currently being edited. Kept tiny + self
//  contained so the entry view stays focused on flow + state.
//

import SwiftUI

struct ShotLogRow: View {
    let shot: Shot
    /// True when this row is the one currently open in the editor.
    let isEditing: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: .spacingMedium) {
                Text("\(shot.shotNumber)")
                    .font(.labelMedium)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(badgeColor))

                VStack(alignment: .leading, spacing: 1) {
                    Text(clubLabel)
                        .font(.bodyMedium)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Text(flowLabel)
                        .font(.bodySmall)
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: .spacingSmall)

                if let distance = shot.distanceBefore {
                    Text("\(distance) yds")
                        .font(.bodySmall)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }
                if shot.penaltyStrokes > 0 {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundColor(Theme.warning)
                }
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .padding(.vertical, 10)
            .padding(.horizontal, .spacingMedium)
            .background(
                RoundedRectangle(cornerRadius: .cornerLarge)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: .cornerLarge)
                    .stroke(Theme.golfAccent, lineWidth: isEditing ? 2 : 0)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Shot \(shot.shotNumber), \(clubLabel), \(flowLabel). Tap to edit.")
    }

    private var clubLabel: String {
        if shot.isPutt { return "Putt" }
        return shot.club?.displayName ?? "No club"
    }

    private var flowLabel: String {
        "\(shot.lie.displayName) → \(shot.outcome.displayName)"
    }

    /// Mirrors the entry view's outcome palette: good outcomes green, misses
    /// amber, fringe neutral, bunker sandy.
    private var badgeColor: Color {
        switch shot.outcome {
        case .fairway, .green, .holed, .close, .on: return Theme.golfAccent
        case .missLeft, .missRight, .short, .long:  return Theme.warning
        case .fringe:                                return .secondary
        case .bunker:                                return .brandGold
        }
    }
}
