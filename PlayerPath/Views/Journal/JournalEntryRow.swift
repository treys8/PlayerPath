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
    /// This row's already-resolved top milestone (for the auto-headline + the
    /// marker), or nil for non-game entries / games without one. The feed resolves
    /// it once from a `[UUID: Milestone]` index, so the row never scans an array.
    var milestone: Milestone? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: .spacingMedium) {
            dateRail

            // The milestone marker rides in the date rail (top-right) instead of
            // its own row above the title — one less stacked text line, so a
            // milestone card keeps the same rhythm as a plain card, and the
            // achievement earns the prominent corner. Headline stands alone here.
            // A caption-less standalone photo has no real title — its image is
            // the hero and the "Photo" type tag already names it — so it drops
            // the placeholder headline (see JournalEntry.showsHeadline).
            if entry.showsHeadline {
                Text(HeadlineBuilder.headline(for: entry, milestone: milestone))
                    .font(.ppTitle3)                   // Fraunces serif
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.leading)
            }

            // Only a practice's course/location sits above the media (context,
            // not a stat). A game's batting/golf stat rides in the footer.
            if let subline = practiceSubline {
                Text(subline)
                    .font(.ppSubheadline)
                    .foregroundStyle(Theme.textSecondary)
            }

            media

            footer
        }
        .padding(.spacingLarge)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ppCard()
    }

    // MARK: - Date rail

    private var dateRail: some View {
        HStack(spacing: 6) {
            // Quiet chrome, not accent: the date bullet is decoration, and the
            // design rule reserves accent for significance (the HOT STREAK
            // kicker, highlight chips, stars). A soft tertiary tone keeps the
            // whole rail — bullet, date, type tag — one calm register.
            Circle()
                .fill(Theme.textTertiary)
                .frame(width: 6, height: 6)
            Text(entry.date.formatted(.dateTime.month(.abbreviated).day().year()))
                .smallCapsLabel()
            Spacer(minLength: .spacingSmall)
            // A milestone takes the corner — its accent star is the card's "this
            // mattered" signal. Otherwise the muted category tag sits here. A
            // milestone is always a game, so the dropped "GAME" tag loses nothing.
            if let marker = milestone?.markerLabel {
                PPMilestoneMarker(label: marker)
            } else {
                Text(typeTag).smallCapsLabel(color: Theme.textTertiary)
            }
        }
    }

    private var typeTag: String {
        switch entry {
        case .game:     return entry.isGolf ? "Golf" : "Game"
        // The headline already carries the specific golf type ("Range Session" /
        // "Practice Round"), so the category chip stays generic — and correct for
        // range sessions, which the old golf branch mislabeled "Practice Round".
        case .practice: return "Practice"
        case .clip:       return entry.containsHighlight ? "Highlight" : "Clip"
        case .photo:      return "Photo"
        case .photoGroup: return "Photos"
        }
    }

    // MARK: - Stat / subline

    /// Game batting/golf line for the footer (left), incl. the milestone
    /// opponent append ("1-for-2 · vs Mag"). Game-only.
    private var footerStat: String? {
        guard case .game(let g) = entry else { return nil }
        let base = entry.isGolf ? golfSubline(g) : baseballSubline(g)
        return appendingOpponent(to: base, game: g)
    }

    /// Practice course/location, shown ABOVE the media as context (not a stat).
    private var practiceSubline: String? {
        guard case .practice(let p) = entry,
              let course = p.course?.trimmingCharacters(in: .whitespaces),
              !course.isEmpty else { return nil }
        return course
    }

    /// When a milestone drives the headline ("Season-high 3 hits in a game"),
    /// the opponent is no longer in the title — so anchor the memory by tacking
    /// "· vs HA" onto the stat line. No-op for non-milestone cards (their
    /// headline already carries the matchup) and when the opponent is blank.
    private func appendingOpponent(to subline: String?, game: Game) -> String? {
        guard milestone != nil else { return subline }
        let opponent = game.opponent.trimmingCharacters(in: .whitespaces)
        guard !opponent.isEmpty else { return subline }
        guard let subline else { return game.opponentLabel }
        return "\(subline) · \(game.opponentLabel)"
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
        if case .photo(let photo) = entry {
            // A standalone-photo entry shows the photo itself. JournalPhotoThumbnail
            // owns its own loading/failed glyph (incl. an iCloud-download hint),
            // so the tile passes no glyph of its own.
            PPMediaTile(tileColor: Theme.tile(forKey: entry.id)) {
                JournalPhotoThumbnail(photo: photo)
            }
        } else if case .photoGroup = entry, let photo = entry.representativePhoto {
            // A multi-photo day collapses to one card: the most recent photo as
            // the cover, with a stack glyph marking it as a set (the headline
            // carries the exact count). Tapping opens the day-scoped grid sheet
            // (see JournalView). JournalPhotoThumbnail owns its own loading glyph.
            PPMediaTile(tileColor: Theme.tile(forKey: entry.id)) {
                JournalPhotoThumbnail(photo: photo)
            }
            .overlay(alignment: .bottomTrailing) { photoStackBadge }
        } else if let clip = entry.representativeClip {
            // Only a single orphan clip card promises inline playback — its ▶
            // and duration are honest because there's exactly one clip to play.
            // Event cards (.game/.practice) are multi-item previews that open
            // the detail page, so they show neither (a ▶ on "3 CLIPS" can't say
            // which clip it would play).
            let chip = outcomeChip(for: clip)
            PPMediaTile(
                tileColor: Theme.tile(forKey: entry.id),
                outcome: chip,
                // The star is the SOLE highlight signal. Drop it when an accent
                // outcome pill already encodes the same significance, and on
                // milestone cards (the date-rail kicker already crowns those). A
                // clip with no tagged result (no pill), or golf's green pill,
                // still earns the star.
                isStarred: clip.isHighlight && milestone == nil && !(chip?.isAccent ?? false),
                duration: isSingleClipEntry ? durationText(clip.duration) : nil,
                showsPlayButton: isSingleClipEntry
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
        } else if let photo = entry.representativePhoto {
            // No clip, but the event has photos — show an actual tagged photo.
            // JournalPhotoThumbnail owns its own loading/failed glyph (incl. the
            // iCloud-download hint), so the tile passes no glyph of its own.
            PPMediaTile(tileColor: Theme.tile(forKey: entry.id)) {
                JournalPhotoThumbnail(photo: photo)
            }
        }
    }

    /// True only for a standalone clip entry — the one card type where tapping
    /// plays the clip (orphan `.clip`, e.g. a Highlight). Drives whether the
    /// media tile shows the ▶ / duration "tap to play" affordance.
    private var isSingleClipEntry: Bool {
        if case .clip = entry { return true } else { return false }
    }

    /// Small "this is a set" affordance pinned to the cover of a photo-group card,
    /// so a multi-photo day reads differently from a single photo at a glance. The
    /// exact count lives in the headline, so the badge stays glyph-only.
    private var photoStackBadge: some View {
        Image(systemName: "photo.stack")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(6)
            .background(Circle().fill(.black.opacity(0.55)))
            .padding(.spacingSmall)
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

    // MARK: - Footer

    /// Game footer: stat on the left (natural case, muted), media counts on the
    /// right (small-caps overline). Either side may be absent — a game with
    /// stats but no media shows just the stat; an event with media but no stats
    /// (or a practice) shows just the counts; neither → no footer row.
    @ViewBuilder
    private var footer: some View {
        let stat = footerStat
        let counts = countsText
        if stat != nil || counts != nil {
            HStack(alignment: .firstTextBaseline, spacing: .spacingSmall) {
                if let stat {
                    Text(stat)
                        .font(.ppFootnote)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: .spacingSmall)
                }
                if let counts {
                    Text(counts).smallCapsLabel()
                }
            }
        }
    }

    // MARK: - Counts

    private var countsText: String? {
        // Only event cards (game/practice) summarize their contained media here. A
        // standalone clip/photo IS its single media item — the tile already shows
        // it (▶/duration for a clip, the image for a photo) — and a photo group
        // states its count in the headline, so a "1 clip"/"6 photos" footer would
        // only repeat what's already on screen.
        switch entry {
        case .game, .practice: break
        case .clip, .photo, .photoGroup: return nil
        }
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
