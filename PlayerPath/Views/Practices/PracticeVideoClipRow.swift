//
//  PracticeVideoClipRow.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import SwiftUI
import SwiftData

struct PracticeVideoClipRow: View {
    let clip: VideoClip
    let hasCoachingAccess: Bool
    var onPlay: (() -> Void)? = nil
    @State private var showingShareToFolder = false
    @State private var showingNoteEditor = false
    @State private var showingMoveSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                // Square thumbnail — no overlays
                Button(action: { onPlay?() }) {
                    VideoThumbnailView(
                        clip: clip,
                        size: CGSize(width: 72, height: 72),
                        cornerRadius: 10,
                        showPlayButton: false,
                        showPlayResult: false,
                        showHighlight: false,
                        showSeason: false,
                        showContext: false
                    )
                    .frame(width: 72, height: 72)
                }
                .buttonStyle(.plain)
                .disabled(onPlay == nil)

                VStack(alignment: .leading, spacing: 2) {
                    Text(clip.createdAt.map { Self.timeFormatter.string(from: $0) } ?? "Practice Clip")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if let playResult = clip.playResult {
                        Text(playResult.type.displayName)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.brandNavy.opacity(0.1))
                            .foregroundColor(.brandNavy)
                            .cornerRadius(4)
                    }
                }

                Spacer()

                if let duration = clip.duration {
                    Text(Self.formatDuration(duration))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            // Athlete note preview
            if let note = clip.note, !note.isEmpty {
                Button {
                    showingNoteEditor = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "note.text")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .multilineTextAlignment(.leading)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }

            // Coach comment thread (loads from Firestore; empty for non-Pro users)
            if let clipId = clip.firestoreId {
                ClipCommentSection(clipId: clipId)
            }
        }
        .padding(.vertical, 10)
        .contextMenu {
            Button {
                showingNoteEditor = true
            } label: {
                Label(clip.note?.isEmpty == false ? "Edit Note" : "Add Note", systemImage: "note.text")
            }
            Button {
                showingShareToFolder = true
            } label: {
                Label("Share to Coach Folder", systemImage: hasCoachingAccess ? "folder.badge.person.crop" : "lock.fill")
            }
            Divider()
            Button {
                showingMoveSheet = true
            } label: {
                Label("Move to Athlete", systemImage: "arrow.right.arrow.left")
            }
        }
        .sheet(isPresented: $showingShareToFolder) {
            ShareToCoachFolderView(clip: clip)
        }
        .sheet(isPresented: $showingNoteEditor) {
            EditClipNoteSheet(clip: clip)
        }
        .sheet(isPresented: $showingMoveSheet) {
            MoveClipSheet(clip: clip)
        }
    }

    // "2:45 PM" — readable clip title derived from creation time
    private static let timeFormatter = DateFormatter.shortTime

    // Static duration string — "0:24", "1:03", etc.
    private static func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
