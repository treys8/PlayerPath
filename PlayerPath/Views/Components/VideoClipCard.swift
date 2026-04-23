//
//  VideoClipCard.swift
//  PlayerPath
//
//  Extracted from VideoClipsView.swift
//

import SwiftUI
import SwiftData
import Photos

struct VideoClipCard: View {
    let video: VideoClip
    var isSelectionMode: Bool = false
    var isSelected: Bool = false
    var hasCoachingAccess: Bool = false
    let onPlay: () -> Void
    let onDelete: () -> Void
    var onToggleSelection: (() -> Void)? = nil
    @Environment(\.modelContext) private var modelContext
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var showingSaveSuccess = false
    @State private var showingShareToFolder = false
    @State private var showingMoveSheet = false
    @State private var showingGameLinker = false
    @State private var showingRetrimFlow = false
    @State private var isSavingToPhotos = false
    @State private var showingTagSheet = false

    var body: some View {
        Button(action: {
            Haptics.light()
            onPlay()
        }) {
            VStack(spacing: 0) {
                // Thumbnail - 16:9 aspect ratio (no GeometryReader for better LazyVGrid perf)
                ZStack {
                    VideoThumbnailView(
                        clip: video,
                        size: .thumbnailLarge,
                        cornerRadius: 0,
                        showPlayButton: !isSelectionMode,
                        showPlayResult: true,
                        showHighlight: true,
                        showSeason: false,
                        showContext: false,
                        fillsContainer: true
                    )

                    // Gradient overlay for better contrast
                    VStack {
                        Spacer()
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.4)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .frame(height: 40)
                    }

                    // Duration badge (bottom-left)
                    VStack {
                        Spacer()
                        HStack {
                            if let duration = video.duration, duration > 0 {
                                Text(formatDuration(duration))
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .badgeSmall()
                                    .background(.ultraThinMaterial, in: Capsule())
                                    .padding(8)
                            }
                            Spacer()
                        }
                    }

                    // Selection overlay
                    selectionOverlay

                    // Backup status badge (top-left, moved from top-right to not conflict with play result).
                    // Factored into its own View struct so SwiftUI scopes UploadQueueManager
                    // observation to the badge — upload progress ticks (~4/sec) no longer
                    // invalidate the entire card body across every visible cell.
                    if !isSelectionMode {
                        VStack {
                            HStack {
                                BackupStatusBadge(clip: video)
                                    .padding(8)
                                Spacer()
                            }
                            Spacer()
                        }
                    }

                    // Coach-feedback badges (top-right). Populated via sync from
                    // the Firestore videos/{id} doc, so clips not yet uploaded
                    // render no badge (both counts default to 0). Local clips
                    // always know their split post-sync — we pass drawingCount
                    // directly, so comment-only clips show a comment badge
                    // (never the legacy lumped variant).
                    if !isSelectionMode {
                        VStack {
                            HStack {
                                Spacer()
                                AnnotationBadgeCluster(
                                    annotationCount: video.annotationCount,
                                    drawingCount: video.drawingCount,
                                    style: .thumbnail
                                )
                                .padding(8)
                            }
                            Spacer()
                        }
                    }
                }
                .aspectRatio(16/9, contentMode: .fit)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 12))

                // Info section
                VStack(alignment: .leading, spacing: 6) {
                        // Headline: play result > fallback
                        HStack {
                            if let result = video.playResult {
                                HStack(spacing: 6) {
                                    Text(result.type.displayName)
                                        .font(.subheadline)
                                        .fontWeight(.bold)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                    if let speed = video.pitchSpeed, speed > 0 {
                                        Text("\(Int(speed)) MPH")
                                            .font(.caption2)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                            .fixedSize(horizontal: true, vertical: false)
                                            .badgeMedium()
                                            .background(.orange, in: Capsule())
                                    }
                                }
                            } else {
                                Text("Video Clip")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                            }

                            Spacer()

                            if !isSelectionMode {
                                Menu {
                                    videoMenuItems
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.secondary)
                                        .frame(width: 28, height: 28)
                                        .contentShape(Rectangle())
                                }
                            }
                        }

                        // Secondary: game/practice context + season badge
                        if let game = video.game {
                            HStack(spacing: 6) {
                                Text("vs \(game.opponent)")
                                    .font(.caption)
                                    .foregroundColor(.brandNavy)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Spacer()
                                if let season = video.season {
                                    SeasonBadge(season: season, fontSize: 8)
                                }
                            }

                            Text((game.date ?? Date()), style: .date)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else if video.practice != nil {
                            HStack(spacing: 6) {
                                Text("Practice")
                                    .font(.caption)
                                    .foregroundColor(.green)
                                Spacer()
                                if let season = video.season {
                                    SeasonBadge(season: season, fontSize: 8)
                                }
                            }

                            Text((video.createdAt ?? Date()), style: .date)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else {
                            if let season = video.season {
                                HStack(spacing: 6) {
                                    Spacer()
                                    SeasonBadge(season: season, fontSize: 8)
                                }
                            }
                            Text((video.createdAt ?? Date()), style: .date)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6))
                }
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: .cornerLarge, style: .continuous))
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 3)
            // Force the Button's tappable region to cover the entire rendered frame.
            // Without this, SwiftUI's default hit-test is the union of child text
            // regions — leaving Spacer-filled gaps in the info section as dead zones
            // that fall through to the next card (opening the wrong clip on
            // long-press or tap near those gaps).
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardButtonStyle())
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .contextMenu {
            if !isSelectionMode { videoMenuItems }
        }
        .sheet(isPresented: $showingShareToFolder) {
            ShareToCoachFolderView(clip: video)
        }
        .sheet(isPresented: $showingMoveSheet) {
            MoveClipSheet(clip: video)
        }
        .sheet(isPresented: $showingTagSheet) {
            PlayResultEditorView(clip: video, modelContext: modelContext)
        }
        .sheet(isPresented: $showingGameLinker) {
            GameLinkerView(clip: video)
        }
        .fullScreenCover(isPresented: $showingRetrimFlow) {
            if let athlete = video.athlete {
                RetrimSavedClipFlow(clip: video, athlete: athlete)
            }
        }
        .alert("Video Action Failed", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "An unexpected error occurred. Please try again.")
        }
        .toast(isPresenting: $showingSaveSuccess, message: "Saved to Photos")
        .overlay {
            if isSavingToPhotos {
                ZStack {
                    Color.black.opacity(0.4)
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Saving to Photos...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: .cornerLarge))
                }
                .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Menu Items

    @ViewBuilder
    private var videoMenuItems: some View {
        if video.playResult == nil {
            Button {
                Haptics.light()
                showingTagSheet = true
            } label: {
                Label("Tag Play Result", systemImage: "tag.fill")
            }
        } else {
            Button {
                Haptics.light()
                showingTagSheet = true
            } label: {
                Label("Edit Play Result", systemImage: AppIcon.edit)
            }
        }
        Divider()

        Button {
            Haptics.light()
            onPlay()
        } label: {
            Label("Play", systemImage: "play.fill")
        }

        Button {
            showingGameLinker = true
        } label: {
            Label(video.game == nil ? "Link to Game" : "Change Game", systemImage: "baseball.diamond.bases")
        }

        Button {
            Haptics.light()
            let prevHighlight = video.isHighlight
            let prevNeedsSync = video.needsSync
            video.isHighlight.toggle()
            video.needsSync = true
            Task {
                do {
                    try modelContext.save()
                } catch {
                    video.isHighlight = prevHighlight
                    video.needsSync = prevNeedsSync
                    errorMessage = "Could not update highlight status. Please try again."
                    showingError = true
                }
            }
        } label: {
            Label(
                video.isHighlight ? "Remove from Highlights" : "Add to Highlights",
                systemImage: video.isHighlight ? "star.slash" : "star.fill"
            )
        }

        if video.isUploaded && video.athlete != nil {
            Divider()
            Button {
                showingRetrimFlow = true
            } label: {
                Label("Trim Clip", systemImage: "scissors")
            }
        }

        Divider()

        if FileManager.default.fileExists(atPath: video.resolvedFilePath) {
            ShareLink(item: video.resolvedFileURL) {
                Label("Share", systemImage: "square.and.arrow.up")
            }

            Button {
                saveToPhotos()
            } label: {
                Label("Save to Photos", systemImage: "square.and.arrow.down")
            }
        }

        // Upload controls
        if video.isUploaded {
            Label("Uploaded to Cloud", systemImage: "checkmark.icloud")
                .foregroundColor(.green)
        } else if let athlete = video.athlete {
            Button {
                Haptics.light()
                UploadQueueManager.shared.enqueue(video, athlete: athlete, priority: .high)
            } label: {
                if UploadQueueManager.shared.activeUploads[video.id] != nil {
                    Label("Uploading...", systemImage: "icloud.and.arrow.up")
                } else if UploadQueueManager.shared.pendingUploads.contains(where: { $0.clipId == video.id }) {
                    Label("Queued for Upload", systemImage: "clock.arrow.circlepath")
                } else {
                    Label("Upload to Cloud", systemImage: "icloud.and.arrow.up")
                }
            }
        }

        Divider()

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

        Divider()

        Button(role: .destructive) {
            onDelete()
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Save to Photos

    private func saveToPhotos() {
        guard FileManager.default.fileExists(atPath: video.resolvedFilePath) else {
            errorMessage = "Video file not found. It may have been deleted or moved."
            showingError = true
            return
        }

        isSavingToPhotos = true
        let videoURL = video.resolvedFileURL

        Task { @MainActor in
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                isSavingToPhotos = false
                errorMessage = "Photo library access is required to save videos. Please enable it in Settings > PlayerPath > Photos."
                showingError = true
                return
            }

            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
                }
                isSavingToPhotos = false
                Haptics.success()
                showingSaveSuccess = true
            } catch {
                isSavingToPhotos = false
                errorMessage = "Could not save video to Photos. \(error.localizedDescription)"
                showingError = true
            }
        }
    }

    // MARK: - Selection Overlay

    @ViewBuilder
    private var selectionOverlay: some View {
        if isSelectionMode {
            ZStack {
                Color.black.opacity(isSelected ? 0.3 : 0.1)

                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 28))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Color.white, Color.blue)
                            .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
                            .padding(10)
                    }
                    Spacer()
                }
            }
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Pressable Card Button Style

struct PressableCardButtonStyle: ButtonStyle {
    // Opacity-only feedback: SwiftUI's `configuration.isPressed` is true for
    // both taps and long-presses, so `.scaleEffect` would shrink the card
    // during a long-press-to-context-menu gesture — a visual glitch where the
    // cell reflows under the user's finger just before the menu appears.
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Backup Status Badge

/// Per-clip upload / backup indicator. Factored out of `VideoClipCard` so
/// SwiftUI's `@Observable` tracking scopes `UploadQueueManager` reads to
/// this tiny view — a progress tick invalidates only the badge, not the
/// whole card across every visible cell in the grid.
struct BackupStatusBadge: View {
    let clip: VideoClip

    private let uploadManager = UploadQueueManager.shared

    var body: some View {
        // Reading clip.isUploaded / clip.firestoreId here — instead of in the
        // parent VideoClipCard — scopes SwiftData's @Observable dependency
        // tracking to this subview. Upload completion invalidates just the
        // badge instead of the whole card (and, transitively, the whole grid),
        // which was previously causing the post-upload "shutter" effect.
        if clip.isUploaded && clip.firestoreId != nil {
            // Fully synced — Storage uploaded + Firestore metadata written (cross-device ready)
            badge(icon: "checkmark.icloud.fill", iconSize: 12, background: .green, shadowOpacity: 0.3)
        } else if clip.isUploaded && clip.firestoreId == nil {
            // Storage upload done but Firestore metadata not yet written — not cross-device accessible yet
            badge(icon: "exclamationmark.icloud.fill", iconSize: 12, background: .yellow, shadowOpacity: 0.3)
        } else if let progress = uploadManager.activeUploads[clip.id] {
            // Currently uploading — blue with percentage
            HStack(spacing: 3) {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(.white)
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color.brandNavy)
            .cornerRadius(6)
            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
        } else if uploadManager.pendingUploads.contains(where: { $0.clipId == clip.id }) {
            // Queued for upload — orange clock
            badge(icon: "clock.fill", iconSize: 12, background: .orange, shadowOpacity: 0.3)
        } else {
            // Local only — subtle gray device icon
            badge(icon: "iphone", iconSize: 11, background: Color.gray.opacity(0.7), shadowOpacity: 0.2)
        }
    }

    private func badge(icon: String, iconSize: CGFloat, background: Color, shadowOpacity: Double) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: iconSize))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(background)
        .cornerRadius(6)
        .shadow(color: .black.opacity(shadowOpacity), radius: 2, x: 0, y: 1)
    }
}
