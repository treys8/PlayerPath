//
//  ClipReviewSheet.swift
//  PlayerPath
//
//  Review sheet for a single coach clip in the Needs Review tab.
//  Lets the coach watch the clip, add notes, then share or discard.
//

import SwiftUI
import AVKit
import PencilKit

struct ClipReviewSheet: View {
    let video: CoachVideoItem
    let folder: SharedFolder
    var onShared: (() -> Void)?
    var onDiscarded: (() -> Void)?

    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @Environment(\.dismiss) private var dismiss
    @State private var notes: String
    @State private var isPublishing = false
    @State private var isDiscarding = false
    @State private var showingDiscardConfirmation = false
    @State private var errorMessage: String?

    // Video playback
    @State private var player: AVPlayer?
    @State private var isLoadingVideo = true
    @State private var videoError: String?
    @State private var videoAspectRatio: CGFloat = 16.0 / 9.0

    // Telestration
    @State private var showingTelestration = false

    private var currentPlaybackTime: Double {
        player?.currentTime().seconds ?? 0
    }

    private var folderID: String { folder.id ?? "" }

    init(video: CoachVideoItem, folder: SharedFolder, onShared: (() -> Void)? = nil, onDiscarded: (() -> Void)? = nil) {
        self.video = video
        self.folder = folder
        self.onShared = onShared
        self.onDiscarded = onDiscarded
        self._notes = State(initialValue: video.notes ?? "")
    }

    var body: some View {
        ZStack {
            navigationContent
            telestrationOverlay
        }
    }

    private var navigationContent: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 16) {
                        // Video player
                        videoPlayerSection

                        // Notes
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Instruction Notes")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)

                            TextField("What should the athlete focus on?", text: $notes, axis: .vertical)
                                .lineLimit(4...8)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: notes) { _, new in
                                    if new.count > CoachNoteLimits.plainNoteCharLimit {
                                        notes = String(new.prefix(CoachNoteLimits.plainNoteCharLimit))
                                    }
                                }
                            HStack {
                                Spacer()
                                Text("\(notes.count)/\(CoachNoteLimits.plainNoteCharLimit)")
                                    .font(.caption2)
                                    .foregroundColor(notes.count >= CoachNoteLimits.plainNoteCharLimit ? .red : .secondary)
                            }
                        }
                        .padding(.horizontal)

                        // Info
                        if video.createdAt != nil || (video.fileSize ?? 0) > 0 {
                            VStack(spacing: 0) {
                                if let createdAt = video.createdAt {
                                    infoRow(label: "Recorded", value: createdAt.formatted(date: .abbreviated, time: .shortened))
                                }
                                if let fileSize = video.fileSize, fileSize > 0 {
                                    if video.createdAt != nil { Divider().padding(.leading) }
                                    infoRow(label: "Size", value: ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))
                                }
                            }
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .padding(.horizontal)
                        }
                    }
                }

                // Actions pinned to bottom
                VStack(spacing: 12) {
                    Button {
                        shareClip()
                    } label: {
                        HStack {
                            if isPublishing {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.white)
                            }
                            Label("Share with Athlete", systemImage: "paperplane.fill")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.brandNavy)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(isPublishing || isDiscarding)

                    Button(role: .destructive) {
                        showingDiscardConfirmation = true
                    } label: {
                        HStack {
                            if isDiscarding {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Label("Discard Clip", systemImage: "trash")
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                    }
                    .disabled(isPublishing || isDiscarding)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Review Clip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        player?.pause()
                        showingTelestration = true
                    } label: {
                        Image(systemName: "pencil.tip")
                            .foregroundColor(.brandNavy)
                    }
                    .disabled(player == nil || isLoadingVideo)
                    .accessibilityLabel("Draw on video frame")
                }
            }
            .alert("Discard this clip?", isPresented: $showingDiscardConfirmation) {
                Button("Discard", role: .destructive) { discardClip() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This clip will be permanently deleted.")
            }
            .alert("Something Went Wrong", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .task {
                await loadVideo()
            }
            .onDisappear {
                player?.pause()
                player = nil
            }
        }
    }

    // MARK: - Video Player

    @ViewBuilder
    private var videoPlayerSection: some View {
        ZStack {
            Color.black

            if isLoadingVideo {
                ProgressView("Loading video...")
                    .tint(.white)
                    .foregroundColor(.white)
            } else if let videoError {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundColor(.orange)
                    Text(videoError)
                        .font(.caption)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await loadVideo() }
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
                .padding()
            } else if let player {
                EnhancedVideoPlayer(player: player, preloadedDuration: video.duration)
            }
        }
        .aspectRatio(4/3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var telestrationOverlay: some View {
        if showingTelestration {
            TelestrationOverlayView(
                timestamp: currentPlaybackTime,
                videoAspectRatio: videoAspectRatio,
                onSave: { drawing, timestamp, canvasSize in
                    guard let userID = authManager.userID,
                          let userName = authManager.userDisplayName ?? authManager.userEmail else { return false }
                    let saved = await saveDrawing(
                        drawing: drawing,
                        timestamp: timestamp,
                        canvasSize: canvasSize,
                        userID: userID,
                        userName: userName
                    )
                    if saved { showingTelestration = false }
                    return saved
                },
                onCancel: { showingTelestration = false }
            )
            .ignoresSafeArea()
            .transition(.opacity)
            .zIndex(1)
        }
    }

    // MARK: - Info Row

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.primary)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
        .font(.subheadline)
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    // MARK: - Video Loading

    @MainActor
    private func loadVideo() async {
        isLoadingVideo = true
        videoError = nil

        let playbackURL: URL
        if let cached = CoachVideoLoader.cachedURL(folderID: folderID, fileName: video.fileName) {
            playbackURL = cached
        } else {
            do {
                playbackURL = try await CoachVideoLoader.fetchAndCache(
                    folderID: folderID,
                    fileName: video.fileName
                )
            } catch {
                ErrorHandlerService.shared.handle(error, context: "ClipReviewSheet.loadVideo", showAlert: false)
                videoError = "Unable to load video. Check your connection."
                isLoadingVideo = false
                return
            }
        }

        let newPlayer = AVPlayer(url: playbackURL)
        player = newPlayer

        if let track = try? await newPlayer.currentItem?.asset.loadTracks(withMediaType: .video).first,
           let size = try? await track.load(.naturalSize),
           size.height > 0 {
            videoAspectRatio = size.width / size.height
        }

        isLoadingVideo = false
    }

    // MARK: - Telestration

    @MainActor
    private func saveDrawing(
        drawing: PKDrawing,
        timestamp: Double,
        canvasSize: CGSize,
        userID: String,
        userName: String
    ) async -> Bool {
        let rawData = drawing.dataRepresentation()
        guard rawData.count <= 200_000 else {
            errorMessage = "Drawing is too complex. Try simplifying and saving again."
            return false
        }

        let base64 = rawData.base64EncodedString()
        let videoID = video.id
        guard !videoID.isEmpty else { return false }

        do {
            _ = try await FirestoreManager.shared.createAnnotation(
                videoID: videoID,
                text: "Drawing annotation",
                timestamp: timestamp,
                userID: userID,
                userName: userName,
                isCoachComment: true,
                type: "drawing",
                drawingData: base64,
                drawingCanvasWidth: canvasSize.width > 0 ? Double(canvasSize.width) : nil,
                drawingCanvasHeight: canvasSize.height > 0 ? Double(canvasSize.height) : nil
            )
            Haptics.success()
            return true
        } catch {
            errorMessage = "Failed to save drawing: \(error.localizedDescription)"
            ErrorHandlerService.shared.handle(error, context: "ClipReviewSheet.saveDrawing", showAlert: false)
            return false
        }
    }

    // MARK: - Actions

    private func shareClip() {
        let videoID = video.id
        isPublishing = true

        Task {
            do {
                let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                try await FirestoreManager.shared.publishPrivateVideo(
                    videoID: videoID,
                    sharedFolderID: folderID,
                    notes: trimmedNotes.isEmpty ? nil : trimmedNotes
                )

                // Athlete is notified by the server-side onVideoPublished CF which
                // fires on the visibility transition private→shared.
                Haptics.success()
                dismiss()
                onShared?()
            } catch {
                errorMessage = "Failed to share clip: \(error.localizedDescription)"
                ErrorHandlerService.shared.handle(error, context: "ClipReviewSheet.shareClip", showAlert: false)
                isPublishing = false
            }
        }
    }

    private func discardClip() {
        let videoID = video.id
        isDiscarding = true

        Task {
            do {
                try await FirestoreManager.shared.deleteCoachPrivateVideo(
                    videoID: videoID,
                    sharedFolderID: folderID,
                    fileName: video.fileName
                )
                Haptics.success()
                dismiss()
                onDiscarded?()
            } catch {
                errorMessage = "Failed to discard clip: \(error.localizedDescription)"
                ErrorHandlerService.shared.handle(error, context: "ClipReviewSheet.discardClip", showAlert: false)
                isDiscarding = false
            }
        }
    }
}
