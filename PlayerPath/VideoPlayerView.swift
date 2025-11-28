//
//  VideoPlayerView.swift
//  PlayerPath
//
//  Extracted from VideoClipsView.swift to be the canonical implementation.
//

import SwiftUI
import AVKit

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
    @State private var setupTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase
    
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
        Rectangle()
            .fill(Color.black)
            .aspectRatio(videoAspect ?? (16.0/9.0), contentMode: .fit)
            .overlay(
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                    Text("Loading video...")
                        .font(.headline)
                        .foregroundColor(.white)
                }
            )
    }
    
    private func activePlayerView(player: AVPlayer) -> some View {
        VideoPlayer(player: player)
            .aspectRatio(videoAspect ?? (16.0/9.0), contentMode: .fit)
            .accessibilityLabel("Video player")
            .onAppear {
                print("VideoPlayerView: VideoPlayer appeared, starting playback")
                player.play()
            }
            .onDisappear {
                print("VideoPlayerView: VideoPlayer disappeared, pausing playback")
                player.pause()
            }
    }
    
    private var errorView: some View {
        Rectangle()
            .fill(Color.black)
            .aspectRatio(videoAspect ?? (16.0/9.0), contentMode: .fit)
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
            VStack {
                // Video Player
                videoPlayerContent
                
                // Video Info
                VideoClipInfoCard(clip: clip)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
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
                        ShareLink(item: URL(fileURLWithPath: clip.filePath)) {
                            Label("Share Video", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .accessibilityLabel("More actions")
                    }
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
        }

        guard !Task.isCancelled else {
            print("VideoPlayerView: Setup cancelled after state reset")
            return
        }

        print("VideoPlayerView: File path: \(clip.filePath)")

        guard let url = findVideoURL() else {
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
    
    private func findVideoURL() -> URL? {
        let primaryURL = URL(fileURLWithPath: clip.filePath)
        
        if FileManager.default.fileExists(atPath: clip.filePath) {
            print("VideoPlayerView: File exists at primary path")
            return primaryURL
        }
        
        print("VideoPlayerView: File not found at primary path, trying alternate")
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let alternateURL = documentsPath.appendingPathComponent(clip.fileName)
        
        if FileManager.default.fileExists(atPath: alternateURL.path) {
            print("VideoPlayerView: File found at alternate path: \(alternateURL.path)")
            return alternateURL
        }
        
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
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                VStack(alignment: .leading) {
                    if let playResult = clip.playResult {
                        Text(playResult.type.displayName)
                            .font(.title2)
                            .fontWeight(.bold)
                    } else {
                        Text("Unrecorded Play")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                    
                    if let game = clip.game {
                        Text("vs \(game.opponent)")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                        if let date = game.date {
                            Text(date, style: .date)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else if let practice = clip.practice {
                        Text("Practice Session")
                            .font(.subheadline)
                            .foregroundColor(.green)
                        if let date = practice.date {
                            Text(date, formatter: DateFormatter.pp_shortDate)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                if clip.isHighlight {
                    VStack {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                            .font(.title2)
                        Text("Highlight")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                }
            }
            
            if let createdAt = clip.createdAt {
                Text("Recorded: \(createdAt, format: .dateTime.month().day().hour().minute())")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Recorded date unavailable")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(uiColor: .systemGray6))
        .cornerRadius(12)
        .padding()
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

