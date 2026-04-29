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
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "person.fill.checkmark")
                        .font(.caption)
                        .foregroundColor(.brandNavy)
                    Text(authorName ?? "Coach")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.brandNavy)
                    Text("COACH")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.brandNavy.opacity(0.2))
                        .foregroundColor(.brandNavy)
                        .cornerRadius(4)
                    Spacer()
                    if let date = updatedAt {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if canEdit, let onEdit {
                        Button(action: onEdit) {
                            Image(systemName: hasNote ? "pencil" : "plus.circle.fill")
                                .font(.subheadline)
                                .foregroundColor(.brandNavy)
                        }
                        .accessibilityLabel(hasNote ? "Edit coach note" : "Add coach note")
                    }
                }
                if hasNote {
                    Text(text)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                } else {
                    Text("Tap + to leave a plain-text note for the athlete.")
                        .font(.subheadline)
                        .italic()
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color.brandNavy.opacity(0.08))
            .cornerRadius(10)
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
    }
}
