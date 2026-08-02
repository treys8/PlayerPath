//
//  PracticeCard.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import SwiftUI

struct PracticeCard: View {
    let practice: Practice

    private var practiceType: PracticeType {
        practice.type
    }

    /// Live hole rows only — tombstones score 0 and would drag the total down.
    private var scoredHoles: [HoleScore] {
        (practice.holeScores ?? []).filter { !$0.isDeletedRemotely && $0.score > 0 }
    }

    /// Running score for a practice round, e.g. "39 · +3 thru 9". Mirrors the
    /// Journal card's phrasing so the same round reads the same in both places.
    /// nil for range sessions, baseball practices, and unscored rounds.
    private var golfScoreLine: String? {
        guard practice.practiceType == PracticeType.practiceRound.rawValue,
              let score = practice.holeScoreSum else { return nil }
        var line: String
        if let par = practice.holeParSum {
            let diff = score - par
            let toPar = diff == 0 ? "E" : (diff > 0 ? "+\(diff)" : "\(diff)")
            line = "\(score) · \(toPar)"
        } else {
            line = "\(score)"
        }
        let played = scoredHoles.count
        let total = practice.holes ?? 18
        if played > 0 && played < total {
            line += " thru \(played)"
        }
        return line
    }

    /// Focus tags, capped at two with a "+N" overflow so a session tagged with
    /// six drills can't push the counts off the card.
    private var focusChips: (shown: [String], overflow: Int) {
        let all = practice.drillFocusDisplayNames
        return (Array(all.prefix(2)), max(0, all.count - 2))
    }

    var body: some View {
        HStack(spacing: 0) {
            // Accent bar
            RoundedRectangle(cornerRadius: 2)
                .fill(practiceType.color)
                .frame(width: 4)
                .padding(.vertical, 4)

            HStack(spacing: 12) {
                // Type icon
                Image(systemName: practiceType.icon)
                    .font(.title3)
                    .foregroundStyle(practiceType.color)
                    .frame(width: 28)

                // Info
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text((practice.date ?? .distantPast).formatted(date: .abbreviated, time: .omitted))
                            .font(.headingMedium)
                            .lineLimit(1)

                        // While live, the badge is the thing to see — the season
                        // chip steps aside (GameRow does the same).
                        if practice.isLive {
                            LiveBadge()
                        } else if let season = practice.season {
                            SeasonBadge(season: season, fontSize: 8)
                        }
                    }

                    // Type, then the course/location when there is one — a
                    // golfer scanning a season of rounds navigates by course.
                    Text(practice.course.map { "\(practiceType.displayName) · \($0)" }
                         ?? practiceType.displayName)
                        .font(.bodyMedium)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if let golfScoreLine {
                        Text(golfScoreLine)
                            .font(.labelSmall)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    let focus = focusChips
                    if !focus.shown.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(focus.shown, id: \.self) { name in
                                PPOutcomeChip(label: name, style: .neutralOnCard)
                            }
                            if focus.overflow > 0 {
                                Text("+\(focus.overflow)")
                                    .font(.labelSmall)
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }
                    }
                }

                Spacer()

                // Counts
                HStack(spacing: 10) {
                    let videoCount = practice.videoClips?.count ?? 0
                    if videoCount > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "video")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("\(videoCount)")
                                .font(.labelSmall)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }

                    let photoCount = practice.photos?.count ?? 0
                    if photoCount > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "photo")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("\(photoCount)")
                                .font(.labelSmall)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }

                    let noteCount = practice.notes?.count ?? 0
                    if noteCount > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "note.text")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("\(noteCount)")
                                .font(.labelSmall)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }

                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.leading, 12)
            .padding(.trailing, 16)
            .padding(.vertical, 12)
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: .cornerLarge, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
    }
}

struct EmptyPracticesView: View {
    /// When non-nil, the title becomes "No <sportTitle> Practice Sessions Yet".
    /// Pass `activeSport.displayName` from a multi-sport context; pass nil for
    /// single-sport athletes to keep the original generic wording.
    var sportTitle: String? = nil
    /// Drives the glyph and copy so a golfer isn't greeted by a batter.
    var sport: Season.SportType = .baseball
    let onAddPractice: () -> Void

    var body: some View {
        EmptyStateView(
            systemImage: sport == .golf ? "figure.golf" : "figure.baseball",
            title: sportTitle.map { "No \($0) Practice Sessions Yet" } ?? "No Practice Sessions Yet",
            message: sport == .golf
                ? "Log a practice round or range session to track training"
                : "Create your first practice to track training",
            actionTitle: "Add Practice",
            action: onAddPractice
        )
    }
}
