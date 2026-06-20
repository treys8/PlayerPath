//
//  CoachVideoPlayerView.swift
//  PlayerPath
//
//  Created by Assistant on 11/21/25.
//  Video player with annotation/notes system for coaches and athletes
//

import SwiftUI
import SwiftData
import AVKit
import PencilKit

struct CoachVideoPlayerView: View {
    let folder: SharedFolder
    let video: CoachVideoItem

    /// Draft-review callbacks. Non-nil only when this view is presented as the
    /// coach's own unpublished draft (the folder "My Drafts" cover). They let
    /// the parent dismiss + reload after the coach publishes / discards / keeps
    /// the draft. Nil for every read-only or already-shared presentation, where
    /// no publish bar appears.
    var onDraftShared: (() -> Void)?
    var onDraftDiscarded: (() -> Void)?
    var onDraftSavedForLater: (() -> Void)?

    /// Sequential-review navigation. Non-nil when the player is presented inside
    /// a `CoachReviewSequenceView` over an ordered clip list, so the coach can
    /// step to the next/previous clip without backing out to the folder. `onNext`
    /// / `onPrevious` are nil at the ends of the list (which disables the chevron).
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    /// 1-based position in the review sequence, for the "n of m" nav-bar label.
    var sequencePosition: CoachReviewSequencePosition?

    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @State private var viewModel: CoachVideoPlayerViewModel
    @State private var showingCoachNoteEditor = false
    @State private var selectedTab: VideoTab = .drawings
    @State private var showingSpeedPicker = false
    @State private var showingDrillCardEditor = false
    /// Non-nil presents the drill-card editor seeded with an existing card to
    /// edit (distinct from `showingDrillCardEditor`, which creates a new one).
    @State private var editingDrillCard: DrillCard?
    /// Drill card awaiting delete confirmation.
    @State private var drillCardPendingDelete: DrillCard?
    @State private var markReviewedError: String?
    // Draft publish/discard state (only used when `isOwnPrivateDraft`).
    @State private var isPublishingDraft = false
    @State private var isDiscardingDraft = false
    @State private var showingDraftDiscardConfirm = false
    @State private var draftActionError: String?
    @State private var showingTelestration = false

    /// Presents the athlete-selection sheet when a downgrade-blocked coach taps a
    /// disabled feedback affordance or the in-review banner.
    @State private var showingDowngradeSelection = false
    @State private var isVerifyingDrawPermission = false
    @State private var drillCards: [DrillCard] = []
    /// True when the drill-card fetch failed, so the Drill Card tab can show a
    /// retry affordance instead of an empty state indistinguishable from "none".
    @State private var drillCardsLoadFailed = false
    /// Guard so the "athlete viewed this clip" write only fires once per open.
    @State private var hasMarkedViewed = false
    /// Quick-cue texts currently applied to this clip (a subset of video.tags),
    /// edited live by the coach via the inline cue picker.
    @State private var selectedCueTags: [String] = []
    @State private var isConfirmingReview = false
    @State private var didConfirmReview = false
    /// Latest athlete view-receipt, refreshed from Firestore on open/foreground
    /// so "Seen" still appears while the coach keeps the clip open. nil until the
    /// first refresh; `athleteViewedAt` falls back to the clip's load snapshot.
    @State private var refreshedAthleteViewedAt: Date?
    private var templateService: CoachTemplateService { .shared }
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var vSizeClass
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.ppAccent) private var ppAccent
    private var isWideLayout: Bool { hSizeClass == .regular || vSizeClass == .compact }
    private var isIPad: Bool { hSizeClass == .regular }

    private var playbackRateLabel: String {
        let rate = viewModel.playbackRate
        if rate == 1.0 { return "1x" }
        if rate < 1.0 { return String(format: "%.2gx", rate) }
        return String(format: "%.4gx", rate)
    }
    
    init(
        folder: SharedFolder,
        video: CoachVideoItem,
        onDraftShared: (() -> Void)? = nil,
        onDraftDiscarded: (() -> Void)? = nil,
        onDraftSavedForLater: (() -> Void)? = nil,
        onNext: (() -> Void)? = nil,
        onPrevious: (() -> Void)? = nil,
        sequencePosition: CoachReviewSequencePosition? = nil
    ) {
        self.folder = folder
        self.video = video
        self.onDraftShared = onDraftShared
        self.onDraftDiscarded = onDraftDiscarded
        self.onDraftSavedForLater = onDraftSavedForLater
        self.onNext = onNext
        self.onPrevious = onPrevious
        self.sequencePosition = sequencePosition
        _viewModel = State(initialValue: CoachVideoPlayerViewModel(video: video, folder: folder))
    }
    
    enum VideoTab: String, CaseIterable {
        case drawings = "Drawings"
        case drillCard = "Drill Card"
        case info = "Info"

        var icon: String {
            switch self {
            case .drawings: return "pencil.tip"
            case .drillCard: return "clipboard.fill"
            case .info: return "info.circle.fill"
            }
        }
    }
    
    /// Trailing nav-bar controls. Extracted from `body` to keep the main view
    /// expression within the Swift type-checker's complexity budget.
    @ViewBuilder
    private var trailingToolbarButtons: some View {
        HStack(spacing: 12) {
            // Telestration draw button (coaches only). Re-verifies comment
            // permission before opening — folder shares can be revoked
            // mid-session, and the server will reject the write anyway; this
            // gives the coach a clean error instead of an opaque Firestore failure.
            if canDeliverFeedback {
                Button {
                    openTelestration()
                } label: {
                    if isVerifyingDrawPermission {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Image(systemName: "pencil.tip")
                            .foregroundColor(ppAccent)
                    }
                }
                .disabled(!viewModel.isPlayerReady || isVerifyingDrawPermission)
                .accessibilityLabel("Draw on video frame")
            }

            // Save to My Videos button — folder owner (athlete) only. Brings the
            // clip into the athlete's in-app Videos tab with a link back to coach
            // annotations.
            if isFolderOwner {
                Button {
                    Task { await viewModel.saveToMyVideos(modelContext: modelContext) }
                } label: {
                    if viewModel.isSavingToMyVideos {
                        ProgressView().scaleEffect(0.8)
                    } else if viewModel.alreadySavedToMyVideos {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Image(systemName: "folder.fill.badge.plus")
                            .foregroundColor(ppAccent)
                    }
                }
                .disabled(viewModel.isSavingToMyVideos || !viewModel.isPlayerReady || viewModel.alreadySavedToMyVideos)
                .accessibilityLabel(viewModel.alreadySavedToMyVideos ? "Already saved to your videos" : "Save to your videos")
            }

            // Save to device button
            Button {
                Task { await viewModel.saveToPhotos() }
            } label: {
                if viewModel.isSaving {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Image(systemName: "square.and.arrow.down")
                        .foregroundColor(ppAccent)
                }
            }
            .disabled(viewModel.isSaving || !viewModel.isPlayerReady)
            .accessibilityLabel("Save video to device")

            // Playback speed button (hidden on iPad — uses inline sidebar control)
            if !isIPad {
                Button {
                    showingSpeedPicker = true
                } label: {
                    Text(playbackRateLabel)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundColor(ppAccent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(ppAccent.opacity(0.12))
                        .clipShape(Capsule())
                }
                .accessibilityLabel("Playback speed: \(viewModel.playbackRate)x")
            }
        }
    }

    var body: some View {
        playerBody
            .sheet(isPresented: $showingCoachNoteEditor) {
                CoachNoteEditorSheet(
                    initialText: viewModel.coachNoteText ?? ""
                ) { newText in
                    guard let userID = authManager.userID else { return }
                    let userName = authManager.userDisplayName ?? authManager.userEmail ?? "Coach"
                    try await viewModel.updateCoachNote(text: newText, authorID: userID, authorName: userName)
                }
            }
            .sheet(isPresented: $showingDrillCardEditor) {
                drillCardEditorSheet
            }
            .sheet(item: $editingDrillCard) { card in
                editDrillCardSheet(existing: card)
            }
            .sheet(isPresented: $showingDowngradeSelection) {
                if let coachID = authManager.userID {
                    CoachDowngradeSelectionView(coachID: coachID)
                        .environmentObject(authManager)
                }
            }
            .confirmationDialog(
                "Delete this drill card?",
                isPresented: Binding(
                    get: { drillCardPendingDelete != nil },
                    set: { if !$0 { drillCardPendingDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: drillCardPendingDelete
            ) { card in
                Button("Delete", role: .destructive) { deleteDrillCard(card) }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Discard this clip?", isPresented: $showingDraftDiscardConfirm) {
                Button("Discard", role: .destructive) { discardDraft() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This clip and any notes, cues, or drawings on it will be permanently deleted. The athlete never received it.")
            }
            .alert("Something Went Wrong", isPresented: Binding(
                get: { draftActionError != nil },
                set: { if !$0 { draftActionError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(draftActionError ?? "")
            }
            .task {
                await runInitialLoad()
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                handleScenePhaseChange(old: oldPhase, new: newPhase)
            }
            .onDisappear {
                // Detach AVPlayer observers at the OUTER view level instead of the
                // inner VideoPlayer's .onDisappear so toggling the telestration
                // overlay doesn't accidentally tear them down mid-session.
                viewModel.stopTimeObserver()
                viewModel.stopFilmstripTimeObserver()
                viewModel.teardownLoopObserver()
            }
    }

    private var playerBody: some View {
        Group {
            if isWideLayout {
                wideLayout
            } else {
                narrowLayout
            }
        }
        .navigationTitle(video.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                trailingToolbarButtons
            }
            if let position = sequencePosition {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 14) {
                        Button { onPrevious?() } label: {
                            Image(systemName: "chevron.left")
                                .fontWeight(.semibold)
                        }
                        .disabled(onPrevious == nil)
                        .accessibilityLabel("Previous clip")

                        Text("\(position.current) of \(position.total)")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()

                        Button { onNext?() } label: {
                            Image(systemName: "chevron.right")
                                .fontWeight(.semibold)
                        }
                        .disabled(onNext == nil)
                        .accessibilityLabel("Next clip")
                    }
                    .tint(ppAccent)
                }
            }
        }
        .toast(isPresenting: $viewModel.didSaveSuccessfully, message: "Video Saved")
        .toast(isPresenting: $viewModel.didSaveToMyVideosSuccessfully, message: "Added to Your Videos")
        .toast(isPresenting: $didConfirmReview, message: "Marked reviewed")
        .alert("Save Failed", isPresented: .init(
            get: { viewModel.saveError != nil },
            set: { if !$0 { viewModel.saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.saveError ?? "An unknown error occurred.")
        }
        .alert("Couldn't Save to Your Videos", isPresented: .init(
            get: { viewModel.saveToMyVideosError != nil },
            set: { if !$0 { viewModel.saveToMyVideosError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.saveToMyVideosError ?? "An unknown error occurred.")
        }
        .alert("Couldn't Mark Reviewed", isPresented: .init(
            get: { markReviewedError != nil },
            set: { if !$0 { markReviewedError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(markReviewedError ?? "")
        }
        .confirmationDialog("Playback Speed", isPresented: $showingSpeedPicker) {
            ForEach([0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                Button(rate == 1.0 ? "1x (Normal)" : "\(String(format: "%gx", rate))") {
                    viewModel.setPlaybackRate(rate)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// All initial async loads for the player. Extracted from the `.task`
    /// modifier so `body` stays within the Swift type-checker's complexity budget.
    private func runInitialLoad() async {
        // Surface the "already saved to My Videos" badge immediately so
        // the athlete doesn't see a "save" prompt for a clip they already
        // brought in. Local SwiftData query — cheap.
        if isFolderOwner {
            viewModel.refreshAlreadySavedToMyVideos(modelContext: modelContext)
        }

        // Load video first (always needed)
        await viewModel.loadVideo()

        // Seed the inline cue picker up front (coach-only) so the chips
        // populate immediately instead of staying blank through the heavier
        // annotation / drill-card loads below. Cue templates load off the
        // critical path into the shared service; selectedCueTags is local.
        if canEditCoachNote, let coachID = authManager.userID {
            selectedCueTags = video.tags
            Task { await templateService.loadQuickCues(coachID: coachID) }
        }

        // Generate filmstrip and load video natural size after player is ready
        await viewModel.loadVideoNaturalSize()
        viewModel.generateFilmstrip()

        // Load annotations, cues, and drill cards sequentially
        // (async let can crash the runtime if the view is dismissed mid-flight)
        await viewModel.loadAnnotations()
        do {
            drillCardsLoadFailed = false
            drillCards = try await FirestoreManager.shared.fetchDrillCards(forVideo: video.id)
        } catch {
            drillCardsLoadFailed = true
            ErrorHandlerService.shared.handle(error, context: "CoachVideoPlayer.loadDrillCards", showAlert: false)
        }
        if let coachID = authManager.userID {
            await templateService.loadDrillTemplates(coachID: coachID)
        }

        // Mark this video's notifications as read (athlete viewing coach feedback)
        if let userID = authManager.userID {
            await ActivityNotificationService.shared.markVideoRead(videoID: video.id, forUserID: userID)
        }

        // Opening a clip no longer auto-marks it reviewed. "Reviewed" now means
        // the coach actually left feedback (note / cue / drawing / drill card) or
        // tapped "Done reviewing", so the Needs-Review queue reflects work
        // remaining rather than what's merely been glanced at. The athlete-facing
        // notification is still cleared above by markVideoRead. See
        // markReviewedOnEngagement().

        // Pull the athlete's view receipt fresh — the clip snapshot can be
        // stale if the athlete watched after the coach opened the folder.
        refreshViewReceipt()

        // Auto-show the earliest coach drawing once everything is loaded.
        // Aspect ratio (videoNaturalSize) is set by loadVideoNaturalSize
        // above; annotations populated by loadAnnotations. No-op when the
        // clip has no drawings.
        viewModel.autoShowFirstDrawingIfReady()
    }

    @ViewBuilder
    private var drillCardEditorSheet: some View {
        if let coachID = authManager.userID {
            DrillCardView(
                videoID: video.id,
                coachID: coachID,
                coachName: authManager.userDisplayName ?? "Coach",
                onSave: { card in
                    drillCards.insert(card, at: 0)
                    markReviewedOnEngagement()
                    // Athlete is notified by the server-side onNewDrillCard CF
                    // which fires on drillCards subcollection creation.
                }
            )
        }
    }

    @ViewBuilder
    private var drillCardLoadErrorView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
                .foregroundColor(.secondary)
            Text("Couldn't load drill cards")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Button("Try Again") {
                Task { await reloadDrillCards() }
            }
            .buttonStyle(.bordered)
            .tint(ppAccent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func reloadDrillCards() async {
        drillCardsLoadFailed = false
        do {
            drillCards = try await FirestoreManager.shared.fetchDrillCards(forVideo: video.id)
        } catch {
            drillCardsLoadFailed = true
            ErrorHandlerService.shared.handle(error, context: "CoachVideoPlayer.reloadDrillCards", showAlert: false)
        }
    }

    private func handleScenePhaseChange(old: ScenePhase, new: ScenePhase) {
        if new != .active {
            viewModel.shouldResumeOnActive = (viewModel.player?.rate ?? 0) > 0
            viewModel.player?.pause()
        } else if new == .active, old != .active {
            if viewModel.shouldResumeOnActive {
                viewModel.player?.play()
            }
            viewModel.shouldResumeOnActive = false
            // Athlete may have watched while the app was backgrounded.
            refreshViewReceipt()
        }
    }
    
    // MARK: - Layout Variants

    private var playerHeight: CGFloat {
        min(max(UIScreen.main.bounds.height * 0.4, 220), 400)
    }

    private var videoAspectRatio: CGFloat {
        if let size = viewModel.videoNaturalSize, size.height > 0 {
            return size.width / size.height
        }
        return 16.0 / 9.0
    }

    @ViewBuilder
    private var filmstripSection: some View {
        if !viewModel.filmstripThumbnails.isEmpty || viewModel.isGeneratingFilmstrip {
            FilmstripScrubberView(
                thumbnails: viewModel.filmstripThumbnails,
                currentTime: viewModel.observedPlaybackTime,
                duration: viewModel.videoDuration ?? 0,
                onSeek: { timestamp in
                    viewModel.seekToTimestampPaused(timestamp)
                },
                isLoading: viewModel.isGeneratingFilmstrip,
                isPlaying: viewModel.isPlaying,
                markers: viewModel.annotations.filter { $0.isDrawing },
                onTapMarker: { annotation in
                    viewModel.showDrawingOverlay(for: annotation)
                }
            )
            .onAppear { viewModel.startFilmstripTimeObserver() }
            .onDisappear { viewModel.stopFilmstripTimeObserver() }
        }
    }

    /// Compact transport row for frame-by-frame stepping and whole-clip looping —
    /// the film-study controls AVKit's stock transport doesn't provide. Sits under
    /// the player in both layouts; the frame buttons disable at the clip ends.
    @ViewBuilder
    private var transportControls: some View {
        if viewModel.isPlayerReady {
            HStack(spacing: 32) {
                Button {
                    viewModel.stepFrame(by: -1)
                } label: {
                    Image(systemName: "backward.frame.fill")
                }
                .disabled(!viewModel.canStepBackward)
                .accessibilityLabel("Previous frame")

                Button {
                    viewModel.toggleLooping()
                } label: {
                    Image(systemName: "repeat")
                        .foregroundColor(viewModel.isLooping ? ppAccent : .secondary)
                }
                .accessibilityLabel(viewModel.isLooping ? "Looping on" : "Loop clip")

                Button {
                    viewModel.stepFrame(by: 1)
                } label: {
                    Image(systemName: "forward.frame.fill")
                }
                .disabled(!viewModel.canStepForward)
                .accessibilityLabel("Next frame")
            }
            .font(.title3)
            .foregroundColor(ppAccent)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Theme.surface)
        }
    }

    /// Portrait phone: the video pins to the top and everything below it scrolls
    /// as one unit (the clip-detail pattern). Previously a fixed, non-scrolling
    /// VStack — its bottom (the annotation panel) fell under the floating tab bar
    /// with no way to reach it. The tab content renders inline (natural height,
    /// no nested scroll) so the page is the single scroll region.
    private var narrowLayout: some View {
        VStack(spacing: 0) {
            playerContent
                .frame(height: playerHeight)
            // Filmstrip stays pinned under the video (matching wideLayout) so the
            // coach keeps precise frame-seeking in portrait while the notes below
            // scroll. Previously wide-layout-only, so phones lost the scrubber.
            filmstripSection
            transportControls
            ScrollView {
                VStack(spacing: 0) {
                    athleteNoteCard
                    coachNoteSection
                    annotationPanel(inline: true)
                }
                .padding(.bottom, .spacingLarge)
            }
            if isOwnPrivateDraft { draftPublishBar }
        }
        .background(Theme.surface)
    }

    private var wideLayout: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Video area
                VStack(spacing: 0) {
                    playerContent
                    filmstripSection
                    transportControls
                }
                Divider()
                // Sidebar
                CoachVideoSidebar(
                    showSpeedControl: isIPad,
                    playbackRate: viewModel.playbackRate,
                    onRateChanged: { viewModel.setPlaybackRate($0) },
                    athleteNote: { athleteNoteCard },
                    coachNote: { coachNoteSection },
                    annotationPanel: { annotationPanel(inline: false) }
                )
                .frame(width: isIPad ? 360 : 320)
                .background(Theme.surface)
            }
            if isOwnPrivateDraft { draftPublishBar }
        }
    }

    /// Coaches get one consolidated `CoachFeedbackCard` (note + cue picker +
    /// view-receipt + compact "Done reviewing"). Non-editing viewers (the
    /// folder-owner athlete) instead see the read-only coach note plus any
    /// applied cues rendered read-only, so coach-authored cues are visible on
    /// the receiving side rather than disappearing with the coach-only picker.
    /// "Done reviewing" handler, or nil on an unpublished draft (where the real
    /// send is "Share Now" on the publish bar, so the button would mislead).
    /// Typed explicitly — a `cond ? nil : methodRef` ternary inline in the
    /// CoachFeedbackCard call defeats the Swift type-checker.
    private var doneReviewingAction: (() -> Void)? {
        guard !isOwnPrivateDraft else { return nil }
        return { confirmReviewComplete() }
    }

    @ViewBuilder
    private var coachNoteSection: some View {
        if canDeliverFeedback {
            CoachFeedbackCard(
                authorName: viewModel.coachNoteAuthorName,
                noteText: viewModel.coachNoteText ?? "",
                updatedAt: viewModel.coachNoteUpdatedAt,
                quickCues: templateService.quickCues,
                appliedCues: selectedCueTags,
                viewedAt: athleteViewedAt,
                isSending: isConfirmingReview,
                onEditNote: { showingCoachNoteEditor = true },
                onToggleCue: toggleCue,
                onAddCue: addCue,
                onDone: doneReviewingAction
            )
        } else {
            coachNoteCard
            if !video.tags.isEmpty {
                readOnlyCueStrip
            }
        }
    }

    /// Read-only cue chips shown to the athlete so coach-applied cues are
    /// visible on the receiving side. Mirrors the cue styling in
    /// `AthleteClipReviewDetail`.
    private var readOnlyCueStrip: some View {
        VStack(alignment: .leading, spacing: .spacingSmall) {
            Text("Cues").smallCapsLabel()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: .spacingSmall) {
                    ForEach(video.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.ppCaptionBold)
                            .foregroundStyle(Theme.cueText)
                            .padding(.horizontal, .spacingMedium)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Theme.cueBg))
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var playerContent: some View {
        if let player = viewModel.player, viewModel.isPlayerReady {
            ZStack(alignment: .bottom) {
                VideoPlayer(player: player)
                    .allowsHitTesting(!showingTelestration && viewModel.activeDrawingOverlay == nil)
                    .onAppear {
                        // Play through the silent switch — coach clips often
                        // carry spoken cues in their audio.
                        AudioSessionManager.configureForPlayback()
                        // Suppress auto-play when the clip has coach drawings.
                        // The auto-show flow seeks to the first drawing's
                        // timestamp + pauses; auto-playing from t=0 here would
                        // cause a visible flash before the seek lands.
                        // dismissDrawingOverlay() resumes playback after the
                        // user dismisses each drawing.
                        if (video.drawingCount ?? 0) == 0 {
                            player.play()
                        }
                        viewModel.startTimeObserver()
                        markViewedIfFolderOwnerAthlete()
                    }
                    .onDisappear {
                        // Pause only — observer teardown lives on the outer
                        // body's .onDisappear so toggling telestration over
                        // the player doesn't drop time observers mid-session.
                        player.pause()
                    }

                // Annotation markers overlay (shared with VideoPlayerView).
                // Non-interactive here — coach/athlete open drawings from the
                // Notes tab on this view.
                if !showingTelestration, viewModel.activeDrawingOverlay == nil,
                   !viewModel.annotations.isEmpty,
                   let duration = viewModel.videoDuration, duration > 0 {
                    AnnotationMarkersOverlay(
                        annotations: viewModel.annotations,
                        duration: duration
                    )
                }

                // Telestration drawing canvas overlay
                if showingTelestration {
                    TelestrationOverlayView(
                        timestamp: viewModel.currentPlaybackTime,
                        videoAspectRatio: videoAspectRatio,
                        onSave: { drawing, shapes, timestamp, canvasSize in
                            guard let userID = authManager.userID,
                                  let userName = authManager.userDisplayName ?? authManager.userEmail else {
                                return "You're signed out. Sign in again to save this drawing."
                            }
                            let saveFailure = await viewModel.addDrawingAnnotation(
                                drawing: drawing,
                                shapes: shapes,
                                timestamp: timestamp,
                                canvasSize: canvasSize,
                                userID: userID,
                                userName: userName
                            )
                            if saveFailure == nil {
                                showingTelestration = false
                                markReviewedOnEngagement()
                            }
                            return saveFailure
                        },
                        onCancel: {
                            showingTelestration = false
                        }
                    )
                }

                // Read-only drawing annotation overlay
                if let overlay = viewModel.activeDrawingOverlay {
                    DrawingAnnotationOverlay(
                        drawingData: overlay.data,
                        videoAspectRatio: videoAspectRatio,
                        canvasSize: overlay.canvasSize,
                        shapes: overlay.shapes,
                        onDismiss: { viewModel.dismissDrawingOverlay() }
                    )
                }
            }
        } else if viewModel.isLoading {
            ZStack {
                Theme.tileNavyDark
                ProgressView("Loading video...")
                    .tint(.white)
            }
        } else if viewModel.errorMessage != nil {
            ZStack {
                Theme.tileNavyDark
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 36))
                        .foregroundColor(.white.opacity(0.7))
                    Text(viewModel.errorMessage ?? "Failed to load video")
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Button {
                        viewModel.errorMessage = nil
                        Task { await viewModel.loadVideo() }
                    } label: {
                        Text("Try Again")
                            .fontWeight(.semibold)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(ppAccent)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
            }
        } else {
            ZStack {
                Theme.tileNavyDark
                ProgressView("Buffering...")
                    .tint(.white)
            }
        }
    }

    /// `inline: true` (portrait phone) renders tab content at natural height
    /// with no internal scroll, since the whole page is one outer ScrollView.
    /// `inline: false` (iPad/landscape sidebar) keeps each tab self-scrolling
    /// inside the fixed-height sidebar region.
    private func annotationPanel(inline: Bool) -> some View {
        VStack(spacing: 0) {
            if feedbackDeliveryBlocked {
                feedbackBlockedBanner
            }
            Picker("View", selection: $selectedTab) {
                ForEach(VideoTab.allCases, id: \.self) { tab in
                    Label(tabTitle(tab), systemImage: tab.icon)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            Group {
                switch selectedTab {
                case .drawings:
                    NotesTabView(
                        notes: viewModel.annotations.filter { $0.isDrawing },
                        isLoading: viewModel.isLoadingAnnotations,
                        errorMessage: viewModel.errorMessage,
                        onDeleteNote: { note in
                            Task { await viewModel.deleteAnnotation(note) }
                        },
                        onSeekToTimestamp: { timestamp in
                            viewModel.seekToTimestamp(timestamp)
                        },
                        onShowDrawing: { annotation in
                            viewModel.showDrawingOverlay(for: annotation)
                        },
                        inline: inline
                    )
                case .drillCard:
                    if drillCardsLoadFailed && drillCards.isEmpty {
                        drillCardLoadErrorView
                    } else {
                        DrillCardTabView(
                            drillCards: drillCards,
                            // Blocks the "New Drill Card" button when feedback is
                            // gated; edit/delete of existing cards stay available
                            // (firestore.rules only blocks drill-card *creates*).
                            canManageCards: canDeliverFeedback,
                            onAdd: { showingDrillCardEditor = true },
                            // Editing re-delivers feedback → gated when blocked.
                            // Delete (removing feedback) stays on plain edit permission.
                            onEdit: canDeliverFeedback ? { card in editingDrillCard = card } : nil,
                            onDelete: canEditCoachNote ? { card in drillCardPendingDelete = card } : nil,
                            inline: inline
                        )
                    }
                case .info:
                    VideoInfoTabView(video: video, inline: inline)
                }
            }
        }
    }

    /// Segment title with a count suffix when the tab holds content, so an
    /// athlete whose only feedback is a drill card (or drawings) sees there's
    /// something to open instead of landing on an empty default tab.
    private func tabTitle(_ tab: VideoTab) -> String {
        switch tab {
        case .drawings:
            let count = viewModel.annotations.filter { $0.isDrawing }.count
            return count > 0 ? "Drawings (\(count))" : "Drawings"
        case .drillCard:
            return drillCards.isEmpty ? "Drill Card" : "Drill Card (\(drillCards.count))"
        case .info:
            return "Info"
        }
    }

    /// Athlete-authored context attached at share time. Suppressed for legacy
    /// instruction clips whose `notes` field actually holds a coach note —
    /// those render via `coachNoteCard` instead.
    @ViewBuilder
    private var athleteNoteCard: some View {
        if let notes = video.notes, !notes.isEmpty, video.uploadedByType != .coach {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "person.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(video.uploadedByName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    if let date = video.createdAt {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Text(notes)
                    .font(.subheadline)
                    .foregroundColor(.primary)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(10)
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
    }

    /// Coach-authored plain note. Visible when a coach note exists, or when the
    /// current viewer is a folder coach (in which case it shows an "add" affordance).
    @ViewBuilder
    private var coachNoteCard: some View {
        CoachNoteCard(
            text: viewModel.coachNoteText ?? "",
            authorName: viewModel.coachNoteAuthorName,
            updatedAt: viewModel.coachNoteUpdatedAt,
            canEdit: canDeliverFeedback,
            onEdit: { showingCoachNoteEditor = true }
        )
    }

    /// Coaches with comment permission can author/edit the coach note.
    /// The folder owner (athlete) cannot — the coach note is coach-only.
    private var canEditCoachNote: Bool {
        guard let userID = authManager.userID else { return false }
        guard userID != folder.ownerAthleteID else { return false }
        guard folder.sharedWithCoachIDs.contains(userID) else { return false }
        return folder.getPermissions(for: userID)?.canComment ?? false
    }

    /// True when this coach is over their athlete limit past the downgrade grace
    /// (server-set `downgradeUnresolved`, which firestore.rules also enforces). The
    /// review surface disables feedback-delivery affordances and points the coach
    /// to resolve, but viewing stays available. Always false for the folder-owner
    /// athlete (the flag only exists on coach profiles).
    private var feedbackDeliveryBlocked: Bool {
        // Server flag is authoritative (it's what firestore.rules enforces); the
        // manager folds in the immediate post-shed `locallyResolved` override.
        CoachDowngradeManager.shared.feedbackBlocked(
            downgradeUnresolved: authManager.userProfile?.downgradeUnresolved
        )
    }

    /// Coach may author/deliver feedback: has comment permission AND isn't blocked
    /// by an unresolved downgrade. Gates note edit, telestration, and drill-card add.
    private var canDeliverFeedback: Bool {
        canEditCoachNote && !feedbackDeliveryBlocked
    }

    /// In-review banner for a downgrade-blocked coach: viewing works, but feedback
    /// delivery is paused until they resolve. Opens the athlete-selection sheet.
    private var feedbackBlockedBanner: some View {
        Button { showingDowngradeSelection = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                    .foregroundStyle(Theme.warning)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Over your athlete limit")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    Text("You can watch this clip, but choose which athletes to keep (or upgrade) to send feedback again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Theme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    /// True when the current user owns this folder (i.e. the athlete whose
    /// coaches are sharing clips with them). Controls visibility of the
    /// "Save to My Videos" toolbar button.
    private var isFolderOwner: Bool {
        guard let userID = authManager.userID else { return false }
        return userID == folder.ownerAthleteID
    }

    /// True when this is the current coach's own still-private draft clip —
    /// recorded/uploaded by them and not yet published to the athlete. Drives
    /// the draft publish bar (Share Now / Save for Later / Discard) and
    /// suppresses the misleading "Done reviewing" button (the real send is
    /// Share Now). The athlete never sees a private clip, so this is coach-only
    /// by construction. Only ever true when presented from the "My Drafts" cover.
    private var isOwnPrivateDraft: Bool {
        guard let userID = authManager.userID else { return false }
        return video.visibility == "private" && video.uploadedBy == userID
    }
    
    /// Re-verifies the current coach still has comment permission on this
    /// folder, then opens the telestration overlay.
    private func openTelestration() {
        guard let userID = authManager.userID else { return }
        viewModel.player?.pause()

        // Skip the network check for the folder owner (athlete) or pre-id folders.
        guard userID != folder.ownerAthleteID, let folderID = folder.id else {
            showingTelestration = true
            return
        }

        isVerifyingDrawPermission = true
        Task {
            defer { isVerifyingDrawPermission = false }
            do {
                let latest = try await SharedFolderManager.shared.verifyFolderAccess(folderID: folderID, coachID: userID)
                guard latest.getPermissions(for: userID)?.canComment ?? false else {
                    viewModel.errorMessage = "You no longer have permission to draw on this folder."
                    return
                }
                showingTelestration = true
            } catch {
                viewModel.errorMessage = "Unable to verify permissions. Please try again."
            }
        }
    }

    // MARK: - Coach review actions

    /// When the athlete last opened this clip (their view receipt), if ever.
    /// Prefers the live-refreshed value over the immutable load snapshot.
    private var athleteViewedAt: Date? {
        refreshedAthleteViewedAt ?? video.viewedBy?[folder.ownerAthleteID]
    }

    /// Coach-side refresh of the athlete's view receipt. `video` is an immutable
    /// snapshot, so without this a coach who keeps the player open would never
    /// see "Seen" once the athlete watches. Best-effort and coach-only — the
    /// athlete's own folder view is what *writes* the receipt.
    private func refreshViewReceipt() {
        guard canEditCoachNote, !isFolderOwner else { return }
        Task {
            if let latest = try? await FirestoreManager.shared.fetchVideo(videoID: video.id) {
                refreshedAthleteViewedAt = latest.viewedBy?[folder.ownerAthleteID]
            }
        }
    }

    /// Marks the clip reviewed by the current coach when they actually leave
    /// feedback — a quick cue, a drawing, or a drill card. The coach-note path
    /// already writes reviewedBy via setCoachNote, and "Done reviewing" marks it
    /// explicitly. Idempotent: markReviewed no-ops once reviewed. Replaces the
    /// old auto-mark-on-open so merely viewing a clip keeps it in the queue.
    private func markReviewedOnEngagement() {
        guard canEditCoachNote, let coachID = authManager.userID,
              !viewModel.isReviewed(by: coachID) else { return }
        Task { try? await viewModel.markReviewed(coachID: coachID, silent: true) }
    }

    /// Apply or remove a cue from the clip's tags and persist. Optimistic —
    /// local state flips immediately; a write failure is logged silently and
    /// the cue is rolled back so the chip never lies about what's saved.
    private func toggleCue(_ text: String) {
        let previous = selectedCueTags
        if selectedCueTags.contains(text) {
            selectedCueTags.removeAll { $0 == text }
        } else {
            selectedCueTags.append(text)
        }
        Haptics.light()
        persistCueTags(rollbackTo: previous)
    }

    /// Create a reusable quick cue and apply it to this clip.
    private func addCue(_ text: String) {
        guard let coachID = authManager.userID else { return }
        let previous = selectedCueTags
        if !selectedCueTags.contains(text) { selectedCueTags.append(text) }
        Haptics.light()
        persistCueTags(rollbackTo: previous)
        Task {
            _ = try? await templateService.addQuickCue(coachID: coachID, text: text, category: .mechanics)
        }
    }

    private func persistCueTags(rollbackTo previous: [String]) {
        let tags = selectedCueTags
        Task {
            do {
                try await FirestoreManager.shared.updateVideoTags(
                    videoID: video.id,
                    tags: tags,
                    drillType: video.drillType
                )
                // Applying a cue is real feedback → mark reviewed. Gated on a
                // non-empty result so clearing the last cue doesn't mark a clip
                // reviewed with no feedback left on it.
                if !tags.isEmpty { markReviewedOnEngagement() }
            } catch {
                selectedCueTags = previous
                ErrorHandlerService.shared.handle(error, context: "CoachVideoPlayer.updateCueTags", showAlert: false)
            }
        }
    }

    /// Coach's explicit "I'm done reviewing" confirmation. Feedback (notes /
    /// drawings / drill cards) is already delivered to the athlete by Cloud
    /// Functions as it's authored. This marks the clip reviewed — useful when the
    /// coach watched without leaving structured feedback but still wants it out of
    /// the Needs-Review queue. It does not itself send or notify (nothing triggers
    /// on `reviewedBy`).
    private func confirmReviewComplete() {
        guard let coachID = authManager.userID else { return }
        isConfirmingReview = true
        Task {
            do {
                try await viewModel.markReviewed(coachID: coachID)
                didConfirmReview = true
            } catch {
                markReviewedError = error.localizedDescription
            }
            isConfirmingReview = false
        }
    }

    // MARK: - Draft publish actions (own private drafts only)

    /// Pinned bottom bar shown for the coach's own unpublished draft. "Share
    /// Now" publishes (private → shared), firing the single onVideoPublished
    /// push; note/cues/drawings were already persisted as the coach authored
    /// them, so this is purely the visibility flip. Replaces the old standalone
    /// ClipReviewSheet so drafts and shared clips share one review surface.
    private var draftPublishBar: some View {
        ClipReviewPublishBar(
            isPublishing: isPublishingDraft,
            isSavingDraft: false,
            isDiscarding: isDiscardingDraft,
            // Publishing delivers feedback to the athlete — blocked while over the
            // downgrade limit. Redirect Share Now to the resolve sheet (rules would
            // reject the publish anyway); Save for Later / Discard stay available
            // since neither delivers anything to the athlete.
            onShareNow: shareDraftAction,
            onSaveForLater: saveDraftForLater,
            onDiscard: { showingDraftDiscardConfirm = true }
        )
        .background(Theme.surface)
    }

    /// Share Now redirects to the resolve sheet while feedback is blocked (the
    /// publish would be rejected by firestore.rules). Typed via guard/return — an
    /// inline `cond ? closure : methodRef` ternary defeats the Swift type-checker
    /// (see `doneReviewingAction`).
    private var shareDraftAction: () -> Void {
        if feedbackDeliveryBlocked {
            return { showingDowngradeSelection = true }
        }
        return shareDraftNow
    }

    private func shareDraftNow() {
        guard let folderID = folder.id else { return }
        isPublishingDraft = true
        Task {
            do {
                // Note + cues already persisted (setCoachNote / updateVideoTags as
                // authored). Publish only flips visibility and fires the cohesive
                // athlete push — pass nil so we never re-write them here.
                try await FirestoreManager.shared.publishPrivateVideo(
                    videoID: video.id,
                    sharedFolderID: folderID
                )
                Haptics.success()
                isPublishingDraft = false
                // The parent (My-Drafts cover) dismisses + reloads via the
                // callback. Fall back to a direct dismiss so a callback-less
                // presentation can't strand a published clip behind a spinner.
                if let onDraftShared { onDraftShared() } else { dismiss() }
            } catch {
                draftActionError = "Couldn't share this clip: \(error.localizedDescription)"
                ErrorHandlerService.shared.handle(error, context: "CoachVideoPlayer.shareDraftNow", showAlert: false)
                isPublishingDraft = false
            }
        }
    }

    /// Keeps the clip private. Note/cues/drawings already autosave, so this just
    /// closes the draft and lets the parent reload.
    private func saveDraftForLater() {
        Haptics.light()
        if let onDraftSavedForLater { onDraftSavedForLater() } else { dismiss() }
    }

    private func discardDraft() {
        guard let folderID = folder.id else { return }
        isDiscardingDraft = true
        Task {
            do {
                try await FirestoreManager.shared.deleteCoachPrivateVideo(
                    videoID: video.id,
                    sharedFolderID: folderID,
                    fileName: video.fileName
                )
                Haptics.success()
                isDiscardingDraft = false
                if let onDraftDiscarded { onDraftDiscarded() } else { dismiss() }
            } catch {
                draftActionError = "Couldn't discard this clip: \(error.localizedDescription)"
                ErrorHandlerService.shared.handle(error, context: "CoachVideoPlayer.discardDraft", showAlert: false)
                isDiscardingDraft = false
            }
        }
    }

    // MARK: - Drill card edit / delete

    /// Drill-card editor seeded with an existing card (distinct from the "New
    /// Drill Card" path, which uses `drillCardEditorSheet`). On save, replaces
    /// the edited card in the local list.
    @ViewBuilder
    private func editDrillCardSheet(existing: DrillCard) -> some View {
        if let coachID = authManager.userID {
            DrillCardView(
                videoID: video.id,
                coachID: coachID,
                coachName: authManager.userDisplayName ?? "Coach",
                existingCard: existing,
                onSave: { updated in
                    if let idx = drillCards.firstIndex(where: { $0.id == updated.id }) {
                        drillCards[idx] = updated
                    }
                }
            )
        }
    }

    /// Deletes a coach-created drill card and removes it from the local list.
    private func deleteDrillCard(_ card: DrillCard) {
        guard let cardID = card.id else { return }
        Task {
            do {
                try await FirestoreManager.shared.deleteDrillCard(videoID: video.id, cardID: cardID)
                drillCards.removeAll { $0.id == cardID }
                Haptics.success()
            } catch {
                ErrorHandlerService.shared.handle(error, context: "CoachVideoPlayer.deleteDrillCard", showAlert: false)
            }
        }
    }

    /// Writes the athlete's view receipt the first time they play a clip in
    /// their own folder. Coaches reviewing their own uploads do not write —
    /// the field tracks athlete-side viewership only.
    private func markViewedIfFolderOwnerAthlete() {
        guard !hasMarkedViewed else { return }
        guard isFolderOwner, let athleteID = authManager.userID else { return }
        hasMarkedViewed = true
        Task {
            do {
                try await FirestoreManager.shared.markVideoViewedByAthlete(
                    videoID: video.id,
                    athleteID: athleteID
                )
            } catch {
                ErrorHandlerService.shared.handle(error, context: "CoachVideoPlayer.markViewed", showAlert: false)
            }
        }
    }

}

// MARK: - Video Info Tab View

struct VideoInfoTabView: View {
    let video: CoachVideoItem
    /// Inline (portrait phone) drops the internal ScrollView — the page's outer
    /// ScrollView handles it. The sidebar (inline = false) keeps self-scrolling.
    var inline: Bool = false

    var body: some View {
        if inline {
            infoContent
        } else {
            ScrollView { infoContent }
        }
    }

    private var infoContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            InfoRow(label: "Uploaded By", value: video.uploadedByName)
                
                if let date = video.createdAt {
                    InfoRow(label: "Upload Date", value: date.formatted(date: .long, time: .shortened))
                }
                
                if let context = video.contextLabel {
                    InfoRow(label: "Context", value: context)
                }

                if let club = video.club {
                    InfoRow(label: "Club", value: club)
                }

                if let hole = video.holeNumber {
                    InfoRow(label: "Hole", value: "\(hole)")
                }

                if let opponent = video.gameOpponent {
                    InfoRow(label: "Opponent", value: opponent)
                }

                if let playResult = video.playResult, !playResult.isEmpty {
                    InfoRow(label: "Play Result", value: playResult)
                }

                if let pitchType = video.pitchType, !pitchType.isEmpty {
                    InfoRow(label: "Pitch Type", value: pitchType.capitalized)
                }

                if let pitchSpeed = video.pitchSpeed, pitchSpeed > 0 {
                    InfoRow(label: "Pitch Speed", value: "\(Int(pitchSpeed.rounded())) mph")
                }

                if let duration = video.duration {
                    InfoRow(label: "Duration", value: formatDuration(duration))
                }
                
                if let fileSize = video.fileSize {
                    InfoRow(label: "File Size", value: formatFileSize(fileSize))
                }
                
                if video.isHighlight {
                    HStack {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                        Text("Highlight Video")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.yellow.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            .padding()
        }

    private func formatDuration(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}


