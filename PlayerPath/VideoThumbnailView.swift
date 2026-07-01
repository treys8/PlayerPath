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
    let showPlayResult: Bool
    let showHighlight: Bool
    let showNote: Bool
    let showSeason: Bool
    let showContext: Bool
    let showDuration: Bool
    let showOutcomeWithDuration: Bool
    let fillsContainer: Bool
    /// Reports the clip thumbnail's raw aspect ratio (width / height) once it
    /// loads. Optional — only the Journal feed uses it (to size its tile to a
    /// portrait clip instead of top-cropping it into a 16:9 box); every other
    /// call site leaves it nil and is unaffected.
    var onAspectResolved: ((CGFloat) -> Void)? = nil

    @State private var thumbnailImage: UIImage?
    @State private var isLoadingThumbnail = false
    @State private var loadError: Error?
    @State private var generationAttempts = 0
    @Environment(\.modelContext) private var modelContext
    @Environment(\.ppAccent) private var ppAccent

    private let maxGenerationAttempts = 2
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.playerpath", category: "VideoThumbnailView")
    // @MainActor-isolated: all read/write sites live in @MainActor methods on
    // this struct. Declaring it explicitly keeps Swift 6 strict-concurrency happy.
    @MainActor private static var activeGenerations = 0
    @MainActor private static let maxConcurrentGenerations = 4

    /// Clip ids we've already checked for a stale (low-res) thumbnail this session.
    /// A one-time-per-clip guard so scrolling doesn't re-probe/re-regenerate, and so a
    /// genuinely low-res source video (which can't be improved) is attempted at most once.
    @MainActor private static var upscaleAttempted = Set<UUID>()
    /// Legacy thumbnails were capped at 480px longest side; current generation reaches
    /// ≥1080px (portrait) / 1920px (landscape). Anything below this is a stale thumbnail
    /// worth regenerating when the source video is still available locally.
    private static let staleThumbnailLongestSide = 640

    // MARK: - Initializers

    init(
        clip: VideoClip,
        size: CGSize = .thumbnailSmall,
        cornerRadius: CGFloat = 12,
        showPlayResult: Bool = true,
        showHighlight: Bool = true,
        showNote: Bool = true,
        showSeason: Bool = false,
        showContext: Bool = true,
        showDuration: Bool = false,
        showOutcomeWithDuration: Bool = false,
        fillsContainer: Bool = false,
        onAspectResolved: ((CGFloat) -> Void)? = nil
    ) {
        self.clip = clip
        self.size = size
        self.cornerRadius = cornerRadius
        self.showPlayResult = showPlayResult
        self.showHighlight = showHighlight
        self.showNote = showNote
        self.showSeason = showSeason
        self.showContext = showContext
        self.showDuration = showDuration
        self.showOutcomeWithDuration = showOutcomeWithDuration
        self.fillsContainer = fillsContainer
        self.onAspectResolved = onAspectResolved
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
                            maxHeight: fillsContainer ? .infinity : safeSize.height,
                            // When embedded as a hero (fillsContainer), a portrait
                            // clip thumbnail overflows the wide 16:9 tile — anchor
                            // the fill to the top so it crops from the bottom and
                            // keeps the subject's head. Fixed-size grid thumbnails
                            // (fillsContainer == false) stay center-cropped.
                            alignment: fillsContainer ? .top : .center
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

            // Top-right indicator: untagged dot when no play result / club.
            // Tagged outcomes are communicated by the bottom overlay bar
            // (`0:04 · Single` or `0:04 · 7i`), so no top-right glyph for them
            // — avoids duplicating the tag in two places on the same thumbnail.
            if showPlayResult, !clip.isTagged {
                VStack {
                    HStack {
                        Spacer()
                        untaggedDot
                    }
                    Spacer()
                }
            }

            // Bottom-right indicators (highlight star / note icon)
            VStack {
                Spacer()
                HStack(spacing: 4) {
                    Spacer()
                    if showNote, let note = clip.note, !note.isEmpty {
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

            // Bottom-left stack: duration (or duration·outcome merged bar) above context label
            if (showContext && contextLabel != nil) || (showDuration && (clip.duration ?? 0) > 0) {
                VStack {
                    Spacer()
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            if showDuration, let duration = clip.duration, duration > 0 {
                                durationBadge(seconds: duration)
                            }
                            if showContext, contextLabel != nil {
                                contextBadgeContent
                            }
                        }
                        .padding(.bottom, 8)
                        .padding(.leading, 8)
                        Spacer()
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        // Drop the shadow when embedded (fillsContainer): the wrapping tile/card
        // already clips us to a rounded rect and provides its own depth, so this
        // shadow is clipped away yet still computed — a wasted offscreen pass per
        // cell during scroll. A .clear/0-radius shadow is a no-op and keeps view
        // identity stable. Standalone thumbnails keep the shadow.
        .shadow(color: fillsContainer ? .clear : .black.opacity(0.1),
                radius: fillsContainer ? 0 : 5, x: 0, y: fillsContainer ? 0 : 2)
        .accessibilityIgnoresInvertColors()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .task(id: clip.id) {
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
        if let tag = clip.displayTagName {
            description += ", \(tag)"
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
        guard clip.isTagged else {
            return [Color.gray.opacity(0.5), Color.gray.opacity(0.7)]
        }
        let base = clip.displayTagColor
        return [base.opacity(0.5), base.opacity(0.7)]
    }

    private var placeholderText: String {
        if isLoadingThumbnail { return "Loading..." }
        else if loadError != nil { return "Failed to Load" }
        else { return contextLabel ?? "No Preview" }
    }

    private var untaggedDot: some View {
        Circle()
            .fill(ppAccent)
            .frame(width: 10, height: 10)
            .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1)
            .padding(.top, 8)
            .padding(.trailing, 8)
            .accessibilityLabel("Untagged")
    }

    private var highlightIndicator: some View {
        Image(systemName: "bookmark.fill")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white)
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
                        .font(.custom("Inter18pt-SemiBold", size: min(scaledValue(8), 12)))
                        .foregroundColor(Theme.cueText)
                        .padding(.horizontal, min(scaledSpacing(4), 6))
                        .padding(.vertical, min(scaledSpacing(2), 3))
                        .background(Theme.cueBg)
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
            // Sport is read from whichever relationship is intact. Falls back
            // to "vs" only when both season and game relationships have been
            // broken by a cross-device restore — opponent is denormalized but
            // sport is not, so this is the best we can do.
            let isGolf = clip.season?.sport == .golf || clip.game?.isGolf == true
            let prefix = isGolf ? "at" : "vs"
            let date = clip.gameDate ?? clip.game?.date
            if let date = date {
                return "\(prefix) \(opponent) · \(Self.contextDateFormatter.string(from: date))"
            }
            return "\(prefix) \(opponent)"
        }
        if clip.practice != nil {
            if let date = clip.practice?.date {
                return "Practice · \(Self.contextDateFormatter.string(from: date))"
            }
            return "Practice"
        }
        return nil
    }

    private var contextBadgeContent: some View {
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
            .accessibilityHidden(true)
    }

    private func durationBadge(seconds: Double) -> some View {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let timeLabel = String(format: "%d:%02d", mins, secs)
        let outcomeLabel: String? = {
            guard showOutcomeWithDuration else { return nil }
            return clip.displayTagName
        }()
        let label = outcomeLabel.map { "\(timeLabel) · \($0)" } ?? timeLabel
        let a11yLabel = outcomeLabel.map { "\($0), \(mins) minutes \(secs) seconds" }
            ?? "Duration \(mins) minutes \(secs) seconds"
        return Text(label)
            .font(.custom("Inter18pt-SemiBold", size: 11, relativeTo: .caption2))
            .foregroundColor(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.black.opacity(0.55), in: Capsule())
            .accessibilityLabel(a11yLabel)
    }

    // MARK: - Thumbnail Loading

    /// Pixel target for downsampling at display time. `ThumbnailCache.downsampleImage`
    /// re-multiplies this by the device display scale internally, so 2× the point size is a
    /// comfortable ceiling that keeps heroes crisp without over-allocating for row thumbnails.
    /// Shared by the initial load and the post-regeneration reload so neither caches a
    /// full-resolution source image.
    private var displayTargetSize: CGSize {
        CGSize(width: size.width * 2, height: size.height * 2)
    }

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
            let image = try await ThumbnailCache.shared.loadThumbnail(at: thumbnailPath, targetSize: displayTargetSize)
            guard !Task.isCancelled else { isLoadingThumbnail = false; return }
            thumbnailImage = image
            isLoadingThumbnail = false
            if image.size.height > 0 { onAspectResolved?(image.size.width / image.size.height) }
            // Existing clips carry legacy low-res thumbnails; upgrade them once when the
            // source video is still local so the feed sharpens without a manual re-import.
            await regenerateStaleThumbnailIfNeeded(currentPath: thumbnailPath)
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
        // The clip may have been deleted during the multi-second generate await; touching a
        // deleted @Model's attributes traps and bypasses the do/catch below. Bail if it's gone.
        guard !clip.isDeleted, clip.modelContext != nil else { isLoadingThumbnail = false; return }

        switch result {
        case .success(let thumbnailPath):
            // Guard mutation — only write if the path changed.
            // Saves are coalesced via ThumbnailSaveDebouncer so fast scrolling
            // through clips missing thumbnails doesn't hammer modelContext.save()
            // on the main thread for every cell.
            if clip.thumbnailPath != thumbnailPath {
                clip.thumbnailPath = thumbnailPath
                ThumbnailSaveDebouncer.shared.scheduleSave(modelContext)
            }
            do {
                // Pass a display target so the freshly generated 1080p source is downsampled,
                // not cached at full resolution.
                let image = try await ThumbnailCache.shared.loadThumbnail(at: thumbnailPath, targetSize: displayTargetSize)
                thumbnailImage = image
                isLoadingThumbnail = false
                if image.size.height > 0 { onAspectResolved?(image.size.width / image.size.height) }
            } catch {
                Self.logger.error("Failed to load generated thumbnail: \(error.localizedDescription, privacy: .public)")
                // Don't clobber a thumbnail that's already on screen (stale-heal reload): a
                // failure here would make accessibilityDescription falsely announce "failed".
                if thumbnailImage == nil { loadError = error }
                isLoadingThumbnail = false
            }
        case .failure(let error):
            Self.logger.error("Failed to generate thumbnail: \(error.localizedDescription, privacy: .public)")
            if thumbnailImage == nil { loadError = error }
            isLoadingThumbnail = false
        }
    }

    /// Upgrades a legacy low-resolution thumbnail in place. Runs at most once per clip per
    /// session (`upscaleAttempted` guard) so scrolling doesn't re-probe and a genuinely
    /// low-res source video isn't regenerated repeatedly. Only fires when the on-disk
    /// thumbnail's longest side is below `staleThumbnailLongestSide` AND the source video is
    /// still local — cloud-only clips are left untouched (regenerating would need a full
    /// video download). Reuses `generateThumbnailFromURL`, which rewrites `clip.thumbnailPath`
    /// and reloads the image; the superseded thumbnail file is then cleaned up.
    @MainActor
    private func regenerateStaleThumbnailIfNeeded(currentPath: String) async {
        // `isDeleted` is safe to read on an invalidated model; check it before any other
        // attribute (e.g. `clip.id`), since this runs right after the load await resumed.
        guard !clip.isDeleted, clip.modelContext != nil else { return }
        guard !Self.upscaleAttempted.contains(clip.id) else { return }
        let clipID = clip.id
        Self.upscaleAttempted.insert(clipID)

        // Read the thumbnail's pixel dimensions off-main without decoding it.
        let longestSide = await Task.detached(priority: .utility) {
            ThumbnailCache.sourceLongestSide(at: currentPath)
        }.value
        // Crisp (current-generation) or unreadable: leave marked so we don't re-probe this
        // clip on every scroll — neither outcome changes within the session.
        guard let longestSide, longestSide < Self.staleThumbnailLongestSide else { return }

        // The probe await could outlive the clip; bail if it was deleted meanwhile.
        guard !clip.isDeleted, clip.modelContext != nil else { return }
        // Cloud-only clips can't be regenerated locally (would need a full video download) —
        // leave marked; the source won't become local within this session.
        guard let videoURL = await resolveLocalVideoURL() else { return }
        guard !clip.isDeleted, clip.modelContext != nil else { return }

        // These are *transient* skips — unmark so a later appearance retries once a slot frees
        // up. Without this, in a feed full of legacy clips only the first few would ever heal.
        guard !Task.isCancelled else { Self.upscaleAttempted.remove(clipID); return }
        guard Self.activeGenerations < Self.maxConcurrentGenerations else {
            Self.upscaleAttempted.remove(clipID)
            return
        }
        Self.activeGenerations += 1
        defer { Self.activeGenerations -= 1 }

        Self.logger.info("Upgrading legacy thumbnail (\(longestSide)px) for \(self.clip.fileName, privacy: .public)")

        let oldResolvedPath = ThumbnailCache.resolveLocalPath(currentPath)
        await generateThumbnailFromURL(videoURL)

        // If the path actually changed, delete the superseded file and drop it from cache.
        // Re-guard: the regeneration await above could have outlived a concurrent delete.
        guard !clip.isDeleted, clip.modelContext != nil else { return }
        if clip.thumbnailPath != currentPath {
            ThumbnailCache.shared.removeThumbnail(at: currentPath)
            VideoFileManager.cleanup(url: URL(fileURLWithPath: oldResolvedPath))
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

// MARK: - Thumbnail Save Debouncer

/// Coalesces `modelContext.save()` calls triggered by thumbnail generation
/// during scroll. Without this, fast scrolling through clips missing
/// thumbnails triggers one save per cell as each one generates its thumbnail,
/// causing main-thread micro-stutters.
@MainActor
final class ThumbnailSaveDebouncer {
    static let shared = ThumbnailSaveDebouncer()

    private var pendingContext: ModelContext?
    private var flushTask: Task<Void, Never>?
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.playerpath", category: "ThumbnailSaveDebouncer")
    private static let flushDelay: Duration = .milliseconds(500)

    private init() {}

    /// Schedule a save. Successive calls within `flushDelay` coalesce into
    /// a single save at the end of the window.
    func scheduleSave(_ context: ModelContext) {
        pendingContext = context
        flushTask?.cancel()
        flushTask = Task { @MainActor in
            try? await Task.sleep(for: Self.flushDelay)
            guard !Task.isCancelled else { return }
            flush()
        }
    }

    /// Force-flush the pending save immediately (e.g., on app backgrounding).
    func flush() {
        guard let context = pendingContext else { return }
        pendingContext = nil
        do {
            try context.save()
        } catch {
            Self.log.error("Failed to flush coalesced thumbnail saves: \(error.localizedDescription, privacy: .public)")
        }
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
