//
//  JournalEntryRow.swift
//  PlayerPath
//
//  Visual overhaul — a single Journal feed row.
//  Date rail (date + accent dot, type tag) → serif headline → stat subline →
//  media tile → media counts. Purely presentational; the screen wraps it in a
//  NavigationLink to the right destination.
//

import SwiftUI

struct JournalEntryRow: View {
    let entry: JournalEntry
    /// Season milestones (for the auto-headline + the marker). Defaults empty
    /// so previews / non-milestone callers fall back to the matchup headline.
    var milestones: [Milestone] = []

    var body: some View {
        VStack(alignment: .leading, spacing: .spacingMedium) {
            dateRail

            if let marker = entryMilestone?.markerLabel {
                PPMilestoneMarker(label: marker)
            }

            Text(HeadlineBuilder.headline(for: entry, milestones: milestones))
                .font(.ppTitle3)                       // Fraunces serif
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.leading)

            if let subline = statSubline {
                Text(subline)
                    .font(.ppSubheadline)
                    .foregroundStyle(Theme.textSecondary)
            }

            media

            if let counts = countsText {
                Text(counts).smallCapsLabel()
            }
        }
        .padding(.spacingLarge)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ppCard()
    }

    /// The most significant milestone linked to this entry's game, if any.
    private var entryMilestone: Milestone? {
        guard case .game(let game) = entry else { return nil }
        return milestones
            .filter { $0.gameID == game.id }
            .max { rank($0.kind) < rank($1.kind) }
    }

    private func rank(_ kind: Milestone.Kind) -> Int {
        switch kind {
        case .seasonFirst:  return 4
        case .personalBest: return 3
        case .streak:       return 2
        case .milestone:    return 1
        }
    }

    // MARK: - Date rail

    private var dateRail: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Theme.accent)
                .frame(width: 6, height: 6)
            Text(entry.date.formatted(.dateTime.month(.abbreviated).day().year()))
                .smallCapsLabel()
            Spacer(minLength: .spacingSmall)
            Text(typeTag).smallCapsLabel(color: Theme.textTertiary)
        }
    }

    private var typeTag: String {
        switch entry {
        case .game:     return entry.isGolf ? "Golf" : "Game"
        case .practice: return entry.isGolf ? "Practice Round" : "Practice"
        case .clip:     return entry.containsHighlight ? "Highlight" : "Clip"
        }
    }

    // MARK: - Stat subline

    private var statSubline: String? {
        switch entry {
        case .game(let g):
            return entry.isGolf ? golfSubline(g) : baseballSubline(g)
        case .practice(let p):
            if let course = p.course, !course.trimmingCharacters(in: .whitespaces).isEmpty {
                return course
            }
            return nil
        case .clip:
            return nil
        }
    }

    /// Hits-for-at-bats plus home runs. Never RBI or runs (no game context).
    private func baseballSubline(_ game: Game) -> String? {
        guard let gs = game.gameStats, gs.atBats > 0 else { return nil }
        var line = "\(gs.hits)-for-\(gs.atBats)"
        if gs.homeRuns > 0 { line += " · \(gs.homeRuns) HR" }
        return line
    }

    /// Round score with to-par. The athlete's own score — safe to surface.
    private func golfSubline(_ game: Game) -> String? {
        guard let score = game.effectiveTotalScore else { return nil }
        guard let par = game.effectivePar else { return "\(score)" }
        let diff = score - par
        let toPar = diff == 0 ? "E" : (diff > 0 ? "+\(diff)" : "\(diff)")
        return "\(score) · \(toPar)"
    }

    // MARK: - Media

    @ViewBuilder
    private var media: some View {
        if let clip = entry.representativeClip {
            PPMediaTile(
                tileColor: Theme.tile(forKey: entry.id),
                outcome: outcomeChip(for: clip),
                isStarred: clip.isHighlight,
                duration: durationText(clip.duration),
                showsPlayButton: true
            ) {
                VideoThumbnailView(
                    clip: clip,
                    cornerRadius: 0,
                    showPlayResult: false,
                    showHighlight: false,
                    showContext: false,
                    showDuration: false,
                    fillsContainer: true
                )
            }
        } else if entry.photoCount > 0 {
            PPMediaTile(
                tileColor: Theme.tile(forKey: entry.id),
                glyph: "photo.on.rectangle.angled"
            )
        }
    }

    private func outcomeChip(for clip: VideoClip) -> PPOutcomeChip? {
        if entry.isGolf {
            return PPOutcomeChip(label: "GOLF", style: .green)
        }
        if let type = clip.playResult?.type {
            return PPOutcomeChip(result: type, overMedia: true, highlighted: clip.isHighlight)
        }
        return nil
    }

    // MARK: - Counts

    private var countsText: String? {
        var parts: [String] = []
        if entry.clipCount > 0 { parts.append("\(entry.clipCount) clip\(entry.clipCount == 1 ? "" : "s")") }
        if entry.photoCount > 0 { parts.append("\(entry.photoCount) photo\(entry.photoCount == 1 ? "" : "s")") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func durationText(_ seconds: Double?) -> String? {
        guard let seconds, seconds > 0 else { return nil }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
