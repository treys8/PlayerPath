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
    @State private var showingSaveError = false

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
        .alert("Unable to Save", isPresented: $showingSaveError) {
            Button("OK", role: .cancel) { dismiss() }
        } message: {
            Text("No athlete profile found. Please create an athlete profile first.")
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
                        let autoShowTrimmer = UserDefaults.standard.bool(forKey: "autoShowTrimmer")
                        let skipShortClips = UserDefaults.standard.bool(forKey: "skipTrimmerForShortClips")

                        let shouldSkip: Bool
                        if autoShowTrimmer {
                            shouldSkip = false // Always show trimmer
                        } else if duration < 15 && skipShortClips {
                            shouldSkip = true  // Short clip + skip setting enabled
                        } else {
                            shouldSkip = false // Long clip or skip setting disabled
                        }

                        withAnimation(.easeInOut(duration: 0.25)) {
                            phase = shouldSkip ? .tagging : .trimming
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
                    Spacer()
                }
                .padding(.top, 16)
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
                },
                onDiscard: {
                    showingDiscardConfirmation = true
                }
            )
        }
    }

    // MARK: - Play Result Phase

    @ViewBuilder
    private var playResultPhaseView: some View {
        if let videoURL = recordedVideoURL {
            let finalVideoURL = trimmedVideoURL ?? videoURL

            if practice != nil {
                PracticeVideoSaveView(
                    videoURL: finalVideoURL,
                    athlete: athlete,
                    practice: practice,
                    onSave: { note, completion in
                        saveVideoWithResult(videoURL: finalVideoURL, playResult: nil, role: athlete?.primaryRole ?? .batter, note: note) {
                            completion()
                            dismiss()
                        }
                    },
                    onDiscard: {
                        showingDiscardConfirmation = true
                    }
                )
            } else {
                PlayResultOverlayView(
                    videoURL: finalVideoURL,
                    athlete: athlete,
                    game: game,
                    practice: practice,
                    onSave: { result, pitchSpeed, role in
                        saveVideoWithResult(videoURL: finalVideoURL, playResult: result, pitchSpeed: pitchSpeed, role: role) { dismiss() }
                    },
                    onCancel: {
                        showingDiscardConfirmation = true
                    }
                )
            }
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

    private func saveVideoWithResult(videoURL: URL, playResult: PlayResultType?, pitchSpeed: Double? = nil, role: AthleteRole = .batter, note: String? = nil, onComplete: @escaping () -> Void) {
        guard let athlete = athlete else {
            Haptics.error()
            showingSaveError = true
            return
        }

        // Dismiss immediately so the user isn't waiting
        Haptics.success()
        onComplete()

        // Save in background using ClipPersistenceService for proper
        // file management, stats, analytics, and playability verification
        saveTask = Task { @MainActor in
            defer { saveTask = nil }

            do {
                _ = try await ClipPersistenceService().saveClip(
                    from: videoURL,
                    playResult: playResult,
                    pitchSpeed: pitchSpeed,
                    role: role,
                    note: note,
                    context: modelContext,
                    athlete: athlete,
                    game: game,
                    practice: practice
                )

                // Post notification for stats update in tab view
                if let resultType = playResult {
                    NotificationCenter.default.post(
                        name: .recordedHitResult,
                        object: ["hitType": resultType.displayName]
                    )
                }

                // Clean up temp files after successful save
                VideoFileManager.cleanup(url: videoURL)
                if let trimmed = trimmedVideoURL {
                    VideoFileManager.cleanup(url: trimmed)
                }
                recordedVideoURL = nil
                trimmedVideoURL = nil
            } catch {
                ErrorHandlerService.shared.handle(
                    AppError.videoRecordingFailed(error.localizedDescription),
                    context: "Saving Video"
                )
            }
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
