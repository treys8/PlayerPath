//
//  CoachFeedbackCard.swift
//  PlayerPath
//
//  Single consolidated "coach feedback" card on CoachVideoPlayerView, coach-
//  editing side only. Merges what used to be two stacked cards — the coach
//  plain-text note (CoachNoteCard's editing layout) and the cue picker /
//  "Done reviewing" / view-receipt block (CoachReviewActionsBar) — into one
//  card so the portrait-phone layout isn't several full-padded slabs.
//
//  The athlete read-only side is unchanged: it keeps the separate CoachNoteCard
//  + read-only cue strip in CoachVideoPlayerView's coachNoteSection `else` branch.
//
//  Purely presentational — all mutation flows through the passed-in closures.
//  "Done reviewing" is confirm-only: the clip auto-marks reviewed on open and
//  feedback delivers via Cloud Functions as it's authored, so the button is a
//  compact re-affirm, not a full-width send action.
//

import SwiftUI

struct CoachFeedbackCard: View {
    let authorName: String?
    let noteText: String
    let updatedAt: Date?

    /// The coach's reusable quick-cue templates.
    let quickCues: [QuickCue]
    /// Cue texts currently applied to this clip (a subset of the video's tags).
    let appliedCues: [String]
    /// When the athlete last opened this clip, if ever.
    let viewedAt: Date?
    var isSending: Bool = false

    var onEditNote: () -> Void
    var onToggleCue: (String) -> Void
    var onAddCue: (String) -> Void
    /// Confirm-only "Done reviewing". Pass `nil` to hide the button entirely —
    /// e.g. when the clip is still an unpublished draft and the real action is
    /// "Share Now" on the publish bar, so "Done reviewing" would mislead.
    var onDone: (() -> Void)?

    @State private var showingAddCue = false
    @State private var newCueText = ""
    @Environment(\.ppAccent) private var ppAccent

    private var hasNote: Bool { !noteText.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: .spacingMedium) {
            header
            noteBody
            Divider()
            cuePicker
            doneRow
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .ppCard()
        .padding(.horizontal)
        .padding(.vertical, 6)
        .alert("Add cue", isPresented: $showingAddCue) {
            TextField("e.g. Stay back", text: $newCueText)
            Button("Add") {
                let trimmed = newCueText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { onAddCue(trimmed) }
                newCueText = ""
            }
            Button("Cancel", role: .cancel) { newCueText = "" }
        } message: {
            Text("Save a short coaching cue you can reuse and tap to attach to clips.")
        }
    }

    // MARK: - Header (coach identity + receipt + edit)

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "person.fill.checkmark")
                .font(.caption)
                .foregroundColor(ppAccent)
            Text(authorName ?? "Coach")
                .font(.ppSubheadline)
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1)
            Text("COACH")
                .smallCapsLabel(color: ppAccent)
            Spacer(minLength: 8)
            receiptBadge
            Button(action: onEditNote) {
                Image(systemName: hasNote ? "pencil" : "plus.circle.fill")
                    .font(.subheadline)
                    .foregroundColor(ppAccent)
            }
            .accessibilityLabel(hasNote ? "Edit coach note" : "Add coach note")
        }
    }

    /// Compact "Seen" pill, folded into the header so the receipt no longer
    /// needs its own line. Absent when the athlete hasn't opened the clip.
    @ViewBuilder
    private var receiptBadge: some View {
        if let viewedAt {
            HStack(spacing: 4) {
                Image(systemName: "eye.fill").font(.system(size: 9))
                Text("Seen \(relative(viewedAt))")
            }
            .font(.ppCaptionBold)
            .foregroundStyle(Theme.chipGreenText)
            .padding(.horizontal, .spacingSmall)
            .padding(.vertical, 4)
            .background(Capsule().fill(Theme.chipGreenBg))
        }
    }

    private var noteBody: some View {
        Group {
            if hasNote {
                Text(noteText)
                    .font(.ppBody)
                    .foregroundColor(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Tap + to leave a plain-text note for the athlete.")
                    .font(.ppBody)
                    .italic()
                    .foregroundColor(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Cues

    /// Coach templates plus any already-applied cue that isn't a saved template
    /// (deduped, order-stable).
    private var cueOptions: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for cue in quickCues where seen.insert(cue.text).inserted {
            result.append(cue.text)
        }
        for tag in appliedCues where seen.insert(tag).inserted {
            result.append(tag)
        }
        return result
    }

    private var cuePicker: some View {
        VStack(alignment: .leading, spacing: .spacingSmall) {
            Text("Cues").smallCapsLabel()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: .spacingSmall) {
                    addChip
                    ForEach(cueOptions, id: \.self) { cue in
                        cueChip(cue, selected: appliedCues.contains(cue))
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var addChip: some View {
        Button {
            showingAddCue = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                Text("Add")
            }
            .font(.ppCaptionBold)
            .foregroundStyle(ppAccent)
            .padding(.horizontal, .spacingMedium)
            .padding(.vertical, 7)
            .overlay(
                Capsule().strokeBorder(ppAccent, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
        }
        .buttonStyle(.plain)
    }

    private func cueChip(_ text: String, selected: Bool) -> some View {
        Button {
            onToggleCue(text)
        } label: {
            Text(text)
                .font(.ppCaptionBold)
                .foregroundStyle(selected ? Theme.surface : Theme.textSecondary)
                .padding(.horizontal, .spacingMedium)
                .padding(.vertical, 7)
                .background(Capsule().fill(selected ? ppAccent : Color.clear))
                .overlay(
                    Capsule().strokeBorder(
                        selected ? Color.clear : Theme.pillBorder,
                        style: StrokeStyle(lineWidth: 1, dash: selected ? [] : [4, 3])
                    )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Done (compact, confirm-only)

    @ViewBuilder
    private var doneRow: some View {
        if let onDone {
            HStack {
                Spacer()
                Button(action: onDone) {
                    HStack(spacing: 6) {
                        if isSending {
                            ProgressView().tint(Theme.surface).scaleEffect(0.85)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                        }
                        Text("Done reviewing")
                    }
                    .font(.ppSubheadline.weight(.semibold))
                    .foregroundStyle(Theme.surface)
                    .padding(.horizontal, .spacingLarge)
                    .padding(.vertical, .spacingSmall)
                    .background(Capsule().fill(ppAccent))
                }
                .buttonStyle(.plain)
                .disabled(isSending)
                .accessibilityLabel("Done reviewing")
            }
        }
    }

    private func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
