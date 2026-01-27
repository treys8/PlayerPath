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

struct VideoClipsView: View {
    let athlete: Athlete
    @Environment(\.modelContext) private var modelContext
    @State private var uploadManager = UploadQueueManager.shared
    @State private var showingRecorder = false
    @State private var showingUploadPicker = false
    @State private var showingAdvancedSearch = false
    @State private var selectedVideo: VideoClip?
    @State private var searchText = ""
    @State private var liveGameContext: Game?
    @State private var refreshTrigger = UUID()
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

    // Get all unique seasons from videos
    private var availableSeasons: [Season] {
        let seasons = (athlete.videoClips ?? []).compactMap { $0.season }
        let uniqueSeasons = Array(Set(seasons))
        return uniqueSeasons.sorted { ($0.startDate ?? Date.distantPast) > ($1.startDate ?? Date.distantPast) }
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

    private var filteredVideos: [VideoClip] {
        // Force refresh by accessing refreshTrigger
        _ = refreshTrigger

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

        // Filter by upload status
        if selectedUploadFilter != .all {
            videos = videos.filter { video in
                switch selectedUploadFilter {
                case .all:
                    return true
                case .uploaded:
                    return video.isUploaded
                case .notUploaded:
                    return !video.isUploaded &&
                           !uploadManager.activeUploads.keys.contains(video.id) &&
                           !uploadManager.pendingUploads.contains(where: { $0.clipId == video.id }) &&
                           !uploadManager.failedUploads.contains(where: { $0.clipId == video.id })
                case .uploading:
                    return uploadManager.activeUploads.keys.contains(video.id) ||
                           uploadManager.pendingUploads.contains(where: { $0.clipId == video.id })
                case .failed:
                    return uploadManager.failedUploads.contains(where: { $0.clipId == video.id })
                }
            }
        }

        // Filter by search text
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            videos = videos.filter { video in
                video.fileName.lowercased().contains(query) ||
                (video.playResult?.type.displayName.lowercased().contains(query) ?? false)
            }
        }

        // Sort by creation date
        return videos.sorted { (lhs: VideoClip, rhs: VideoClip) in
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
            } else if let season = availableSeasons.first(where: { $0.id.uuidString == seasonID }) {
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
    }
    
    var body: some View {
        Group {
            if filteredVideos.isEmpty {
                if hasActiveFilters && hasAnyVideos {
                    // Filtered empty state
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
        .safeAreaInset(edge: .top, spacing: 0) {
            UploadStatusBanner()
        }
        .navigationTitle("Videos")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search videos")
        .toolbar {
            if isSelectionMode {
                // Selection mode toolbar
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
                        Button {
                            bulkUploadSelected()
                        } label: {
                            Label("Upload Selected", systemImage: "icloud.and.arrow.up")
                        }
                        .disabled(selectedVideos.isEmpty)

                        Button {
                            bulkMarkAsHighlight()
                        } label: {
                            Label("Mark as Highlights", systemImage: "star.fill")
                        }
                        .disabled(selectedVideos.isEmpty)

                        Divider()

                        Button(role: .destructive) {
                            showingBulkDeleteConfirmation = true
                        } label: {
                            Label("Delete Selected", systemImage: "trash")
                        }
                        .disabled(selectedVideos.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            } else {
                // Normal mode toolbar
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Haptics.light()
                        showingRecorder = true
                    } label: {
                        Image(systemName: "video.badge.plus")
                    }
                    .accessibilityLabel("Record video")
                }

                // Season filter menu
                if !(athlete.videoClips?.isEmpty ?? true) {
                    ToolbarItem(placement: .topBarLeading) {
                        SeasonFilterMenu(
                            selectedSeasonID: $selectedSeasonFilter,
                            availableSeasons: availableSeasons,
                            showNoSeasonOption: (athlete.videoClips ?? []).contains(where: { $0.season == nil })
                        )
                    }
                }

                // Secondary actions menu
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if !(athlete.videoClips?.isEmpty ?? true) {
                            Button {
                                Haptics.light()
                                showingAdvancedSearch = true
                            } label: {
                                Label("Advanced Search", systemImage: "magnifyingglass.circle")
                            }

                            Divider()
                        }

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
        .sheet(isPresented: $showingRecorder) {
            VideoRecorderView_Refactored(athlete: athlete, game: liveGameContext)
        }
        .sheet(isPresented: $showingUploadPicker) {
            VideoPicker(athlete: athlete, onError: { error in
                errorMessage = error
                showingError = true
            }, onImportStart: {
                isImporting = true
            }, onImportComplete: {
                isImporting = false
                refreshTrigger = UUID()
            })
        }
        .sheet(item: $selectedVideo) { video in
            VideoDetailView(video: video)
        }
        .sheet(isPresented: $showingStatistics) {
            UploadStatisticsView()
        }
        .sheet(isPresented: $showingAdvancedSearch) {
            AdvancedSearchView(athlete: athlete)
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
        }
        .onDisappear {
            // Reset when leaving Videos tab
            NotificationCenter.default.post(name: .videosManageOwnControls, object: false)
            liveGameContext = nil
        }
        .onChange(of: athlete.videoClips?.count) { _, _ in
            refreshTrigger = UUID()
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
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
                    .cornerRadius(16)
                    .shadow(radius: 20)
                }
            }
        }
    }

    private func performDelete(_ video: VideoClip) {
        Haptics.medium()

        // Use VideoClip's delete method for proper cleanup
        video.delete(in: modelContext)

        do {
            try modelContext.save()

            // Track video deletion analytics
            AnalyticsService.shared.trackVideoDeleted(videoID: video.id.uuidString)
        } catch {
            errorMessage = "Failed to delete video: \(error.localizedDescription)"
            showingError = true
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
        Haptics.medium()

        let videosToDelete = (athlete.videoClips ?? []).filter { selectedVideos.contains($0.id) }

        for video in videosToDelete {
            video.delete(in: modelContext)
        }

        do {
            try modelContext.save()

            // Track analytics
            for video in videosToDelete {
                AnalyticsService.shared.trackVideoDeleted(videoID: video.id.uuidString)
            }

            Haptics.success()
        } catch {
            errorMessage = "Failed to delete videos: \(error.localizedDescription)"
            showingError = true
        }

        // Exit selection mode
        isSelectionMode = false
        selectedVideos.removeAll()
    }

    private func bulkUploadSelected() {
        let videosToUpload = (athlete.videoClips ?? []).filter { selectedVideos.contains($0.id) }

        for video in videosToUpload {
            if !video.isUploaded {
                UploadQueueManager.shared.enqueue(video, athlete: athlete, priority: .high)
            }
        }

        Haptics.success()

        // Exit selection mode
        isSelectionMode = false
        selectedVideos.removeAll()
    }

    private func bulkMarkAsHighlight() {
        let videosToMark = (athlete.videoClips ?? []).filter { selectedVideos.contains($0.id) }

        for video in videosToMark {
            video.isHighlight = true
        }

        do {
            try modelContext.save()
            Haptics.success()
        } catch {
            errorMessage = "Failed to mark videos as highlights: \(error.localizedDescription)"
            showingError = true
        }

        // Exit selection mode
        isSelectionMode = false
        selectedVideos.removeAll()
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
            VStack(spacing: 0) {
                // Upload status filter picker
                if hasAnyVideos {
                    uploadStatusFilterPicker
                }

                LazyVGrid(
                    columns: [
                        GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 16, alignment: .top)
                    ],
                    spacing: 16
                ) {
                    ForEach(Array(filteredVideos.enumerated()), id: \.element.id) { index, video in
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
                            prefetchNearbyThumbnails(for: index, in: filteredVideos)
                        }
                    }
                }
                .padding()
            }
        }
        .refreshable {
            await refreshVideos()
        }
    }

    @MainActor
    private func refreshVideos() async {
        Haptics.light()
        refreshTrigger = UUID()
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
        let targetSize = CGSize(width: 400, height: 300) // 2x display size for retina

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
    @State private var uploadManager = UploadQueueManager.shared

    var body: some View {
        Button(action: onPlay) {
            VStack(spacing: 0) {
                // Larger thumbnail - fills most of the card
                ZStack(alignment: .topTrailing) {
                    VideoThumbnailView(
                        clip: video,
                        size: CGSize(width: 200, height: 150), // Taller for more video visibility
                        cornerRadius: 12,
                        showPlayButton: false, // Remove play button - users know it's a video
                        showPlayResult: false, // Move to info section below
                        showHighlight: true, // Keep highlight star
                        showSeason: false // Remove duplicate season badge
                    )
                    .overlay(
                        // Selection mode overlay
                        Group {
                            if isSelectionMode {
                                ZStack {
                                    Color.black.opacity(isSelected ? 0.3 : 0.1)

                                    VStack {
                                        HStack {
                                            Spacer()
                                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                                .font(.system(size: 28))
                                                .foregroundColor(isSelected ? .blue : .white)
                                                .padding(8)
                                        }
                                        Spacer()
                                    }
                                }
                            }
                        }
                    )

                    // Backup status badge (top-right corner) - only show when not in selection mode
                    if !isSelectionMode {
                        backupStatusBadge
                            .padding(8)
                    }
                }

                // Compact single-line info section
                HStack(spacing: 6) {
                    // Play result badge
                    if let result = video.playResult {
                        HStack(spacing: 3) {
                            playResultIcon(for: result.type)
                                .font(.system(size: 10))
                            Text(playResultAbbreviation(for: result.type))
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(playResultColor(for: result.type))
                        .cornerRadius(5)
                    }

                    // Date
                    if let created = video.createdAt {
                        Text(created, format: .dateTime.month().day())
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Season badge
                    if let season = video.season {
                        Text(season.displayName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(season.isActive ? Color.blue : Color.gray)
                            .cornerRadius(4)
                    }

                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 2)
        }
        .buttonStyle(.plain)
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
                do {
                    try modelContext.save()
                } catch {
                    errorMessage = "Failed to toggle highlight: \(error.localizedDescription)"
                    showingError = true
                }
            } label: {
                Label(
                    video.isHighlight ? "Remove from Highlights" : "Add to Highlights",
                    systemImage: video.isHighlight ? "star.slash" : "star.fill"
                )
            }

            if FileManager.default.fileExists(atPath: video.filePath) {
                ShareLink(item: URL(fileURLWithPath: video.filePath)) {
                    Label("Share", systemImage: "square.and.arrow.up")
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
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
    }

    // MARK: - Backup Status Badge

    @ViewBuilder
    private var backupStatusBadge: some View {
        if video.isUploaded {
            // Uploaded to cloud - green checkmark
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

    // MARK: - Play Result Helpers

    private func playResultIcon(for type: PlayResultType) -> Image {
        switch type {
        case .single: return Image(systemName: "1.circle.fill")
        case .double: return Image(systemName: "2.circle.fill")
        case .triple: return Image(systemName: "3.circle.fill")
        case .homeRun: return Image(systemName: "4.circle.fill")
        case .walk: return Image(systemName: "figure.walk")
        case .strikeout: return Image(systemName: "k.circle.fill")
        case .groundOut: return Image(systemName: "arrow.down.circle.fill")
        case .flyOut: return Image(systemName: "arrow.up.circle.fill")
        }
    }

    private func playResultAbbreviation(for type: PlayResultType) -> String {
        switch type {
        case .single: return "1B"
        case .double: return "2B"
        case .triple: return "3B"
        case .homeRun: return "HR"
        case .walk: return "BB"
        case .strikeout: return "K"
        case .groundOut: return "GO"
        case .flyOut: return "FO"
        }
    }

    private func playResultColor(for type: PlayResultType) -> Color {
        switch type {
        case .single: return .green
        case .double: return .blue
        case .triple: return .orange
        case .homeRun: return .red
        case .walk: return .cyan
        case .strikeout: return .red.opacity(0.8)
        case .groundOut, .flyOut: return .gray
        }
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

// MARK: - Video Detail View

struct VideoDetailView: View {
    let video: VideoClip
    @Environment(\.dismiss) private var dismiss
    @State private var showMetadata = false

    var body: some View {
        ZStack {
            if FileManager.default.fileExists(atPath: video.filePath) {
                // Video Player - FULL SCREEN
                VideoPlayer(player: AVPlayer(url: URL(fileURLWithPath: video.filePath)))
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation {
                            showMetadata.toggle()
                        }
                    }

                // Overlay metadata when tapped
                if showMetadata {
                    VStack {
                        Spacer()

                        // Compact metadata bar at bottom
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                if let result = video.playResult {
                                    Text(result.type.displayName)
                                        .font(.headline)
                                        .foregroundColor(.white)
                                } else {
                                    Text(video.fileName)
                                        .font(.headline)
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                }

                                HStack(spacing: 8) {
                                    if let game = video.game {
                                        Text("vs \(game.opponent)")
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.9))
                                    }

                                    if let season = video.season {
                                        Text(season.displayName)
                                            .font(.caption2)
                                            .fontWeight(.medium)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.blue.opacity(0.8))
                                            .cornerRadius(4)
                                    }

                                    if video.isHighlight {
                                        Image(systemName: "star.fill")
                                            .foregroundColor(.yellow)
                                            .font(.caption)
                                    }
                                }
                            }

                            Spacer()
                        }
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [.clear, .black.opacity(0.7)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Done button (always visible)
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                                .padding()
                                .background(Circle().fill(Color.black.opacity(0.5)))
                        }
                        .padding()
                    }
                    Spacer()
                }
            } else {
                // Error state
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 60))
                        .foregroundColor(.orange)
                    Text("Video File Not Found")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("The video file may have been deleted or moved.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Close") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
            }
        }
    }
}

#Preview {
    NavigationStack {
        VideoClipsView(athlete: Athlete(name: "Test Player"))
    }
    .modelContainer(for: [Athlete.self, VideoClip.self])
}
