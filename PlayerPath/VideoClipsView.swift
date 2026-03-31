//
//  VideoClipsView.swift
//  PlayerPath
//
//  Created by Trey Schilling on 11/17/25.
//

import SwiftUI
import SwiftData
import AVKit
import PhotosUI
import Photos

struct VideoClipsView: View {
    let athlete: Athlete
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    private let uploadManager = UploadQueueManager.shared
    @State private var showingRecorder = false
    @State private var showingUploadPicker = false
    @State private var showingAdvancedSearch = false
    @State private var selectedVideo: VideoClip?
    @State private var viewModel = VideoClipsViewModel()
    @State private var liveGameContext: Game?
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var isImporting = false
    @State private var videoToDelete: VideoClip?
    @State private var showingDeleteConfirmation = false

    // Batch selection mode
    @State private var isSelectionMode = false
    @State private var selectedVideos: Set<UUID> = []
    @State private var showingBulkDeleteConfirmation = false
    @State private var showingStatistics = false
    @State private var bulkOperationMessage: String?

    // Delete guard
    @State private var isDeleting = false

    // Debounce for search-driven filtering
    @State private var filterDebounceTask: Task<Void, Never>?

    // Post-import tagging
    @State private var clipToTag: VideoClip?
    @State private var isAwaitingImportedClip = false

    // Check if filters are active
    private var hasActiveFilters: Bool {
        viewModel.selectedSeasonFilter != nil ||
        viewModel.selectedUploadFilter != .all ||
        !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // Check if we have any videos at all (before filtering)
    private var hasAnyVideos: Bool {
        !(athlete.videoClips?.isEmpty ?? true)
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

        if viewModel.selectedUploadFilter != .all {
            parts.append("upload: \(viewModel.selectedUploadFilter.rawValue)")
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
        }
    }

    private func clearAllFilters() {
        Haptics.light()
        withAnimation {
            viewModel.selectedSeasonFilter = nil
            viewModel.selectedUploadFilter = .all
            viewModel.searchText = ""
        }
        viewModel.update(videos: athlete.videoClips ?? [])
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
                Text("\(selectedVideos.count) selected")
                    .font(.headline)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { bulkUploadSelected() } label: {
                        Label("Upload Selected", systemImage: "icloud.and.arrow.up")
                    }
                    .disabled(selectedVideos.isEmpty)

                    Button { bulkMarkAsHighlight() } label: {
                        Label("Mark as Highlights", systemImage: "star.fill")
                    }
                    .disabled(selectedVideos.isEmpty)

                    Divider()

                    Button(role: .destructive) { showingBulkDeleteConfirmation = true } label: {
                        Label("Delete Selected", systemImage: "trash")
                    }
                    .disabled(selectedVideos.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Selection actions")
            }
        } else {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Haptics.light()
                    showingRecorder = true
                } label: {
                    Image(systemName: "video.badge.plus")
                }
                .accessibilityLabel("Record video")
            }

            if !(athlete.videoClips?.isEmpty ?? true) {
                ToolbarItem(placement: .topBarLeading) {
                    SeasonFilterMenu(
                        selectedSeasonID: $viewModel.selectedSeasonFilter,
                        availableSeasons: viewModel.availableSeasons,
                        showNoSeasonOption: (athlete.videoClips ?? []).contains(where: { $0.season == nil })
                    )
                }
            }

            if !(athlete.videoClips?.isEmpty ?? true) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.light()
                        showingAdvancedSearch = true
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("Advanced Search")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        Haptics.light()
                        showingUploadPicker = true
                    } label: {
                        Label("Upload from Library", systemImage: "square.and.arrow.up")
                    }

                    if !(athlete.videoClips?.isEmpty ?? true) {
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
                    Image(systemName: "ellipsis.circle")
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
                FilteredEmptyStateView(
                        filterDescription: filterDescription,
                        onClearFilters: clearAllFilters
                    )
                } else {
                    // True empty state
                    emptyStateView
                }
            } else {
                videoListView
            }
    }

    var body: some View {
        videosContent
        .safeAreaInset(edge: .top, spacing: 0) {
            UploadStatusBanner()
        }
        .navigationTitle("Videos")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $viewModel.searchText, prompt: "Search videos")
        .toolbar { videosToolbar }
        .fullScreenCover(isPresented: $showingRecorder) {
            DirectCameraRecorderView(athlete: athlete, game: liveGameContext)
        }
        .sheet(isPresented: $showingUploadPicker) {
            VideoRecorderView_Refactored(athlete: athlete)
        }
        .onChange(of: showingUploadPicker) { _, isShowing in
            if isShowing {
                isAwaitingImportedClip = true
            }
        }
        .fullScreenCover(item: $selectedVideo) { video in
            VideoPlayerView(clip: video)
        }
        .sheet(isPresented: $showingStatistics) {
            UploadStatisticsView()
        }
        .sheet(isPresented: $showingAdvancedSearch) {
            AdvancedSearchView(athlete: athlete)
        }
        .sheet(item: $clipToTag) { clip in
            ImportTaggingSheet(clip: clip, athlete: athlete)
        }
        .onReceive(NotificationCenter.default.publisher(for: .videoRecorded)) { notification in
            // Capture the most recently imported clip when it has no game context
            if isAwaitingImportedClip, let clip = notification.object as? VideoClip, clip.game == nil {
                // Delay slightly so the upload picker sheet can dismiss first
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(600))
                    clipToTag = clip
                    isAwaitingImportedClip = false
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .presentVideoRecorder)) { notification in
            liveGameContext = notification.object as? Game
            showingRecorder = true
            Haptics.light()
        }
        .onReceive(NotificationCenter.default.publisher(for: .presentFullscreenVideo)) { notification in
            if let video = notification.object as? VideoClip {
                selectedVideo = video
                Haptics.light()
            }
        }
        .task {
            viewModel.update(videos: athlete.videoClips ?? [])
        }
        .onAppear {
            // Tell MainTabView that Videos manages its own controls
            NotificationCenter.default.post(name: .videosManageOwnControls, object: true)
        }
        .onDisappear {
            // Reset when leaving Videos tab
            NotificationCenter.default.post(name: .videosManageOwnControls, object: false)
            liveGameContext = nil
        }
        .onChange(of: viewModel.searchText) { _, _ in
            debouncedFilterUpdate()
        }
        .onChange(of: viewModel.selectedSeasonFilter) { _, _ in
            viewModel.refilter()
        }
        .onChange(of: viewModel.selectedUploadFilter) { _, _ in
            viewModel.refilter()
        }
        .onChange(of: athlete.videoClips?.count) { _, _ in
            viewModel.update(videos: athlete.videoClips ?? [])
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
            Button("Delete \(selectedVideos.count) Videos", role: .destructive) {
                performBulkDelete()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete \(selectedVideos.count) video\(selectedVideos.count == 1 ? "" : "s")? This action cannot be undone.")
        }
        .overlay {
            if isImporting {
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Importing Video...")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .padding(32)
                    .background(Color(.systemBackground))
                    .cornerRadius(.cornerXLarge)
                    .shadow(radius: 20)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let message = bulkOperationMessage {
                Text(message)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.green, in: Capsule())
                    .shadow(radius: 8)
                    .padding(.bottom, 32)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
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
                viewModel.update(videos: athlete.videoClips ?? [])
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

        let videosToDelete = (athlete.videoClips ?? []).filter { selectedVideos.contains($0.id) }

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

                viewModel.update(videos: athlete.videoClips ?? [])
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
        let videosToUpload = (athlete.videoClips ?? []).filter { selectedVideos.contains($0.id) }
        var queuedCount = 0

        for video in videosToUpload {
            if !video.isUploaded {
                UploadQueueManager.shared.enqueue(video, athlete: athlete, priority: .high)
                queuedCount += 1
            }
        }

        Haptics.success()
        showBulkToast("\(queuedCount) video\(queuedCount == 1 ? "" : "s") queued for upload")

        // Exit selection mode
        isSelectionMode = false
        selectedVideos.removeAll()
    }

    private func bulkMarkAsHighlight() {
        let videosToMark = (athlete.videoClips ?? []).filter { selectedVideos.contains($0.id) }

        for video in videosToMark {
            video.isHighlight = true
            video.needsSync = true
        }

        do {
            try modelContext.save()
            viewModel.refilter()
            Haptics.success()
            showBulkToast("\(videosToMark.count) video\(videosToMark.count == 1 ? "" : "s") marked as highlights")
        } catch {
            errorMessage = "Could not mark videos as highlights. Your changes may not have been saved."
            showingError = true
        }

        // Exit selection mode
        isSelectionMode = false
        selectedVideos.removeAll()
    }

    private func showBulkToast(_ message: String) {
        withAnimation(.spring(response: 0.4)) {
            bulkOperationMessage = message
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut) {
                bulkOperationMessage = nil
            }
        }
    }

    private var emptyStateView: some View {
        EmptyStateView(
            systemImage: "video.slash",
            title: "No Videos Yet",
            message: "Record your first video to build your highlight reel",
            actionTitle: "Record Video",
            action: {
                Haptics.light()
                showingRecorder = true
            }
        )
        .tooltip(TipID.videosRecord, text: "Videos you record during games will show up here", arrowEdge: .bottom, showWhen: !(athlete.games ?? []).isEmpty)
    }

    private var uploadStatusFilterPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(UploadStatusFilter.allCases, id: \.self) { filter in
                    Button {
                        withAnimation {
                            viewModel.selectedUploadFilter = filter
                        }
                        Haptics.light()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: filter.icon)
                                .font(.caption)

                            Text(filter.rawValue)
                                .font(.subheadline)
                                .fontWeight(viewModel.selectedUploadFilter == filter ? .semibold : .regular)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            viewModel.selectedUploadFilter == filter ?
                                filter.color.opacity(0.2) :
                                Color.gray.opacity(0.1)
                        )
                        .foregroundColor(
                            viewModel.selectedUploadFilter == filter ?
                                filter.color :
                                .secondary
                        )
                        .cornerRadius(20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(
                                    viewModel.selectedUploadFilter == filter ?
                                        filter.color :
                                        Color.clear,
                                    lineWidth: 1.5
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .systemBackground))
    }

    private var videoListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Upload status filter picker
                if hasAnyVideos {
                    uploadStatusFilterPicker
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
                            hasCoachingAccess: authManager.hasCoachingAccess,
                            onPlay: {
                                if isSelectionMode {
                                    toggleSelection(for: video)
                                } else {
                                    selectedVideo = video
                                    Haptics.light()
                                }
                            },
                            onDelete: {
                                videoToDelete = video
                                showingDeleteConfirmation = true
                            },
                            onToggleSelection: {
                                toggleSelection(for: video)
                            }
                        )
                        .onAppear {
                            viewModel.onItemAppear(video)
                            if let index = viewModel.filteredVideoIndex[video.id] {
                                prefetchNearbyThumbnails(for: index, in: viewModel.filteredVideos)
                            }
                        }
                    }
                }
                .padding(.vertical)
                .padding(.horizontal, horizontalSizeClass == .regular ? 32 : 16)
            }
        }
        .refreshable {
            await refreshVideos()
        }
    }

    @MainActor
    private func refreshVideos() async {
        Haptics.light()
        // Small delay for haptic feedback
        try? await Task.sleep(for: .milliseconds(300))
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
