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
    @State private var showingRecorder = false
    @State private var showingUploadPicker = false
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

    // Get all unique seasons from videos
    private var availableSeasons: [Season] {
        let seasons = (athlete.videoClips ?? []).compactMap { $0.season }
        let uniqueSeasons = Array(Set(seasons))
        return uniqueSeasons.sorted { ($0.startDate ?? Date.distantPast) > ($1.startDate ?? Date.distantPast) }
    }

    // Check if filters are active
    private var hasActiveFilters: Bool {
        selectedSeasonFilter != nil ||
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

        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("search: \"\(searchText)\"")
        }

        return parts.isEmpty ? "your filters" : parts.joined(separator: ", ")
    }

    private func clearAllFilters() {
        Haptics.light()
        withAnimation {
            selectedSeasonFilter = nil
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
        .navigationTitle("Videos")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search videos")
        .toolbar {
            // Primary action: Record Video (most common action)
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

            // Secondary actions menu (upload)
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        Haptics.light()
                        showingUploadPicker = true
                    } label: {
                        Label("Upload from Library", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More options")
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

        // Delete file
        if FileManager.default.fileExists(atPath: video.filePath) {
            try? FileManager.default.removeItem(atPath: video.filePath)
        }

        // Delete thumbnail
        if let thumbPath = video.thumbnailPath {
            try? FileManager.default.removeItem(atPath: thumbPath)
        }

        // Delete from database
        modelContext.delete(video)

        do {
            try modelContext.save()
        } catch {
            errorMessage = "Failed to delete video: \(error.localizedDescription)"
            showingError = true
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
    
    private var videoListView: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 12, alignment: .top)
                ],
                spacing: 12
            ) {
                ForEach(filteredVideos) { video in
                    VideoClipCard(video: video, onPlay: {
                        selectedVideo = video
                        Haptics.light()
                    }, onDelete: {
                        videoToDelete = video
                        showingDeleteConfirmation = true
                    })
                }
            }
            .padding()
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
}

struct VideoClipCard: View {
    let video: VideoClip
    let onPlay: () -> Void
    let onDelete: () -> Void
    @Environment(\.modelContext) private var modelContext
    @State private var errorMessage: String?
    @State private var showingError = false

    var body: some View {
        Button(action: onPlay) {
            VStack(spacing: 0) {
                // Use the dedicated VideoThumbnailView component
                VideoThumbnailView(
                    clip: video,
                    size: CGSize(width: 200, height: 112), // 16:9 aspect
                    cornerRadius: 8,
                    showPlayButton: true,
                    showPlayResult: true,
                    showHighlight: true
                )

                // Info section - more compact
                VStack(alignment: .leading, spacing: 6) {
                    if let result = video.playResult {
                        Text(result.type.displayName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                    } else {
                        Text(video.fileName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                    }

                    HStack(spacing: 8) {
                        if let created = video.createdAt {
                            Text(created, format: .dateTime.month().day())
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        if let season = video.season {
                            SeasonBadge(season: season, fontSize: 8)
                        }
                    }

                    if let game = video.game {
                        HStack(spacing: 3) {
                            Image(systemName: "baseball.fill")
                                .font(.system(size: 8))
                            Text(game.opponent)
                                .lineLimit(1)
                        }
                        .font(.caption2)
                        .foregroundColor(.blue)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(.secondarySystemBackground))
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
