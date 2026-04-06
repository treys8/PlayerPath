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

struct VideoPlayerView: View {
    let clip: VideoClip
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var errorMessage = ""
    @State private var isPlayerReady = false
    @State private var isLoading = true
    @State private var hasAppeared = false
    @State private var shouldResumeOnActive = false
    @State private var showingRetrimFlow = false
    @State private var showingPlayResultEditor = false
    @State private var showingGameLinker = false
    @State private var showingShareToFolder = false
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @State private var setupTask: Task<Void, Never>?
    @State private var isDownloadingFromCloud = false
    @State private var downloadProgress: Double = 0.0
    @State private var showingSaveSuccess = false
    @State private var saveErrorMessage: String?
    @State private var isSavingToPhotos = false
    @State private var videoDuration: Double?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Environment(\.verticalSizeClass) private var vSizeClass

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
                            .font(.headline)
                            .foregroundColor(.white)
                        Text("\(Int(downloadProgress * 100))%")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    } else {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                        Text("Loading video...")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                }
            )
    }

    private func activePlayerView(player: AVPlayer) -> some View {
        EnhancedVideoPlayer(player: player, preloadedDuration: videoDuration, onClose: { dismiss() })
            .accessibilityLabel("Video player")
            .onDisappear {
                player.pause()
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
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(errorMessage)
                        .font(.caption)
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
            VStack(spacing: 0) {
                // Video Player - fills available space
                videoPlayerContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)

                // Video Info - hidden in landscape so video fills the screen
                if vSizeClass != .compact {
                    VideoClipInfoCard(clip: clip)
                        .padding(.bottom, 8)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(vSizeClass == .compact ? .hidden : .visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Button {
                            showingPlayResultEditor = true
                        } label: {
                            Label("Edit Play Result", systemImage: "pencil.circle")
                        }
                        .accessibilityLabel("Edit the play result for this video")

                        Button {
                            showingGameLinker = true
                        } label: {
                            Label(clip.game == nil ? "Link to Game" : "Change Game", systemImage: "baseball.diamond.bases")
                        }
                        .accessibilityLabel(clip.game == nil ? "Link this video to a game" : "Change which game this video is linked to")

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
                        .accessibilityLabel(clip.isHighlight ? "Remove this video from highlights" : "Add this video to highlights")

                        if clip.isUploaded && clip.athlete != nil {
                            Divider()
                            Button {
                                showingRetrimFlow = true
                            } label: {
                                Label("Trim Clip", systemImage: "scissors")
                            }
                            .accessibilityLabel("Trim this video")
                        }

                        Divider()
                        Button {
                            saveToPhotos()
                        } label: {
                            if isSavingToPhotos {
                                Label {
                                    Text("Saving...")
                                } icon: {
                                    ProgressView()
                                }
                            } else {
                                Label("Save to Photos", systemImage: "square.and.arrow.down")
                            }
                        }
                        .disabled(isSavingToPhotos)
                        .accessibilityLabel("Save video to Photos library")
                        ShareLink(item: clip.resolvedFileURL) {
                            Label("Share Video", systemImage: "square.and.arrow.up")
                        }
                        if AppFeatureFlags.isCoachEnabled {
                            Divider()
                            Button {
                                showingShareToFolder = true
                            } label: {
                                Label("Share to Coach Folder", systemImage: authManager.hasCoachingAccess ? "folder.badge.person.crop" : "lock.fill")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .accessibilityLabel("More actions")
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
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
            }
        }
        .onAppear {
            if !hasAppeared {
                hasAppeared = true
                setupTask = Task { await setupPlayer() }
            }
        }
        .onChange(of: clip.version) { _, _ in
            // Re-trim bumps version — reload the player so the new file is picked up.
            setupTask?.cancel()
            setupTask = Task { await setupPlayer() }
        }
        .onDisappear {
            setupTask?.cancel()
            setupTask = nil
            player?.pause()
            player?.replaceCurrentItem(with: nil)
            player = nil
            isPlayerReady = false
            isLoading = true
            hasAppeared = false
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
                    clip.filePath = VideoClip.toRelativePath(destinationPath)
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
        HStack(spacing: 12) {
            if let playResult = clip.playResult {
                Text(playResult.type.displayName)
                    .font(.headline)
                    .fontWeight(.bold)
            } else {
                Text("Unrecorded")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }

            if let game = clip.game {
                Text("vs \(game.opponent)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else if clip.practice != nil {
                Text("Practice")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if clip.isHighlight {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
                    .font(.body)
            }

            if let createdAt = clip.createdAt {
                Text(createdAt, format: .dateTime.month(.abbreviated).day())
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(uiColor: .systemBackground))
    }
}
