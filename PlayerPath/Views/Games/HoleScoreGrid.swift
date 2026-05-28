//
//  HoleScoreGrid.swift
//  PlayerPath
//
//  Read-only per-hole summary grid for a live golf round. Tapping a cell
//  re-opens ScoreHoleSheet for that hole so older entries can be corrected
//  without leaving GameDetailView.
//

import SwiftUI

/// Lightweight Identifiable wrapper so `.sheet(item:)` can present
/// ScoreHoleSheet against an Int payload. Using a UUID id forces SwiftUI to
/// rebuild the sheet when the user opens different holes back-to-back.
struct ScoreHoleTarget: Identifiable {
    let id = UUID()
    let holeNumber: Int
}

struct HoleScoreGrid: View {
    let holes: [HoleScore]
    let onTap: (HoleScore) -> Void

    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 64), spacing: 8)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(holes) { hole in
                Button {
                    Haptics.light()
                    onTap(hole)
                } label: {
                    HoleScoreCell(hole: hole)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct HoleScoreCell: View {
    let hole: HoleScore

    private var diffColor: Color { .parRelative(hole.diff) }

    var body: some View {
        VStack(spacing: 2) {
            Text("\(hole.holeNumber)")
                .font(.labelSmall)
                .foregroundColor(.secondary)
            Text("\(hole.score)")
                .font(.headingMedium)
                .monospacedDigit()
                .foregroundColor(diffColor)
            Text("Par \(hole.par)")
                .font(.labelSmall)
                .foregroundColor(.secondary)
        }
        .frame(minWidth: 56, minHeight: 56)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(hole.isBirdieOrBetter ? Color.green.opacity(0.5) : Color.clear, lineWidth: 1.5)
        )
    }
}
