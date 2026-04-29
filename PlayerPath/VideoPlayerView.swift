//
//  VideoPlayerView.swift
//  PlayerPath
//
//  Extracted from VideoClipsView.swift to be the canonical implementation.
//  Supporting views extracted to:
//  - PlayResultEditorView.swift
//  - GameLinkerView.swift
//

import SwiftUI
import AVKit
import SwiftData
import Photos
import FirebaseFirestore

struct VideoPlayerView: View {
    let clip: VideoClip
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var errorMessage = ""
    @State private var isPlayerReady = false
    @State private var isLoading = true
    @State private var shouldResumeOnActive = false
    @State private var showingRetrimFlow = false
    @State private var showingPlayResultEditor = false
    @State private var showingGameLinker = false
    @State private var showingShareToFolder = false
    @State private var showingMoveSheet = false
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @State private var isDownloadingFromCloud = false
    @State private var downloadProgress: Double = 0.0
    @State private var showingSaveSuccess = false
    @State private var saveErrorMessage: String?
    @State private var isSavingToPhotos = false
    @State private var videoDuration: Double?

    // Coach-annotation playback state — only populated when
    // `clip.sourceCoachVideoID` is set (clip was saved from a coach's shared
    // folder). Loads the original coach doc's annotations so saved-in-app
    // playback preserves drawings + coach notes.
    @State private var coachAnnotations: [VideoAnnotation] = []
    @State private var coachAnnotationsListener: ListenerRegistration?
    @State private var activeDrawingOverlay: ActiveDrawingOverlay?
    @State private var videoAspectRatio: CGFloat = 16.0 / 9.0
    @State private var coachNoteText: String = ""
    @State private var coachNoteAuthorName: String?
    @State private var coachNoteUpdatedAt: Date?
    /// Guard so the "athlete viewed this clip" write only fires once per open.
    @State private var hasMarkedViewed = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Environment(\.verticalSizeClass) private var vSizeClass
    @Environment(\.horizontalSizeClass) private var hSizeClass

    // MARK: - Shared Controls

    @ViewBuilder
    private var playerMenuItems: some View {
        if clip.playResult == nil {
            Button {
                showingPlayResultEditor = true
            } label: {
                Label("Tag Play Result", systemImage: "tag.fill")
            }
        } else {
            Button {
                showingPlayResultEditor = true
            } label: {
                Label("Edit Play Result", systemImage: AppIcon.edit)
            }
        }

        Button {
            showingGameLinker = true
        } label: {
            Label(clip.game == nil ? "Link to Game" : "Change Game", systemImage: "baseball.diamond.bases")
        }

        Button {
            clip.isHighlight.toggle()
            clip.needsSync = true
            ErrorHandlerService.shared.saveContext(modelContext, caller: "VideoPlayerView.toggleHighlight")
            Haptics.medium()
        } label: {
            Label(
                clip.isHighlight ? "Remove from Highlights" : "Add to Highlights",
                systemImage: clip.isHighlight ? "star.slash" : "star"
            )
        }

        if clip.isUploaded && clip.athlete != nil {
            Divider()
            Button {
                showingRetrimFlow = true
            } label: {
                Label("Trim Clip", systemImage: "scissors")
            }
        }

        Divider()
        Button {
            saveToPhotos()
        } label: {
            if isSavingToPhotos {
                Label { Text("Saving...") } icon: { ProgressView() }
            } else {
                Label("Save to Photos", systemImage: "square.and.arrow.down")
            }
        }
        .disabled(isSavingToPhotos)

        if FileManager.default.fileExists(atPath: clip.resolvedFilePath) {
            ShareLink(item: clip.resolvedFileURL) {
                Label("Share Video", systemImage: "square.and.arrow.up")
            }
        }
        // Upload controls
        if clip.isUploaded {
            Label("Uploaded to Cloud", systemImage: "checkmark.icloud")
                .foregroundColor(.green)
        } else if let athlete = clip.athlete {
            Button {
                Haptics.light()
                UploadQueueManager.shared.enqueue(clip, athlete: athlete, priority: .high)
            } label: {
                if UploadQueueManager.shared.activeUploads[clip.id] != nil {
                    Label("Uploading...", systemImage: "icloud.and.arrow.up")
                } else if UploadQueueManager.shared.pendingUploads.contains(where: { $0.clipId == clip.id }) {
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
            Label("Share to Coach Folder", systemImage: authManager.hasCoachingAccess ? "folder.badge.person.crop" : "lock.fill")
        }

        Divider()

        Button {
            showingMoveSheet = true
        } label: {
            Label("Move to Athlete", systemImage: "arrow.right.arrow.left")
        }
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel("Close video player")
    }

    private var landscapeControls: some View {
        VStack {
            HStack {
                Menu {
                    playerMenuItems
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                }
                .accessibilityLabel("More actions")

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                }
                .accessibilityLabel("Close video player")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Spacer()
        }
    }

    // MARK: - Computed Properties

    @ViewBuilder
    private var videoPlayerContent: some View {
        if isLoading {
            loadingView
        } else if let player = player, isPlayerReady {
            activePlayerView(player: player)
        } else if !errorMessage.isEmpty {
            errorView
        }
    }

    private var loadingView: some View {
        Color.black
            .overlay(
                VStack(spacing: 12) {
                    if isDownloadingFromCloud {
                        ProgressView(value: downloadProgress)
                            .progressViewStyle(LinearProgressViewStyle(tint: .white))
                            .frame(width: 200)
                            .padding(.bottom, 8)
                        Text("Downloading from cloud...")
                            .font(.headingMedium)
                            .foregroundColor(.white)
                        Text("\(Int(downloadProgress * 100))%")
                            .font(.bodySmall)
                            .monospacedDigit()
                            .foregroundColor(.white.opacity(0.8))
                    } else {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                        Text("Loading video...")
                            .font(.headingMedium)
                            .foregroundColor(.white)
                    }
                }
            )
    }

    private func activePlayerView(player: AVPlayer) -> some View {
        ZStack {
            EnhancedVideoPlayer(player: player, preloadedDuration: videoDuration, onClose: { dismiss() })
                .accessibilityLabel("Video player")

            // Tappable timeline markers for coach annotations (drawings only
            // are interactive; text annotations render as inert markers).
            if activeDrawingOverlay == nil,
               !coachAnnotations.isEmpty,
               let duration = videoDuration, duration > 0 {
                AnnotationMarkersOverlay(
                    annotations: coachAnnotations,
                    duration: duration,
                    onTapDrawing: { annotation in showDrawing(for: annotation) }
                )
            }

            // Read-only drawing overlay — shown when user taps a drawing marker.
            if let overlay = activeDrawingOverlay {
                DrawingAnnotationOverlay(
                    drawingData: overlay.data,
                    videoAspectRatio: videoAspectRatio,
                    canvasSize: overlay.canvasSize,
                    shapes: overlay.shapes,
                    onDismiss: { activeDrawingOverlay = nil }
                )
            }
        }
    }

    private func showDrawing(for annotation: VideoAnnotation) {
        guard let data = annotation.drawingPKData else { return }
        player?.pause()
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

    /// Writes the athlete's view receipt against the source coach video so
    /// the coach folder grid can show a "Viewed" pill. Only runs for clips
    /// derived from a coach folder (`sourceCoachVideoID` set), once per open.
    private func markCoachClipViewedIfNeeded() {
        guard !hasMarkedViewed,
              let sourceID = clip.sourceCoachVideoID, !sourceID.isEmpty,
              let athleteID = authManager.userID else { return }
        hasMarkedViewed = true
        Task {
            do {
                try await FirestoreManager.shared.markVideoViewedByAthlete(
                    videoID: sourceID,
                    athleteID: athleteID
                )
            } catch {
                ErrorHandlerService.shared.handle(error, context: "VideoPlayer.markCoachClipViewed", showAlert: false)
            }
        }
    }

    /// Loads coach-authored annotations for this clip from the original coach
    /// video doc (pointed at by `clip.sourceCoachVideoID`). Also attaches a
    /// live listener so new coach drawings appear without a refetch.
    /// One-shot fetch of the source doc populates the plain coach note so the
    /// athlete sees it below the player (matches CoachVideoPlayerView).
    private func loadCoachAnnotationsIfNeeded() {
        guard let sourceID = clip.sourceCoachVideoID, !sourceID.isEmpty else { return }

        Task {
            if let fetched = try? await FirestoreManager.shared.fetchAnnotations(forVideo: sourceID) {
                await MainActor.run { coachAnnotations = fetched.sorted { $0.timestamp < $1.timestamp } }
            }
            if let video = try? await FirestoreManager.shared.fetchVideo(videoID: sourceID) {
                await MainActor.run {
                    coachNoteText = video.coachNote ?? ""
                    coachNoteAuthorName = video.coachNoteAuthorName
                    coachNoteUpdatedAt = video.coachNoteUpdatedAt
                }
            }
        }

        coachAnnotationsListener?.remove()
        coachAnnotationsListener = FirestoreManager.shared.listenToAnnotations(forVideo: sourceID) { updated in
            coachAnnotations = updated.sorted { $0.timestamp < $1.timestamp }
        }
    }

    /// Computes the display aspect ratio by applying the video's preferred
    /// transform to its natural size. Required for correct drawing-overlay
    /// scaling when the clip was originally recorded in portrait.
    ///
    /// Prefers the player's already-loaded asset (set up by `setupPlayer`) so
    /// we don't refetch remote metadata for cloud-streamed clips. Falls back
    /// to a fresh local asset only if the player isn't ready yet.
    private func loadVideoAspectRatio() async {
        let asset: AVAsset = player?.currentItem?.asset
            ?? AVURLAsset(url: clip.resolvedFileURL)
        if let track = try? await asset.loadTracks(withMediaType: .video).first,
           let size = try? await track.load(.naturalSize),
           let transform = try? await track.load(.preferredTransform) {
            let rendered = size.applying(transform)
            let w = abs(rendered.width)
            let h = abs(rendered.height)
            if h > 0 {
                await MainActor.run { videoAspectRatio = w / h }
            }
        }
    }

    private var errorView: some View {
        Color.black
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.yellow)
                    Text("Video Unavailable")
                        .font(.headingLarge)
                        .foregroundColor(.white)
                    Text(errorMessage)
                        .font(.bodySmall)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .accessibilityLabel("Error: \(errorMessage)")
                    Button("Try Again") {
                        Haptics.light()
                        Task { await setupPlayer() }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.brandNavy)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .padding(.top)
                    .accessibilityLabel("Try loading the video again")
                }
            )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 0) {
                    videoPlayerContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)

                    if vSizeClass != .compact {
                        if !coachNoteText.isEmpty {
                            CoachNoteCard(
                                text: coachNoteText,
                                authorName: coachNoteAuthorName,
                                updatedAt: coachNoteUpdatedAt
                            )
                        }
                        VideoClipInfoCard(clip: clip)
                            .padding(.bottom, 8)
                    }
                }

                if vSizeClass == .compact {
                    landscapeControls
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(vSizeClass == .compact ? .hidden : .visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        playerMenuItems
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .accessibilityLabel("More actions")
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    closeButton
                }
            }
        }
        .task(id: clip.version) {
            await setupPlayer()
            // Coach-annotation + aspect-ratio loading is only meaningful for
            // clips saved from a coach's shared folder — gated internally.
            loadCoachAnnotationsIfNeeded()
            if clip.sourceCoachVideoID != nil {
                await loadVideoAspectRatio()
                markCoachClipViewedIfNeeded()
            }
        }
        .onDisappear {
            player?.pause()
            coachAnnotationsListener?.remove()
            coachAnnotationsListener = nil
        }
        .sheet(isPresented: $showingPlayResultEditor) {
            PlayResultEditorView(clip: clip, modelContext: modelContext)
        }
        .sheet(isPresented: $showingGameLinker) {
            GameLinkerView(clip: clip)
        }
        .sheet(isPresented: $showingShareToFolder) {
            ShareToCoachFolderView(clip: clip)
        }
        .sheet(isPresented: $showingMoveSheet) {
            MoveClipSheet(clip: clip)
        }
        .fullScreenCover(isPresented: $showingRetrimFlow) {
            if let athlete = clip.athlete {
                RetrimSavedClipFlow(clip: clip, athlete: athlete)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                if shouldResumeOnActive, isPlayerReady {
                    player?.play()
                }
                shouldResumeOnActive = false
            case .inactive, .background:
                shouldResumeOnActive = (player?.rate ?? 0) > 0
                player?.pause()
            @unknown default:
                player?.pause()
            }
        }
        .toast(isPresenting: $showingSaveSuccess, message: "Saved to Photos")
        .alert("Save Failed", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("OK") { }
        } message: {
            Text(saveErrorMessage ?? "Unknown error")
        }
    }

    private func saveToPhotos() {
        guard !isSavingToPhotos else { return }
        isSavingToPhotos = true
        let videoURL = clip.resolvedFileURL
        guard FileManager.default.fileExists(atPath: clip.resolvedFilePath) else {
            isSavingToPhotos = false
            saveErrorMessage = "Video file not found"
            return
        }

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    self.isSavingToPhotos = false
                    self.saveErrorMessage = "Photo library access denied. Please enable in Settings."
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
                        self.saveErrorMessage = error?.localizedDescription ?? "Failed to save video"
                    }
                }
            }
        }
    }

    private func setupPlayer() async {

        guard !Task.isCancelled else {
            return
        }

        await MainActor.run {
            isLoading = true
            errorMessage = ""
            player = nil
            isPlayerReady = false
            isDownloadingFromCloud = false
            downloadProgress = 0.0
        }

        guard !Task.isCancelled else {
            return
        }

        let result = await findVideoURL()
        guard let url = result.url else {
            await MainActor.run {
                isLoading = false
                errorMessage = "Video file not found. It may have been moved or deleted."
            }
            return
        }

        guard !Task.isCancelled else {
            return
        }

        await loadPlayer(from: url, isLocal: result.isLocal)
    }

    private struct VideoURLResult {
        let url: URL?
        let isLocal: Bool
    }

    private func findVideoURL() async -> VideoURLResult {
        let primaryURL = clip.resolvedFileURL

        if FileManager.default.fileExists(atPath: clip.resolvedFilePath) {
            return VideoURLResult(url: primaryURL, isLocal: true)
        }

        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return VideoURLResult(url: nil, isLocal: false)
        }
        let alternateURL = documentsPath.appendingPathComponent(clip.fileName)

        if FileManager.default.fileExists(atPath: alternateURL.path) {
            return VideoURLResult(url: alternateURL, isLocal: true)
        }

        // Try downloading from cloud if cloudURL exists and file is uploaded
        if let cloudURL = clip.cloudURL, clip.isUploaded {
            var downloadURL = cloudURL
            if let ownerUID = authManager.userID, !clip.fileName.isEmpty {
                do {
                    downloadURL = try await SecureURLManager.shared.getPersonalVideoURL(
                        ownerUID: ownerUID,
                        fileName: clip.fileName
                    )
                } catch {
                    ErrorHandlerService.shared.handle(error, context: "VideoPlayerView.getSignedURL", showAlert: false)
                }
            }

            await MainActor.run {
                isDownloadingFromCloud = true
                downloadProgress = 0.0
            }

            let clipsDirectory = documentsPath.appendingPathComponent("Clips", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: clipsDirectory, withIntermediateDirectories: true)
            } catch {
                ErrorHandlerService.shared.handle(error, context: "VideoPlayerView.createClipsDirectory", showAlert: false)
            }
            let destinationPath = clipsDirectory.appendingPathComponent(clip.fileName).path

            let cloudManager = VideoCloudManager.shared
            let clipId = clip.id

            let progressTask = Task { @MainActor in
                while !Task.isCancelled {
                    if let progress = cloudManager.downloadProgress[clipId] {
                        downloadProgress = progress
                    }
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }

            do {
                try await cloudManager.downloadVideo(from: downloadURL, to: destinationPath, clipId: clipId)

                progressTask.cancel()

                await MainActor.run {
                    clip.updateFilePath(VideoClip.toRelativePath(destinationPath))
                    ErrorHandlerService.shared.saveContext(modelContext, caller: "VideoPlayerView.downloadComplete")
                    isDownloadingFromCloud = false
                }

                return VideoURLResult(url: URL(fileURLWithPath: destinationPath), isLocal: true)

            } catch {
                progressTask.cancel()
                await MainActor.run {
                    isDownloadingFromCloud = false
                    errorMessage = "Failed to download video from cloud: \(error.localizedDescription)"
                }
                return VideoURLResult(url: nil, isLocal: false)
            }
        }

        return VideoURLResult(url: nil, isLocal: false)
    }

    private func loadPlayer(from url: URL, isLocal: Bool = false) async {

        guard !Task.isCancelled else {
            return
        }

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        let newPlayer = AVPlayer(playerItem: item)

        if isLocal {
            await MainActor.run {
                self.player = newPlayer
                self.isPlayerReady = true
                self.isLoading = false
            }
            if let loadedDuration = try? await asset.load(.duration) {
                await MainActor.run {
                    self.videoDuration = CMTimeGetSeconds(loadedDuration)
                }
            }
        } else {
            do {
                let (isPlayable, loadedDuration) = try await asset.load(.isPlayable, .duration)

                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    if isPlayable {
                        self.player = newPlayer
                        self.isPlayerReady = true
                        self.isLoading = false
                        self.videoDuration = CMTimeGetSeconds(loadedDuration)
                    } else {
                        self.isLoading = false
                        self.errorMessage = "Video file is not playable"
                    }
                }
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = "Unable to load video: \(error.localizedDescription)"
                }
            }
        }
    }

}

#Preview {
    let mock = VideoClip(fileName: "mock.mov", filePath: "/tmp/mock.mov")
    return VideoPlayerView(clip: mock)
}

// MARK: - Video Clip Info Card
struct VideoClipInfoCard: View {
    let clip: VideoClip

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if let playResult = clip.playResult {
                Text(playResult.type.displayName)
                    .font(.headingLarge)
            } else {
                Text("Unrecorded")
                    .font(.headingLarge)
                    .foregroundColor(.secondary)
            }

            if let game = clip.game {
                Text("vs \(game.opponent)")
                    .font(.bodyMedium)
                    .foregroundColor(.secondary)
            } else if clip.practice != nil {
                Text("Practice")
                    .font(.bodyMedium)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if clip.isHighlight {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
                    .font(.body)
            }

            if let createdAt = clip.createdAt {
                Text(createdAt, format: .dateTime.month(.abbreviated).day().year())
                    .font(.bodyMedium)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(uiColor: .systemBackground))
    }
}
