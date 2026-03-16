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
    private let uploadManager = UploadQueueManager.shared
    @State private var showingRecorder = false
    @State private var showingUploadPicker = false
    @State private var showingAdvancedSearch = false
    @State private var selectedVideo: VideoClip?
    @State private var searchText = ""
    @State private var liveGameContext: Game?
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var isImporting = false
    @State private var videoToDelete: VideoClip?
    @State private var showingDeleteConfirmation = false
    @State private var selectedSeasonFilter: String? = nil // nil = All Seasons
    @State private var selectedUploadFilter: UploadStatusFilter = .all

    // Batch selection mode
    @State private var isSelectionMode = false
    @State private var selectedVideos: Set<UUID> = []
    @State private var showingBulkDeleteConfirmation = false
    @State private var showingStatistics = false
    @State private var bulkOperationMessage: String?

    // Delete guard
    @State private var isDeleting = false

    // Post-import tagging
    @State private var clipToTag: VideoClip?
    @State private var isAwaitingImportedClip = false

    // Cached computed results — updated explicitly via updateFilteredVideos() / updateAvailableSeasons()
    @State private var cachedFilteredVideos: [VideoClip] = []
    @State private var cachedAvailableSeasons: [Season] = []

    // Get all unique seasons from videos
    private func updateAvailableSeasons() {
        let seasons = (athlete.videoClips ?? []).compactMap { $0.season }
        let uniqueSeasons = Array(Set(seasons))
        cachedAvailableSeasons = uniqueSeasons.sorted { ($0.startDate ?? Date.distantPast) > ($1.startDate ?? Date.distantPast) }
    }

    // Check if filters are active
    private var hasActiveFilters: Bool {
        selectedSeasonFilter != nil ||
        selectedUploadFilter != .all ||
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // Check if we have any videos at all (before filtering)
    private var hasAnyVideos: Bool {
        !(athlete.videoClips?.isEmpty ?? true)
    }

    private static let searchDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private static let searchShortFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d/yy"
        return f
    }()

    private func updateFilteredVideos() {
        var videos = athlete.videoClips ?? []

        // Filter by season
        if let seasonFilter = selectedSeasonFilter {
            videos = videos.filter { video in
                if seasonFilter == "no_season" {
                    return video.season == nil
                } else {
                    return video.season?.id.uuidString == seasonFilter
                }
            }
        }

        // Filter by upload status — build ID sets once for O(1) lookups
        if selectedUploadFilter != .all {
            let pendingIDs = Set(uploadManager.pendingUploads.map(\.clipId))
            let failedIDs = Set(uploadManager.failedUploads.map(\.clipId))
            let activeIDs = Set(uploadManager.activeUploads.keys)

            videos = videos.filter { video in
                switch selectedUploadFilter {
                case .all:
                    return true
                case .uploaded:
                    return video.isUploaded
                case .notUploaded:
                    return !video.isUploaded &&
                           !activeIDs.contains(video.id) &&
                           !pendingIDs.contains(video.id) &&
                           !failedIDs.contains(video.id)
                case .uploading:
                    return activeIDs.contains(video.id) || pendingIDs.contains(video.id)
                case .failed:
                    return failedIDs.contains(video.id)
                }
            }
        }

        // Filter by search text
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            videos = videos.filter { video in
                video.fileName.lowercased().contains(query) ||
                (video.playResult?.type.displayName.lowercased().contains(query) ?? false) ||
                (video.game?.opponent.lowercased().contains(query) ?? false) ||
                (video.note?.lowercased().contains(query) ?? false) ||
                (video.createdAt.map { Self.searchDateFormatter.string(from: $0).lowercased() }?.contains(query) ?? false) ||
                (video.createdAt.map { Self.searchShortFormatter.string(from: $0).lowercased() }?.contains(query) ?? false)
            }
        }

        // Sort by creation date
        cachedFilteredVideos = videos.sorted { (lhs: VideoClip, rhs: VideoClip) in
            switch (lhs.createdAt, rhs.createdAt) {
            case let (l?, r?):
                return l > r
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            case (nil, nil):
                return false
            }
        }
    }

    private var filterDescription: String {
        var parts: [String] = []

        if let seasonID = selectedSeasonFilter {
            if seasonID == "no_season" {
                parts.append("season: None")
            } else if let season = cachedAvailableSeasons.first(where: { $0.id.uuidString == seasonID }) {
                parts.append("season: \(season.displayName)")
            }
        }

        if selectedUploadFilter != .all {
            parts.append("upload: \(selectedUploadFilter.rawValue)")
        }

        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("search: \"\(searchText)\"")
        }

        return parts.isEmpty ? "your filters" : parts.joined(separator: ", ")
    }

    private func clearAllFilters() {
        Haptics.light()
        withAnimation {
            selectedSeasonFilter = nil
            selectedUploadFilter = .all
            searchText = ""
        }
        updateFilteredVideos()
        updateAvailableSeasons()
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
                        selectedSeasonID: $selectedSeasonFilter,
                        availableSeasons: cachedAvailableSeasons,
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
        if cachedFilteredVideos.isEmpty {
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
        .searchable(text: $searchText, prompt: "Search videos")
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
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("VideoRecorded"))) { notification in
            // Capture the most recently imported clip when it has no game context
            if isAwaitingImportedClip, let clip = notification.object as? VideoClip, clip.game == nil {
                // Delay slightly so the upload picker sheet can dismiss first
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
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
        .onAppear {
            // Tell MainTabView that Videos manages its own controls
            NotificationCenter.default.post(name: .videosManageOwnControls, object: true)
            updateAvailableSeasons()
            updateFilteredVideos()
        }
        .onDisappear {
            // Reset when leaving Videos tab
            NotificationCenter.default.post(name: .videosManageOwnControls, object: false)
            liveGameContext = nil
        }
        .onChange(of: searchText) { _, _ in
            updateFilteredVideos()
        }
        .onChange(of: selectedSeasonFilter) { _, _ in
            updateFilteredVideos()
        }
        .onChange(of: selectedUploadFilter) { _, _ in
            updateFilteredVideos()
        }
        .onChange(of: athlete.videoClips?.count) { _, _ in
            updateAvailableSeasons()
            updateFilteredVideos()
        }
        .alert("Something Went Wrong", isPresented: $showingError) {
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
                updateAvailableSeasons()
                updateFilteredVideos()
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

                updateAvailableSeasons()
                updateFilteredVideos()
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
            updateFilteredVideos()
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
    }

    private var uploadStatusFilterPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(UploadStatusFilter.allCases, id: \.self) { filter in
                    Button {
                        withAnimation {
                            selectedUploadFilter = filter
                        }
                        Haptics.light()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: filter.icon)
                                .font(.caption)

                            Text(filter.rawValue)
                                .font(.subheadline)
                                .fontWeight(selectedUploadFilter == filter ? .semibold : .regular)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            selectedUploadFilter == filter ?
                                filter.color.opacity(0.2) :
                                Color.gray.opacity(0.1)
                        )
                        .foregroundColor(
                            selectedUploadFilter == filter ?
                                filter.color :
                                .secondary
                        )
                        .cornerRadius(20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(
                                    selectedUploadFilter == filter ?
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
                    ForEach(cachedFilteredVideos) { video in
                        VideoClipCard(
                            video: video,
                            isSelectionMode: isSelectionMode,
                            isSelected: selectedVideos.contains(video.id),
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
                            if let index = cachedFilteredVideos.firstIndex(where: { $0.id == video.id }) {
                                prefetchNearbyThumbnails(for: index, in: cachedFilteredVideos)
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
        try? await Task.sleep(nanoseconds: 300_000_000)
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

struct VideoClipCard: View {
    let video: VideoClip
    var isSelectionMode: Bool = false
    var isSelected: Bool = false
    let onPlay: () -> Void
    let onDelete: () -> Void
    var onToggleSelection: (() -> Void)? = nil
    @Environment(\.modelContext) private var modelContext
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var showingSaveSuccess = false
    private let uploadManager = UploadQueueManager.shared
    @State private var isPressed = false
    @State private var isSavingToPhotos = false

    var body: some View {
        Button(action: {
            Haptics.light()
            onPlay()
        }) {
            VStack(spacing: 0) {
                // Thumbnail - 16:9 aspect ratio (no GeometryReader for better LazyVGrid perf)
                ZStack {
                    VideoThumbnailView(
                        clip: video,
                        size: CGSize(width: 200, height: 112),
                        cornerRadius: 0,
                        showPlayButton: !isSelectionMode,
                        showPlayResult: true,
                        showHighlight: true,
                        showSeason: false,
                        showContext: false,
                        fillsContainer: true
                    )

                    // Gradient overlay for better contrast
                    VStack {
                        Spacer()
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.4)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .frame(height: 40)
                    }

                    // Duration badge (bottom-left)
                    VStack {
                        Spacer()
                        HStack {
                            if let duration = video.duration, duration > 0 {
                                Text(formatDuration(duration))
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
                                    .padding(8)
                            }
                            Spacer()
                        }
                    }

                    // Selection overlay
                    selectionOverlay

                    // Backup status badge (top-left, moved from top-right to not conflict with play result)
                    if !isSelectionMode {
                        VStack {
                            HStack {
                                backupStatusBadge
                                    .padding(8)
                                Spacer()
                            }
                            Spacer()
                        }
                    }
                }
                .aspectRatio(16/9, contentMode: .fit)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 12))

                // Info section
                VStack(alignment: .leading, spacing: 6) {
                        // Headline: game context > practice > play result > fallback
                        if let game = video.game {
                            HStack(spacing: 6) {
                                Text("vs \(game.opponent)")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Spacer()
                                if let season = video.season {
                                    SeasonBadge(season: season, fontSize: 8)
                                }
                            }
                        } else if video.practice != nil {
                            HStack(spacing: 6) {
                                if let practiceDate = video.practice?.date {
                                    Text("Practice · \(practiceDate, format: .dateTime.month(.abbreviated).day())")
                                        .font(.subheadline)
                                        .fontWeight(.bold)
                                        .foregroundColor(.green)
                                } else {
                                    Text("Practice")
                                        .font(.subheadline)
                                        .fontWeight(.bold)
                                        .foregroundColor(.green)
                                }
                                Spacer()
                                if let season = video.season {
                                    SeasonBadge(season: season, fontSize: 8)
                                }
                            }
                        } else if let result = video.playResult {
                            Text(result.type.displayName)
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        } else {
                            Text("Video Clip")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                        }

                        // Secondary: play result + pitch speed (when game/practice is headline)
                        if video.game != nil || video.practice != nil {
                            if let result = video.playResult {
                                HStack(spacing: 6) {
                                    Text(result.type.displayName)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    if let speed = video.pitchSpeed, speed > 0 {
                                        Text("·").foregroundColor(.secondary)
                                        Text("\(Int(speed)) MPH")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.orange)
                                    }
                                }
                            } else if let speed = video.pitchSpeed, speed > 0 {
                                Text("\(Int(speed)) MPH")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.orange)
                            }
                        }

                        // Date
                        if let created = video.createdAt {
                            Text(created, style: .date)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6))
                }
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: .cornerLarge, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
            .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(PressableCardButtonStyle())
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .contextMenu {
            Button {
                Haptics.light()
                onPlay()
            } label: {
                Label("Play", systemImage: "play.fill")
            }

            Button {
                Haptics.light()
                video.isHighlight.toggle()
                video.needsSync = true
                Task {
                    do {
                        try modelContext.save()
                    } catch {
                        errorMessage = "Could not update highlight status. Please try again."
                        showingError = true
                    }
                }
            } label: {
                Label(
                    video.isHighlight ? "Remove from Highlights" : "Add to Highlights",
                    systemImage: video.isHighlight ? "star.slash" : "star.fill"
                )
            }

            if FileManager.default.fileExists(atPath: video.resolvedFilePath) {
                ShareLink(item: video.resolvedFileURL) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }

                Button {
                    saveToPhotos()
                } label: {
                    Label("Save to Photos", systemImage: "square.and.arrow.down")
                }
            }

            Divider()

            // Upload controls
            if video.isUploaded {
                Label("Uploaded to Cloud", systemImage: "checkmark.icloud")
                    .foregroundColor(.green)
            } else if let athlete = video.athlete {
                Button {
                    Haptics.light()
                    UploadQueueManager.shared.enqueue(video, athlete: athlete, priority: .high)
                } label: {
                    if UploadQueueManager.shared.activeUploads[video.id] != nil {
                        Label("Uploading...", systemImage: "icloud.and.arrow.up")
                    } else if UploadQueueManager.shared.pendingUploads.contains(where: { $0.clipId == video.id }) {
                        Label("Queued for Upload", systemImage: "clock.arrow.circlepath")
                    } else {
                        Label("Upload to Cloud", systemImage: "icloud.and.arrow.up")
                    }
                }
            }

            Divider()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .alert("Something Went Wrong", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "An unexpected error occurred. Please try again.")
        }
        .alert("Saved to Photos", isPresented: $showingSaveSuccess) {
            Button("OK") { }
        } message: {
            Text("Video has been saved to your Photos library.")
        }
        .overlay {
            if isSavingToPhotos {
                ZStack {
                    Color.black.opacity(0.4)
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Saving to Photos...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: .cornerLarge))
                }
                .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Save to Photos

    private func saveToPhotos() {
        guard FileManager.default.fileExists(atPath: video.resolvedFilePath) else {
            errorMessage = "Video file not found. It may have been deleted or moved."
            showingError = true
            return
        }

        isSavingToPhotos = true
        let videoURL = video.resolvedFileURL

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    self.isSavingToPhotos = false
                    self.errorMessage = "Photo library access is required to save videos. Please enable it in Settings > PlayerPath > Photos."
                    self.showingError = true
                }
                return
            }

            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    self.isSavingToPhotos = false
                    if success {
                        Haptics.success()
                        self.showingSaveSuccess = true
                    } else {
                        self.errorMessage = "Could not save video to Photos. \(error?.localizedDescription ?? "Please try again.")"
                        self.showingError = true
                    }
                }
            }
        }
    }

    // MARK: - Selection Overlay

    @ViewBuilder
    private var selectionOverlay: some View {
        if isSelectionMode {
            ZStack {
                Color.black.opacity(isSelected ? 0.3 : 0.1)

                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 28))
                            .foregroundColor(isSelected ? .blue : .white)
                            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                            .padding(10)
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: - Backup Status Badge

    @ViewBuilder
    private var backupStatusBadge: some View {
        if video.isUploaded && video.firestoreId != nil {
            // Fully synced — Storage uploaded + Firestore metadata written (cross-device ready)
            HStack(spacing: 3) {
                Image(systemName: "checkmark.icloud.fill")
                    .font(.system(size: 12))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(.green)
            .cornerRadius(6)
            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
        } else if video.isUploaded && video.firestoreId == nil {
            // Storage upload done but Firestore metadata not yet written — not cross-device accessible yet
            HStack(spacing: 3) {
                Image(systemName: "exclamationmark.icloud.fill")
                    .font(.system(size: 12))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(.yellow)
            .cornerRadius(6)
            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
        } else if let progress = uploadManager.activeUploads[video.id] {
            // Currently uploading - blue with percentage
            HStack(spacing: 3) {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(.white)
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(.blue)
            .cornerRadius(6)
            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
        } else if uploadManager.pendingUploads.contains(where: { $0.clipId == video.id }) {
            // Queued for upload - orange clock
            HStack(spacing: 3) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 12))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(.orange)
            .cornerRadius(6)
            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
        } else {
            // Local only - subtle gray device icon
            HStack(spacing: 3) {
                Image(systemName: "iphone")
                    .font(.system(size: 11))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color.gray.opacity(0.7))
            .cornerRadius(6)
            .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Pressable Card Button Style

struct PressableCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Upload Status Filter

enum UploadStatusFilter: String, CaseIterable {
    case all = "All Videos"
    case uploaded = "Uploaded"
    case notUploaded = "Not Uploaded"
    case uploading = "Uploading"
    case failed = "Failed"

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .uploaded: return "checkmark.icloud.fill"
        case .notUploaded: return "iphone"
        case .uploading: return "arrow.up.circle"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .all: return .primary
        case .uploaded: return .green
        case .notUploaded: return .gray
        case .uploading: return .blue
        case .failed: return .red
        }
    }
}


#Preview {
    NavigationStack {
        VideoClipsView(athlete: Athlete(name: "Test Player"))
    }
    .modelContainer(for: [Athlete.self, VideoClip.self])
}
