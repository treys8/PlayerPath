//
//  VideoClipRow.swift
//  PlayerPath
//
//  Row view for displaying a video clip in a game's clip list.
//

import SwiftUI
import SwiftData

struct VideoClipRow: View {
    let clip: VideoClip
    let hasCoachingAccess: Bool
    @State private var showingVideoPlayer = false
    @State private var showingShareToFolder = false
    @State private var showingMoveSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: { showingVideoPlayer = true }) {
                HStack(spacing: 14) {
                    VideoThumbnailView(
                        clip: clip,
                        size: CGSize(width: 72, height: 72),
                        cornerRadius: 10,
                        showPlayResult: true,
                        showHighlight: false,
                        showSeason: false,
                        showContext: false,
                        showDuration: true,
                        fillsContainer: false
                    )
                    .frame(width: 72, height: 72)

                    VStack(alignment: .leading, spacing: 4) {
                        if let playResult = clip.playResult {
                            HStack(spacing: 6) {
                                Text(playResult.type.displayName)
                                    .font(.headingMedium)
                                    .foregroundColor(.primary)
                                if let speed = clip.pitchSpeed, speed > 0 {
                                    Text("\(Int(speed)) MPH")
                                        .font(.custom("Inter18pt-SemiBold", size: 11, relativeTo: .caption2))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(.orange, in: Capsule())
                                }
                            }
                        } else {
                            Text("Unrecorded Play")
                                .font(.bodyMedium)
                                .foregroundColor(.secondary)
                        }

                        if let createdAt = clip.createdAt {
                            Text(createdAt, formatter: DateFormatter.shortTime)
                                .font(.bodySmall)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Unknown Time")
                                .font(.bodySmall)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    if clip.isHighlight {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                            .font(.caption)
                    }

                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                        .font(.caption)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(clip.playResult?.type.displayName ?? "Unrecorded Play")
            .accessibilityHint("Opens the video")

            // Coach comment thread
            if let clipId = clip.firestoreId {
                ClipCommentSection(clipId: clipId)
            }
        }
        .padding(.vertical, 10)
        .contextMenu {
            Button {
                showingShareToFolder = true
            } label: {
                Label("Share to Coach Folder", systemImage: hasCoachingAccess ? "folder.badge.person.crop" : "lock.fill")
            }

            Button {
                showingMoveSheet = true
            } label: {
                Label("Move to Athlete", systemImage: "arrow.right.arrow.left")
            }
        }
        .fullScreenCover(isPresented: $showingVideoPlayer) {
            VideoPlayerView(clip: clip)
        }
        .sheet(isPresented: $showingShareToFolder) {
            ShareToCoachFolderView(clip: clip)
        }
        .sheet(isPresented: $showingMoveSheet) {
            MoveClipSheet(clip: clip)
        }
    }
}
