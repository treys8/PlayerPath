//
//  NotesTabView.swift
//  PlayerPath
//
//  Feedback tab inside CoachVideoPlayerView — list of timestamped notes
//  with an "Add Feedback" entry point.
//

import SwiftUI

struct NotesTabView: View {
    let notes: [VideoAnnotation]
    let isLoading: Bool
    var errorMessage: String? = nil
    let onAddNote: () -> Void
    let onDeleteNote: (VideoAnnotation) -> Void
    let onSeekToTimestamp: (Double) -> Void
    var onShowDrawing: ((VideoAnnotation) -> Void)?
    let canComment: Bool

    @EnvironmentObject private var authManager: ComprehensiveAuthManager

    var body: some View {
        VStack(spacing: 0) {
            if canComment {
                Button(action: onAddNote) {
                    Label("Add Feedback", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.brandNavy.opacity(0.1))
                        .foregroundColor(.brandNavy)
                }
            }

            Divider()

            if isLoading {
                ProgressView("Loading feedback...")
                    .frame(maxHeight: .infinity)
            } else if let error = errorMessage, notes.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 50))
                        .foregroundColor(.orange.opacity(0.7))

                    Text("Failed to Load Feedback")
                        .font(.headline)

                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxHeight: .infinity)
            } else if notes.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "note.text")
                        .font(.system(size: 50))
                        .foregroundColor(.gray.opacity(0.5))

                    Text("No feedback yet")
                        .font(.headline)

                    Text("Add timestamped feedback markers for this video.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(notes) { note in
                            NoteCardView(
                                note: note,
                                canDelete: note.userID == authManager.userID,
                                onDelete: {
                                    onDeleteNote(note)
                                },
                                onSeek: {
                                    if note.isDrawing, let onShowDrawing {
                                        onShowDrawing(note)
                                    } else {
                                        onSeekToTimestamp(note.timestamp)
                                    }
                                    Haptics.light()
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
    }
}
