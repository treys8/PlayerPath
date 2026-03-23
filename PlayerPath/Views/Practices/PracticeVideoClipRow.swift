//
//  PracticeVideoClipRow.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import SwiftUI
import SwiftData
import UIKit

struct PracticeVideoClipRow: View {
    let clip: VideoClip
    let hasCoachingAccess: Bool
    var onPlay: (() -> Void)? = nil
    @State private var showingShareToFolder = false
    @State private var showingNoteEditor = false
    @State private var thumbnailImage: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                // Thumbnail — tappable play button
                Button(action: { onPlay?() }) {
                    Group {
                        if let uiImage = thumbnailImage {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Image(systemName: "video.fill")
                                .foregroundColor(.brandNavy)
                                .font(.title3)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.brandNavy.opacity(0.1))
                        }
                    }
                    .frame(width: 56, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(alignment: .center) {
                        Image(systemName: "play.fill")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(Circle().fill(.black.opacity(0.55)))
                    }
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
        .padding(.vertical, 4)
        .contextMenu {
            Button {
                showingNoteEditor = true
            } label: {
                Label(clip.note?.isEmpty == false ? "Edit Note" : "Add Note", systemImage: "note.text")
            }
            if AppFeatureFlags.isCoachEnabled {
                Button {
                    showingShareToFolder = true
                } label: {
                    Label("Share to Coach Folder", systemImage: hasCoachingAccess ? "folder.badge.person.fill" : "lock.fill")
                }
            }
        }
        .sheet(isPresented: $showingShareToFolder) {
            ShareToCoachFolderView(clip: clip)
        }
        .sheet(isPresented: $showingNoteEditor) {
            EditClipNoteSheet(clip: clip)
        }
        .task {
            // Load thumbnail asynchronously instead of synchronously in the view body
            guard thumbnailImage == nil, let thumbPath = clip.thumbnailPath else { return }
            let size = CGSize(width: 112, height: 80)
            if let image = try? await ThumbnailCache.shared.loadThumbnail(at: thumbPath, targetSize: size) {
                thumbnailImage = image
            }
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
