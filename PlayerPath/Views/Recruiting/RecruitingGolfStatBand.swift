//
//  RecruitingGolfStatBand.swift
//  PlayerPath
//
//  Golf is the recruiting-stats exception: scoring is objective and IS the
//  recruiting currency, so golf profiles carry a full stat band. Values come
//  from RecruitingGolfStats — the same type the publish snapshot serializes —
//  so the public web page always shows exactly what the athlete previewed here.
//  Never snapshot these into the bio blob.
//

import SwiftUI

struct RecruitingGolfStatBand: View {
    let athlete: Athlete

    /// Computed once per identity rather than inline in `body`: the roll-up walks
    /// the whole game + hole graph, and `body` can re-run on any ancestor change.
    @State private var stats: RecruitingGolfStats?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Golf")
                .font(.headingMedium)

            if let stats {
                if stats.hasScores {
                    grid(stats.leadStats)
                    if stats.hasDetailed {
                        grid(stats.detailedStats)
                    }
                    if !stats.recentRounds.isEmpty {
                        recentRoundsList(stats.recentRounds)
                    }
                    Text(RecruitingGolfStats.footnote)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    emptyState
                }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .task(id: athlete.id) {
            stats = RecruitingGolfStats.compute(for: athlete)
        }
    }

    // MARK: - Subviews

    private func grid(_ items: [RecruitingStatItem]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(items, id: \.kind) { item in
                CompactStatChip(data: .init(label: item.label, value: item.value, color: item.kind.chipColor))
            }
        }
    }

    /// Recent scores are the line a college golf coach reads first — mirrored on
    /// the published page from the same `stats.recentRounds`.
    private func recentRoundsList(_ rounds: [RecruitingGolfRound]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Rounds")
                .font(.labelMedium)
                .foregroundColor(.secondary)
            ForEach(Array(rounds.enumerated()), id: \.offset) { _, round in
                HStack(spacing: 8) {
                    Text(round.course)
                        .font(.bodySmall)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(round.dateString)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(round.score)")
                        .font(.bodyMedium)
                        .monospacedDigit()
                    Text(round.toParString)
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                        .frame(minWidth: 24, alignment: .trailing)
                }
            }
        }
    }

    private var emptyState: some View {
        HStack(spacing: 10) {
            Image(systemName: "figure.golf")
                .foregroundStyle(.secondary)
            Text("Play a scored tournament round to show your scoring stats.")
                .font(.bodySmall)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
    }

}
