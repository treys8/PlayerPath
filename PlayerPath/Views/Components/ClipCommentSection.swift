//
//  ClipCommentSection.swift
//  PlayerPath
//
//  Reusable view that displays coach comments on a VideoClip.
//  Loads from ClipCommentService on appear.
//

import SwiftUI
import FirebaseFirestore

struct ClipCommentSection: View {
    let clipId: String

    @State private var comments: [ClipComment] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var listener: ListenerRegistration?

    var coachComments: [ClipComment] {
        comments.filter { $0.isCoachComment }
    }

    var body: some View {
        Group {
            if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading comments...")
                        .font(.bodySmall)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            } else if loadError != nil {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text("Couldn't load comments")
                        .font(.bodySmall)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .onTapGesture {
                    loadError = nil
                    attachListener()
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Retry loading comments")
            } else if coachComments.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "text.bubble")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("No coach feedback yet")
                        .font(.bodySmall)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(coachComments) { comment in
                        CoachCommentRow(comment: comment)
                    }
                }
            }
        }
        .task(id: clipId) {
            // Tear down any prior listener synchronously before awaits so a
            // cancelled previous task can't resurrect a stale-clipId listener
            // after this task has already attached the new one.
            listener?.remove()
            listener = nil
            comments = []
            isLoading = true
            loadError = nil
            // Seed from one-shot fetch for instant render, then attach listener
            // for live updates while the view is visible.
            do {
                comments = try await ClipCommentService.shared.fetchComments(clipId: clipId)
            } catch {
                loadError = error.localizedDescription
            }
            isLoading = false
            attachListener()
        }
        .onDisappear {
            listener?.remove()
            listener = nil
        }
    }

    private func attachListener() {
        listener?.remove()
        listener = ClipCommentService.shared.listenToComments(clipId: clipId) { updated in
            comments = updated
            loadError = nil
        }
    }
}

// MARK: - Individual coach comment row

private struct CoachCommentRow: View {
    let comment: ClipComment

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "person.badge.shield.checkmark")
                .font(.caption)
                .foregroundColor(.orange)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(comment.authorName)
                        .font(.custom("Inter18pt-SemiBold", size: 12, relativeTo: .caption))
                        .foregroundColor(.primary)
                    Text("Coach")
                        .font(.labelSmall)
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.85))
                        .cornerRadius(4)
                    if let date = comment.createdAt {
                        Text(date, style: .relative)
                            .font(.labelSmall)
                            .foregroundColor(.secondary)
                    }
                }
                Text(comment.text)
                    .font(.bodySmall)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.06))
        .cornerRadius(8)
    }
}
