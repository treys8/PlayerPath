//
//  AthleteClipReviewDetail.swift
//  PlayerPath
//
//  Visual overhaul — the editorial block below the player on the athlete /
//  parent (read-only) clip detail. Purely presentational: it renders the
//  outcome headline, the coach's review (note + read-only drill stars), the
//  coach's quick-cue tags, and a bottom action bar. All data is passed in by
//  the host (VideoPlayerView); this view fetches nothing and mutates nothing.
//
//  Read-only by design — the coach authors this elsewhere
//  (CoachVideoPlayerView). Here the athlete only reads it back.
//

import SwiftUI

struct AthleteClipReviewDetail: View {
    let clip: VideoClip

    // Coach-authored content (empty / nil for ordinary athlete clips).
    let coachNoteText: String
    let coachNoteAuthorName: String?
    let coachNoteUpdatedAt: Date?
    let drillCards: [DrillCard]
    let cueTags: [String]

    // Bottom-bar actions wired to existing host functionality.
    var isHighlight: Bool
    var onToggleHighlight: () -> Void
    var onSave: () -> Void
    /// Local file URL for the system share sheet; `nil` hides the Share action.
    var shareURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: .spacingLarge) {
                    headline
                    if hasCoachReview { coachReviewCard }
                    if !cueTags.isEmpty { cueStrip }
                }
                .padding(.horizontal, .spacingLarge)
                .padding(.top, .spacingLarge)
                .padding(.bottom, .spacingMedium)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            bottomBar
        }
        .background(Theme.surface)
    }

    // MARK: - Headline

    private var headline: some View {
        VStack(alignment: .leading, spacing: 6) {
            if clip.isHighlight {
                PPMilestoneMarker(label: "Highlight")
            }
            Text(clip.displayTagName ?? "Unrecorded")
                .font(.ppTitle2)
                .foregroundStyle(clip.displayTagName == nil ? Theme.textSecondary : Theme.textPrimary)
            if let subline {
                Text(subline)
                    .smallCapsLabel()
            }
        }
    }

    /// Context line: opponent / practice, then date — whichever exist.
    private var subline: String? {
        var parts: [String] = []
        if let game = clip.game {
            parts.append(game.opponentLabel)
        } else if clip.practice != nil {
            parts.append("Practice")
        }
        if let createdAt = clip.createdAt {
            parts.append(createdAt.formatted(.dateTime.month(.abbreviated).day().year()))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Coach review

    private var hasCoachReview: Bool {
        !coachNoteText.isEmpty || drillCards.contains { !$0.ratedCategories.isEmpty }
    }

    private var coachReviewCard: some View {
        VStack(alignment: .leading, spacing: .spacingMedium) {
            HStack(spacing: .spacingSmall) {
                avatar
                VStack(alignment: .leading, spacing: 1) {
                    Text(coachNoteAuthorName ?? "Coach")
                        .font(.ppHeadline)
                        .foregroundStyle(Theme.textPrimary)
                    if let reviewedLabel {
                        Text(reviewedLabel).smallCapsLabel()
                    }
                }
                Spacer()
            }

            if !coachNoteText.isEmpty {
                Text(coachNoteText)
                    .font(.ppBody)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(ratedDrillCards) { card in
                drillRatings(card)
            }
        }
        .padding(.spacingLarge)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ppCard()
    }

    private var avatar: some View {
        Circle()
            .fill(Theme.accent.opacity(0.15))
            .frame(width: .profileSmall, height: .profileSmall)
            .overlay(
                Text(coachInitials)
                    .font(.ppSubheadline)
                    .foregroundStyle(Theme.accent)
            )
    }

    private var coachInitials: String {
        let parts = (coachNoteAuthorName ?? "Coach").split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        let result = String(letters).uppercased()
        return result.isEmpty ? "C" : result
    }

    private var reviewedLabel: String? {
        guard let updatedAt = coachNoteUpdatedAt else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Reviewed \(formatter.localizedString(for: updatedAt, relativeTo: Date()))"
    }

    private var ratedDrillCards: [DrillCard] {
        drillCards.filter { !$0.ratedCategories.isEmpty }
    }

    private func drillRatings(_ card: DrillCard) -> some View {
        VStack(alignment: .leading, spacing: .spacingSmall) {
            Divider().overlay(Theme.divider)
            Text(card.template?.displayName ?? "Review")
                .smallCapsLabel()
            ForEach(Array(card.ratedCategories.enumerated()), id: \.offset) { _, category in
                HStack {
                    Text(category.name)
                        .font(.ppFootnote)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    starRow(rating: category.rating)
                }
            }
        }
    }

    private func starRow(rating: Int) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { index in
                Image(systemName: index < rating ? "star.fill" : "star")
                    .font(.system(size: 11))
                    .foregroundStyle(index < rating ? Theme.accent : Theme.pillBorder)
            }
        }
    }

    // MARK: - Quick-cue chips

    private var cueStrip: some View {
        VStack(alignment: .leading, spacing: .spacingSmall) {
            Text("Cues").smallCapsLabel()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: .spacingSmall) {
                    ForEach(cueTags, id: \.self) { tag in
                        Text(tag)
                            .font(.ppCaptionBold)
                            .foregroundStyle(Theme.cueText)
                            .padding(.horizontal, .spacingMedium)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Theme.cueBg))
                    }
                }
            }
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 0) {
            barButton(
                title: isHighlight ? "Highlighted" : "Highlight",
                systemImage: isHighlight ? "star.fill" : "star",
                tint: isHighlight ? Theme.accent : Theme.textSecondary,
                action: onToggleHighlight
            )
            barDivider
            barButton(
                title: "Save",
                systemImage: "square.and.arrow.down",
                tint: Theme.textSecondary,
                action: onSave
            )
            if let shareURL {
                barDivider
                ShareLink(item: shareURL) {
                    barLabel(title: "Share", systemImage: "square.and.arrow.up", tint: Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, .spacingSmall)
        .background(Theme.card)
        .overlay(alignment: .top) { Rectangle().fill(Theme.divider).frame(height: 1) }
    }

    private var barDivider: some View {
        Rectangle().fill(Theme.divider).frame(width: 1, height: 24)
    }

    private func barButton(title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            barLabel(title: title, systemImage: systemImage, tint: tint)
        }
        .buttonStyle(.plain)
    }

    private func barLabel(title: String, systemImage: String, tint: Color) -> some View {
        VStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
            Text(title)
                .font(.ppCaption)
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

// MARK: - DrillCard helper

private extension DrillCard {
    /// Categories the coach actually scored (rating > 0). Unrated categories
    /// are hidden so the athlete only sees graded mechanics.
    var ratedCategories: [DrillCardCategory] {
        categories.filter { $0.rating > 0 }
    }
}
