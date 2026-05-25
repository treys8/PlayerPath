//
//  NotesTabView.swift
//  PlayerPath
//
//  Drawings tab inside CoachVideoPlayerView — list of telestration drawings
//  (frame-specific annotations). Free-form text notes live on the coach-note
//  card above; this tab is for frame-specific drawings only.
//

import SwiftUI

struct NotesTabView: View {
    let notes: [VideoAnnotation]
    let isLoading: Bool
    var errorMessage: String? = nil
    let onDeleteNote: (VideoAnnotation) -> Void
    let onSeekToTimestamp: (Double) -> Void
    var onShowDrawing: ((VideoAnnotation) -> Void)?

    @EnvironmentObject private var authManager: ComprehensiveAuthManager

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView("Loading drawings...")
                    .frame(maxHeight: .infinity)
            } else if let error = errorMessage, notes.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 50))
                        .foregroundColor(.orange.opacity(0.7))

                    Text("Failed to Load Drawings")
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
                    Image(systemName: "pencil.tip")
                        .font(.system(size: 50))
                        .foregroundColor(.gray.opacity(0.5))

                    Text("No drawings yet")
                        .font(.headline)

                    Text("Use the pencil tool to draw on a frame.")
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
