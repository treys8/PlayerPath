//
//  DirectCameraRecorderView.swift
//  PlayerPath
//
//  Instant camera access for Quick Record - bypasses options screen
//  Opens ModernCameraView immediately, then flows to trimmer → play result tagging
//

import SwiftUI
import SwiftData
import AVFoundation

/// Streamlined video recorder that opens camera immediately
/// Used for Quick Record from Dashboard and live game recording
@MainActor
struct DirectCameraRecorderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let athlete: Athlete?
    let game: Game?
    let practice: Practice?

    /// Phases of the Quick Record flow, rendered inline within a single fullScreenCover
    private enum RecordingPhase: Equatable {
        case camera
        case trimming
        case tagging
    }

    // Core state
    @State private var phase: RecordingPhase = .camera
    @State private var recordedVideoURL: URL?
    @State private var trimmedVideoURL: URL?
    @State private var showingDiscardConfirmation = false

    // Cleanup task
    @State private var saveTask: Task<Void, Never>?

    init(athlete: Athlete?, game: Game? = nil, practice: Practice? = nil) {
        self.athlete = athlete
        self.game = game
        self.practice = practice
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch phase {
            case .camera:
                cameraPhaseView
            case .trimming:
                trimmerPhaseView
            case .tagging:
                playResultPhaseView
            }
        }
        .confirmationDialog(
            "Discard Recording?",
            isPresented: $showingDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard Video", role: .destructive) {
                cleanupAndDismiss()
            }
            Button("Keep Recording", role: .cancel) { }
        } message: {
            Text("This video hasn't been saved yet. Are you sure you want to discard it?")
        }
        .alert("Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) {
                ErrorHandlerService.shared.dismissError()
                dismiss()
            }
        } message: {
            if let error = ErrorHandlerService.shared.currentError {
                Text(error.errorDescription ?? "An error occurred")
            }
        }
        .onDisappear {
            saveTask?.cancel()
        }
    }

    // MARK: - Camera Phase

    @ViewBuilder
    private var cameraPhaseView: some View {
        ZStack {
            ModernCameraView(
                settings: .shared,
                onVideoRecorded: { videoURL in
                    recordedVideoURL = videoURL

                    // Smart trimmer logic
                    Task {
                        let duration = await getVideoDuration(videoURL)
                        let shouldShowTrimmer = UserDefaults.standard.bool(forKey: "autoShowTrimmer")

                        // Skip trimmer for very short clips (< 15 seconds) unless user wants it
                        if duration < 15 && !shouldShowTrimmer {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                phase = .tagging
                            }
                        } else {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                phase = .trimming
                            }
                        }
                    }
                },
                onCancel: {
                    dismiss()
                },
                onError: { error in
                    ErrorHandlerService.shared.handle(
                        AppError.videoRecordingFailed(error.localizedDescription),
                        context: "Camera Recording"
                    )
                }
            )

            // Live game context overlay on top of camera
            if let game = game, game.isLive {
                VStack {
                    liveGameBadge(for: game)
                        .padding(.top, 70)
                    Spacer()
                }
            }
        }
    }

    // MARK: - Live Game Badge

    @ViewBuilder
    private func liveGameBadge(for game: Game) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
            Text("LIVE")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
            Text("vs \(game.opponent)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
        )
        .allowsHitTesting(false)
    }

    // MARK: - Trimmer Phase

    @ViewBuilder
    private var trimmerPhaseView: some View {
        if let videoURL = recordedVideoURL {
            NavigationStack {
                PreUploadTrimmerView(
                    videoURL: videoURL,
                    onSave: { trimmedURL in
                        trimmedVideoURL = trimmedURL
                        withAnimation(.easeInOut(duration: 0.25)) {
                            phase = .tagging
                        }
                    },
                    onSkip: {
                        trimmedVideoURL = nil
                        withAnimation(.easeInOut(duration: 0.25)) {
                            phase = .tagging
                        }
                    },
                    onCancel: {
                        showingDiscardConfirmation = true
                    }
                )
            }
        }
    }

    // MARK: - Play Result Phase

    @ViewBuilder
    private var playResultPhaseView: some View {
        if let videoURL = recordedVideoURL {
            let finalVideoURL = trimmedVideoURL ?? videoURL

            PlayResultOverlayView(
                videoURL: finalVideoURL,
                athlete: athlete,
                game: game,
                practice: practice,
                onSave: { result in
                    saveVideoWithResult(videoURL: finalVideoURL, playResult: result)
                    dismiss()
                },
                onCancel: {
                    showingDiscardConfirmation = true
                }
            )
        }
    }

    // MARK: - Helpers

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { ErrorHandlerService.shared.showErrorAlert },
            set: { _ in ErrorHandlerService.shared.dismissError() }
        )
    }

    private func getVideoDuration(_ url: URL) async -> Double {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            return CMTimeGetSeconds(duration)
        } catch {
            return 0
        }
    }

    private func saveVideoWithResult(videoURL: URL, playResult: PlayResultType?) {
        guard !Task.isCancelled else { return }

        saveTask = Task { @MainActor in
            defer { saveTask = nil }

            guard !Task.isCancelled else { return }

            do {
                // Generate thumbnail
                let thumbnailResult = await VideoFileManager.generateThumbnail(from: videoURL)
                let thumbnailPath = try? thumbnailResult.get()

                // Determine season
                let season = game?.season ?? practice?.season ?? athlete?.seasons?.first(where: { $0.isActive })

                // Get video duration
                let asset = AVURLAsset(url: videoURL)
                let duration = try? await asset.load(.duration)
                let durationSeconds = duration.map { CMTimeGetSeconds($0) }

                // Create video clip
                let clip = VideoClip(
                    fileName: videoURL.lastPathComponent,
                    filePath: videoURL.path
                )
                clip.thumbnailPath = thumbnailPath
                clip.createdAt = Date()
                clip.duration = durationSeconds
                clip.athlete = athlete
                clip.game = game
                clip.practice = practice
                clip.season = season

                // Tag play result
                if let resultType = playResult {
                    let result = PlayResult(type: resultType)
                    result.createdAt = Date()
                    result.videoClip = clip
                    clip.playResult = result

                    // Auto-highlight hits
                    if [.single, .double, .triple, .homeRun].contains(resultType) {
                        clip.isHighlight = true
                    }

                    modelContext.insert(result)
                }

                modelContext.insert(clip)
                try modelContext.save()

                // Post notification for stats update
                if let resultType = playResult {
                    NotificationCenter.default.post(
                        name: .recordedHitResult,
                        object: ["hitType": resultType.rawValue]
                    )
                }

                // Check auto-upload preference and enqueue if enabled
                if let athlete = athlete {
                    await checkAndEnqueueAutoUpload(clip: clip, athlete: athlete)
                }

                Haptics.success()
            } catch {
                await MainActor.run {
                    ErrorHandlerService.shared.handle(
                        AppError.videoRecordingFailed(error.localizedDescription),
                        context: "Saving Video"
                    )
                }
            }
        }
    }

    private func checkAndEnqueueAutoUpload(clip: VideoClip, athlete: Athlete) async {
        // Get user preferences
        let prefs = UserPreferences.shared(in: modelContext)
        let uploadMode = prefs.autoUploadMode ?? .off

        guard uploadMode != .off else {
            #if DEBUG
            print("🎬 Auto-upload disabled - video saved locally only")
            #endif
            return
        }

        // Check network status
        let networkMonitor = ConnectivityMonitor.shared
        let isOnWifi = networkMonitor.connectionType == .wifi
        let isConnected = networkMonitor.isConnected

        // Determine if we should upload based on mode and network
        let shouldUpload: Bool
        switch uploadMode {
        case .off:
            shouldUpload = false
        case .wifiOnly:
            shouldUpload = isOnWifi
        case .always:
            shouldUpload = isConnected
        }

        if shouldUpload {
            #if DEBUG
            print("🎬 Auto-uploading video (mode: \(uploadMode.rawValue), wifi: \(isOnWifi))")
            #endif
            UploadQueueManager.shared.enqueue(clip, athlete: athlete, priority: .normal)
        } else {
            #if DEBUG
            print("🎬 Skipping auto-upload - mode: \(uploadMode.rawValue), wifi: \(isOnWifi), connected: \(isConnected)")
            #endif
        }
    }

    private func cleanupAndDismiss() {
        if let videoURL = recordedVideoURL {
            VideoFileManager.cleanup(url: videoURL)
        }
        if let trimmedURL = trimmedVideoURL {
            VideoFileManager.cleanup(url: trimmedURL)
        }
        recordedVideoURL = nil
        trimmedVideoURL = nil
        dismiss()
    }
}

#Preview("Normal Mode") {
    DirectCameraRecorderView(athlete: nil, game: nil)
}

#Preview("Live Game Mode") {
    DirectCameraRecorderView(athlete: nil, game: nil)
}
