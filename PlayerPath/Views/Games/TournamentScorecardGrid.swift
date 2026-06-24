//
//  TournamentScorecardGrid.swift
//  PlayerPath
//
//  Read-only round-by-round holes matrix for a multi-round golf tournament.
//  One row per scored round; columns are holes 1…maxHoles plus a trailing
//  total + to-par. Horizontally scrollable. Purely a visual summary — editing
//  happens by tapping into a round's GameDetailView from the Rounds list.
//

import SwiftUI

struct TournamentScorecardGrid: View {
    let rounds: [Game]   // already sorted by the caller
    /// When false, render a compact Round | Total | To-Par table only (no per-hole
    /// columns) — used when no round has per-hole scores (quick-entry tournaments).
    var includeHoleDetails: Bool = true

    private var scoredRounds: [Game] {
        rounds.filter { !($0.holeScores ?? []).isEmpty || $0.effectiveTotalScore != nil }
    }

    /// Widest round drives the column count so a 9-hole round in an 18-hole
    /// tournament still lines up under the right hole numbers.
    private var maxHoles: Int {
        let counts = scoredRounds.map { ($0.holeScores ?? []).map(\.holeNumber).max() ?? 0 }
        // Never below 1 — `1...maxHoles` would trap on an empty/zero range.
        return max(1, counts.max() ?? 18)
    }

    private let labelWidth: CGFloat = 48
    private let cellWidth: CGFloat = 28
    private let totWidth: CGFloat = 60

    var body: some View {
        ScrollView(.horizontal, showsIndicators: includeHoleDetails) {
            VStack(alignment: .leading, spacing: 6) {
                headerRow
                ForEach(scoredRounds) { roundRow($0) }
            }
            .padding(.vertical, 2)
        }
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text(includeHoleDetails ? "Hole" : "Round")
                .font(.labelSmall)
                .foregroundColor(.secondary)
                .frame(width: labelWidth, alignment: .leading)
            if includeHoleDetails {
                ForEach(1...maxHoles, id: \.self) { n in
                    Text("\(n)")
                        .font(.labelSmall)
                        .foregroundColor(.secondary)
                        .frame(width: cellWidth)
                }
            }
            Text("Tot")
                .font(.labelSmall)
                .foregroundColor(.secondary)
                .frame(width: totWidth)
        }
    }

    private func roundRow(_ round: Game) -> some View {
        let byHole = Dictionary((round.holeScores ?? []).map { ($0.holeNumber, $0) },
                                uniquingKeysWith: { first, _ in first })
        return HStack(spacing: 0) {
            Text("R\(round.roundNumber.map(String.init) ?? "–")")
                .font(.labelMedium)
                .frame(width: labelWidth, alignment: .leading)
            if includeHoleDetails {
                ForEach(1...maxHoles, id: \.self) { n in
                    if let hole = byHole[n] {
                        Text("\(hole.score)")
                            .font(.bodySmall)
                            .monospacedDigit()
                            .foregroundColor(.parRelative(hole.diff))
                            .frame(width: cellWidth)
                    } else {
                        Text("·")
                            .font(.bodySmall)
                            .foregroundColor(.secondary)
                            .frame(width: cellWidth)
                    }
                }
            }
            totalCell(round)
                .frame(width: totWidth)
        }
    }

    private func totalCell(_ round: Game) -> some View {
        HStack(spacing: 3) {
            if let score = round.effectiveTotalScore {
                Text("\(score)")
                    .font(.bodySmall)
                    .monospacedDigit()
                    .fontWeight(.semibold)
                if let par = round.effectivePar {
                    let diff = score - par
                    Text(diff == 0 ? "E" : (diff > 0 ? "+\(diff)" : "\(diff)"))
                        .font(.labelSmall)
                        .monospacedDigit()
                        .foregroundColor(diff < 0 ? .green : (diff > 0 ? .red : .secondary))
                }
            } else {
                Text("—")
                    .font(.bodySmall)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
