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

    var body: some View {
        VStack(spacing: .spacingSmall) {
            Text("\(hole.holeNumber)")
                .font(.labelSmall)
                .foregroundColor(.secondary)
            ScoreToParBadge(score: hole.score, par: hole.par)
            Text("Par \(hole.par)")
                .font(.labelSmall)
                .foregroundColor(.secondary)
        }
        .frame(minWidth: 56, minHeight: 56)
        .padding(.spacingSmall)
        .background(
            // Par-relative wash so bogeys/doubles read at a glance too — not just
            // the old birdie-or-better ring.
            RoundedRectangle(cornerRadius: .cornerMedium)
                .fill(ScoreNotation(diff: hole.diff).wash)
        )
    }
}
