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
    @State private var thumbnailImage: UIImage?
    @State private var isLoadingThumbnail = false
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: { showingVideoPlayer = true }) {
                HStack(spacing: 14) {
                    // Square thumbnail — no overlays
                    Group {
                        if let thumbnail = thumbnailImage {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 72, height: 72)
                                .clipped()
                        } else {
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 72, height: 72)
                                .overlay(
                                    Group {
                                        if isLoadingThumbnail {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .gray))
                                                .scaleEffect(0.7)
                                        } else {
                                            Image(systemName: "video.fill")
                                                .foregroundColor(.gray)
                                                .font(.title3)
                                        }
                                    }
                                )
                        }
                    }
                    .cornerRadius(10)

                    VStack(alignment: .leading, spacing: 4) {
                        if let playResult = clip.playResult {
                            HStack(spacing: 6) {
                                Text(playResult.type.displayName)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                if let speed = clip.pitchSpeed, speed > 0 {
                                    Text("\(Int(speed)) MPH")
                                        .font(.caption2)
                                        .fontWeight(.semibold)
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
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        if let createdAt = clip.createdAt {
                            Text(createdAt, formatter: DateFormatter.shortTime)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Unknown Time")
                                .font(.caption)
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
            if AppFeatureFlags.isCoachEnabled {
                Button {
                    showingShareToFolder = true
                } label: {
                    Label("Share to Coach Folder", systemImage: hasCoachingAccess ? "folder.badge.person.crop" : "lock.fill")
                }
            }

            Button {
                showingMoveSheet = true
            } label: {
                Label("Move to Athlete", systemImage: "arrow.right.arrow.left")
            }
        }
        .task {
            await loadThumbnail()
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

    @MainActor
    private func loadThumbnail() async {
        guard !isLoadingThumbnail, thumbnailImage == nil else { return }

        isLoadingThumbnail = true

        // Try loading from existing path first
        if let thumbnailPath = clip.thumbnailPath {
            if let image = try? await ThumbnailCache.shared.loadThumbnail(at: thumbnailPath, targetSize: .thumbnailSmall) {
                thumbnailImage = image
                isLoadingThumbnail = false
                return
            }
        }

        // Generate thumbnail from video file
        let result = await VideoFileManager.generateThumbnail(from: clip.resolvedFileURL)

        switch result {
        case .success(let thumbnailPath):
            clip.thumbnailPath = thumbnailPath
            ErrorHandlerService.shared.saveContext(modelContext, caller: "VideoClipRow.generateThumbnail")

            if let image = try? await ThumbnailCache.shared.loadThumbnail(at: thumbnailPath, targetSize: .thumbnailSmall) {
                thumbnailImage = image
            }
        case .failure:
            break
        }

        isLoadingThumbnail = false
    }

}
