//
//  VideoThumbnailView.swift
//  PlayerPath
//

import SwiftUI
import SwiftData
import os

/// Reusable video thumbnail view with automatic loading, caching, and overlays.
struct VideoThumbnailView: View {
    let clip: VideoClip
    let size: CGSize
    let cornerRadius: CGFloat
    let showPlayButton: Bool
    let showPlayResult: Bool
    let showHighlight: Bool
    let showSeason: Bool
    let showContext: Bool
    let fillsContainer: Bool

    @State private var thumbnailImage: UIImage?
    @State private var isLoadingThumbnail = false
    @State private var loadError: Error?
    @State private var generationAttempts = 0
    @Environment(\.modelContext) private var modelContext

    private let maxGenerationAttempts = 2
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.playerpath", category: "VideoThumbnailView")
    private static var activeGenerations = 0
    private static let maxConcurrentGenerations = 4

    // MARK: - Initializers

    init(
        clip: VideoClip,
        size: CGSize = .thumbnailSmall,
        cornerRadius: CGFloat = 12,
        showPlayButton: Bool = true,
        showPlayResult: Bool = true,
        showHighlight: Bool = true,
        showSeason: Bool = false,
        showContext: Bool = true,
        fillsContainer: Bool = false
    ) {
        self.clip = clip
        self.size = size
        self.cornerRadius = cornerRadius
        self.showPlayButton = showPlayButton
        self.showPlayResult = showPlayResult
        self.showHighlight = showHighlight
        self.showSeason = showSeason
        self.showContext = showContext
        self.fillsContainer = fillsContainer
    }

    // Convenience initializers for common landscape sizes (16:9)
    static func small(clip: VideoClip) -> VideoThumbnailView {
        VideoThumbnailView(clip: clip, size: CGSize(width: 50, height: 28), cornerRadius: 8)
    }

    static func medium(clip: VideoClip) -> VideoThumbnailView {
        VideoThumbnailView(clip: clip, size: CGSize(width: 80, height: 45), cornerRadius: 12)
    }

    static func large(clip: VideoClip) -> VideoThumbnailView {
        VideoThumbnailView(clip: clip, size: CGSize(width: 120, height: 68), cornerRadius: 12)
    }

    // MARK: - Body

    var body: some View {
        let safeSize = CGSize(width: max(size.width, 1), height: max(size.height, 1))

        ZStack {
            // Thumbnail image with fade-in transition
            ZStack {
                if let thumbnail = thumbnailImage {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(
                            minWidth: fillsContainer ? 0 : safeSize.width,
                            maxWidth: fillsContainer ? .infinity : safeSize.width,
                            minHeight: fillsContainer ? 0 : safeSize.height,
                            maxHeight: fillsContainer ? .infinity : safeSize.height
                        )
                        .clipped()
                        .transition(.opacity)
                } else {
                    if fillsContainer {
                        placeholder(size: safeSize)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .transition(.opacity)
                    } else {
                        placeholder(size: safeSize)
                            .transition(.opacity)
                    }
                }
            }
            .animation(.easeIn(duration: 0.2), value: thumbnailImage == nil)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(playButtonOverlay)

            // Play result badge (top-right) — or untagged dot when play result missing
            if showPlayResult {
                if let playResult = clip.playResult {
                    VStack {
                        HStack {
                            Spacer()
                            playResultBadge(for: playResult.type)
                        }
                        Spacer()
                    }
                } else {
                    VStack {
                        HStack {
                            Spacer()
                            untaggedDot
                        }
                        Spacer()
                    }
                }
            }

            // Bottom-right indicators (highlight star / note icon)
            VStack {
                Spacer()
                HStack(spacing: 4) {
                    Spacer()
                    if let note = clip.note, !note.isEmpty {
                        noteIndicator
                    }
                    if showHighlight && clip.isHighlight {
                        highlightIndicator
                    }
                }
            }

            // Season badge (top-right, only when play result is hidden)
            if showSeason && !showPlayResult {
                seasonBadge
            }

            // Context label (bottom-left): game opponent or "Practice" — hidden for untagged clips
            if showContext, contextLabel != nil {
                VStack {
                    Spacer()
                    HStack {
                        contextBadge
                        Spacer()
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
        .accessibilityIgnoresInvertColors()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .task {
            await loadThumbnail()
        }
        .onChange(of: clip.thumbnailPath) { _, newPath in
            guard newPath != nil, thumbnailImage == nil else { return }
            // Reset stale error state so the reload gets a clean slate
            loadError = nil
            generationAttempts = 0
            isLoadingThumbnail = false
            Task { await loadThumbnail() }
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
        if clip.isHighlight { description += ", highlighted" }
        if let game = clip.game {
            description += ", from game versus \(game.opponent)"
        } else if clip.practice != nil {
            description += ", from practice session"
        }
        if loadError != nil { description += ", failed to load thumbnail" }
        else if isLoadingThumbnail { description += ", loading thumbnail" }
        return description
    }

    // MARK: - Subviews

    private func placeholder(size: CGSize) -> some View {
        Rectangle()
            .fill(LinearGradient(colors: playResultGradient, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size.width, height: size.height)
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
                        Image(systemName: "video.fill")
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

    private var playResultGradient: [Color] {
        guard let playResult = clip.playResult else {
            return [Color.gray.opacity(0.5), Color.gray.opacity(0.7)]
        }
        let base = playResult.type.badgeColor
        return [base.opacity(0.5), base.opacity(0.7)]
    }

    private var placeholderText: String {
        if isLoadingThumbnail { return "Loading..." }
        else if loadError != nil { return "Failed to Load" }
        else { return contextLabel ?? "No Preview" }
    }

    @ViewBuilder
    private var playButtonOverlay: some View {
        if showPlayButton {
            let circleSize = min(scaledValue(44), 44)
            let iconSize = min(scaledValue(14), 15)
            Circle()
                .fill(.black.opacity(0.35))
                .background(.ultraThinMaterial, in: Circle())
                .frame(width: circleSize, height: circleSize)
                .overlay(
                    Image(systemName: "play.fill")
                        .foregroundColor(.white)
                        .font(.system(size: iconSize))
                        .offset(x: 1)
                        .accessibilityHidden(true)
                )
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
        }
    }

    private func playResultBadge(for type: PlayResultType) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(type.badgeColor)
                .frame(width: 8, height: 8)
            Text(type.abbreviation)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.3))
            }
        }
        .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
        .padding(.top, 8)
        .padding(.trailing, 8)
        .accessibilityHidden(true)
    }

    private var untaggedDot: some View {
        Circle()
            .fill(Color.orange)
            .frame(width: 10, height: 10)
            .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1)
            .padding(.top, 8)
            .padding(.trailing, 8)
            .accessibilityLabel("Untagged — needs play result")
    }

    private var highlightIndicator: some View {
        Image(systemName: "star.fill")
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.yellow)
            .padding(6)
            .background(.ultraThinMaterial, in: Circle())
            .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
            .padding(.bottom, 8)
            .padding(.trailing, 8)
            .accessibilityHidden(true)
    }

    private var noteIndicator: some View {
        Image(systemName: "note.text")
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.white.opacity(0.9))
            .padding(5)
            .background(.ultraThinMaterial, in: Circle())
            .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
            .padding(.bottom, 8)
            .padding(.trailing, clip.isHighlight ? 0 : 8)
            .accessibilityLabel("Has note")
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
                        .background(season.isActive ? Color.brandNavy.opacity(0.9) : Color.gray.opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: min(scaledValue(3), 5)))
                        .offset(x: min(scaledValue(-4), -6), y: min(scaledValue(4), 6))
                        .accessibilityHidden(true)
                }
            }
            Spacer()
        }
    }

    // MARK: - Context Label

    private static let contextDateFormatter = DateFormatter.monthDay

    private var contextLabel: String? {
        let opponent = clip.gameOpponent ?? clip.game?.opponent
        if let opponent = opponent {
            let date = clip.gameDate ?? clip.game?.date
            if let date = date {
                return "vs \(opponent) · \(Self.contextDateFormatter.string(from: date))"
            }
            return "vs \(opponent)"
        }
        if clip.practice != nil {
            if let date = clip.practice?.date {
                return "Practice · \(Self.contextDateFormatter.string(from: date))"
            }
            return "Practice"
        }
        return nil
    }

    private var contextBadge: some View {
        Text(contextLabel ?? "")
            .font(.system(size: min(scaledValue(9), 11), weight: .semibold))
            .foregroundColor(.white)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, min(scaledSpacing(5), 7))
            .padding(.vertical, min(scaledSpacing(2), 3))
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 5).fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 5).fill(.black.opacity(0.4))
                }
            }
            .padding(.bottom, 8)
            .padding(.leading, 8)
            .accessibilityHidden(true)
    }

    // MARK: - Thumbnail Loading

    @MainActor
    private func loadThumbnail() async {
        guard !isLoadingThumbnail, thumbnailImage == nil else { return }
        guard !Task.isCancelled else { return }

        loadError = nil

        guard let thumbnailPath = clip.thumbnailPath else {
            await generateMissingThumbnail()
            return
        }

        isLoadingThumbnail = true

        guard !Task.isCancelled else { isLoadingThumbnail = false; return }

        do {
            let targetSize = CGSize(width: size.width * 2, height: size.height * 2)
            let image = try await ThumbnailCache.shared.loadThumbnail(at: thumbnailPath, targetSize: targetSize)
            guard !Task.isCancelled else { isLoadingThumbnail = false; return }
            thumbnailImage = image
            isLoadingThumbnail = false
        } catch {
            guard !Task.isCancelled else { isLoadingThumbnail = false; return }
            Self.logger.warning("Failed to load thumbnail: \(error.localizedDescription, privacy: .public)")
            loadError = error
            isLoadingThumbnail = false
            if generationAttempts < maxGenerationAttempts {
                await generateMissingThumbnail()
            }
        }
    }

    @MainActor
    private func generateMissingThumbnail() async {
        guard Self.activeGenerations < Self.maxConcurrentGenerations else { return }
        Self.activeGenerations += 1
        defer { Self.activeGenerations -= 1 }

        generationAttempts += 1
        guard !Task.isCancelled else { return }
        guard generationAttempts <= maxGenerationAttempts else {
            Self.logger.warning("Max generation attempts reached for \(self.clip.fileName, privacy: .public)")
            loadError = NSError(domain: "VideoThumbnailView", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Max retry attempts exceeded"])
            isLoadingThumbnail = false
            return
        }

        Self.logger.info("Generating thumbnail (attempt \(self.generationAttempts)/\(self.maxGenerationAttempts)) for \(self.clip.fileName, privacy: .public)")

        if let videoURL = await resolveLocalVideoURL() {
            await generateThumbnailFromURL(videoURL)
        } else {
            // Local file missing — show error placeholder.
            // SyncCoordinator handles downloading cloud-only videos when needed;
            // downloading a full video just for a thumbnail is too costly.
            Self.logger.warning("Video file not found locally for thumbnail: \(self.clip.fileName, privacy: .public)")
            loadError = NSError(domain: "VideoThumbnailView", code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Video not available locally"])
            isLoadingThumbnail = false
        }
    }

    /// Returns the local video URL using the model's resolved path.
    /// File existence check runs off main thread to avoid blocking during scroll.
    private func resolveLocalVideoURL() async -> URL? {
        let resolved = clip.resolvedFilePath
        return await Task.detached(priority: .userInitiated) {
            if FileManager.default.fileExists(atPath: resolved) {
                return URL(fileURLWithPath: resolved)
            }
            return nil
        }.value
    }

    /// Generates a thumbnail from a known-good local URL and updates the clip.
    private func generateThumbnailFromURL(_ videoURL: URL) async {
        guard !Task.isCancelled else { isLoadingThumbnail = false; return }

        let result = await VideoFileManager.generateThumbnail(from: videoURL)
        guard !Task.isCancelled else { isLoadingThumbnail = false; return }

        switch result {
        case .success(let thumbnailPath):
            // Guard save — only write if the path changed to reduce concurrent save races.
            if clip.thumbnailPath != thumbnailPath {
                clip.thumbnailPath = thumbnailPath
                Task {
                    do {
                        try modelContext.save()
                        Self.logger.debug("Thumbnail path saved for \(self.clip.fileName, privacy: .public)")
                    } catch {
                        Self.logger.error("Failed to save thumbnail path: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
            do {
                let image = try await ThumbnailCache.shared.loadThumbnail(at: thumbnailPath)
                thumbnailImage = image
                isLoadingThumbnail = false
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

    private func scaledValue(_ baseValue: CGFloat) -> CGFloat {
        let baseWidth: CGFloat = 80
        return baseValue * (size.width / baseWidth)
    }

    private func scaledSpacing(_ baseSpacing: CGFloat) -> CGFloat {
        scaledValue(baseSpacing)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Small") {
    VideoThumbnailView.small(clip: .preview).padding()
}

#Preview("Medium") {
    VideoThumbnailView.medium(clip: .preview).padding()
}

#Preview("Large") {
    VideoThumbnailView.large(clip: .preview).padding()
}

extension VideoClip {
    static var preview: VideoClip {
        let clip = VideoClip(fileName: "preview.mov", filePath: "/tmp/preview.mov")
        clip.createdAt = Date()
        return clip
    }
}
#endif
