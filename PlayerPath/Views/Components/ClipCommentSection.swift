//
//  ClipCommentSection.swift
//  PlayerPath
//
//  Reusable view that displays coach comments on a VideoClip.
//  Loads from ClipCommentService on appear.
//

import SwiftUI

struct ClipCommentSection: View {
    let clipId: String

    @State private var comments: [ClipComment] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var lastFetchDate: Date?

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
                        .font(.caption)
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
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .onTapGesture {
                    Task { await loadComments() }
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Retry loading comments")
            } else if coachComments.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "text.bubble")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("No coach feedback yet")
                        .font(.caption)
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
            // Reset state when clipId changes (e.g. cell reuse in a List)
            comments = []
            lastFetchDate = nil
            await loadComments()
            lastFetchDate = Date()
        }
    }

    private func loadComments() async {
        guard !isLoading else { return }
        isLoading = true
        loadError = nil
        do {
            comments = try await ClipCommentService.shared.fetchComments(clipId: clipId)
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
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
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Text("Coach")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.85))
                        .cornerRadius(4)
                    if let date = comment.createdAt {
                        Text(date, style: .relative)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                Text(comment.text)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.06))
        .cornerRadius(8)
    }
}
