//
//  VideoPlayerView.swift
//  PlayerPath
//
//  Extracted from VideoClipsView.swift to be the canonical implementation.
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
    @State private var showingVideoEditor = false
    @State private var shouldResumeOnActive = false
    @State private var videoAspect: CGFloat? // width / height
    @State private var showingTrimmer = false
    @State private var showingPlayResultEditor = false
    @State private var showingGameLinker = false
    @State private var setupTask: Task<Void, Never>?
    @State private var isDownloadingFromCloud = false
    @State private var downloadProgress: Double = 0.0
    @State private var showingSaveSuccess = false
    @State private var saveErrorMessage: String?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    
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
        EnhancedVideoPlayer(player: player)
            .accessibilityLabel("Video player")
            .onDisappear {
                print("VideoPlayerView: VideoPlayer disappeared, pausing playback")
                player.pause()
            }
    }
    
    private var errorView: some View {
        Color.black
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
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
                    .background(Color.blue)
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

                // Video Info - compact at bottom with safe area padding
                VideoClipInfoCard(clip: clip)
                    .padding(.bottom, 8)
            }
            .navigationBarTitleDisplayMode(.inline)
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
                            Label(clip.game == nil ? "Link to Game" : "Change Game", systemImage: "sportscourt")
                        }
                        .accessibilityLabel(clip.game == nil ? "Link this video to a game" : "Change which game this video is linked to")

                        Divider()

                        Button {
                            showingVideoEditor = true
                        } label: {
                            Text("Edit Video")
                        }
                        .accessibilityLabel("Edit this video")
                        Button {
                            showingTrimmer = true
                        } label: {
                            Text("Trim Clip")
                        }
                        .accessibilityLabel("Trim this video")
                        Divider()
                        Button {
                            saveToPhotos()
                        } label: {
                            Label("Save to Photos", systemImage: "square.and.arrow.down")
                        }
                        .accessibilityLabel("Save video to Photos library")
                        ShareLink(item: URL(fileURLWithPath: clip.filePath)) {
                            Label("Share Video", systemImage: "square.and.arrow.up")
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
                print("VideoPlayerView: View appeared, setting up player")
                setupTask = Task { await setupPlayer() }
            }
        }
        .onDisappear {
            print("VideoPlayerView: View disappeared")
            setupTask?.cancel()
            setupTask = nil
            player?.pause()
            player?.replaceCurrentItem(with: nil)
            player = nil
            isPlayerReady = false
            isLoading = true
            hasAppeared = false
        }
        .sheet(isPresented: $showingVideoEditor) {
            VideoEditorStub(clip: clip)
        }
        .sheet(isPresented: $showingTrimmer) {
            if let player = player {
                VideoTrimmerSheet(player: player, sourceURL: URL(fileURLWithPath: clip.filePath)) { outputURL in
                    // Reload player with trimmed clip
                    Task { await reloadPlayer(with: outputURL) }
                }
            } else {
                Text("Player unavailable")
                    .padding()
            }
        }
        .sheet(isPresented: $showingPlayResultEditor) {
            PlayResultEditorView(clip: clip, modelContext: modelContext)
        }
        .sheet(isPresented: $showingGameLinker) {
            GameLinkerView(clip: clip)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                if shouldResumeOnActive, isPlayerReady, !showingVideoEditor {
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
        .alert("Saved to Photos", isPresented: $showingSaveSuccess) {
            Button("OK") { }
        } message: {
            Text("Video has been saved to your Photos library.")
        }
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
        let videoURL = URL(fileURLWithPath: clip.filePath)
        guard FileManager.default.fileExists(atPath: clip.filePath) else {
            saveErrorMessage = "Video file not found"
            return
        }

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    self.saveErrorMessage = "Photo library access denied. Please enable in Settings."
                }
                return
            }

            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
            } completionHandler: { success, error in
                DispatchQueue.main.async {
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
        print("VideoPlayerView: Starting player setup for clip: \(clip.fileName)")

        guard !Task.isCancelled else {
            print("VideoPlayerView: Setup cancelled before start")
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
            print("VideoPlayerView: Setup cancelled after state reset")
            return
        }

        print("VideoPlayerView: File path: \(clip.filePath)")

        guard let url = await findVideoURL() else {
            print("VideoPlayerView: No valid video file found")
            await MainActor.run {
                isLoading = false
                errorMessage = "Video file not found. It may have been moved or deleted."
            }
            return
        }

        guard !Task.isCancelled else {
            print("VideoPlayerView: Setup cancelled after finding URL")
            return
        }

        await loadPlayer(from: url)
    }
    
    private func findVideoURL() async -> URL? {
        let primaryURL = URL(fileURLWithPath: clip.filePath)

        if FileManager.default.fileExists(atPath: clip.filePath) {
            print("VideoPlayerView: File exists at primary path")
            return primaryURL
        }

        print("VideoPlayerView: File not found at primary path, trying alternate")
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("VideoPlayerView: Could not access documents directory")
            return nil
        }
        let alternateURL = documentsPath.appendingPathComponent(clip.fileName)

        if FileManager.default.fileExists(atPath: alternateURL.path) {
            print("VideoPlayerView: File found at alternate path: \(alternateURL.path)")
            return alternateURL
        }

        // Try downloading from cloud if cloudURL exists and file is uploaded
        if let cloudURL = clip.cloudURL, clip.isUploaded {
            print("VideoPlayerView: File not found locally, attempting cloud download from: \(cloudURL)")

            do {
                await MainActor.run {
                    isDownloadingFromCloud = true
                    downloadProgress = 0.0
                }

                // Create destination path in Documents/Clips directory
                let clipsDirectory = documentsPath.appendingPathComponent("Clips", isDirectory: true)
                try? FileManager.default.createDirectory(at: clipsDirectory, withIntermediateDirectories: true)
                let destinationPath = clipsDirectory.appendingPathComponent(clip.fileName).path

                // Download from cloud with progress updates
                let cloudManager = VideoCloudManager.shared

                // Start monitoring download progress
                let progressTask = Task { @MainActor in
                    while isDownloadingFromCloud {
                        if let progress = cloudManager.downloadProgress[clip.id] {
                            downloadProgress = progress
                        }
                        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                    }
                }

                try await cloudManager.downloadVideo(from: cloudURL, to: destinationPath, clipId: clip.id)

                // Stop progress monitoring
                progressTask.cancel()

                // Update clip's filePath in database
                await MainActor.run {
                    clip.filePath = destinationPath
                    try? modelContext.save()
                    isDownloadingFromCloud = false
                }

                print("VideoPlayerView: Successfully downloaded video from cloud to: \(destinationPath)")
                return URL(fileURLWithPath: destinationPath)

            } catch {
                print("VideoPlayerView: Failed to download from cloud: \(error.localizedDescription)")
                await MainActor.run {
                    isDownloadingFromCloud = false
                    errorMessage = "Failed to download video from cloud: \(error.localizedDescription)"
                }
                return nil
            }
        }

        print("VideoPlayerView: No cloud URL available for download")
        return nil
    }
    
    private func loadPlayer(from url: URL) async {
        print("VideoPlayerView: Creating AVPlayer with URL: \(url)")

        guard !Task.isCancelled else {
            print("VideoPlayerView: Load cancelled before creating player")
            return
        }

        let newPlayer = AVPlayer(url: url)
        let asset = AVURLAsset(url: url)

        do {
            let (isPlayable, _, tracks) = try await asset.load(.isPlayable, .duration, .tracks)

            guard !Task.isCancelled else {
                print("VideoPlayerView: Load cancelled after loading asset")
                return
            }

            let computedAspect = await calculateVideoAspect(from: tracks)

            guard !Task.isCancelled else {
                print("VideoPlayerView: Load cancelled after calculating aspect")
                return
            }

            await MainActor.run {
                if let aspect = computedAspect {
                    self.videoAspect = aspect
                }

                if isPlayable {
                    self.player = newPlayer
                    self.isPlayerReady = true
                    self.isLoading = false
                    print("VideoPlayerView: Player setup successful and ready")
                } else {
                    self.isLoading = false
                    self.errorMessage = "Video file is not playable"
                    print("VideoPlayerView: Player setup failed: Video is not playable")
                }
            }
        } catch {
            guard !Task.isCancelled else {
                print("VideoPlayerView: Load cancelled during error handling")
                return
            }

            await MainActor.run {
                self.isLoading = false
                self.errorMessage = "Unable to load video: \(error.localizedDescription)"
                print("VideoPlayerView: Player setup failed: \(self.errorMessage)")
            }
        }
    }
    
    private func calculateVideoAspect(from tracks: [AVAssetTrack]) async -> CGFloat? {
        guard let videoTrack = tracks.first(where: { $0.mediaType == .video }),
              let size = try? await videoTrack.load(.naturalSize),
              size.height > 0 else {
            return nil
        }
        return size.width / size.height
    }
    
    private func reloadPlayer(with url: URL) async {
        await MainActor.run {
            isLoading = true
            isPlayerReady = false
            errorMessage = ""
        }
        await loadPlayer(from: url)
    }
}

#Preview {
    // Minimal mock for preview
    let mock = VideoClip(fileName: "mock.mov", filePath: "/tmp/mock.mov")
    return VideoPlayerView(clip: mock)
}

// MARK: - Video Clip Info Card
struct VideoClipInfoCard: View {
    let clip: VideoClip

    var body: some View {
        HStack(spacing: 12) {
            // Play result or unrecorded
            if let playResult = clip.playResult {
                Text(playResult.type.displayName)
                    .font(.headline)
                    .fontWeight(.bold)
            } else {
                Text("Unrecorded")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }

            // Game/practice context
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

            // Highlight badge
            if clip.isHighlight {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
                    .font(.body)
            }

            // Date
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

// MARK: - Play Result Editor View
struct PlayResultEditorView: View {
    let clip: VideoClip
    let modelContext: ModelContext

    @Environment(\.dismiss) private var dismiss
    @State private var selectedResult: PlayResultType?
    @State private var showingConfirmation = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Current result
                VStack(spacing: 12) {
                    Text("Current Play Result")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    if let currentResult = clip.playResult?.type {
                        HStack {
                            Image(systemName: currentResult.iconName)
                                .font(.title)
                                .foregroundColor(currentResult.uiColor)
                            Text(currentResult.displayName)
                                .font(.title2)
                                .fontWeight(.bold)
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(currentResult.uiColor.opacity(0.1))
                        )
                    } else {
                        Text("No result recorded")
                            .font(.title3)
                            .foregroundColor(.secondary)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.gray.opacity(0.1))
                            )
                    }
                }
                .padding(.top)

                Divider()

                // New result selection
                VStack(spacing: 16) {
                    Text("Select New Result")
                        .font(.headline)

                    ScrollView {
                        VStack(spacing: 12) {
                            // Hits Section
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Hits")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 4)

                                LazyVGrid(columns: [
                                    GridItem(.flexible(), spacing: 8),
                                    GridItem(.flexible(), spacing: 8)
                                ], spacing: 8) {
                                    ForEach([PlayResultType.single, .double, .triple, .homeRun], id: \.self) { result in
                                        PlayResultEditButton(
                                            result: result,
                                            isSelected: selectedResult == result,
                                            isCurrent: clip.playResult?.type == result
                                        ) {
                                            selectedResult = result
                                            Haptics.medium()
                                        }
                                    }
                                }
                            }

                            // Walk Section
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Walk")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 4)

                                PlayResultEditButton(
                                    result: .walk,
                                    isSelected: selectedResult == .walk,
                                    isCurrent: clip.playResult?.type == .walk,
                                    fullWidth: true
                                ) {
                                    selectedResult = .walk
                                    Haptics.medium()
                                }
                            }

                            // Outs Section
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Outs")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 4)

                                LazyVGrid(columns: [
                                    GridItem(.flexible(), spacing: 8),
                                    GridItem(.flexible(), spacing: 8)
                                ], spacing: 8) {
                                    ForEach([PlayResultType.strikeout, .groundOut, .flyOut], id: \.self) { result in
                                        PlayResultEditButton(
                                            result: result,
                                            isSelected: selectedResult == result,
                                            isCurrent: clip.playResult?.type == result
                                        ) {
                                            selectedResult = result
                                            Haptics.medium()
                                        }
                                    }
                                }
                            }

                            // Remove result option
                            Button {
                                selectedResult = nil
                                showingConfirmation = true
                            } label: {
                                Label("Remove Play Result", systemImage: "xmark.circle")
                                    .font(.body.weight(.medium))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.red.opacity(0.5), lineWidth: 1.5)
                                    )
                                    .foregroundColor(.red)
                            }
                            .padding(.top, 8)
                        }
                        .padding()
                    }
                }

                Spacer()

                // Save button
                Button {
                    showingConfirmation = true
                } label: {
                    Text("Save Changes")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .disabled(selectedResult == clip.playResult?.type)
                .opacity(selectedResult == clip.playResult?.type ? 0.5 : 1.0)
                .padding()
            }
            .navigationTitle("Edit Play Result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .confirmationDialog(
                "Confirm Changes",
                isPresented: $showingConfirmation,
                titleVisibility: .visible
            ) {
                Button("Save", role: .none) {
                    saveChanges()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let selected = selectedResult {
                    Text("Change play result to \(selected.displayName)?")
                } else {
                    Text("Remove play result from this clip?")
                }
            }
        }
    }

    private func saveChanges() {
        if let selected = selectedResult {
            // Update or create play result
            if let existing = clip.playResult {
                existing.type = selected
            } else {
                let newResult = PlayResult(type: selected)
                clip.playResult = newResult
            }
        } else {
            // Remove play result
            clip.playResult = nil
        }

        do {
            try modelContext.save()
            Haptics.success()
            dismiss()
        } catch {
            print("Failed to save play result: \(error)")
            Haptics.warning()
        }
    }
}

struct PlayResultEditButton: View {
    let result: PlayResultType
    let isSelected: Bool
    let isCurrent: Bool
    var fullWidth: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(result.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, alignment: .center)

                if isCurrent {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? result.uiColor : result.uiColor.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isCurrent ? Color.green.opacity(0.5) : Color.clear,
                        lineWidth: 2
                    )
            )
            .foregroundColor(isSelected ? .white : result.uiColor)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Video Trimmer Sheet
struct VideoTrimmerSheet: View {
    let player: AVPlayer
    let sourceURL: URL
    var onExported: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var startTime: Double = 0
    @State private var endTime: Double = 0
    @State private var duration: Double = 0
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var exportedTempURL: URL?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                VideoPlayer(player: player)
                    .frame(height: 200)
                    .cornerRadius(8)

                if duration > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Start: \(format(time: startTime))  •  End: \(format(time: endTime))")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("Trim Range")
                            .font(.headline)

                        // Start slider
                        Slider(value: $startTime, in: 0...endTime - 0.1, step: 0.1) {
                            Text("Start")
                        }
                        .accessibilityLabel("Trim start time")

                        // End slider
                        Slider(value: $endTime, in: startTime + 0.1...duration, step: 0.1) {
                            Text("End")
                        }
                        .accessibilityLabel("Trim end time")
                    }
                    .padding(.horizontal)
                }

                if let exportError {
                    Text(exportError)
                        .foregroundColor(.red)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer()
            }
            .navigationTitle("Trim Clip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isExporting ? "Exporting…" : "Save") {
                        Task { await exportTrim() }
                    }
                    .disabled(isExporting || endTime - startTime < 0.2)
                }
            }
            .onAppear {
                setup()
            }
            .onDisappear {
                // Pause player to free resources
                player.pause()

                // Clean up temp file if export was successful but not yet processed
                // Note: If onExported was called, parent is responsible for cleanup
                if let tempURL = exportedTempURL, FileManager.default.fileExists(atPath: tempURL.path) {
                    try? FileManager.default.removeItem(at: tempURL)
                    print("VideoTrimmerSheet: Cleaned up temp file on dismiss")
                }
            }
        }
    }

    private func setup() {
        let asset = AVURLAsset(url: sourceURL)
        Task {
            do {
                let d = try await asset.load(.duration)
                let seconds = CMTimeGetSeconds(d)
                await MainActor.run {
                    self.duration = seconds
                    self.startTime = 0
                    self.endTime = seconds
                }
            } catch {
                await MainActor.run {
                    self.exportError = "Unable to read duration: \(error.localizedDescription)"
                }
            }
        }
    }

    private func exportTrim() async {
        isExporting = true
        exportError = nil
        let asset = AVURLAsset(url: sourceURL)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            exportError = "Export session could not be created."
            isExporting = false
            return
        }
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("trimmed_\(UUID().uuidString).mp4")
        let start = CMTime(seconds: startTime, preferredTimescale: 600)
        let end = CMTime(seconds: endTime, preferredTimescale: 600)
        session.timeRange = CMTimeRangeFromTimeToTime(start: start, end: end)
        session.outputURL = outputURL
        session.outputFileType = .mp4

        // Use iOS 18+ API if available, otherwise fallback to older API
        if #available(iOS 18.0, *) {
            do {
                try await session.export(to: outputURL, as: .mp4)
                await MainActor.run {
                    self.isExporting = false
                    self.exportedTempURL = outputURL
                    self.onExported(outputURL)
                    self.dismiss()
                }
            } catch {
                await MainActor.run {
                    // Clean up failed export
                    try? FileManager.default.removeItem(at: outputURL)
                    self.isExporting = false
                    self.exportError = error.localizedDescription
                }
            }
        } else {
            // Fallback for iOS 17 and earlier
            await session.export()
            await MainActor.run {
                switch session.status {
                case .completed:
                    self.isExporting = false
                    self.exportedTempURL = outputURL
                    self.onExported(outputURL)
                    self.dismiss()
                case .failed:
                    // Clean up failed export
                    try? FileManager.default.removeItem(at: outputURL)
                    self.isExporting = false
                    self.exportError = session.error?.localizedDescription ?? "Export failed"
                case .cancelled:
                    // Clean up cancelled export
                    try? FileManager.default.removeItem(at: outputURL)
                    self.isExporting = false
                    self.exportError = "Export was cancelled"
                default:
                    // Clean up unknown status
                    try? FileManager.default.removeItem(at: outputURL)
                    self.isExporting = false
                    self.exportError = "Export ended with unknown status"
                }
            }
        }
    }

    private func format(time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Game Linker View

struct GameLinkerView: View {
    let clip: VideoClip
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Game.date, order: .reverse) private var allGames: [Game]

    @State private var selectedGame: Game?
    @State private var hasChanges = false

    private var athleteGames: [Game] {
        guard let athleteId = clip.athlete?.id else { return [] }
        return allGames.filter { $0.athlete?.id == athleteId }
    }

    var body: some View {
        NavigationStack {
            List {
                // Option to unlink
                Section {
                    Button {
                        selectedGame = nil
                        hasChanges = (clip.game != nil)
                    } label: {
                        HStack {
                            Label("No Game", systemImage: "minus.circle")
                                .foregroundColor(.primary)
                            Spacer()
                            if selectedGame == nil && clip.game == nil {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            } else if selectedGame == nil && hasChanges {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                } footer: {
                    Text("Video will not be associated with any game")
                }

                // Games list
                if athleteGames.isEmpty {
                    Section {
                        Text("No games found for this athlete")
                            .foregroundColor(.secondary)
                    }
                } else {
                    Section("Games") {
                        ForEach(athleteGames) { game in
                            Button {
                                selectedGame = game
                                hasChanges = (clip.game?.id != game.id)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("vs \(game.opponent.isEmpty ? "Unknown" : game.opponent)")
                                            .foregroundColor(.primary)
                                        if let date = game.date {
                                            Text(date, format: .dateTime.month(.abbreviated).day().year())
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        if let season = game.season {
                                            Text(season.displayName)
                                                .font(.caption2)
                                                .foregroundColor(.blue)
                                        }
                                    }
                                    Spacer()
                                    if (selectedGame?.id == game.id) || (!hasChanges && clip.game?.id == game.id) {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Link to Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                    .disabled(!hasChanges)
                }
            }
            .onAppear {
                selectedGame = clip.game
            }
        }
    }

    private func saveChanges() {
        clip.game = selectedGame
        // Also update the season to match the game's season if linking to a game
        if let game = selectedGame {
            clip.season = game.season
        }

        do {
            try modelContext.save()
            Haptics.success()
            dismiss()
        } catch {
            print("Failed to save game link: \(error)")
        }
    }
}

