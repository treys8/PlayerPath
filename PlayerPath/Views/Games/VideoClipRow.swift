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
    @State private var thumbnailImage: UIImage?
    @State private var isLoadingThumbnail = false
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Button(action: { showingVideoPlayer = true }) {
            HStack {
                // Enhanced thumbnail with overlay - using the same logic as VideoClipListItem
                ZStack(alignment: .bottomLeading) {
                    // Thumbnail Image
                    Group {
                        if let thumbnail = thumbnailImage {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 50, height: 35)
                                .clipped()
                        } else {
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 50, height: 35)
                                .overlay(
                                    VStack(spacing: 2) {
                                        if isLoadingThumbnail {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                                .scaleEffect(0.5)
                                        } else {
                                            Image(systemName: "video.fill")
                                                .foregroundColor(.white)
                                                .font(.caption)
                                        }

                                        if !isLoadingThumbnail {
                                            Text("No Preview")
                                                .font(.system(size: 8))
                                                .foregroundColor(.white)
                                        }
                                    }
                                )
                        }
                    }
                    .cornerRadius(6)
                    .overlay(
                        // Play button overlay
                        Circle()
                            .fill(Color.black.opacity(0.6))
                            .frame(width: 16, height: 16)
                            .overlay(
                                Image(systemName: "play.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: 8))
                            )
                    )

                    // Play result badge
                    if let playResult = clip.playResult {
                        Text(playResultAbbreviation(for: playResult.type))
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(playResultColor(for: playResult.type))
                            .cornerRadius(3)
                            .offset(x: 2, y: -2)
                    } else {
                        Text("?")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .frame(width: 12, height: 12)
                            .background(Color.gray)
                            .clipShape(Circle())
                            .offset(x: 2, y: -2)
                    }

                    // Highlight indicator
                    if clip.isHighlight {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                            .font(.system(size: 8))
                            .background(Circle().fill(Color.black.opacity(0.6)).frame(width: 12, height: 12))
                            .offset(x: -2, y: 2)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    if let playResult = clip.playResult {
                        Text(String(describing: playResult.type))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    } else {
                        Text("Unrecorded Play")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    if let createdAt = clip.createdAt {
                        Text(createdAt, formatter: DateFormatter.shortTime)
                    } else {
                        Text("Unknown Time")
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
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(clip.playResult?.type.displayName ?? "Unrecorded Play")
        .accessibilityHint("Opens the video")
        .contextMenu {
            if hasCoachingAccess {
                Button {
                    showingShareToFolder = true
                } label: {
                    Label("Share to Coach Folder", systemImage: "folder.badge.person.fill")
                }
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
    }

    @MainActor
    private func loadThumbnail() async {
        // Skip if already loading or already have image
        guard !isLoadingThumbnail, thumbnailImage == nil else { return }

        // Check if we have a thumbnail path
        guard let thumbnailPath = clip.thumbnailPath else {
            // Generate thumbnail if none exists
            await generateMissingThumbnail()
            return
        }

        isLoadingThumbnail = true

        do {
            // Load thumbnail asynchronously using the same cache system
            let size = CGSize(width: 160, height: 90)
            let image = try await ThumbnailCache.shared.loadThumbnail(at: thumbnailPath, targetSize: size)
            thumbnailImage = image
        } catch {
            // Try to regenerate thumbnail
            await generateMissingThumbnail()
        }

        isLoadingThumbnail = false
    }

    private func generateMissingThumbnail() async {

        let videoURL = clip.resolvedFileURL
        let result = await VideoFileManager.generateThumbnail(from: videoURL)

        await MainActor.run {
            switch result {
            case .success(let thumbnailPath):
                clip.thumbnailPath = thumbnailPath
                do {
                    try modelContext.save()
                } catch {
                    ErrorHandlerService.shared.handle(error, context: "GamesView.saveThumbnailPath", showAlert: false)
                }
                isLoadingThumbnail = false
            case .failure(_):
                isLoadingThumbnail = false
            }
        }
        // Load through the cache (off main thread) after saving the path
        if case .success(let thumbnailPath) = result {
            let size = CGSize(width: 160, height: 90)
            if let image = try? await ThumbnailCache.shared.loadThumbnail(at: thumbnailPath, targetSize: size) {
                await MainActor.run { thumbnailImage = image }
            }
        }
    }

    // Helper functions for styling
    private func playResultAbbreviation(for type: PlayResultType) -> String {
        switch type {
        case .single: return "1B"
        case .double: return "2B"
        case .triple: return "3B"
        case .homeRun: return "HR"
        case .walk: return "BB"
        case .strikeout: return "K"
        case .groundOut: return "GO"
        case .flyOut: return "FO"
        case .ball: return "B"
        case .strike: return "S"
        case .hitByPitch: return "HBP"
        case .wildPitch: return "WP"
        }
    }

    private func playResultColor(for type: PlayResultType) -> Color {
        switch type {
        case .single: return .green
        case .double: return .blue
        case .triple: return .orange
        case .homeRun: return .gold
        case .walk: return .cyan
        case .strikeout: return .red
        case .groundOut, .flyOut: return .red
        case .ball: return .orange
        case .strike: return .green
        case .hitByPitch: return .purple
        case .wildPitch: return .red
        }
    }
}
