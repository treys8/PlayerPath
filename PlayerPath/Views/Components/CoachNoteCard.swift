//
//  CoachNoteCard.swift
//  PlayerPath
//
//  Shared coach plain-text note card. Used by CoachVideoPlayerView (with
//  edit affordance) and the athlete-side VideoPlayerView (read-only) so a
//  saved coach clip surfaces the same note in both contexts.
//

import SwiftUI

struct CoachNoteCard: View {
    let text: String
    let authorName: String?
    let updatedAt: Date?
    var canEdit: Bool = false
    var onEdit: (() -> Void)? = nil

    var body: some View {
        let hasNote = !text.isEmpty
        if hasNote || canEdit {
            VStack(alignment: .leading, spacing: .spacingSmall) {
                HStack(spacing: 6) {
                    Image(systemName: "person.fill.checkmark")
                        .font(.caption)
                        .foregroundColor(Theme.accent)
                    Text(authorName ?? "Coach")
                        .font(.ppSubheadline)
                        .foregroundColor(Theme.textPrimary)
                    Text("COACH")
                        .smallCapsLabel(color: Theme.accent)
                    Spacer()
                    if let date = updatedAt {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.ppCaption)
                            .foregroundColor(Theme.textSecondary)
                    }
                    if canEdit, let onEdit {
                        Button(action: onEdit) {
                            Image(systemName: hasNote ? "pencil" : "plus.circle.fill")
                                .font(.subheadline)
                                .foregroundColor(Theme.accent)
                        }
                        .accessibilityLabel(hasNote ? "Edit coach note" : "Add coach note")
                    }
                }
                if hasNote {
                    Text(text)
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
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .ppCard()
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
    }
}
