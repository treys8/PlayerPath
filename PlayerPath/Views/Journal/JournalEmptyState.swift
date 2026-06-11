//
//  JournalEmptyState.swift
//  PlayerPath
//
//  Visual overhaul — the first-run Journal state (ghosted preview).
//  Shown only when the active athlete has zero entries. Rather than an empty
//  feed, it sells what the journal becomes: a faded, clearly-labelled EXAMPLE
//  entry plus the two lowest-friction first actions. Sport-aware — a golf
//  athlete sees a round preview, never a baseball one. Purely presentational;
//  the host (JournalView) owns the actual add/log routing via the closures.
//
//  A calmer plain fallback lives in JournalView.welcomeEmptyState if this ever
//  tests as confusing.
//

import SwiftUI

struct JournalEmptyState: View {
    let athlete: Athlete
    /// Opens the "Add a photo or video" action sheet (record / import).
    let onAdd: () -> Void
    /// Routes to the new-game/-round flow.
    let onLogEvent: () -> Void

    @Environment(\.ppAccent) private var ppAccent

    private var isGolf: Bool { athlete.sportType == .golf }
    private var eventNoun: String { isGolf ? "Round" : "Game" }

    var body: some View {
        VStack(alignment: .leading, spacing: .spacingLarge) {
            titleBlock
            ghostedSample
            caption
            actions
        }
        .padding(.horizontal, 18)
        .padding(.top, .spacingMedium)
    }

    // MARK: - Title block

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: .spacingXSmall) {
            if !eyebrowText.isEmpty {
                Text(eyebrowText).smallCapsLabel()
            }
            Text("The Journal.")
                .font(.ppTitle)                    // Fraunces serif
                .foregroundStyle(Theme.textPrimary)
            Text("Empty for now — here's where it's headed.")
                .font(.ppBody)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    /// `[ATHLETE] · [SEASON]`, dropping whichever piece is missing.
    private var eyebrowText: String {
        [athlete.name.trimmingCharacters(in: .whitespaces), athlete.activeSeason?.displayName ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    // MARK: - Ghosted sample

    /// The faded, non-interactive sample with a full-opacity EXAMPLE chip. The
    /// fade + chip + generic opponent guarantee it can't read as real content;
    /// it has no tap target at all.
    private var ghostedSample: some View {
        sampleCard
            .opacity(0.45)
            .overlay(alignment: .topTrailing) { exampleChip.padding(12) }
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Example of a journal entry")
    }

    private var exampleChip: some View {
        Text("EXAMPLE")
            .font(.ppCaptionBold)
            .tracking(0.8)
            .foregroundStyle(Theme.surface)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Theme.textPrimary))
    }

    /// A static replica of JournalEntryRow — keep the two visually in sync if the
    /// real row's anatomy changes (date rail [milestone marker in the corner] →
    /// headline → media → stat-and-counts footer).
    private var sampleCard: some View {
        VStack(alignment: .leading, spacing: .spacingMedium) {
            sampleDateRail
            Text(sampleHeadline)
                .font(.ppTitle3)
                .foregroundStyle(Theme.textPrimary)
            PPMediaTile(
                tileColor: Theme.tileNavy,
                outcome: sampleOutcomeChip,
                showsPlayButton: true
            )
            HStack(alignment: .firstTextBaseline, spacing: .spacingSmall) {
                Text(sampleSubline)
                    .font(.ppFootnote)
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: .spacingSmall)
                Text(sampleFooter).smallCapsLabel()
            }
        }
        .padding(.spacingLarge)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ppCard()
    }

    private var sampleDateRail: some View {
        HStack(spacing: 6) {
            Circle().fill(Theme.textTertiary).frame(width: 6, height: 6)
            Text(sampleDateLabel).smallCapsLabel()
            Spacer(minLength: .spacingSmall)
            PPMilestoneMarker(label: markerLabel)
        }
    }

    // MARK: - Sport-aware sample copy
    // Opponents/courses are deliberately generic placeholders ("vs Rivals",
    // "Pebble Creek") so the preview can never be mistaken for a real game.

    private var sampleDateLabel: String {
        isGolf ? "Jun 14 · Pebble Creek" : "Jun 14 · vs Rivals"
    }
    private var markerLabel: String {
        isGolf ? "Personal Best" : "Season First"
    }
    private var sampleHeadline: String {
        isGolf ? "Best round of the season" : "First home run of the season"
    }
    private var sampleSubline: String {
        isGolf ? "72 · E" : "3-for-4 · HR"
    }
    private var sampleFooter: String {
        isGolf ? "3 clips · 6 photos" : "4 clips · 11 photos"
    }
    private var sampleOutcomeChip: PPOutcomeChip {
        isGolf ? PPOutcomeChip(label: "Golf", style: .green)
               : PPOutcomeChip(label: "HR", style: .accent)
    }

    // MARK: - Caption

    private var caption: some View {
        Text("Your first \(eventNoun.lowercased()) will look like this.")
            .font(.ppSubheadline)
            .foregroundStyle(Theme.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: .spacingSmall) {
            Button(action: onAdd) {
                actionLabel("Add a photo or video", icon: "camera.fill")
                    .foregroundStyle(.white)
                    .background(Capsule().fill(ppAccent))
            }
            .buttonStyle(.plain)

            Button(action: onLogEvent) {
                actionLabel("Log a \(eventNoun)", icon: "plus.circle")
                    .foregroundStyle(Theme.textPrimary)
                    .background(Capsule().stroke(Theme.pillBorder, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, .spacingSmall)
    }

    private func actionLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.body)
            Text(title).font(.ppHeadline)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }
}
