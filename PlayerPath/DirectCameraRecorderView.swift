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
import FirebaseAuth

/// Context for coach session recording mode
struct CoachSessionContext: Identifiable {
    let sessionID: String
    let session: CoachSession
    var id: String { sessionID }
}

/// Streamlined video recorder that opens camera immediately
/// Used for Quick Record from Dashboard, live game recording, and coach instruction sessions
@MainActor
struct DirectCameraRecorderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var vSizeClass
    private var isLandscape: Bool { vSizeClass == .compact }

    let athlete: Athlete?
    let game: Game?
    let practice: Practice?
    let coachContext: CoachSessionContext?

    private var isCoachMode: Bool { coachContext != nil }

    /// Sport context for this recording: prefer the explicit game/practice season,
    /// then the athlete's primary sport, then baseball as a last resort.
    private var clipSport: Season.SportType {
        game?.season?.sport ?? practice?.season?.sport ?? athlete?.sportType ?? .baseball
    }

    /// Show the casual current-hole stepper only when recording golf with NO
    /// live round (no game/practice) and not in coach mode — the orphan-golf
    /// path that GolfCaptureContext/saveClip group into a session. A live
    /// round/practice derives its hole from scoring instead (LiveHoleTracker).
    private var showsHoleStepper: Bool {
        !isCoachMode && game == nil && practice == nil && athlete?.sportType == .golf
    }

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
    @State private var clipOrientation: VideoOrientation = .portrait
    @State private var showingDiscardConfirmation = false
    @State private var showingSaveError = false
    @State private var showingSaveFailedError = false

    // Coach mode state
    @State private var lastSelectedAthleteID: String?
    @State private var didAutoSave = false

    // Cleanup task
    @State private var saveTask: Task<Void, Never>?

    // Tagging-phase save lifecycle (drives PlayResultOverlayView spinner)
    @State private var isSavingTaggedClip = false

    init(athlete: Athlete?, game: Game? = nil, practice: Practice? = nil) {
        self.athlete = athlete
        self.game = game
        self.practice = practice
        self.coachContext = nil
    }

    init(coachContext: CoachSessionContext) {
        self.athlete = nil
        self.game = nil
        self.practice = nil
        self.coachContext = coachContext
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
        .alert("Save Failed", isPresented: $showingSaveFailedError) {
            Button("OK", role: .cancel) { dismiss() }
        } message: {
            Text("The video could not be saved. Please try recording again.")
        }
        .alert("Recording Error", isPresented: errorBinding) {
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
            // Ensure orientation is released no matter which path dismissed the flow.
            OrientationLocker.restore()
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
                        clipOrientation = await VideoOrientationDetector.detect(url: videoURL)
                        let duration = await getVideoDuration(videoURL)
                        let autoShowTrimmer = UserDefaults.standard.bool(forKey: TrimmerPrefKeys.autoShowTrimmer)
                        let skipShortClips = UserDefaults.standard.bool(forKey: TrimmerPrefKeys.skipTrimmerForShortClips)

                        let shouldSkip: Bool
                        if autoShowTrimmer {
                            shouldSkip = false // Always show trimmer
                        } else if duration < TrimmerPrefKeys.shortClipThreshold && skipShortClips {
                            shouldSkip = true  // Short clip + skip setting enabled
                        } else {
                            shouldSkip = false // Long clip or skip setting disabled
                        }

                        // Lock orientation before transitioning to trimmer/tagging so
                        // the overlays render in the clip's native aspect.
                        if shouldSkip {
                            OrientationLocker.lock(for: clipOrientation)
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

            // Context badge overlay — positioned to avoid overlapping ModernCameraView controls
            if isCoachMode {
                VStack {
                    if isLandscape {
                        Spacer()
                        liveSessionBadge
                            .padding(.bottom, 16)
                    } else {
                        liveSessionBadge
                            .padding(.top, 72)
                        Spacer()
                    }
                }
            } else if let game = game, game.isLive {
                VStack {
                    if isLandscape {
                        Spacer()
                        liveGameBadge(for: game)
                            .padding(.bottom, 16)
                    } else {
                        liveGameBadge(for: game)
                            .padding(.top, 72)
                        Spacer()
                    }
                }
            } else if showsHoleStepper {
                VStack {
                    if isLandscape {
                        Spacer()
                        CurrentHoleStepper()
                            .padding(.bottom, 16)
                    } else {
                        CurrentHoleStepper()
                            .padding(.top, 72)
                        Spacer()
                    }
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
            Text(game.opponentLabel)
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

    // MARK: - Live Session Badge

    private var liveSessionBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
            Text("LIVE SESSION")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(.ultraThinMaterial))
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
                    OrientationLocker.lock(for: clipOrientation)
                    withAnimation(.easeInOut(duration: 0.25)) {
                        phase = .tagging
                    }
                },
                onSkip: {
                    trimmedVideoURL = nil
                    OrientationLocker.lock(for: clipOrientation)
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

    // MARK: - Tagging Phase

    @ViewBuilder
    private var playResultPhaseView: some View {
        if let videoURL = recordedVideoURL {
            let finalVideoURL = trimmedVideoURL ?? videoURL

            if let ctx = coachContext {
                if ctx.session.athleteIDs.count == 1, let athleteID = ctx.session.athleteIDs.first {
                    // Single athlete — auto-save without showing picker
                    Color.black.ignoresSafeArea()
                        .onAppear {
                            guard !didAutoSave else { return }
                            didAutoSave = true
                            saveCoachClip(videoURL: finalVideoURL, athleteID: athleteID, context: ctx)
                        }
                } else {
                    // Multi-athlete — show athlete picker
                    coachTaggingView(videoURL: finalVideoURL, context: ctx)
                }
            } else if athlete?.trackStatsEnabled == false {
                // Journal mode: skip play-result tagging and save immediately.
                ZStack {
                    Color.black.ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        Text("Saving...")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Saving recording")
                .accessibilityAddTraits(.updatesFrequently)
                .onAppear {
                    guard !didAutoSave else { return }
                    didAutoSave = true
                    saveVideoWithResult(
                        videoURL: finalVideoURL,
                        playResult: nil,
                        role: athlete?.primaryRole ?? .batter
                    ) { dismiss() }
                }
            } else if practice != nil {
                PracticeVideoSaveView(
                    videoURL: finalVideoURL,
                    athlete: athlete,
                    practice: practice,
                    clipOrientation: clipOrientation,
                    onSave: { note, completion in
                        saveVideoWithResult(videoURL: finalVideoURL, playResult: nil, role: athlete?.primaryRole ?? .batter, note: note, onError: {
                            completion() // Reset PracticeVideoSaveView spinner so user can retry
                        }) {
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
                    sport: clipSport,
                    clipOrientation: clipOrientation,
                    isSaving: $isSavingTaggedClip,
                    onSave: { result, pitchSpeed, pitchType, role, club, markAsHighlight in
                        isSavingTaggedClip = true
                        saveVideoWithResult(
                            videoURL: finalVideoURL,
                            playResult: result,
                            pitchSpeed: pitchSpeed,
                            pitchType: pitchType,
                            club: club,
                            role: role,
                            markAsHighlight: markAsHighlight,
                            onError: { isSavingTaggedClip = false }
                        ) { dismiss() }
                    },
                    onCancel: {
                        showingDiscardConfirmation = true
                    }
                )
            }
        }
    }

    // MARK: - Coach Tagging

    @ViewBuilder
    private func coachTaggingView(videoURL: URL, context: CoachSessionContext) -> some View {
        let athletes: [(id: String, name: String)] = context.session.athleteIDs.compactMap { id in
            guard let name = context.session.athleteNames[id] else { return nil }
            return (id: id, name: name)
        }

        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()

            SessionAthletePickerOverlay(
                athletes: athletes,
                lastSelectedID: lastSelectedAthleteID,
                onSelect: { athleteID in
                    saveCoachClip(videoURL: videoURL, athleteID: athleteID, context: context)
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

    private func saveVideoWithResult(videoURL: URL, playResult: PlayResultType?, pitchSpeed: Double? = nil, pitchType: String? = nil, club: Club? = nil, role: AthleteRole = .batter, note: String? = nil, markAsHighlight: Bool = false, onError: (() -> Void)? = nil, onComplete: @escaping () -> Void) {
        guard let athlete = athlete else {
            Haptics.error()
            showingSaveError = true
            return
        }

        // Prevent double-saves
        guard saveTask == nil else { return }

        // Save in background — success feedback and dismiss happen AFTER save confirms
        saveTask = Task { @MainActor in
            defer { saveTask = nil }

            do {
                _ = try await ClipPersistenceService().saveClip(
                    from: videoURL,
                    playResult: playResult,
                    pitchSpeed: pitchSpeed,
                    pitchType: pitchType,
                    club: club,
                    role: role,
                    note: note,
                    markAsHighlight: markAsHighlight,
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

                // Save succeeded — now dismiss
                Haptics.success()
                VideoFileManager.cleanup(url: videoURL)
                if let trimmed = trimmedVideoURL {
                    VideoFileManager.cleanup(url: trimmed)
                }
                recordedVideoURL = nil
                trimmedVideoURL = nil
                onComplete()
            } catch {
                Haptics.error()
                ErrorHandlerService.shared.handle(
                    AppError.videoRecordingFailed(error.localizedDescription),
                    context: "Saving Video",
                    showAlert: false
                )
                onError?()
                showingSaveFailedError = true
            }
        }
    }

    private func saveCoachClip(videoURL: URL, athleteID: String, context: CoachSessionContext) {
        guard let folderID = context.session.folderIDs[athleteID],
              let currentUser = Auth.auth().currentUser else {
            Haptics.error()
            showingSaveFailedError = true
            return
        }

        // Remember for next clip's athlete picker pre-selection
        lastSelectedAthleteID = athleteID

        // Enqueue unconditionally — UploadQueueManager handles retry with exponential
        // backoff (up to 10 retries; not 3 as a prior comment claimed).
        let coachID = currentUser.uid
        let coachName = currentUser.displayName ?? currentUser.email ?? "Coach"

        // If trimmed, the upload manager handles the trimmed file — clean up the original
        if trimmedVideoURL != nil, let original = recordedVideoURL {
            VideoFileManager.cleanup(url: original)
        }

        // Await the enqueue call and branch on its outcome — uploadClip routes
        // permission-denied clips to coach_failed_uploads and reports a genuinely
        // lost clip as `.failed`. Only `.queued` earns a success haptic.
        Task {
            let outcome = await CoachSessionManager.shared.uploadClip(
                videoURL: videoURL,
                folderID: folderID,
                sessionID: context.sessionID,
                coachID: coachID,
                coachName: coachName
            )
            await MainActor.run {
                switch outcome {
                case .queued:
                    Haptics.success()
                    dismiss()
                case .accessRevoked:
                    // Clip is safely parked in coach_failed_uploads and a recovery
                    // notification was posted — don't claim success, and don't tell
                    // them to re-record (re-recording won't help; access was revoked).
                    Haptics.warning()
                    dismiss()
                case .failed:
                    // Clip genuinely lost (copy error). Surface it so the coach re-records.
                    Haptics.error()
                    showingSaveFailedError = true
                }
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
        OrientationLocker.restore()
        dismiss()
    }
}

#Preview("Normal Mode") {
    DirectCameraRecorderView(athlete: nil, game: nil)
}

#Preview("Live Game Mode") {
    DirectCameraRecorderView(athlete: nil, game: nil)
}
