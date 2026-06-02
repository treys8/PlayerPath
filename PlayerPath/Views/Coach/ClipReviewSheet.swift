//
//  ClipReviewSheet.swift
//  PlayerPath
//
//  Unified review sheet for a coach-owned private clip. Coach can draft
//  notes, drill cards, and telestration drawings in one pass, then
//  "Share Now" (atomic publish) or "Save for Later" (keep private).
//  Drafts persist on the private clip; the athlete only sees anything
//  once the clip is published.
//

import SwiftUI
import AVKit
import PencilKit

struct ClipReviewSheet: View {
    let video: CoachVideoItem
    let folder: SharedFolder
    var onShared: (() -> Void)?
    var onDiscarded: (() -> Void)?
    var onSavedDraft: (() -> Void)?

    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.ppAccentLight) private var ppAccentLight
    @State private var notes: String
    @State private var isPublishing = false
    @State private var isSavingDraft = false
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
    @State private var telestrationFrameImage: UIImage?
    @State private var isPreparingTelestration = false

    // Drafts (drill cards + drawings attached to the still-private clip)
    @State private var drillCards: [DrillCard] = []
    @State private var drawingAnnotations: [VideoAnnotation] = []
    @State private var isLoadingDrafts = false
    @State private var showingDrillEditor = false
    @State private var drillExpanded = false
    @State private var telestrationExpanded = false

    /// Read-only overlay shown when the coach taps a saved drawing row.
    /// Tapping the overlay clears it and leaves the player paused at the
    /// seeked frame — no auto-resume (this is an editing surface).
    @State private var activeDrawingOverlay: ActiveDrawingOverlay?

    private var currentPlaybackTime: Double {
        player?.currentTime().seconds ?? 0
    }

    private var folderID: String { folder.id ?? "" }

    private var hasDrafts: Bool {
        !drillCards.isEmpty || !drawingAnnotations.isEmpty
    }

    private var trimmedNotes: String {
        notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var notesDirty: Bool {
        trimmedNotes != (video.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
    }

    init(
        video: CoachVideoItem,
        folder: SharedFolder,
        onShared: (() -> Void)? = nil,
        onDiscarded: (() -> Void)? = nil,
        onSavedDraft: (() -> Void)? = nil
    ) {
        self.video = video
        self.folder = folder
        self.onShared = onShared
        self.onDiscarded = onDiscarded
        self.onSavedDraft = onSavedDraft
        self._notes = State(initialValue: video.notes ?? "")
    }

    var body: some View {
        navigationContent
            .fullScreenCover(isPresented: $showingTelestration, onDismiss: {
                telestrationFrameImage = nil
            }) {
                TelestrationOverlayView(
                    timestamp: currentPlaybackTime,
                    videoAspectRatio: videoAspectRatio,
                    onSave: { drawing, shapes, timestamp, canvasSize in
                        guard let userID = authManager.userID,
                              let userName = authManager.userDisplayName ?? authManager.userEmail else {
                            return "You're signed out. Sign in again to save this drawing."
                        }
                        let saved = await saveDrawing(
                            drawing: drawing,
                            shapes: shapes,
                            timestamp: timestamp,
                            canvasSize: canvasSize,
                            userID: userID,
                            userName: userName
                        )
                        if saved {
                            showingTelestration = false
                            return nil
                        }
                        return "Drawing couldn't be saved. Check your connection and try again."
                    },
                    onCancel: { showingTelestration = false },
                    frameImage: telestrationFrameImage
                )
            }
            .sheet(isPresented: $showingDrillEditor) {
                drillEditorSheet
            }
    }

    @ViewBuilder
    private var drillEditorSheet: some View {
        if let coachID = authManager.userID {
            DrillCardView(
                videoID: video.id,
                coachID: coachID,
                coachName: authManager.userDisplayName ?? authManager.userEmail ?? "Coach",
                onSave: { card in
                    drillCards.insert(card, at: 0)
                    drillExpanded = true
                }
            )
        }
    }

    private var navigationContent: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 16) {
                        videoPlayerSection

                        notesSection

                        ClipReviewDrillSection(
                            drillCards: drillCards,
                            isLoading: isLoadingDrafts,
                            isExpanded: $drillExpanded,
                            onAdd: { showingDrillEditor = true }
                        )

                        ClipReviewTelestrationSection(
                            drawings: drawingAnnotations,
                            isLoading: isLoadingDrafts,
                            isStartingTelestration: isPreparingTelestration,
                            canStart: player != nil && !isLoadingVideo,
                            isExpanded: $telestrationExpanded,
                            onStartDrawing: { startTelestration() },
                            onTapDrawing: { drawing in showDrawing(for: drawing) }
                        )

                        if video.club != nil || video.holeNumber != nil || video.createdAt != nil || (video.fileSize ?? 0) > 0 {
                            VStack(spacing: 0) {
                                if let club = video.club {
                                    infoRow(label: "Club", value: club)
                                }
                                if let hole = video.holeNumber {
                                    if video.club != nil { Divider().padding(.leading) }
                                    infoRow(label: "Hole", value: "\(hole)")
                                }
                                if let createdAt = video.createdAt {
                                    if video.club != nil || video.holeNumber != nil { Divider().padding(.leading) }
                                    infoRow(label: "Recorded", value: createdAt.formatted(date: .abbreviated, time: .shortened))
                                }
                                if let fileSize = video.fileSize, fileSize > 0 {
                                    if video.club != nil || video.holeNumber != nil || video.createdAt != nil { Divider().padding(.leading) }
                                    infoRow(label: "Size", value: ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))
                                }
                            }
                            .background(Theme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .padding(.horizontal)
                        }
                    }
                    .padding(.bottom, 8)
                }

                ClipReviewPublishBar(
                    isPublishing: isPublishing,
                    isSavingDraft: isSavingDraft,
                    isDiscarding: isDiscarding,
                    onShareNow: { shareNow() },
                    onSaveForLater: { saveForLater() },
                    onDiscard: { showingDiscardConfirmation = true }
                )
            }
            .background(Theme.surface)
            .navigationTitle("Review Clip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        startTelestration()
                    } label: {
                        if isPreparingTelestration {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "pencil.tip")
                                .foregroundColor(.brandNavy)
                        }
                    }
                    .disabled(player == nil || isLoadingVideo || isPreparingTelestration)
                    .accessibilityLabel("Draw on video frame")
                }
            }
            .alert("Discard this clip?", isPresented: $showingDiscardConfirmation) {
                Button("Discard", role: .destructive) { discardClip() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(discardMessage)
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
                async let videoLoad: Void = loadVideo()
                async let draftsLoad: Void = loadDrafts()
                _ = await (videoLoad, draftsLoad)
            }
            .onDisappear {
                player?.pause()
                player = nil
            }
        }
    }

    private var discardMessage: String {
        if !hasDrafts {
            return "This clip will be permanently deleted."
        }
        var pieces: [String] = []
        if !drillCards.isEmpty {
            pieces.append(drillCards.count == 1 ? "your drill card" : "\(drillCards.count) drill cards")
        }
        if !drawingAnnotations.isEmpty {
            pieces.append(drawingAnnotations.count == 1 ? "1 drawing" : "\(drawingAnnotations.count) drawings")
        }
        let tail = pieces.joined(separator: " and ")
        return "This clip and \(tail) will be permanently deleted."
    }

    // MARK: - Notes Section

    private var notesSection: some View {
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
                        .foregroundColor(Theme.warning)
                    Text(videoError)
                        .font(.caption)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await loadVideo() }
                    }
                    .font(.caption)
                    .foregroundColor(ppAccentLight)
                }
                .padding()
            } else if let player {
                EnhancedVideoPlayer(
                    player: player,
                    preloadedDuration: video.duration,
                    alwaysShowControls: true
                )
                // Mirror `CoachVideoPlayerView` — block underlying player
                // gestures (zoom/pan/tap-to-pause) while the read-only
                // drawing overlay is up; only the overlay's own tap-to-
                // dismiss should fire.
                .allowsHitTesting(activeDrawingOverlay == nil)

                if let overlay = activeDrawingOverlay {
                    DrawingAnnotationOverlay(
                        drawingData: overlay.data,
                        videoAspectRatio: videoAspectRatio,
                        canvasSize: overlay.canvasSize,
                        shapes: overlay.shapes,
                        onDismiss: { dismissDrawing() }
                    )
                }
            }
        }
        .aspectRatio(videoAspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.top, 8)
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
           let transform = try? await track.load(.preferredTransform) {
            let rendered = size.applying(transform)
            let w = abs(rendered.width)
            let h = abs(rendered.height)
            if h > 0 { videoAspectRatio = w / h }
        }

        isLoadingVideo = false
    }

    // MARK: - Drafts Loading

    @MainActor
    private func loadDrafts() async {
        let videoID = video.id
        guard !videoID.isEmpty else { return }
        isLoadingDrafts = true
        defer { isLoadingDrafts = false }

        async let cardsResult = FirestoreManager.shared.fetchDrillCards(forVideo: videoID)
        async let annotationsResult = FirestoreManager.shared.fetchAnnotations(forVideo: videoID)

        do {
            drillCards = try await cardsResult
        } catch {
            ErrorHandlerService.shared.handle(error, context: "ClipReviewSheet.loadDrafts.drillCards", showAlert: false)
        }

        do {
            let all = try await annotationsResult
            drawingAnnotations = all.filter { $0.isDrawing }
        } catch {
            ErrorHandlerService.shared.handle(error, context: "ClipReviewSheet.loadDrafts.annotations", showAlert: false)
        }
    }

    // MARK: - Drawing Overlay (read-only)

    /// Pause + seek to the drawing's timestamp and show it as an overlay.
    /// Mirrors `CoachVideoPlayerViewModel.showDrawingOverlay(for:)` but lives
    /// directly on the view because this sheet has no view-model.
    @MainActor
    private func showDrawing(for annotation: VideoAnnotation) {
        guard let data = annotation.drawingPKData else { return }
        // 600 is the codebase convention for video timescales; CMTimeScale is
        // Int32 and NSEC_PER_SEC (1e9) silently inflates math precision in
        // ways AVFoundation isn't expecting.
        let cmTime = CMTimeMakeWithSeconds(annotation.timestamp, preferredTimescale: 600)
        player?.pause()
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        let size: CGSize? = {
            guard let w = annotation.drawingCanvasWidth,
                  let h = annotation.drawingCanvasHeight,
                  w > 0, h > 0 else { return nil }
            return CGSize(width: w, height: h)
        }()
        activeDrawingOverlay = ActiveDrawingOverlay(
            data: data,
            canvasSize: size,
            shapes: annotation.decodedShapes
        )
    }

    /// Clear the overlay. Deliberately does NOT resume playback — the coach
    /// is editing, not consuming a lesson, so we leave them paused at the
    /// seeked frame, ready to draw again or scrub.
    @MainActor
    private func dismissDrawing() {
        activeDrawingOverlay = nil
    }

    // MARK: - Telestration

    @MainActor
    private func startTelestration() {
        guard let player, !isPreparingTelestration else { return }
        player.pause()
        isPreparingTelestration = true
        let captureTime = player.currentTime()
        let asset = player.currentItem?.asset
        Task {
            // Re-verify folder permission before letting the coach draw —
            // shares can be revoked mid-session, and the server will reject
            // the write anyway. Cleaner to surface here than on save.
            if let coachID = authManager.userID,
               coachID != folder.ownerAthleteID,
               let folderID = folder.id {
                do {
                    let latest = try await SharedFolderManager.shared.verifyFolderAccess(folderID: folderID, coachID: coachID)
                    guard latest.getPermissions(for: coachID)?.canComment ?? false else {
                        errorMessage = "You no longer have permission to draw on this folder."
                        isPreparingTelestration = false
                        return
                    }
                } catch {
                    errorMessage = "Unable to verify permissions. Please try again."
                    isPreparingTelestration = false
                    return
                }
            }

            let image = await captureFrame(from: asset, at: captureTime)
            telestrationFrameImage = image
            isPreparingTelestration = false
            showingTelestration = true
        }
    }

    private func captureFrame(from asset: AVAsset?, at time: CMTime) async -> UIImage? {
        guard let asset else { return nil }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        do {
            let cgImage = try await generator.image(at: time).image
            return UIImage(cgImage: cgImage)
        } catch {
            ErrorHandlerService.shared.handle(error, context: "ClipReviewSheet.captureFrame", showAlert: false)
            return nil
        }
    }

    @MainActor
    private func saveDrawing(
        drawing: PKDrawing,
        shapes: [TelestrationShape],
        timestamp: Double,
        canvasSize: CGSize,
        userID: String,
        userName: String
    ) async -> Bool {
        do {
            let annotation = try await DrawingAnnotationSaver.save(
                videoID: video.id,
                drawing: drawing,
                shapes: shapes,
                timestamp: timestamp,
                canvasSize: canvasSize,
                userID: userID,
                userName: userName
            )
            drawingAnnotations.append(annotation)
            telestrationExpanded = true
            Haptics.success()
            return true
        } catch {
            errorMessage = error.localizedDescription
            ErrorHandlerService.shared.handle(error, context: "ClipReviewSheet.saveDrawing", showAlert: false)
            return false
        }
    }

    // MARK: - Actions

    private func shareNow() {
        let videoID = video.id
        isPublishing = true

        Task {
            do {
                let notesArg = trimmedNotes.isEmpty ? nil : trimmedNotes
                try await FirestoreManager.shared.publishPrivateVideo(
                    videoID: videoID,
                    sharedFolderID: folderID,
                    notes: notesArg
                )
                Haptics.success()
                dismiss()
                onShared?()
            } catch {
                errorMessage = "Failed to share clip: \(error.localizedDescription)"
                ErrorHandlerService.shared.handle(error, context: "ClipReviewSheet.shareNow", showAlert: false)
                isPublishing = false
            }
        }
    }

    private func saveForLater() {
        guard notesDirty else {
            Haptics.light()
            dismiss()
            onSavedDraft?()
            return
        }
        guard let authorID = authManager.userID,
              let authorName = authManager.userDisplayName ?? authManager.userEmail else {
            dismiss()
            return
        }
        let videoID = video.id
        isSavingDraft = true
        Task {
            do {
                try await FirestoreManager.shared.setCoachNote(
                    videoID: videoID,
                    text: trimmedNotes.isEmpty ? nil : trimmedNotes,
                    authorID: authorID,
                    authorName: authorName
                )
                Haptics.success()
                dismiss()
                onSavedDraft?()
            } catch {
                errorMessage = "Failed to save note: \(error.localizedDescription)"
                ErrorHandlerService.shared.handle(error, context: "ClipReviewSheet.saveForLater", showAlert: false)
                isSavingDraft = false
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
