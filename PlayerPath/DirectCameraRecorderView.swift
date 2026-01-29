//
//  DirectCameraRecorderView.swift
//  PlayerPath
//
//  Instant camera access for Quick Record - bypasses options screen
//  Opens camera immediately, then flows to trimmer → play result tagging
//

import SwiftUI
import SwiftData
import AVFoundation
import PhotosUI

/// Streamlined video recorder that opens camera immediately
/// Used for Quick Record from Dashboard and live game recording
@MainActor
struct DirectCameraRecorderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let athlete: Athlete?
    let game: Game?
    let practice: Practice?

    // Core state
    @State private var recordedVideoURL: URL?
    @State private var trimmedVideoURL: URL?
    @State private var showingCamera = true
    @State private var showingTrimmer = false
    @State private var showingPlayResultOverlay = false
    @State private var showingDiscardConfirmation = false
    @State private var selectedVideoQuality: UIImagePickerController.QualityType = .typeHigh

    // Services
    @StateObject private var uploadService = VideoUploadService()

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

            // Show context header while camera is opening
            if showingCamera && game != nil {
                contextHeader
                    .transition(.opacity)
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            nativeCameraView
        }
        .sheet(isPresented: $showingTrimmer) {
            trimmerView
        }
        .sheet(isPresented: $showingPlayResultOverlay) {
            playResultOverlay
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
        .task {
            // Load quality preference
            if let savedQuality = UserDefaults.standard.value(forKey: "selectedVideoQuality") as? Int {
                selectedVideoQuality = UIImagePickerController.QualityType(rawValue: savedQuality) ?? .typeHigh
            }
        }
        .onDisappear {
            saveTask?.cancel()
        }
    }

    // MARK: - Context Header

    @ViewBuilder
    private var contextHeader: some View {
        if let game = game {
            VStack {
                VStack(spacing: 8) {
                    // Live game badge
                    if game.isLive {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 6, height: 6)
                            Text("LIVE GAME")
                                .font(.caption)
                                .fontWeight(.bold)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.red))
                        .foregroundColor(.white)
                    }

                    // Opponent
                    Text("vs \(game.opponent)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    Text("Opening camera...")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.black.opacity(0.7))
                        .background(.ultraThinMaterial)
                )
                .padding(.top, 100)

                Spacer()
            }
        }
    }

    // MARK: - Native Camera

    @ViewBuilder
    private var nativeCameraView: some View {
        NativeCameraView(
            videoQuality: selectedVideoQuality,
            maxDuration: 600, // 10 minutes
            onVideoRecorded: { videoURL in
                recordedVideoURL = videoURL
                showingCamera = false

                // Smart trimmer logic
                Task {
                    let duration = await getVideoDuration(videoURL)
                    let shouldShowTrimmer = UserDefaults.standard.bool(forKey: "autoShowTrimmer")

                    // Skip trimmer for very short clips (< 15 seconds) unless user wants it
                    if duration < 15 && !shouldShowTrimmer {
                        showingPlayResultOverlay = true
                    } else {
                        showingTrimmer = true
                    }
                }
            },
            onCancel: {
                showingCamera = false
                dismiss()
            },
            onError: { error in
                ErrorHandlerService.shared.handle(
                    AppError.videoRecordingFailed(error.localizedDescription),
                    context: "Camera Recording"
                )
                showingCamera = false
            }
        )
    }

    // MARK: - Trimmer

    @ViewBuilder
    private var trimmerView: some View {
        if let videoURL = recordedVideoURL {
            NavigationStack {
                PreUploadTrimmerView(
                    videoURL: videoURL,
                    onSave: { trimmedURL in
                        trimmedVideoURL = trimmedURL
                        showingTrimmer = false
                        showingPlayResultOverlay = true
                    },
                    onSkip: {
                        trimmedVideoURL = nil
                        showingTrimmer = false
                        showingPlayResultOverlay = true
                    },
                    onCancel: {
                        showingDiscardConfirmation = true
                    }
                )
            }
        }
    }

    // MARK: - Play Result Overlay

    @ViewBuilder
    private var playResultOverlay: some View {
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

                // Create video clip
                let clip = VideoClip(
                    fileName: videoURL.lastPathComponent,
                    filePath: videoURL.path
                )
                clip.thumbnailPath = thumbnailPath
                clip.createdAt = Date()
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
