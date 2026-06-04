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
    
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @State private var viewModel: CoachVideoPlayerViewModel
    @State private var showingCoachNoteEditor = false
    @State private var selectedTab: VideoTab = .drawings
    @State private var showingSpeedPicker = false
    @State private var showingDrillCardEditor = false
    @State private var markReviewedError: String?
    @State private var showingTelestration = false
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
    
    init(folder: SharedFolder, video: CoachVideoItem) {
        self.folder = folder
        self.video = video
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
    
    var body: some View {
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
                HStack(spacing: 12) {
                    // Telestration draw button (coaches only). Re-verifies
                    // comment permission before opening — folder shares can
                    // be revoked mid-session, and the server will reject the
                    // write anyway; this gives the coach a clean error
                    // instead of an opaque Firestore failure.
                    if canEditCoachNote {
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

                    // Save to My Videos button — folder owner (athlete) only.
                    // Brings the clip into the athlete's in-app Videos tab
                    // with a link back to coach annotations.
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
        .task {
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

            // A folder coach opening an unreviewed clip counts as reviewing it —
            // keeps the dashboard "Needs Review" count in sync with the folder
            // badge that markVideoRead just cleared, so the two never disagree.
            // The explicit "Mark Reviewed" button stays for marking from a list.
            if canEditCoachNote, let coachID = authManager.userID, !viewModel.isReviewed(by: coachID) {
                try? await viewModel.markReviewed(coachID: coachID, silent: true)
            }

            // Pull the athlete's view receipt fresh — the clip snapshot can be
            // stale if the athlete watched after the coach opened the folder.
            refreshViewReceipt()

            // Auto-show the earliest coach drawing once everything is loaded.
            // Aspect ratio (videoNaturalSize) is set by loadVideoNaturalSize
            // above; annotations populated by loadAnnotations. No-op when the
            // clip has no drawings.
            viewModel.autoShowFirstDrawingIfReady()
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
        }
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

    private var narrowLayout: some View {
        VStack(spacing: 0) {
            playerContent
                .frame(height: playerHeight)
            athleteNoteCard
            coachNoteSection
            annotationPanel
        }
        .background(Theme.surface)
    }

    private var wideLayout: some View {
        HStack(spacing: 0) {
            // Video area
            VStack(spacing: 0) {
                playerContent
                filmstripSection
            }
            Divider()
            // Sidebar
            CoachVideoSidebar(
                showSpeedControl: isIPad,
                playbackRate: viewModel.playbackRate,
                onRateChanged: { viewModel.setPlaybackRate($0) },
                athleteNote: { athleteNoteCard },
                coachNote: { coachNoteSection },
                annotationPanel: { annotationPanel }
            )
            .frame(width: isIPad ? 360 : 320)
            .background(Theme.surface)
        }
    }

    /// Coach note + (coach-only) the cue picker / Send / view-receipt bar.
    @ViewBuilder
    private var coachNoteSection: some View {
        coachNoteCard
        if canEditCoachNote {
            CoachReviewActionsBar(
                athleteName: athleteFirstName,
                quickCues: templateService.quickCues,
                appliedCues: selectedCueTags,
                viewedAt: athleteViewedAt,
                isSending: isConfirmingReview,
                onToggleCue: toggleCue,
                onAddCue: addCue,
                onSend: confirmReviewComplete
            )
        }
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

    private var annotationPanel: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $selectedTab) {
                ForEach(VideoTab.allCases, id: \.self) { tab in
                    Label(tab.rawValue, systemImage: tab.icon)
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
                        }
                    )
                case .drillCard:
                    if drillCardsLoadFailed && drillCards.isEmpty {
                        drillCardLoadErrorView
                    } else {
                        DrillCardTabView(
                            drillCards: drillCards,
                            canComment: canComment,
                            onAdd: { showingDrillCardEditor = true }
                        )
                    }
                case .info:
                    VideoInfoTabView(video: video)
                }
            }
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
            canEdit: canEditCoachNote,
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

    private var canComment: Bool {
        guard let userID = authManager.userID else { return false }
        if userID == folder.ownerAthleteID { return true }
        return folder.getPermissions(for: userID)?.canComment ?? false
    }

    /// True when the current user owns this folder (i.e. the athlete whose
    /// coaches are sharing clips with them). Controls visibility of the
    /// "Save to My Videos" toolbar button.
    private var isFolderOwner: Bool {
        guard let userID = authManager.userID else { return false }
        return userID == folder.ownerAthleteID
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

    /// First name of the folder-owning athlete, used in the review-actions copy.
    private var athleteFirstName: String {
        guard let name = folder.ownerAthleteName,
              let first = name.split(separator: " ").first else { return "athlete" }
        return String(first)
    }

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
            } catch {
                selectedCueTags = previous
                ErrorHandlerService.shared.handle(error, context: "CoachVideoPlayer.updateCueTags", showAlert: false)
            }
        }
    }

    /// Coach's explicit "I'm done reviewing" confirmation. Feedback (notes /
    /// drawings / drill cards) is already delivered to the athlete by Cloud
    /// Functions as it's authored, and the clip is auto-marked reviewed on open
    /// — so this re-affirms the reviewed mark and confirms with a toast. It does
    /// not itself send or notify (nothing triggers on `reviewedBy`).
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
    
    var body: some View {
        ScrollView {
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


