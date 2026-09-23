//
//  VideoClipsView.swift
//  PlayerPath
//
//  Created by Trey Schilling on 11/17/25.
//

import SwiftUI
import SwiftData
import TipKit

struct VideoClipsView: View {
    let athlete: Athlete
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    private var activeSport: Season.SportType { athlete.sportType }
    private let uploadManager = UploadQueueManager.shared
    @State private var showingRecorder = false
    @State private var showingAdvancedSearch = false
    @State private var selectedVideo: VideoClip?
    /// Grid taps open the prev/next pager over the filtered list; the
    /// notification path (no list context) still uses `selectedVideo`.
    @State private var playerSession: VideoPlayerSession?
    @State private var viewModel = VideoClipsViewModel()
    @State private var liveGameContext: Game?
    @State private var livePracticeContext: Practice?
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var videoToDelete: VideoClip?
    @State private var showingDeleteConfirmation = false

    // Batch selection mode
    @State private var isSelectionMode = false
    @State private var selectedVideos: Set<UUID> = []
    @State private var showingBulkDeleteConfirmation = false
    @State private var showingStatistics = false
    /// IDs (never models) captured when the bulk Link to Game sheet opens; the
    /// sheet resolves them live so a clip deleted mid-sheet just drops out.
    @State private var bulkLinkClipIDs: Set<UUID> = []
    @State private var showingBulkLinker = false
    @State private var showingBulkToast = false
    @State private var bulkToastMessage = ""
    @State private var bulkToastType: ToastType = .success

    // Delete guard
    @State private var isDeleting = false

    // Tips
    private let recordTip = VideoClipsRecordTip()
    private let videoClipOptionsTip = VideoClipOptionsTip()

    // Debounce for search-driven filtering
    @State private var filterDebounceTask: Task<Void, Never>?

    // Upload Video — state owned by BulkImportAttach modifier.
    @State private var importTrigger = false

    // Check if filters are active
    private var hasActiveFilters: Bool {
        viewModel.selectedSeasonFilter != nil ||
        viewModel.filter.isActive ||
        !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // Check if we have any videos at all (before filtering)
    private var hasAnyVideos: Bool {
        !videosForActiveSport.isEmpty
    }

    /// True when this athlete has seasons in more than one sport. Used to gate
    /// sport-aware empty-state copy ("No Golf Videos Yet") so single-sport
    /// athletes see the original "No Videos Yet" wording.
    private var isMultiSport: Bool {
        Set((athlete.seasons ?? []).map { $0.sport ?? .baseball }).count > 1
    }

    /// Clips that belong to the active sport, plus seasonless clips. Seasonless
    /// items (untagged imports, coach-recorded sessions, ad-hoc captures) are
    /// shown under both sports so they aren't hidden from a user mid-toggle.
    private var videosForActiveSport: [VideoClip] {
        (athlete.videoClips ?? []).filter { clip in
            guard let season = clip.season else { return true }
            return (season.sport ?? .baseball) == activeSport
        }
    }

    private var filterDescription: String {
        var parts: [String] = []

        if let seasonID = viewModel.selectedSeasonFilter {
            if seasonID == "no_season" {
                parts.append("season: None")
            } else if let season = viewModel.availableSeasons.first(where: { $0.id.uuidString == seasonID }) {
                parts.append("season: \(season.displayName)")
            }
        }

        if viewModel.filter.isActive {
            parts.append(viewModel.filter.summary)
        }

        if !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("search: \"\(viewModel.searchText)\"")
        }

        return parts.isEmpty ? "your filters" : parts.joined(separator: ", ")
    }

    /// Debounce search-driven filter updates so typing doesn't block the main thread on every keystroke.
    private func debouncedFilterUpdate() {
        filterDebounceTask?.cancel()
        filterDebounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            viewModel.refilter()
            pruneSelection()
        }
    }

    /// Drop selections the current filters hide, so bulk actions only ever act
    /// on clips the user can see.
    private func pruneSelection() {
        guard isSelectionMode, !selectedVideos.isEmpty else { return }
        selectedVideos.formIntersection(viewModel.allFilteredVideos.map(\.id))
    }

    private var allFilteredSelected: Bool {
        !viewModel.allFilteredVideos.isEmpty && selectedVideos.count == viewModel.allFilteredVideos.count
    }

    private func clearAllFilters() {
        Haptics.light()
        withAnimation {
            viewModel.selectedSeasonFilter = nil
            viewModel.filter = VideoClipFilter()
            viewModel.searchText = ""
        }
        viewModel.update(videos: videosForActiveSport)
    }
    
    @ToolbarContentBuilder
    private var videosToolbar: some ToolbarContent {
        if isSelectionMode {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") {
                    isSelectionMode = false
                    selectedVideos.removeAll()
                    Haptics.light()
                }
            }

            ToolbarItem(placement: .principal) {
                if selectedVideos.isEmpty {
                    Text("Tap videos to select")
                        .font(.bodyMedium)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(selectedVideos.count) selected")
                        .font(.headingMedium)
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        if allFilteredSelected {
                            selectedVideos.removeAll()
                        } else {
                            selectedVideos = Set(viewModel.allFilteredVideos.map(\.id))
                        }
                        Haptics.selection()
                    } label: {
                        if allFilteredSelected {
                            Label("Deselect All", systemImage: "circle")
                        } else {
                            Label("Select All (\(viewModel.allFilteredVideos.count))", systemImage: "checkmark.circle.fill")
                        }
                    }

                    Divider()

                    Button { bulkUploadSelected() } label: {
                        Label("Upload Selected", systemImage: "icloud.and.arrow.up")
                    }
                    .disabled(selectedVideos.isEmpty)

                    Button { bulkSetHighlight(true) } label: {
                        Label("Mark as Highlights", systemImage: "star.fill")
                    }
                    .disabled(selectedVideos.isEmpty)

                    Button { bulkSetHighlight(false) } label: {
                        Label("Remove from Highlights", systemImage: "star.slash")
                    }
                    .disabled(selectedVideos.isEmpty)

                    Button {
                        bulkLinkClipIDs = selectedVideos
                        showingBulkLinker = true
                    } label: {
                        Label(activeSport == .golf ? "Link to Tournament…" : "Link to Game…",
                              systemImage: activeSport == .golf ? "figure.golf" : "baseball.diamond.bases")
                    }
                    .disabled(selectedVideos.isEmpty)

                    Divider()

                    Button(role: .destructive) { showingBulkDeleteConfirmation = true } label: {
                        Label("Delete Selected", systemImage: "trash")
                    }
                    .disabled(selectedVideos.isEmpty)
                } label: {
                    Image(systemName: ToolbarSymbol.more)
                }
                .accessibilityLabel("Selection actions")
            }
        } else {
            ToolbarItem(placement: .principal) {
                PPAthleteSwitcher(athlete: athlete)
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    Haptics.light()
                    showingRecorder = true
                } label: {
                    Image(systemName: "video.badge.plus")
                }
                .accessibilityLabel("Record video")
            }

            if !videosForActiveSport.isEmpty {
                // Leading, not trailing: three trailing items leave iOS no room to
                // center the principal athlete switcher, so it drifted left here.
                ToolbarItem(placement: .topBarLeading) {
                    SeasonFilterMenu(
                        selectedSeasonID: $viewModel.selectedSeasonFilter,
                        availableSeasons: viewModel.availableSeasons,
                        showNoSeasonOption: videosForActiveSport.contains(where: { $0.season == nil })
                    )
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if !videosForActiveSport.isEmpty {
                        Button {
                            Haptics.light()
                            showingAdvancedSearch = true
                        } label: {
                            Label("Advanced Search", systemImage: "text.magnifyingglass")
                        }

                        Divider()
                    }

                    Button {
                        Haptics.light()
                        importTrigger = true
                    } label: {
                        Label("Upload Video", systemImage: "square.and.arrow.down.on.square")
                    }

                    if !videosForActiveSport.isEmpty {
                        Button {
                            Haptics.light()
                            showingStatistics = true
                        } label: {
                            Label("Upload Statistics", systemImage: "chart.bar.fill")
                        }

                        Divider()

                        Button {
                            isSelectionMode = true
                            Haptics.light()
                        } label: {
                            Label("Select Videos", systemImage: "checkmark.circle")
                        }
                    }
                } label: {
                    Image(systemName: ToolbarSymbol.more)
                }
                .accessibilityLabel("More options")
            }
        }
    }

    @ViewBuilder
    private var videosContent: some View {
        if viewModel.isLoading {
            VideoGridSkeletonView()
        } else if viewModel.filteredVideos.isEmpty {
            if hasActiveFilters && hasAnyVideos {
                // Keep the chip bar so the user can turn off the one chip that
                // emptied the grid instead of clearing every filter.
                VStack(spacing: 0) {
                    filterBar
                    FilteredEmptyStateView(
                        filterDescription: filterDescription,
                        onClearFilters: clearAllFilters
                    )
                    .frame(maxHeight: .infinity)
                }
                } else {
                    // True empty state
                    emptyStateView
                }
            } else {
                videoListView
            }
    }

    private var untaggedCount: Int {
        videosForActiveSport.filter { !$0.isTagged && !$0.isDeletedRemotely }.count
    }

    var body: some View {
        videosContent
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface)
        .navigationTitle("The Tape.")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $viewModel.searchText, prompt: "Search videos")
        .toolbar { videosToolbar }
        .fullScreenCover(isPresented: $showingRecorder) {
            DirectCameraRecorderView(athlete: athlete, game: liveGameContext, practice: livePracticeContext)
        }
        .fullScreenCover(item: $selectedVideo) { video in
            VideoPlayerView(clip: video)
        }
        .fullScreenCover(item: $playerSession) { session in
            VideoClipPagerView(athlete: athlete, session: session)
        }
        .sheet(isPresented: $showingStatistics) {
            UploadStatisticsView()
        }
        .sheet(isPresented: $showingAdvancedSearch) {
            AdvancedSearchView(athlete: athlete)
        }
        .sheet(isPresented: $showingBulkLinker, onDismiss: {
            bulkLinkClipIDs = []
        }) {
            GameLinkerView(
                clips: (athlete.videoClips ?? []).filter { bulkLinkClipIDs.contains($0.id) },
                onSaved: {
                    // Only a successful save ends selection — Cancel keeps it.
                    isSelectionMode = false
                    selectedVideos.removeAll()
                }
            )
        }
        .bulkImportAttach(athlete: athlete, trigger: $importTrigger)
        .onReceive(NotificationCenter.default.publisher(for: .presentVideoRecorder)) { notification in
            // Bind the recorder to a game/practice when a reminder forwarded its id.
            // Resolve against the selected athlete's own games/practices — a reminder
            // for a different profile falls back to a generic recording. Game/Practice
            // ids are UUID; we filter the in-memory relationship (no fetch/#Predicate).
            if let game = notification.object as? Game {
                liveGameContext = game
                livePracticeContext = nil
            } else if let gameId = notification.userInfo?["gameId"] as? String,
                      let uuid = UUID(uuidString: gameId) {
                liveGameContext = athlete.games?.first { $0.id == uuid }
                livePracticeContext = nil
            } else if let practiceId = notification.userInfo?["practiceId"] as? String,
                      let uuid = UUID(uuidString: practiceId) {
                livePracticeContext = athlete.practices?.first { $0.id == uuid }
                liveGameContext = nil
            } else {
                liveGameContext = nil
                livePracticeContext = nil
            }
            showingRecorder = true
            Haptics.light()
        }
        .onReceive(NotificationCenter.default.publisher(for: .presentFullscreenVideo)) { notification in
            if let video = notification.object as? VideoClip {
                selectedVideo = video
                Haptics.light()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToUntaggedClips)) { _ in
            // Clip-tagging nudge tap landed here. Clear EVERY filter dimension the
            // VM ANDs together — search text, season pin, and the filter struct
            // (Highlights/Coach/result/club) — so a leftover from a prior session
            // can't intersect untagged to an empty dead-end. The existing
            // onChange handlers refilter. MainTabView handles the tab switch.
            viewModel.searchText = ""
            viewModel.selectedSeasonFilter = nil
            viewModel.filter = VideoClipFilter(untaggedOnly: true)
        }
        .task {
            viewModel.update(videos: videosForActiveSport)
        }
        .onAppear {
            // Tell MainTabView that Videos manages its own controls
            NotificationCenter.default.post(name: .videosManageOwnControls, object: true)
        }
        .onDisappear {
            // Reset when leaving Videos tab
            NotificationCenter.default.post(name: .videosManageOwnControls, object: false)
            liveGameContext = nil
            livePracticeContext = nil
        }
        .onChange(of: viewModel.searchText) { _, _ in
            debouncedFilterUpdate()
        }
        .onChange(of: viewModel.selectedSeasonFilter) { _, _ in
            viewModel.refilter()
            pruneSelection()
        }
        .onChange(of: viewModel.filter) { _, _ in
            viewModel.refilter()
            pruneSelection()
        }
        .onChange(of: videoClipsChangeKey) { _, _ in
            viewModel.update(videos: videosForActiveSport)
        }
        .onChange(of: activeSport) { _, newSport in
            // Sport toggle changes the visible clip set — refresh VM and bail
            // out of selection mode so users don't have stale cross-sport
            // selections that no longer appear in the grid.
            if isSelectionMode {
                isSelectionMode = false
                selectedVideos.removeAll()
            }
            // The Result menu (baseball/softball) and Club menu (golf) are
            // mutually exclusive in the bar. Clear whichever dimension just
            // became hidden so the user can't be stuck filtering by an
            // invisible, unclearable control after a sport toggle.
            if newSport == .golf {
                viewModel.filter.result = .any
            } else {
                viewModel.filter.club = .any
            }
            viewModel.update(videos: videosForActiveSport)
        }
        .alert("Unable to Load Videos", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "An unexpected error occurred. Please try again.")
        }
        .confirmationDialog("Delete Video", isPresented: $showingDeleteConfirmation, presenting: videoToDelete) { video in
            Button("Delete", role: .destructive) {
                performDelete(video)
            }
            Button("Cancel", role: .cancel) { }
        } message: { video in
            Text("Are you sure you want to delete this video? This action cannot be undone.")
        }
        .confirmationDialog("Delete Multiple Videos", isPresented: $showingBulkDeleteConfirmation) {
            Button("Delete \(selectedVideos.count.pluralized("Video"))", role: .destructive) {
                performBulkDelete()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete \(selectedVideos.count) video\(selectedVideos.count == 1 ? "" : "s")? This action cannot be undone.")
        }
        .toast(isPresenting: $showingBulkToast, type: bulkToastType, message: bulkToastMessage)
    }

    private func performDelete(_ video: VideoClip) {
        guard !isDeleting else { return }
        isDeleting = true
        Haptics.medium()

        // Capture ID, game, and athlete before deletion — accessing SwiftData object properties after
        // context.delete() is undefined behavior.
        let videoID = video.id.uuidString
        let videoGame = video.game
        let videoAthlete = video.athlete

        video.delete(in: modelContext)

        Task {
            do {
                try modelContext.save()
                AnalyticsService.shared.trackVideoDeleted(videoID: videoID)

                // Recalculate game statistics first (if clip belonged to a game),
                // then athlete statistics which aggregate from game stats.
                if let game = videoGame {
                    try StatisticsService.shared.recalculateGameStatistics(for: game, context: modelContext)
                }
                if let athlete = videoAthlete {
                    try StatisticsService.shared.recalculateAthleteStatistics(for: athlete, context: modelContext)
                }
                viewModel.update(videos: videosForActiveSport)
                isDeleting = false
            } catch {
                isDeleting = false
                errorMessage = "Could not delete this video. Please try again or restart the app if the problem continues."
                showingError = true
            }
        }
    }

    // MARK: - Selection Helper

    private func toggleSelection(for video: VideoClip) {
        if selectedVideos.contains(video.id) {
            selectedVideos.remove(video.id)
        } else {
            selectedVideos.insert(video.id)
        }
        Haptics.selection()
    }

    // MARK: - Bulk Operations

    private func performBulkDelete() {
        guard !isDeleting else { return }
        isDeleting = true
        Haptics.medium()

        let videosToDelete = videosForActiveSport.filter { selectedVideos.contains($0.id) }

        // Capture IDs and affected games before deletion — accessing SwiftData object properties
        // after context.delete() is undefined behavior.
        let deletedIDs = videosToDelete.map { $0.id.uuidString }
        let affectedGames = Set(videosToDelete.compactMap { $0.game })

        for video in videosToDelete {
            video.delete(in: modelContext)
        }

        Task {
            do {
                try modelContext.save()
                deletedIDs.forEach { AnalyticsService.shared.trackVideoDeleted(videoID: $0) }

                // Recalculate game statistics first for any affected games,
                // then athlete statistics which aggregate from game stats.
                for game in affectedGames {
                    try StatisticsService.shared.recalculateGameStatistics(for: game, context: modelContext)
                }
                try StatisticsService.shared.recalculateAthleteStatistics(for: athlete, context: modelContext)

                viewModel.update(videos: videosForActiveSport)
                Haptics.success()
            } catch {
                errorMessage = "Could not delete the selected videos. Please try again or restart the app if the problem continues."
                showingError = true
            }

            isDeleting = false
            isSelectionMode = false
            selectedVideos.removeAll()
        }
    }

    private func bulkUploadSelected() {
        let videosToUpload = videosForActiveSport.filter { selectedVideos.contains($0.id) }
        let pendingIDs = Set(UploadQueueManager.shared.pendingUploads.map(\.clipId))
        var queuedCount = 0
        var alreadyQueuedCount = 0

        for video in videosToUpload where !video.isUploaded {
            if pendingIDs.contains(video.id) || UploadQueueManager.shared.activeUploads[video.id] != nil {
                alreadyQueuedCount += 1
            } else {
                UploadQueueManager.shared.enqueue(video, athlete: athlete, priority: .high)
                queuedCount += 1
            }
        }

        if queuedCount > 0 {
            Haptics.success()
            showBulkToast("\(queuedCount.pluralized("video")) queued for upload")
        } else if alreadyQueuedCount > 0 {
            showBulkToast("Already queued for upload", type: .info)
        } else {
            showBulkToast("Already backed up", type: .info)
        }

        // Exit selection mode
        isSelectionMode = false
        selectedVideos.removeAll()
    }

    private func bulkSetHighlight(_ isHighlight: Bool) {
        let videosToMark = videosForActiveSport.filter { selectedVideos.contains($0.id) && $0.isHighlight != isHighlight }
        guard !videosToMark.isEmpty else {
            showBulkToast(isHighlight ? "Already highlights" : "None were highlights", type: .info)
            isSelectionMode = false
            selectedVideos.removeAll()
            return
        }

        for video in videosToMark {
            video.isHighlight = isHighlight
            video.needsSync = true
        }

        do {
            try modelContext.save()
            // Clips starred here may have been skipped by the save-time auto-upload gate
            // (e.g. "Highlights Only"); re-evaluate each now that it's a highlight.
            if isHighlight {
                for video in videosToMark {
                    UploadQueueManager.shared.reevaluateAutoUploadAfterHighlightChange(video, context: modelContext)
                }
            }
            viewModel.refilter(resetPaging: false)
            Haptics.success()
            let noun = videosToMark.count.pluralized("video")
            showBulkToast(isHighlight ? "\(noun) marked as highlights" : "\(noun) removed from highlights")
        } catch {
            errorMessage = "Could not update highlights. Your changes may not have been saved."
            showingError = true
        }

        // Exit selection mode
        isSelectionMode = false
        selectedVideos.removeAll()
    }

    private func showBulkToast(_ message: String, type: ToastType = .success) {
        bulkToastType = type
        bulkToastMessage = message
        showingBulkToast = true
    }

    private var emptyStateView: some View {
        EmptyStateView(
            systemImage: "video.slash",
            title: isMultiSport ? "No \(activeSport.displayName) Videos Yet" : "No Videos Yet",
            message: "Record a clip or import the videos you already have.",
            actionTitle: "Record Video",
            action: {
                Haptics.light()
                showingRecorder = true
            },
            secondaryActionTitle: "Import from Photos",
            secondaryAction: {
                importTrigger = true
            }
        )
        .onboardingTip(recordTip, arrowEdge: .top, also: !(athlete.games ?? []).isEmpty)
    }

    private var filterBar: some View {
        VideoFilterBar(
            filter: $viewModel.filter,
            sport: activeSport,
            opponents: viewModel.availableOpponents
        )
    }

    private var videoListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                UploadStatusBanner()

                // Tagging nudge scrolls with the grid so it's out of the way
                // once the user starts reviewing clips.
                if untaggedCount >= 3 && !viewModel.filter.untaggedOnly {
                    UntaggedClipsBanner(count: untaggedCount) {
                        withAnimation {
                            viewModel.filter.untaggedOnly = true
                        }
                    }
                    .padding(.top, 8)
                }

                // Combinable quick-filter chip bar
                if hasAnyVideos {
                    filterBar
                }

                LazyVGrid(
                    columns: [
                        GridItem(.adaptive(minimum: horizontalSizeClass == .regular ? 200 : 160, maximum: horizontalSizeClass == .regular ? 280 : 220), spacing: 16, alignment: .top)
                    ],
                    spacing: 16
                ) {
                    ForEach(viewModel.filteredVideos) { video in
                        VideoClipCard(
                            video: video,
                            isSelectionMode: isSelectionMode,
                            isSelected: selectedVideos.contains(video.id),
                            onPlay: {
                                if isSelectionMode {
                                    toggleSelection(for: video)
                                } else {
                                    playerSession = VideoPlayerSession(
                                        clipIDs: viewModel.allFilteredVideos.map(\.id),
                                        startID: video.id
                                    )
                                    Haptics.light()
                                }
                            },
                            onDelete: {
                                videoToDelete = video
                                showingDeleteConfirmation = true
                            },
                            onToggleSelection: {
                                toggleSelection(for: video)
                            },
                            onContextMenuOpened: {
                                videoClipOptionsTip.invalidate(reason: .actionPerformed)
                            }
                        )
                        .onboardingTip(videoClipOptionsTip, arrowEdge: .top, also: video.id == viewModel.filteredVideos.first?.id)
                        .onAppear {
                            viewModel.onItemAppear(video)
                            if let index = viewModel.filteredVideoIndex[video.id] {
                                prefetchNearbyThumbnails(for: index, in: viewModel.filteredVideos)
                            }
                        }
                    }
                }
                .padding(.vertical)
                .padding(.horizontal, horizontalSizeClass == .regular ? 32 : 18)
            }
        }
        .background(Theme.surface)
        .refreshable {
            await refreshVideos()
        }
    }

    @MainActor
    private func refreshVideos() async {
        Haptics.light()
        if let user = athlete.user, user.firebaseAuthUid != nil {
            do {
                try await SyncCoordinator.shared.syncAll(for: user)
            } catch is SyncCoordinatorError {
                // Already syncing or signed out — expected, ignore.
            } catch {
                ErrorHandlerService.shared.handle(error, context: "VideoClipsView.refreshable", showAlert: false)
            }
        }
        viewModel.update(videos: videosForActiveSport)
    }

    /// Composite key for `.onChange` that reacts to property mutations the
    /// filter depends on, not just add/remove. A count-only key misses edits
    /// like toggling isHighlight, tagging a playResult/club, or coach feedback
    /// arriving via sync. Uses `Hasher` to avoid allocating a multi-KB string
    /// on every SwiftUI body re-eval.
    private var videoClipsChangeKey: Int {
        var hasher = Hasher()
        for clip in (athlete.videoClips ?? []) {
            hasher.combine(clip.id)
            hasher.combine(clip.isHighlight)
            hasher.combine(clip.playResult?.type.rawValue)
            hasher.combine(clip.club)
            hasher.combine(clip.annotationCount)
            hasher.combine(clip.drawingCount)
            // Linking a game re-seasons the clip; both feed the sport scope, the
            // season filter, and the Opponent menu. Note-only coach feedback
            // feeds the Coach chip.
            hasher.combine(clip.season?.id)
            hasher.combine(clip.game?.id)
            hasher.combine(clip.practice?.id)
            hasher.combine(clip.gameOpponent)
            hasher.combine(clip.coachNoteSnapshot)
        }
        return hasher.finalize()
    }

    /// Prefetch thumbnails for videos near the current index for smooth scrolling
    private func prefetchNearbyThumbnails(for index: Int, in videos: [VideoClip]) {
        let prefetchRange = 3 // Prefetch 3 items ahead
        let startIndex = index + 1
        let endIndex = min(index + prefetchRange, videos.count - 1)

        guard startIndex <= endIndex else { return }

        let thumbnailPaths = videos[startIndex...endIndex].compactMap { $0.thumbnailPath }
        let targetSize = CGSize(width: 320, height: 180) // 2x of 160x90 display size for retina

        ThumbnailCache.shared.prefetchThumbnails(paths: thumbnailPaths, targetSize: targetSize)
    }
}

#Preview {
    NavigationStack {
        VideoClipsView(athlete: Athlete(name: "Test Player"))
    }
    .modelContainer(for: [Athlete.self, VideoClip.self])
}
