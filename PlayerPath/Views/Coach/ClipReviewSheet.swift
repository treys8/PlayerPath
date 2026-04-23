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
                            onStartDrawing: { startTelestration() }
                        )

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
            .background(Color(.systemGroupedBackground))
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
            drawingAnnotations = all.filter { $0.type == "drawing" }
        } catch {
            ErrorHandlerService.shared.handle(error, context: "ClipReviewSheet.loadDrafts.annotations", showAlert: false)
        }
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
            let annotation = try await FirestoreManager.shared.createAnnotation(
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
            drawingAnnotations.append(annotation)
            telestrationExpanded = true
            Haptics.success()
            return true
        } catch {
            errorMessage = "Failed to save drawing: \(error.localizedDescription)"
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
