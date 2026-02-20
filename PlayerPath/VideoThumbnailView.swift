//
//  VideoThumbnailView.swift
//  PlayerPath
//
//  Created by Assistant on 11/17/25.
//

import SwiftUI
import SwiftData
import os

/// Reusable video thumbnail view with automatic loading, caching, and overlays
struct VideoThumbnailView: View {
    let clip: VideoClip
    let size: CGSize
    let cornerRadius: CGFloat
    let showPlayButton: Bool
    let showPlayResult: Bool
    let showHighlight: Bool
    let showSeason: Bool
    
    @State private var thumbnailImage: UIImage?
    @State private var isLoadingThumbnail = false
    @State private var loadError: Error?
    @State private var generationAttempts = 0
    @Environment(\.modelContext) private var modelContext

    // Constants
    private let maxGenerationAttempts = 2
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.playerpath", category: "VideoThumbnailView")
    
    // MARK: - Initializers
    
    /// Create a thumbnail view with customizable options
    /// - Parameters:
    ///   - clip: The video clip to display
    ///   - size: The size of the thumbnail (default: 80x60)
    ///   - cornerRadius: Corner radius for the thumbnail (default: 12)
    ///   - showPlayButton: Whether to show the play button overlay (default: true)
    ///   - showPlayResult: Whether to show the play result badge (default: true)
    ///   - showHighlight: Whether to show the highlight star (default: true)
    ///   - showSeason: Whether to show the season badge (default: false)
    init(
        clip: VideoClip,
        size: CGSize = CGSize(width: 80, height: 60),
        cornerRadius: CGFloat = 12,
        showPlayButton: Bool = true,
        showPlayResult: Bool = true,
        showHighlight: Bool = true,
        showSeason: Bool = false
    ) {
        self.clip = clip
        self.size = size
        self.cornerRadius = cornerRadius
        self.showPlayButton = showPlayButton
        self.showPlayResult = showPlayResult
        self.showHighlight = showHighlight
        self.showSeason = showSeason
    }
    
    // Convenience initializers for common sizes (16:9 landscape aspect ratio)
    static func small(clip: VideoClip) -> VideoThumbnailView {
        VideoThumbnailView(clip: clip, size: CGSize(width: 50, height: 28), cornerRadius: 8)
    }

    static func medium(clip: VideoClip) -> VideoThumbnailView {
        VideoThumbnailView(clip: clip, size: CGSize(width: 80, height: 45), cornerRadius: 12)
    }

    static func large(clip: VideoClip) -> VideoThumbnailView {
        VideoThumbnailView(clip: clip, size: CGSize(width: 120, height: 68), cornerRadius: 12)
    }

    // Portrait orientation (9:16 aspect ratio)
    static func smallPortrait(clip: VideoClip) -> VideoThumbnailView {
        VideoThumbnailView(clip: clip, size: CGSize(width: 28, height: 50), cornerRadius: 8)
    }

    static func mediumPortrait(clip: VideoClip) -> VideoThumbnailView {
        VideoThumbnailView(clip: clip, size: CGSize(width: 45, height: 80), cornerRadius: 12)
    }

    static func largePortrait(clip: VideoClip) -> VideoThumbnailView {
        VideoThumbnailView(clip: clip, size: CGSize(width: 68, height: 120), cornerRadius: 12)
    }
    
    // MARK: - Body
    
    var body: some View {
        // Defensive check to prevent zero-dimension rendering errors
        let safeSize = CGSize(
            width: max(size.width, 1),
            height: max(size.height, 1)
        )

        ZStack {
            // Thumbnail Image
            Group {
                if let thumbnail = thumbnailImage {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: safeSize.width, height: safeSize.height)
                        .clipped()
                } else {
                    placeholderView
                }
            }
            .background(Color.black)
            .cornerRadius(cornerRadius)
            .overlay(playButtonOverlay)

            // Play Result Badge Overlay (top-right, vertical layout)
            if showPlayResult {
                VStack {
                    HStack {
                        Spacer()
                        playResultBadge
                    }
                    Spacer()
                }
            }

            // Highlight Star Indicator (bottom-left, larger)
            if showHighlight && clip.isHighlight {
                VStack {
                    Spacer()
                    HStack {
                        highlightIndicator
                        Spacer()
                    }
                }
            }

            // Season Badge (top-right) - only if explicitly enabled and no play result shown
            if showSeason && !showPlayResult {
                seasonBadge
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .task {
            await loadThumbnail()
        }
        .onDisappear {
            // Reset state when view disappears
            thumbnailImage = nil
            generationAttempts = 0
            loadError = nil
            isLoadingThumbnail = false
        }
    }

    // MARK: - Accessibility

    private var accessibilityDescription: String {
        var description = "Video clip"

        if let playResult = clip.playResult {
            description += ", \(playResult.type.displayName)"
        } else {
            description += ", unrecorded play"
        }

        if clip.isHighlight {
            description += ", highlighted"
        }

        if let game = clip.game {
            description += ", from game versus \(game.opponent)"
        } else if clip.practice != nil {
            description += ", from practice session"
        }

        if loadError != nil {
            description += ", failed to load thumbnail"
        } else if isLoadingThumbnail {
            description += ", loading thumbnail"
        }

        return description
    }
    
    // MARK: - Subviews
    
    private var placeholderView: some View {
        let safeSize = CGSize(
            width: max(size.width, 1),
            height: max(size.height, 1)
        )

        return Rectangle()
            .fill(
                LinearGradient(
                    colors: playResultGradient,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: safeSize.width, height: safeSize.height)
            .overlay(
                VStack(spacing: scaledSpacing(8)) {
                    if isLoadingThumbnail {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(scaledValue(1.0))
                    } else if loadError != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                            .font(.system(size: scaledValue(24)))
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: "video")
                            .foregroundColor(.white)
                            .font(.system(size: scaledValue(24)))
                            .accessibilityHidden(true)
                    }

                    Text(placeholderText)
                        .font(.system(size: scaledValue(10)))
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
                .padding(scaledSpacing(4))
            )
    }

    /// Gradient colors based on play result type (matches HighlightCard style)
    private var playResultGradient: [Color] {
        guard let playResult = clip.playResult else {
            return [Color.gray.opacity(0.5), Color.gray.opacity(0.7)]
        }
        switch playResult.type {
        case .single:
            return [Color.green.opacity(0.5), Color.green.opacity(0.7)]
        case .double:
            return [Color.blue.opacity(0.5), Color.blue.opacity(0.7)]
        case .triple:
            return [Color.orange.opacity(0.5), Color.orange.opacity(0.7)]
        case .homeRun:
            return [Color.red.opacity(0.5), Color.red.opacity(0.7)]
        case .walk:
            return [Color.cyan.opacity(0.5), Color.cyan.opacity(0.7)]
        case .strikeout:
            return [Color.red.opacity(0.4), Color.red.opacity(0.6)]
        case .groundOut, .flyOut:
            return [Color.red.opacity(0.5), Color.red.opacity(0.7)]
        case .ball:
            return [Color.orange.opacity(0.5), Color.orange.opacity(0.7)]
        case .strike:
            return [Color.green.opacity(0.5), Color.green.opacity(0.7)]
        case .hitByPitch:
            return [Color.purple.opacity(0.5), Color.purple.opacity(0.7)]
        case .wildPitch:
            return [Color.red.opacity(0.5), Color.red.opacity(0.7)]
        }
    }

    private var placeholderText: String {
        if isLoadingThumbnail {
            return "Loading..."
        } else if loadError != nil {
            return "Failed to Load"
        } else {
            return "No Preview"
        }
    }
    
    @ViewBuilder
    private var playButtonOverlay: some View {
        if showPlayButton {
            Circle()
                .fill(Color.black.opacity(0.6))
                .frame(width: scaledValue(44), height: scaledValue(44))
                .overlay(
                    Image(systemName: "play.fill")
                        .foregroundColor(.white)
                        .font(.title3)
                        .accessibilityHidden(true)
                )
        }
    }
    
    @ViewBuilder
    private var playResultBadge: some View {
        if let playResult = clip.playResult {
            VStack(spacing: 2) {
                Image(systemName: playResultIcon(for: playResult.type))
                    .foregroundColor(.white)
                    .font(.caption)

                Text(playResultAbbreviation(for: playResult.type))
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(playResultColor(for: playResult.type))
            .cornerRadius(8)
            .padding(.top, 8)
            .padding(.trailing, 8)
            .accessibilityHidden(true) // Already described in main accessibility label
        } else {
            // Unrecorded indicator
            VStack(spacing: 2) {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundColor(.white)
                    .font(.caption)

                Text("?")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.gray)
            .cornerRadius(8)
            .padding(.top, 8)
            .padding(.trailing, 8)
            .accessibilityHidden(true) // Already described in main accessibility label
        }
    }
    
    private var highlightIndicator: some View {
        Image(systemName: "star.fill")
            .font(.title3)
            .foregroundColor(.yellow)
            .background(
                Circle()
                    .fill(Color.black.opacity(0.6))
                    .frame(width: 32, height: 32)
            )
            .padding(.bottom, 8)
            .padding(.leading, 8)
            .accessibilityHidden(true) // Already described in main accessibility label
    }

    @ViewBuilder
    private var seasonBadge: some View {
        VStack {
            HStack {
                Spacer()
                if let season = clip.season {
                    Text(season.displayName)
                        .font(.system(size: min(scaledValue(8), 12)))
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, min(scaledSpacing(4), 6))
                        .padding(.vertical, min(scaledSpacing(2), 3))
                        .background(season.isActive ? Color.blue.opacity(0.9) : Color.gray.opacity(0.9))
                        .cornerRadius(min(scaledValue(3), 5))
                        .offset(x: min(scaledValue(-4), -6), y: min(scaledValue(4), 6))
                        .accessibilityHidden(true)
                }
            }
            Spacer()
        }
    }
    
    // MARK: - Thumbnail Loading

    @MainActor
    private func loadThumbnail() async {
        // Skip if already loading or already have image
        guard !isLoadingThumbnail, thumbnailImage == nil else { return }

        // Check for cancellation
        guard !Task.isCancelled else {
            Self.logger.debug("Load cancelled before start")
            return
        }

        // Clear any previous error
        loadError = nil

        // Check if we have a thumbnail path
        guard let thumbnailPath = clip.thumbnailPath else {
            // Generate thumbnail if none exists
            await generateMissingThumbnail()
            return
        }

        isLoadingThumbnail = true

        // Check for cancellation before loading
        guard !Task.isCancelled else {
            Self.logger.debug("Load cancelled before file load")
            isLoadingThumbnail = false
            return
        }

        do {
            // Load thumbnail asynchronously using cache with downsampling for memory efficiency
            // Downsample to 2x target size for retina display quality
            let targetSize = CGSize(width: size.width * 2, height: size.height * 2)
            let image = try await ThumbnailCache.shared.loadThumbnail(at: thumbnailPath, targetSize: targetSize)

            // Check for cancellation after loading
            guard !Task.isCancelled else {
                Self.logger.debug("Load cancelled after file load")
                isLoadingThumbnail = false
                return
            }

            thumbnailImage = image
            isLoadingThumbnail = false
        } catch {
            // Check for cancellation during error handling
            guard !Task.isCancelled else {
                Self.logger.debug("Load cancelled during error handling")
                isLoadingThumbnail = false
                return
            }

            Self.logger.warning("Failed to load thumbnail: \(error.localizedDescription, privacy: .public)")
            loadError = error
            isLoadingThumbnail = false

            // Try to regenerate thumbnail only if we haven't exceeded retry limit
            if generationAttempts < maxGenerationAttempts {
                await generateMissingThumbnail()
            }
        }
    }
    
    @MainActor
    private func generateMissingThumbnail() async {
        // Increment generation attempts to prevent infinite loops
        generationAttempts += 1

        // Check for cancellation
        guard !Task.isCancelled else {
            Self.logger.debug("Generation cancelled before start")
            return
        }

        // Check retry limit to prevent infinite recursion
        guard generationAttempts <= maxGenerationAttempts else {
            Self.logger.warning("Max generation attempts reached for \(self.clip.fileName, privacy: .public)")
            loadError = NSError(
                domain: "VideoThumbnailView",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Max retry attempts exceeded"]
            )
            isLoadingThumbnail = false
            return
        }

        Self.logger.info("Generating thumbnail (attempt \(self.generationAttempts)/\(self.maxGenerationAttempts)) for \(self.clip.fileName, privacy: .public)")

        let videoURL = URL(fileURLWithPath: clip.filePath)

        // Check if video file exists before attempting generation
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            Self.logger.error("Video file does not exist at \(videoURL.path, privacy: .public)")
            loadError = NSError(
                domain: "VideoThumbnailView",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Video file not found"]
            )
            isLoadingThumbnail = false
            return
        }

        // Check for cancellation before generation
        guard !Task.isCancelled else {
            Self.logger.debug("Generation cancelled before file check")
            isLoadingThumbnail = false
            return
        }

        let result = await VideoFileManager.generateThumbnail(from: videoURL)

        // Check for cancellation after generation
        guard !Task.isCancelled else {
            Self.logger.debug("Generation cancelled after completion")
            isLoadingThumbnail = false
            return
        }

        switch result {
        case .success(let thumbnailPath):
            clip.thumbnailPath = thumbnailPath

            // Save the thumbnail path to model context
            do {
                try modelContext.save()
                Self.logger.debug("Thumbnail path saved for \(self.clip.fileName, privacy: .public)")
            } catch {
                Self.logger.error("Failed to save thumbnail path: \(error.localizedDescription, privacy: .public)")
                // Continue anyway - the thumbnail is already generated
            }

            // Load the newly generated thumbnail
            do {
                let image = try await ThumbnailCache.shared.loadThumbnail(at: thumbnailPath)
                thumbnailImage = image
                isLoadingThumbnail = false
                Self.logger.debug("Successfully loaded generated thumbnail")
            } catch {
                Self.logger.error("Failed to load generated thumbnail: \(error.localizedDescription, privacy: .public)")
                loadError = error
                isLoadingThumbnail = false
            }

        case .failure(let error):
            Self.logger.error("Failed to generate thumbnail: \(error.localizedDescription, privacy: .public)")
            loadError = error
            isLoadingThumbnail = false
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

    private func playResultIcon(for type: PlayResultType) -> String {
        switch type {
        case .single:
            return "1.circle.fill"
        case .double:
            return "2.circle.fill"
        case .triple:
            return "3.circle.fill"
        case .homeRun:
            return "4.circle.fill"
        case .walk:
            return "figure.walk"
        case .strikeout:
            return "k.circle.fill"
        case .groundOut:
            return "arrow.down.circle.fill"
        case .flyOut:
            return "arrow.up.circle.fill"
        case .ball:
            return "circle"
        case .strike:
            return "xmark.circle.fill"
        case .hitByPitch:
            return "figure.fall"
        case .wildPitch:
            return "arrow.up.right.and.arrow.down.left"
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
        case .homeRun: return .red
        case .walk: return .cyan
        case .strikeout: return .red.opacity(0.8)
        case .groundOut, .flyOut: return .red.opacity(0.8)
        case .ball: return .orange
        case .strike: return .green
        case .hitByPitch: return .purple
        case .wildPitch: return .red
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

#Preview("Portrait Thumbnails") {
    VStack(spacing: 16) {
        VideoThumbnailView.smallPortrait(clip: .preview)
        VideoThumbnailView.mediumPortrait(clip: .preview)
        VideoThumbnailView.largePortrait(clip: .preview)
    }
    .padding()
}

#Preview("Landscape vs Portrait") {
    HStack(spacing: 16) {
        VStack {
            Text("Landscape 16:9")
                .font(.caption)
            VideoThumbnailView.medium(clip: .preview)
        }
        VStack {
            Text("Portrait 9:16")
                .font(.caption)
            VideoThumbnailView.mediumPortrait(clip: .preview)
        }
    }
    .padding()
}

// Preview helper
extension VideoClip {
    static var preview: VideoClip {
        let clip = VideoClip(fileName: "preview.mov", filePath: "/tmp/preview.mov")
        clip.createdAt = Date()
        return clip
    }
}
#endif
