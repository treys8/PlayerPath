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
    ///   - cornerRadius: Corner radius for the thumbnail (default: 8)
    ///   - showPlayButton: Whether to show the play button overlay (default: true)
    ///   - showPlayResult: Whether to show the play result badge (default: true)
    ///   - showHighlight: Whether to show the highlight star (default: true)
    ///   - showSeason: Whether to show the season badge (default: true)
    init(
        clip: VideoClip,
        size: CGSize = CGSize(width: 80, height: 60),
        cornerRadius: CGFloat = 8,
        showPlayButton: Bool = true,
        showPlayResult: Bool = true,
        showHighlight: Bool = true,
        showSeason: Bool = true
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
        VideoThumbnailView(clip: clip, size: CGSize(width: 50, height: 28), cornerRadius: 6)
    }

    static func medium(clip: VideoClip) -> VideoThumbnailView {
        VideoThumbnailView(clip: clip, size: CGSize(width: 80, height: 45), cornerRadius: 8)
    }

    static func large(clip: VideoClip) -> VideoThumbnailView {
        VideoThumbnailView(clip: clip, size: CGSize(width: 120, height: 68), cornerRadius: 10)
    }

    // Portrait orientation (9:16 aspect ratio)
    static func smallPortrait(clip: VideoClip) -> VideoThumbnailView {
        VideoThumbnailView(clip: clip, size: CGSize(width: 28, height: 50), cornerRadius: 6)
    }

    static func mediumPortrait(clip: VideoClip) -> VideoThumbnailView {
        VideoThumbnailView(clip: clip, size: CGSize(width: 45, height: 80), cornerRadius: 8)
    }

    static func largePortrait(clip: VideoClip) -> VideoThumbnailView {
        VideoThumbnailView(clip: clip, size: CGSize(width: 68, height: 120), cornerRadius: 10)
    }
    
    // MARK: - Body
    
    var body: some View {
        // Defensive check to prevent zero-dimension rendering errors
        let safeSize = CGSize(
            width: max(size.width, 1),
            height: max(size.height, 1)
        )

        ZStack(alignment: .bottomLeading) {
            // Thumbnail Image
            Group {
                if let thumbnail = thumbnailImage {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: safeSize.width, height: safeSize.height)
                } else {
                    placeholderView
                }
            }
            .background(Color.black.opacity(0.1)) // Background for letterboxing
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

            // Season Badge (top-right)
            if showSeason {
                seasonBadge
            }
        }
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
            .fill(Color.gray.opacity(0.3))
            .frame(width: safeSize.width, height: safeSize.height)
            .overlay(
                VStack(spacing: scaledSpacing(4)) {
                    if isLoadingThumbnail {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(scaledValue(0.7))
                    } else if loadError != nil {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.yellow)
                            .font(.system(size: scaledValue(20)))
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: "video")
                            .foregroundColor(.white)
                            .font(.system(size: scaledValue(20)))
                            .accessibilityHidden(true)
                    }

                    Text(placeholderText)
                        .font(.system(size: scaledValue(10)))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                }
                .padding(scaledSpacing(4))
            )
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
                    .font(.system(size: min(scaledValue(10), 14)))

                Text(playResultAbbreviation(for: playResult.type))
                    .font(.system(size: min(scaledValue(10), 14)))
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
            .padding(.horizontal, min(scaledSpacing(6), 8))
            .padding(.vertical, min(scaledSpacing(2), 3))
            .background(playResultColor(for: playResult.type))
            .cornerRadius(min(scaledValue(4), 6))
            .offset(x: min(scaledValue(4), 6), y: min(scaledValue(-4), -6))
            .accessibilityHidden(true) // Already described in main accessibility label
        } else {
            // Unrecorded indicator
            Text("?")
                .font(.system(size: min(scaledValue(10), 14)))
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: min(scaledValue(16), 20), height: min(scaledValue(16), 20))
                .background(Color.gray)
                .clipShape(Circle())
                .offset(x: min(scaledValue(4), 6), y: min(scaledValue(-4), -6))
                .accessibilityHidden(true) // Already described in main accessibility label
        }
    }
    
    private var highlightIndicator: some View {
        Image(systemName: "star.fill")
            .foregroundColor(.yellow)
            .font(.system(size: scaledValue(10)))
            .padding(scaledValue(4))
            .background(
                Circle()
                    .fill(Color.black.opacity(0.6))
            )
            .offset(x: scaledValue(-4), y: scaledValue(4))
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
            // Load thumbnail asynchronously using cache
            let image = try await ThumbnailCache.shared.loadThumbnail(at: thumbnailPath)

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
