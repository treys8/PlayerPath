//
//  VideoThumbnailView.swift
//  PlayerPath
//
//  Created by Assistant on 11/17/25.
//

import SwiftUI
import SwiftData

/// Reusable video thumbnail view with automatic loading, caching, and overlays
struct VideoThumbnailView: View {
    let clip: VideoClip
    let size: CGSize
    let cornerRadius: CGFloat
    let showPlayButton: Bool
    let showPlayResult: Bool
    let showHighlight: Bool
    
    @State private var thumbnailImage: UIImage?
    @State private var isLoadingThumbnail = false
    @Environment(\.modelContext) private var modelContext
    
    // MARK: - Initializers
    
    /// Create a thumbnail view with customizable options
    /// - Parameters:
    ///   - clip: The video clip to display
    ///   - size: The size of the thumbnail (default: 80x60)
    ///   - cornerRadius: Corner radius for the thumbnail (default: 8)
    ///   - showPlayButton: Whether to show the play button overlay (default: true)
    ///   - showPlayResult: Whether to show the play result badge (default: true)
    ///   - showHighlight: Whether to show the highlight star (default: true)
    init(
        clip: VideoClip,
        size: CGSize = CGSize(width: 80, height: 60),
        cornerRadius: CGFloat = 8,
        showPlayButton: Bool = true,
        showPlayResult: Bool = true,
        showHighlight: Bool = true
    ) {
        self.clip = clip
        self.size = size
        self.cornerRadius = cornerRadius
        self.showPlayButton = showPlayButton
        self.showPlayResult = showPlayResult
        self.showHighlight = showHighlight
    }
    
    // Convenience initializers for common sizes
    static func small(clip: VideoClip) -> VideoThumbnailView {
        VideoThumbnailView(clip: clip, size: CGSize(width: 50, height: 35), cornerRadius: 6)
    }
    
    static func medium(clip: VideoClip) -> VideoThumbnailView {
        VideoThumbnailView(clip: clip, size: CGSize(width: 80, height: 60), cornerRadius: 8)
    }
    
    static func large(clip: VideoClip) -> VideoThumbnailView {
        VideoThumbnailView(clip: clip, size: CGSize(width: 120, height: 90), cornerRadius: 10)
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Thumbnail Image
            Group {
                if let thumbnail = thumbnailImage {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size.width, height: size.height)
                        .clipped()
                } else {
                    placeholderView
                }
            }
            .cornerRadius(cornerRadius)
            .overlay(playButtonOverlay)
            
            // Play Result Badge Overlay
            if showPlayResult {
                playResultBadge
            }
            
            // Highlight Star Indicator
            if showHighlight && clip.isHighlight {
                highlightIndicator
            }
        }
        .task {
            await loadThumbnail()
        }
    }
    
    // MARK: - Subviews
    
    private var placeholderView: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .frame(width: size.width, height: size.height)
            .overlay(
                VStack(spacing: scaledSpacing(4)) {
                    if isLoadingThumbnail {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(scaledValue(0.7))
                    } else {
                        Image(systemName: "video")
                            .foregroundColor(.white)
                            .font(.system(size: scaledValue(20)))
                            .accessibilityHidden(true)
                    }
                    
                    Text(isLoadingThumbnail ? "Loading..." : "No Preview")
                        .font(.system(size: scaledValue(10)))
                        .foregroundColor(.white)
                }
            )
    }
    
    @ViewBuilder
    private var playButtonOverlay: some View {
        if showPlayButton {
            Circle()
                .fill(Color.black.opacity(0.6))
                .frame(width: scaledValue(24), height: scaledValue(24))
                .overlay(
                    Image(systemName: "play.fill")
                        .foregroundColor(.white)
                        .font(.system(size: scaledValue(10)))
                        .accessibilityHidden(true)
                )
        }
    }
    
    @ViewBuilder
    private var playResultBadge: some View {
        if let playResult = clip.playResult {
            HStack(spacing: scaledSpacing(2)) {
                playResultIcon(for: playResult.type)
                    .foregroundColor(.white)
                    .font(.system(size: scaledValue(10)))
                
                Text(playResultAbbreviation(for: playResult.type))
                    .font(.system(size: scaledValue(10)))
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
            .padding(.horizontal, scaledSpacing(6))
            .padding(.vertical, scaledSpacing(2))
            .background(playResultColor(for: playResult.type))
            .cornerRadius(scaledValue(4))
            .offset(x: scaledValue(4), y: scaledValue(-4))
        } else {
            // Unrecorded indicator
            Text("?")
                .font(.system(size: scaledValue(10)))
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: scaledValue(16), height: scaledValue(16))
                .background(Color.gray)
                .clipShape(Circle())
                .offset(x: scaledValue(4), y: scaledValue(-4))
        }
    }
    
    private var highlightIndicator: some View {
        Image(systemName: "star.fill")
            .foregroundColor(.yellow)
            .font(.system(size: scaledValue(10)))
            .background(
                Circle()
                    .fill(Color.black.opacity(0.6))
                    .frame(width: scaledValue(18), height: scaledValue(18))
            )
            .offset(x: scaledValue(-4), y: scaledValue(4))
    }
    
    // MARK: - Thumbnail Loading
    
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
            // Load thumbnail asynchronously using cache
            let image = try await ThumbnailCache.shared.loadThumbnail(at: thumbnailPath)
            thumbnailImage = image
        } catch {
            print("Failed to load thumbnail: \(error)")
            // Try to regenerate thumbnail
            await generateMissingThumbnail()
        }
        
        isLoadingThumbnail = false
    }
    
    private func generateMissingThumbnail() async {
        print("Generating missing thumbnail for clip: \(clip.fileName)")
        
        let videoURL = URL(fileURLWithPath: clip.filePath)
        let result = await VideoFileManager.generateThumbnail(from: videoURL)
        
        await MainActor.run {
            switch result {
            case .success(let thumbnailPath):
                clip.thumbnailPath = thumbnailPath
                // Save the thumbnail path to model context
                do {
                    try modelContext.save()
                } catch {
                    print("Failed to save thumbnail path: \(error)")
                }
                Task {
                    await loadThumbnail()
                }
            case .failure(let error):
                print("Failed to generate thumbnail: \(error)")
                isLoadingThumbnail = false
            }
        }
    }
    
    // MARK: - Scaling Helpers
    
    /// Scale a value based on the thumbnail size relative to the default medium size
    private func scaledValue(_ baseValue: CGFloat) -> CGFloat {
        let baseWidth: CGFloat = 80 // Medium size width
        let scale = size.width / baseWidth
        return baseValue * scale
    }
    
    private func scaledSpacing(_ baseSpacing: CGFloat) -> CGFloat {
        scaledValue(baseSpacing)
    }
    
    // MARK: - Play Result Helpers
    
    private func playResultIcon(for type: PlayResultType) -> Image {
        switch type {
        case .single:
            return Image(systemName: "1.circle.fill")
        case .double:
            return Image(systemName: "2.circle.fill")
        case .triple:
            return Image(systemName: "3.circle.fill")
        case .homeRun:
            return Image(systemName: "4.circle.fill")
        case .walk:
            return Image(systemName: "figure.walk")
        case .strikeout:
            return Image(systemName: "k.circle.fill")
        case .groundOut:
            return Image(systemName: "arrow.down.circle.fill")
        case .flyOut:
            return Image(systemName: "arrow.up.circle.fill")
        }
    }
    
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
        }
    }
    
    private func playResultColor(for type: PlayResultType) -> Color {
        switch type {
        case .single: return .green
        case .double: return .blue
        case .triple: return .orange
        case .homeRun: return .red
        case .walk: return .cyan
        case .strikeout: return .red.opacity(0.8)
        case .groundOut, .flyOut: return .gray
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Small Thumbnail") {
    VideoThumbnailView.small(clip: .preview)
        .padding()
}

#Preview("Medium Thumbnail") {
    VideoThumbnailView.medium(clip: .preview)
        .padding()
}

#Preview("Large Thumbnail") {
    VideoThumbnailView.large(clip: .preview)
        .padding()
}

// Preview helper
extension VideoClip {
    static var preview: VideoClip {
        let clip = VideoClip(fileName: "preview.mov", filePath: "/tmp/preview.mov", createdAt: Date())
        return clip
    }
}
#endif
