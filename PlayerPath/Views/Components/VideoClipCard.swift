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
    private let uploadManager = UploadQueueManager.shared
    @State private var isPressed = false
    @State private var isSavingToPhotos = false

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
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
                                    .padding(8)
                            }
                            Spacer()
                        }
                    }

                    // Selection overlay
                    selectionOverlay

                    // Backup status badge (top-left, moved from top-right to not conflict with play result)
                    if !isSelectionMode {
                        VStack {
                            HStack {
                                backupStatusBadge
                                    .padding(8)
                                Spacer()
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
                        if let result = video.playResult {
                            Text(result.type.displayName)
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        } else {
                            Text("Video Clip")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
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
                        } else if let created = video.createdAt {
                            Text(created, style: .date)
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
            .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
            .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(PressableCardButtonStyle())
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .contextMenu {
            Button {
                Haptics.light()
                onPlay()
            } label: {
                Label("Play", systemImage: "play.fill")
            }

            Button {
                Haptics.light()
                video.isHighlight.toggle()
                video.needsSync = true
                Task {
                    do {
                        try modelContext.save()
                    } catch {
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

            Divider()

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

            if AppFeatureFlags.isCoachEnabled {
                Divider()

                Button {
                    showingShareToFolder = true
                } label: {
                    Label("Share to Coach Folder", systemImage: hasCoachingAccess ? "folder.badge.person.fill" : "lock.fill")
                }
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
        .sheet(isPresented: $showingShareToFolder) {
            ShareToCoachFolderView(clip: video)
        }
        .sheet(isPresented: $showingMoveSheet) {
            MoveClipSheet(clip: video)
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

    // MARK: - Save to Photos

    private func saveToPhotos() {
        guard FileManager.default.fileExists(atPath: video.resolvedFilePath) else {
            errorMessage = "Video file not found. It may have been deleted or moved."
            showingError = true
            return
        }

        isSavingToPhotos = true
        let videoURL = video.resolvedFileURL

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    self.isSavingToPhotos = false
                    self.errorMessage = "Photo library access is required to save videos. Please enable it in Settings > PlayerPath > Photos."
                    self.showingError = true
                }
                return
            }

            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    self.isSavingToPhotos = false
                    if success {
                        Haptics.success()
                        self.showingSaveSuccess = true
                    } else {
                        self.errorMessage = "Could not save video to Photos. \(error?.localizedDescription ?? "Please try again.")"
                        self.showingError = true
                    }
                }
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
                            .foregroundColor(isSelected ? .brandNavy : .white)
                            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                            .padding(10)
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: - Backup Status Badge

    @ViewBuilder
    private var backupStatusBadge: some View {
        if video.isUploaded && video.firestoreId != nil {
            // Fully synced — Storage uploaded + Firestore metadata written (cross-device ready)
            HStack(spacing: 3) {
                Image(systemName: "checkmark.icloud.fill")
                    .font(.system(size: 12))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(.green)
            .cornerRadius(6)
            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
        } else if video.isUploaded && video.firestoreId == nil {
            // Storage upload done but Firestore metadata not yet written — not cross-device accessible yet
            HStack(spacing: 3) {
                Image(systemName: "exclamationmark.icloud.fill")
                    .font(.system(size: 12))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(.yellow)
            .cornerRadius(6)
            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
        } else if let progress = uploadManager.activeUploads[video.id] {
            // Currently uploading - blue with percentage
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
        } else if uploadManager.pendingUploads.contains(where: { $0.clipId == video.id }) {
            // Queued for upload - orange clock
            HStack(spacing: 3) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 12))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(.orange)
            .cornerRadius(6)
            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
        } else {
            // Local only - subtle gray device icon
            HStack(spacing: 3) {
                Image(systemName: "iphone")
                    .font(.system(size: 11))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color.gray.opacity(0.7))
            .cornerRadius(6)
            .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
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
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
