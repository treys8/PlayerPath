//
//  CoachReviewActionsBar.swift
//  PlayerPath
//
//  Visual overhaul — the coach authoring actions block on
//  CoachVideoPlayerView. Coach-only. Composes three things, all backed by
//  existing services (no new Firestore fields):
//
//    • Inline quick-cue picker — accent-fill when applied, dashed outline when
//      not, plus a "+ add" chip. Toggling persists the cue into the video's
//      `tags` (updateVideoTags); "+ add" creates a reusable QuickCue.
//    • "Done reviewing" — the coach's explicit review-complete confirmation.
//      Feedback (notes / drawings / drill cards) is already delivered to the
//      athlete by Cloud Functions as it's authored, and the clip auto-marks
//      reviewed on open, so this re-affirms the reviewed mark and confirms with
//      a toast. It does not itself send or notify.
//    • View receipt — read-only "Seen" / "Not seen yet" from `video.viewedBy`,
//      written by the athlete when they open the clip.
//
//  Purely presentational: all mutation happens through the passed-in closures.
//

import SwiftUI

struct CoachReviewActionsBar: View {
    let athleteName: String
    /// The coach's reusable quick-cue templates.
    let quickCues: [QuickCue]
    /// Cue texts currently applied to this clip (a subset of the video's tags).
    let appliedCues: [String]
    /// Timestamp the athlete last viewed this clip, if ever.
    let viewedAt: Date?
    var isSending: Bool = false

    var onToggleCue: (String) -> Void
    var onAddCue: (String) -> Void
    var onSend: () -> Void

    @State private var showingAddCue = false
    @State private var newCueText = ""
    @Environment(\.ppAccent) private var ppAccent

    var body: some View {
        VStack(alignment: .leading, spacing: .spacingMedium) {
            cuePicker
            sendBlock
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

    // MARK: - Cue picker

    /// Cue texts to show: the coach's templates plus any already-applied cue
    /// that isn't a saved template (deduped, order-stable).
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
                .background(
                    Capsule().fill(selected ? ppAccent : Color.clear)
                )
                .overlay(
                    Capsule().strokeBorder(
                        selected ? Color.clear : Theme.pillBorder,
                        style: StrokeStyle(lineWidth: 1, dash: selected ? [] : [4, 3])
                    )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Send + receipt

    private var sendBlock: some View {
        VStack(spacing: 6) {
            Button(action: onSend) {
                HStack(spacing: .spacingSmall) {
                    if isSending {
                        ProgressView().tint(Theme.surface)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    Text("Done reviewing")
                }
                .font(.ppHeadline)
                .foregroundStyle(Theme.surface)
                .frame(maxWidth: .infinity)
                .padding(.vertical, .spacingMedium)
                .background(Capsule().fill(ppAccent))
            }
            .buttonStyle(.plain)
            .disabled(isSending)

            Text("You'll see when \(athleteName) opens it")
                .font(.ppCaption)
                .foregroundStyle(Theme.textTertiary)

            receiptLine
        }
    }

    @ViewBuilder
    private var receiptLine: some View {
        if let viewedAt {
            HStack(spacing: 5) {
                Image(systemName: "eye.fill").font(.system(size: 10))
                Text("Seen \(relative(viewedAt))")
            }
            .font(.ppCaptionBold)
            .foregroundStyle(Theme.chipGreenText)
            .padding(.horizontal, .spacingMedium)
            .padding(.vertical, 5)
            .background(Capsule().fill(Theme.chipGreenBg))
        } else {
            Text("Not seen yet")
                .smallCapsLabel(color: Theme.textTertiary)
        }
    }

    private func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
