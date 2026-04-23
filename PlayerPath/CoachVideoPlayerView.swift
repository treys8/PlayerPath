//
//  CoachVideoPlayerView.swift
//  PlayerPath
//
//  Created by Assistant on 11/21/25.
//  Video player with annotation/notes system for coaches and athletes
//

import SwiftUI
import AVKit
import PencilKit

struct CoachVideoPlayerView: View {
    let folder: SharedFolder
    let video: CoachVideoItem
    
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @State private var viewModel: CoachVideoPlayerViewModel
    @State private var showingAddNote = false
    @State private var showingCoachNoteEditor = false
    @State private var selectedTab: VideoTab = .feedback
    @State private var showingSpeedPicker = false
    @State private var showingQuickCueManager = false
    @State private var showingDrillCardEditor = false
    @State private var isMarkingReviewed = false
    @State private var markReviewedError: String?
    @State private var showingTelestration = false
    @State private var drillCards: [DrillCard] = []
    private var templateService: CoachTemplateService { .shared }
    @Environment(\.modelContext) private var modelContext
    @Environment(\.verticalSizeClass) private var vSizeClass
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.scenePhase) private var scenePhase
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
        case feedback = "Feedback"
        case drillCard = "Drill Card"
        case info = "Info"

        var icon: String {
            switch self {
            case .feedback: return "bubble.left.fill"
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
                    // Mark as Reviewed button — only for folder coaches who
                    // haven't yet reviewed this clip.
                    if canEditCoachNote, !viewModel.isReviewed(by: authManager.userID ?? "") {
                        Button {
                            markReviewed()
                        } label: {
                            Image(systemName: "checkmark.circle")
                                .foregroundColor(.brandNavy)
                        }
                        .disabled(isMarkingReviewed)
                        .accessibilityLabel("Mark as reviewed")
                    }

                    // Telestration draw button (coaches only)
                    if canEditCoachNote {
                        Button {
                            viewModel.player?.pause()
                            showingTelestration = true
                        } label: {
                            Image(systemName: "pencil.tip")
                                .foregroundColor(.brandNavy)
                        }
                        .disabled(!viewModel.isPlayerReady)
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
                                    .foregroundColor(.brandNavy)
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
                                .foregroundColor(.brandNavy)
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
                                .foregroundColor(.brandNavy)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.brandNavy.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        .accessibilityLabel("Playback speed: \(viewModel.playbackRate)x")
                    }
                }
            }
        }
        .toast(isPresenting: $viewModel.didSaveSuccessfully, message: "Video Saved")
        .toast(isPresenting: $viewModel.didSaveToMyVideosSuccessfully, message: "Added to Your Videos")
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
        .sheet(isPresented: $showingAddNote) {
            EnhancedAddNoteView(
                currentTime: viewModel.currentPlaybackTime,
                quickCues: templateService.quickCues,
                onSave: { noteText, timestamp, category in
                    Task {
                        await addNote(text: noteText, timestamp: timestamp, category: category)
                    }
                }
            )
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
        .sheet(isPresented: $showingQuickCueManager) {
            if let coachID = authManager.userID {
                QuickCueManager(coachID: coachID)
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

            // Generate filmstrip and load video natural size after player is ready
            await viewModel.loadVideoNaturalSize()
            viewModel.generateFilmstrip()

            // Load annotations, cues, and drill cards sequentially
            // (async let can crash the runtime if the view is dismissed mid-flight)
            await viewModel.loadAnnotations()
            do {
                drillCards = try await FirestoreManager.shared.fetchDrillCards(forVideo: video.id)
            } catch {
                ErrorHandlerService.shared.handle(error, context: "CoachVideoPlayer.loadDrillCards", showAlert: false)
            }
            if let coachID = authManager.userID {
                await templateService.loadQuickCues(coachID: coachID)
            }

            // Mark this video's notifications as read (athlete viewing coach feedback)
            if let userID = authManager.userID {
                await ActivityNotificationService.shared.markVideoRead(videoID: video.id, forUserID: userID)
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            handleScenePhaseChange(old: oldPhase, new: newPhase)
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

    private func handleScenePhaseChange(old: ScenePhase, new: ScenePhase) {
        if new != .active {
            viewModel.shouldResumeOnActive = (viewModel.player?.rate ?? 0) > 0
            viewModel.player?.pause()
        } else if new == .active, old != .active {
            if viewModel.shouldResumeOnActive {
                viewModel.player?.play()
            }
            viewModel.shouldResumeOnActive = false
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
                isLoading: viewModel.isGeneratingFilmstrip
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
            coachNoteCard
            if canComment && !templateService.quickCues.isEmpty {
                QuickCueBar(
                    cues: templateService.quickCues,
                    onTap: { cue in quickCueTapped(cue) },
                    onManage: { showingQuickCueManager = true }
                )
            }
            annotationPanel
        }
    }

    private var wideLayout: some View {
        HStack(spacing: 0) {
            // Video area
            VStack(spacing: 0) {
                playerContent
                filmstripSection
                // On iPhone landscape, quick cues stay below the video
                if !isIPad, canComment, !templateService.quickCues.isEmpty {
                    QuickCueBar(
                        cues: templateService.quickCues,
                        onTap: { cue in quickCueTapped(cue) },
                        onManage: { showingQuickCueManager = true }
                    )
                }
            }
            Divider()
            // Sidebar
            CoachVideoSidebar(
                showSpeedControl: isIPad,
                playbackRate: viewModel.playbackRate,
                onRateChanged: { viewModel.setPlaybackRate($0) },
                athleteNote: { athleteNoteCard },
                coachNote: { coachNoteCard },
                quickCues: {
                    // On iPad, quick cues move into the sidebar
                    if isIPad, canComment, !templateService.quickCues.isEmpty {
                        QuickCueBar(
                            cues: templateService.quickCues,
                            onTap: { cue in quickCueTapped(cue) },
                            onManage: { showingQuickCueManager = true }
                        )
                    }
                },
                annotationPanel: { annotationPanel }
            )
            .frame(width: isIPad ? 360 : 320)
        }
    }

    @ViewBuilder
    private var playerContent: some View {
        if let player = viewModel.player, viewModel.isPlayerReady {
            ZStack(alignment: .bottom) {
                VideoPlayer(player: player)
                    .allowsHitTesting(!showingTelestration && viewModel.activeDrawingOverlay == nil)
                    .onAppear {
                        player.play()
                        viewModel.startTimeObserver()
                    }
                    .onDisappear {
                        player.pause()
                        viewModel.stopTimeObserver()
                        viewModel.stopFilmstripTimeObserver()
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
                                  let userName = authManager.userDisplayName ?? authManager.userEmail else { return false }
                            let saved = await viewModel.addDrawingAnnotation(
                                drawing: drawing,
                                shapes: shapes,
                                timestamp: timestamp,
                                canvasSize: canvasSize,
                                userID: userID,
                                userName: userName
                            )
                            if saved {
                                showingTelestration = false
                            }
                            return saved
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
                Color.black
                ProgressView("Loading video...")
                    .tint(.white)
            }
        } else if viewModel.errorMessage != nil {
            ZStack {
                Color(white: 0.3)
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
                            .background(Color.brandNavy)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
            }
        } else {
            ZStack {
                Color.black
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
                case .feedback:
                    NotesTabView(
                        notes: viewModel.annotations,
                        isLoading: viewModel.isLoadingAnnotations,
                        errorMessage: viewModel.errorMessage,
                        onAddNote: { showingAddNote = true },
                        onDeleteNote: { note in
                            Task { await viewModel.deleteAnnotation(note) }
                        },
                        onSeekToTimestamp: { timestamp in
                            viewModel.seekToTimestamp(timestamp)
                        },
                        onShowDrawing: { annotation in
                            viewModel.showDrawingOverlay(for: annotation)
                        },
                        canComment: canComment
                    )
                case .drillCard:
                    DrillCardTabView(
                        drillCards: drillCards,
                        canComment: canComment,
                        onAdd: { showingDrillCardEditor = true }
                    )
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
        let hasNote = !(viewModel.coachNoteText ?? "").isEmpty
        if hasNote || canEditCoachNote {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "person.fill.checkmark")
                        .font(.caption)
                        .foregroundColor(.brandNavy)
                    Text(viewModel.coachNoteAuthorName ?? "Coach")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.brandNavy)
                    Text("COACH")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.brandNavy.opacity(0.2))
                        .foregroundColor(.brandNavy)
                        .cornerRadius(4)
                    Spacer()
                    if let date = viewModel.coachNoteUpdatedAt {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if canEditCoachNote {
                        Button {
                            showingCoachNoteEditor = true
                        } label: {
                            Image(systemName: hasNote ? "pencil" : "plus.circle.fill")
                                .font(.subheadline)
                                .foregroundColor(.brandNavy)
                        }
                        .accessibilityLabel(hasNote ? "Edit coach note" : "Add coach note")
                    }
                }
                if hasNote {
                    Text(viewModel.coachNoteText ?? "")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                } else {
                    Text("Tap + to leave a plain-text note for the athlete.")
                        .font(.subheadline)
                        .italic()
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color.brandNavy.opacity(0.08))
            .cornerRadius(10)
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
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
    
    private func markReviewed() {
        guard let coachID = authManager.userID else { return }
        isMarkingReviewed = true
        Task {
            do {
                try await viewModel.markReviewed(coachID: coachID)
            } catch {
                markReviewedError = error.localizedDescription
            }
            isMarkingReviewed = false
        }
    }

    private func addNote(text: String, timestamp: Double, category: AnnotationCategory? = nil) async {
        guard let userID = authManager.userID,
              let userName = authManager.userDisplayName ?? authManager.userEmail else {
            return
        }

        // Re-verify comment permission before submitting (folder permissions may have changed)
        if userID != folder.ownerAthleteID, let folderID = folder.id {
            do {
                let latest = try await SharedFolderManager.shared.verifyFolderAccess(folderID: folderID, coachID: userID)
                guard latest.getPermissions(for: userID)?.canComment ?? false else {
                    viewModel.errorMessage = "You no longer have permission to comment on this folder."
                    return
                }
            } catch {
                viewModel.errorMessage = "Unable to verify permissions. Please try again."
                return
            }
        }

        let isCoach = authManager.userRole == .coach

        await viewModel.addAnnotation(
            text: text,
            timestamp: timestamp,
            userID: userID,
            userName: userName,
            isCoachComment: isCoach,
            category: category?.rawValue
        )
    }

    private func quickCueTapped(_ cue: QuickCue) {
        guard let coachID = authManager.userID else { return }
        Haptics.light()
        Task {
            await addNote(
                text: cue.text,
                timestamp: viewModel.currentPlaybackTime,
                category: cue.annotationCategory
            )
            if let cueID = cue.id {
                await templateService.incrementUsage(coachID: coachID, cueID: cueID)
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


