//
//  HighlightsView.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import SwiftUI
import SwiftData
import Foundation

struct HighlightsView: View {
    let athlete: Athlete?
    @Environment(\.modelContext) private var modelContext
    @State private var selectedClip: VideoClip?
    @State private var showingVideoPlayer = false
    @State private var showingDeleteAlert = false
    @State private var clipToDelete: VideoClip?
    @State private var editMode: EditMode = .inactive

    @State private var searchText: String = ""
    enum Filter: String, CaseIterable, Identifiable { case all, game, practice; var id: String { rawValue } }
    @State private var filter: Filter = .all
    enum SortOrder: String, CaseIterable, Identifiable { case newest, oldest; var id: String { rawValue } }
    @State private var sortOrder: SortOrder = .newest
    @State private var selection = Set<VideoClip.ID>()
    @AppStorage("hasCompletedHighlightMigration") private var hasCompletedMigration = false
    @State private var expandedGroups = Set<UUID>()
    @State private var selectedSeasonFilter: String? = nil // nil = All Seasons
    
    // Get all unique seasons from highlights
    private var availableSeasons: [Season] {
        guard let athlete = athlete, let videoClips = athlete.videoClips else { return [] }
        let highlightClips = videoClips.filter { $0.isHighlight }
        let seasons = highlightClips.compactMap { $0.season }
        let uniqueSeasons = Array(Set(seasons))
        return uniqueSeasons.sorted { ($0.startDate ?? Date.distantPast) > ($1.startDate ?? Date.distantPast) }
    }

    var highlights: [VideoClip] {
        guard let athlete = athlete, let videoClips = athlete.videoClips else { return [] }
        var filtered = videoClips.filter { $0.isHighlight }

        // Filter by season
        if let seasonFilter = selectedSeasonFilter {
            filtered = filtered.filter { clip in
                if seasonFilter == "no_season" {
                    return clip.season == nil
                } else {
                    return clip.season?.id.uuidString == seasonFilter
                }
            }
        }

        // Filter by type
        filtered = filtered.filter { clip in
            switch filter {
            case .all: return true
            case .game: return clip.game != nil
            case .practice: return clip.game == nil
            }
        }

        // Filter by search text
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let q = searchText.lowercased()
            filtered = filtered.filter { clip in
                let opponent = clip.game?.opponent.lowercased() ?? ""
                let result = clip.playResult?.type.displayName.lowercased() ?? ""
                let fileName = clip.fileName.lowercased()
                return opponent.contains(q) || result.contains(q) || fileName.contains(q)
            }
        }

        // Sort
        return filtered.sorted { lhs, rhs in
            let l = lhs.createdAt ?? .distantPast
            let r = rhs.createdAt ?? .distantPast
            return sortOrder == .newest ? (l > r) : (l < r)
        }
    }

    // Group highlights by game for better organization
    var groupedHighlights: [GameHighlightGroup] {
        let clips = highlights

        // Separate game clips and practice clips
        var gameClips: [UUID: [VideoClip]] = [:]
        var practiceClips: [VideoClip] = []

        for clip in clips {
            if let game = clip.game {
                let gameID = game.id
                gameClips[gameID, default: []].append(clip)
            } else {
                practiceClips.append(clip)
            }
        }

        // Create groups for games (sorted by clips within each game)
        var groups: [GameHighlightGroup] = gameClips.map { gameID, clips in
            let sortedClips = clips.sorted { lhs, rhs in
                let l = lhs.createdAt ?? .distantPast
                let r = rhs.createdAt ?? .distantPast
                return l < r  // Always chronological within game
            }

            return GameHighlightGroup(
                id: gameID,
                game: clips.first?.game,
                clips: sortedClips,
                isExpanded: expandedGroups.contains(gameID)
            )
        }

        // Sort groups by game date
        groups.sort { lhs, rhs in
            let lDate = lhs.game?.date ?? .distantPast
            let rDate = rhs.game?.date ?? .distantPast
            return sortOrder == .newest ? (lDate > rDate) : (lDate < rDate)
        }

        // Add practice clips as individual groups
        for clip in practiceClips {
            let practiceID = clip.id
            groups.append(GameHighlightGroup(
                id: practiceID,
                game: nil,
                clips: [clip],
                isExpanded: true  // Practice clips always expanded (single clip)
            ))
        }

        // Auto-expand single-clip game groups
        groups = groups.map { group in
            var updatedGroup = group
            if group.clips.count == 1 {
                updatedGroup.isExpanded = true
            }
            return updatedGroup
        }

        return groups
    }
    
    var body: some View {
        contentView
            .navigationTitle("\(athlete?.name ?? "Highlights") (\(highlights.count))")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
            .toolbar {
                toolbarContent
            }
            .environment(\.editMode, $editMode)
        .sheet(isPresented: $showingVideoPlayer) {
            if let clip: VideoClip = selectedClip {
                VideoPlayerView(clip: clip)
            }
        }
        .alert("Delete Highlight", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {
                clipToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let clip = clipToDelete {
                    deleteHighlight(clip)
                }
                clipToDelete = nil
            }
        } message: {
            Text("Are you sure you want to delete this highlight?")
        }
        .onAppear {
            migrateHitVideosToHighlights()
        }
    }

    private func migrateHitVideosToHighlights() {
        // Only run migration once per app install
        guard !hasCompletedMigration, let athlete = athlete else { return }

        // Find all videos with hit play results that aren't marked as highlights
        guard let allVideos = athlete.videoClips else { return }

        var migrationCount = 0
        for video in allVideos {
            // Check if video has a hit play result but isn't marked as highlight
            if let playResult = video.playResult,
               playResult.type.isHighlight,
               !video.isHighlight {
                video.isHighlight = true
                migrationCount += 1
            }
        }

        // Save if we migrated any videos
        if migrationCount > 0 {
            do {
                try modelContext.save()
                print("HighlightsView: Migrated \(migrationCount) hit videos to highlights")
                hasCompletedMigration = true
            } catch {
                print("HighlightsView: Failed to migrate highlights: \(error)")
            }
        } else {
            // No videos to migrate, mark as complete anyway
            hasCompletedMigration = true
        }
    }

    // Check if filters are active
    private var hasActiveFilters: Bool {
        selectedSeasonFilter != nil ||
        filter != .all ||
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // Check if we have any highlights at all (before filtering)
    private var hasAnyHighlights: Bool {
        guard let athlete = athlete, let videoClips = athlete.videoClips else { return false }
        return videoClips.contains(where: { $0.isHighlight })
    }

    @ViewBuilder
    private var contentView: some View {
        if highlights.isEmpty {
            if hasActiveFilters && hasAnyHighlights {
                // Filtered empty state - user has highlights but filters exclude them
                FilteredEmptyStateView(
                    filterDescription: filterDescription,
                    onClearFilters: clearAllFilters
                )
            } else {
                // True empty state - no highlights at all
                EmptyHighlightsView()
            }
        } else {
            highlightGridView
                .safeAreaInset(edge: .top, spacing: 0) {
                    // Type filter segmented control pinned at top
                    Picker("Type", selection: $filter) {
                        Text("All").tag(Filter.all)
                        Text("Games").tag(Filter.game)
                        Text("Practice").tag(Filter.practice)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.regularMaterial)
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

        if filter != .all {
            parts.append("type: \(filter == .game ? "Games" : "Practice")")
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
            filter = .all
            searchText = ""
        }
    }

    private var highlightGridView: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                ForEach(groupedHighlights) { group in
                    GameHighlightSection(
                        group: group,
                        editMode: editMode,
                        selection: $selection,
                        onToggleExpand: {
                            toggleGroupExpansion(group.id)
                        },
                        onClipTap: { clip in
                            if editMode == .inactive {
                                selectedClip = clip
                                showingVideoPlayer = true
                            } else {
                                toggleSelection(clip)
                            }
                        },
                        onDeleteClip: { clip in
                            clipToDelete = clip
                            showingDeleteAlert = true
                        }
                    )
                }
            }
            .padding()
        }
        .refreshable {
            await refreshHighlights()
        }
    }

    @MainActor
    private func refreshHighlights() async {
        Haptics.light()
        // Trigger re-migration check
        migrateHitVideosToHighlights()
    }

    private func toggleGroupExpansion(_ groupID: UUID) {
        if expandedGroups.contains(groupID) {
            expandedGroups.remove(groupID)
        } else {
            expandedGroups.insert(groupID)
        }
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Season filter (only show if we have highlights)
        if !groupedHighlights.isEmpty {
            ToolbarItem(placement: .topBarLeading) {
                SeasonFilterMenu(
                    selectedSeasonID: $selectedSeasonFilter,
                    availableSeasons: availableSeasons,
                    showNoSeasonOption: (athlete?.videoClips ?? []).filter { $0.isHighlight }.contains(where: { $0.season == nil })
                )
            }
        }

        // Filter/Sort menu
        if !groupedHighlights.isEmpty {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort", selection: $sortOrder) {
                        Label("Newest", systemImage: "arrow.down").tag(SortOrder.newest)
                        Label("Oldest", systemImage: "arrow.up").tag(SortOrder.oldest)
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down.circle")
                }
                .accessibilityLabel("Sort highlights")
            }
        }

        // More options menu
        ToolbarItem(placement: .primaryAction) {
            Menu {
                NavigationLink(destination: SimpleCloudStorageView()) {
                    Label("Cloud Storage", systemImage: "icloud")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }

        // Edit button
        if !highlights.isEmpty {
            ToolbarItem(placement: .secondaryAction) {
                editButton
            }
        }

        // Bottom bar in edit mode
        ToolbarItemGroup(placement: .bottomBar) {
            if editMode == .active {
                bottomBarButtons
            }
        }
    }
    
    private var editButton: some View {
        Button(editMode == .inactive ? "Select" : (selection.isEmpty ? "Done" : "Done (\(selection.count))")) {
            withAnimation { toggleEditMode() }
        }
    }
    
    @ViewBuilder
    private var bottomBarButtons: some View {
        Menu {
            Button(role: .destructive) {
                batchDeleteSelected()
            } label: {
                Label("Delete", systemImage: "trash")
            }

            Button {
                batchRemoveFromHighlights()
            } label: {
                Label("Remove from Highlights", systemImage: "star.slash")
            }

            Button {
                batchUploadSelected()
            } label: {
                Label("Upload to Cloud", systemImage: "icloud.and.arrow.up")
            }

            Button {
                batchShareSelected()
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        } label: {
            Label("Actions", systemImage: "ellipsis.circle")
        }
        .disabled(selection.isEmpty)

        Spacer()

        Button {
            selectAll()
        } label: {
            Label("Select All", systemImage: "checkmark.circle")
        }
        .disabled(highlights.isEmpty)

        Spacer()

        Button {
            selection.removeAll()
        } label: {
            Label("Deselect All", systemImage: "xmark.circle")
        }
        .disabled(selection.isEmpty)
    }
    
    private func deleteHighlight(_ clip: VideoClip) {
        // Delete the video file
        if FileManager.default.fileExists(atPath: clip.filePath) {
            try? FileManager.default.removeItem(atPath: clip.filePath)
            print("Deleted video file: \(clip.filePath)")
        }

        // Delete the thumbnail file and remove from cache
        if let thumbnailPath = clip.thumbnailPath {
            do {
                try FileManager.default.removeItem(atPath: thumbnailPath)
                print("Deleted thumbnail file: \(thumbnailPath)")

                // Remove from cache (ThumbnailCache is @MainActor, synchronous)
                ThumbnailCache.shared.removeThumbnail(at: thumbnailPath)
            } catch {
                print("Failed to delete thumbnail file: \(error)")
            }
        }

        withAnimation {
            // SwiftData handles relationship cleanup automatically
            // Just delete the clip and its associated PlayResult
            if let playResult = clip.playResult {
                modelContext.delete(playResult)
            }

            modelContext.delete(clip)

            do {
                try modelContext.save()

                // Track video deletion analytics
                AnalyticsService.shared.trackVideoDeleted(videoID: clip.id.uuidString)

                print("Successfully deleted highlight")
            } catch {
                print("Failed to delete highlight: \(error)")
            }
        }
    }

    private func toggleEditMode() {
        if editMode == .inactive {
            editMode = .active
        } else {
            editMode = .inactive
            selection.removeAll()
        }
    }

    private func toggleSelection(_ clip: VideoClip) {
        if selection.contains(clip.id) {
            selection.remove(clip.id)
        } else {
            selection.insert(clip.id)
        }
    }

    private func selectAll() {
        Haptics.light()
        selection = Set(highlights.map { $0.id })
    }

    private func batchDeleteSelected() {
        let clips = highlights.filter { selection.contains($0.id) }
        guard !clips.isEmpty else { return }
        for clip in clips {
            deleteHighlight(clip)
        }
        selection.removeAll()
        withAnimation { editMode = .inactive }
    }

    private func batchRemoveFromHighlights() {
        let clips = highlights.filter { selection.contains($0.id) }
        guard !clips.isEmpty else { return }

        withAnimation {
            for clip in clips {
                clip.isHighlight = false
            }

            do {
                try modelContext.save()
                print("Successfully removed \(clips.count) clips from highlights")
                Haptics.success()
            } catch {
                print("Failed to remove from highlights: \(error)")
                Haptics.error()
            }
        }

        selection.removeAll()
        withAnimation { editMode = .inactive }
    }

    private func batchUploadSelected() {
        let clips = highlights.filter { selection.contains($0.id) }
        guard !clips.isEmpty, let athlete = athlete else { return }

        Task {
            for clip in clips {
                guard clip.needsUpload else { continue }

                do {
                    let cloudURL = try await VideoCloudManager.shared.uploadVideo(clip, athlete: athlete)

                    await MainActor.run {
                        clip.cloudURL = cloudURL
                        clip.isUploaded = true
                        clip.lastSyncDate = Date()
                    }
                } catch {
                    print("Failed to upload \(clip.fileName): \(error)")
                }
            }

            await MainActor.run {
                do {
                    try modelContext.save()
                    print("Successfully uploaded \(clips.count) highlights")
                    Haptics.success()
                } catch {
                    print("Failed to save after uploads: \(error)")
                    Haptics.error()
                }

                selection.removeAll()
                withAnimation { editMode = .inactive }
            }
        }
    }

    private func batchShareSelected() {
        let clips = highlights.filter { selection.contains($0.id) }
        guard !clips.isEmpty else { return }

        // Get file URLs for all selected clips
        let fileURLs = clips.compactMap { clip -> URL? in
            guard FileManager.default.fileExists(atPath: clip.filePath) else { return nil }
            return URL(fileURLWithPath: clip.filePath)
        }

        guard !fileURLs.isEmpty else {
            print("No valid files to share")
            return
        }

        // Present share sheet
        let activityVC = UIActivityViewController(activityItems: fileURLs, applicationActivities: nil)

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            activityVC.popoverPresentationController?.sourceView = rootVC.view
            rootVC.present(activityVC, animated: true)
        }

        Haptics.light()
    }
}

struct EmptyHighlightsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "star")
                .font(.system(size: 80))
                .foregroundColor(.yellow)

            Text("No Highlights Yet")
                .font(.title)
                .fontWeight(.bold)

            Text("Star great plays! Hits automatically become highlights")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button {
                Haptics.light()
                // Navigate to Videos tab
                NotificationCenter.default.post(name: .switchToVideosTab, object: nil)
                dismiss()
            } label: {
                Label("Go to Videos", systemImage: "video.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
        }
        .padding()
    }
}

extension Notification.Name {
    static let switchToVideosTab = Notification.Name("switchToVideosTab")
}

struct HighlightCard: View {
    let clip: VideoClip
    let editMode: EditMode
    let onTap: () -> Void
    @State private var thumbnailImage: UIImage?
    @State private var isLoadingThumbnail = false
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                // Video thumbnail area with proper thumbnail loading
                GeometryReader { geometry in
                    ZStack {
                        Group {
                            if let thumbnail = thumbnailImage {
                                Image(uiImage: thumbnail)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: geometry.size.width, height: geometry.size.height)
                                    .clipped()
                            } else {
                                Rectangle()
                                    .fill(
                                        LinearGradient(
                                            colors: playResultGradient,
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .overlay(
                                        VStack(spacing: 8) {
                                            if isLoadingThumbnail {
                                                ProgressView()
                                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                                    .scaleEffect(1.2)
                                            } else {
                                                Image(systemName: "video")
                                                    .font(.title2)
                                                    .foregroundColor(.white)
                                                
                                                Text("Loading...")
                                                    .font(.caption)
                                                    .foregroundColor(.white.opacity(0.8))
                                            }
                                        }
                                    )
                            }
                        }
                    
                    // Play button overlay (only in normal mode)
                    if editMode == .inactive {
                        Circle()
                            .fill(Color.black.opacity(0.6))
                            .frame(width: 44, height: 44)
                            .overlay(
                                Image(systemName: "play.fill")
                                    .font(.title3)
                                    .foregroundColor(.white)
                            )
                    }
                    
                    // Play result badge in top-right corner (always visible)
                    VStack {
                        HStack {
                            Spacer()
                            
                            if let playResult = clip.playResult {
                                VStack(spacing: 2) {
                                    Image(systemName: playResultIcon(for: playResult.type))
                                        .foregroundColor(.white)
                                        .font(.caption)
                                    
                                    Text(playResultAbbreviation(for: playResult.type))
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(playResultColor(for: playResult.type))
                                .cornerRadius(8)
                                .padding(.top, 8)
                                .padding(.trailing, 8)
                            }
                        }
                        
                        Spacer()
                        
                        // Highlight star in bottom-left corner (always visible)
                        HStack {
                            Image(systemName: "star.fill")
                                .font(.title3)
                                .foregroundColor(.yellow)
                                .background(
                                    Circle()
                                        .fill(Color.black.opacity(0.6))
                                        .frame(width: 32, height: 32)
                                )
                                .padding(.bottom, 8)
                                .padding(.leading, 8)
                            
                            Spacer()
                        }
                    }
                    }
                }
                .aspectRatio(16/9, contentMode: .fit) // Landscape video aspect ratio
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                
                // Info overlay at bottom
                VStack(alignment: .leading, spacing: 4) {
                    if let playResult = clip.playResult {
                        Text(playResult.type.displayName)
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                    }

                    if let game = clip.game {
                        HStack(spacing: 8) {
                            Text("vs \(game.opponent)")
                                .font(.subheadline)
                                .foregroundColor(.blue)

                            if let season = clip.season {
                                SeasonBadge(season: season, fontSize: 8)
                            }
                        }

                        Text((game.date ?? Date()), style: .date)
                    } else {
                        HStack(spacing: 8) {
                            Text("Practice")
                                .font(.subheadline)
                                .foregroundColor(.green)

                            if let season = clip.season {
                                SeasonBadge(season: season, fontSize: 8)
                            }
                        }

                        Text((clip.createdAt ?? Date()), style: .date)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6))
            }
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(editMode == .active ? "Tap to select. Use bottom toolbar to delete." : "Tap to play the highlight.")
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
        .scaleEffect(editMode == .active ? 0.95 : 1.0) // Slightly smaller in edit mode
        .animation(.easeInOut(duration: 0.2), value: editMode)
        .task {
            await loadThumbnail()
        }
    }
    
    private var accessibilityLabel: String {
        var parts: [String] = []
        if let pr = clip.playResult { parts.append(pr.type.displayName) }
        if let game = clip.game { parts.append("vs \(game.opponent)") }
        else { parts.append("Practice") }
        let dateText = DateFormatter.pp_shortDate.string(from: (clip.createdAt ?? Date()))
        parts.append(dateText)
        return parts.joined(separator: ", ")
    }
    
    @MainActor
    private func loadThumbnail() async {
        // Skip if already loading or already have image
        guard !isLoadingThumbnail, thumbnailImage == nil else { return }
        
        // Check if we have a thumbnail path
        guard let thumbnailPath = clip.thumbnailPath else {
            // Generate thumbnail if none exists
            await generateMissingThumbnail()
            return
        }
        
        isLoadingThumbnail = true
        
        do {
            // Load thumbnail asynchronously using the same cache system
            let image = try await ThumbnailCache.shared.loadThumbnail(at: thumbnailPath)
            thumbnailImage = image
        } catch {
            print("Failed to load thumbnail in HighlightCard: \(error)")
            // Try to regenerate thumbnail
            await generateMissingThumbnail()
        }
        
        isLoadingThumbnail = false
    }
    
    private func generateMissingThumbnail() async {
        print("Generating missing thumbnail for highlight: \(clip.fileName)")
        
        let videoURL = URL(fileURLWithPath: clip.filePath)
        let result = await VideoFileManager.generateThumbnail(from: videoURL)
        
        await MainActor.run {
            switch result {
            case .success(let thumbnailPath):
                clip.thumbnailPath = thumbnailPath
                Task {
                    await loadThumbnail()
                }
            case .failure(let error):
                print("Failed to generate thumbnail in HighlightCard: \(error)")
                isLoadingThumbnail = false
            }
        }
    }
    
    private var playResultGradient: [Color] {
        guard let playResult = clip.playResult else { return [.gray, .gray.opacity(0.7)] }
        
        switch playResult.type {
        case .single:
            return [.green, .green.opacity(0.7)]
        case .double:
            return [.blue, .blue.opacity(0.7)]
        case .triple:
            return [.orange, .orange.opacity(0.7)]
        case .homeRun:
            return [.red, .red.opacity(0.7)]
        default:
            return [.gray, .gray.opacity(0.7)]
        }
    }
    
    // Helper functions for play result styling
    private func playResultIcon(for type: PlayResultType) -> String {
        switch type {
        case .single:
            return "1.circle.fill"
        case .double:
            return "2.circle.fill"
        case .triple:
            return "3.circle.fill"
        case .homeRun:
            return "4.circle.fill"
        case .walk:
            return "figure.walk"
        case .strikeout:
            return "k.circle.fill"
        case .groundOut:
            return "arrow.down.circle.fill"
        case .flyOut:
            return "arrow.up.circle.fill"
        }
    }
    
    private func playResultAbbreviation(for type: PlayResultType) -> String {
        switch type {
        case .single:
            return "1B"
        case .double:
            return "2B"
        case .triple:
            return "3B"
        case .homeRun:
            return "HR"
        case .walk:
            return "BB"
        case .strikeout:
            return "K"
        case .groundOut:
            return "GO"
        case .flyOut:
            return "FO"
        }
    }
    
    private func playResultColor(for type: PlayResultType) -> Color {
        switch type {
        case .single:
            return .green
        case .double:
            return .blue
        case .triple:
            return .orange
        case .homeRun:
            return .red
        case .walk:
            return .cyan
        case .strikeout:
            return .red.opacity(0.8)
        case .groundOut, .flyOut:
            return .gray
        }
    }
}

// MARK: - Temporary Simple Cloud Progress View
struct SimpleCloudProgressView: View {
    let clip: VideoClip
    let athlete: Athlete?

    @Environment(\.modelContext) private var modelContext
    @State private var isUploading = false
    @State private var uploadProgress: Double = 0.0
    @State private var uploadError: String?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: cloudStatusIcon)
                .foregroundColor(cloudStatusColor)
                .font(.caption)

            if isUploading {
                HStack(spacing: 4) {
                    ProgressView(value: uploadProgress)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 100)

                    Text("\(Int(uploadProgress * 100))%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            } else {
                Text(cloudStatusText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if clip.needsUpload && !isUploading {
                Button("Upload") {
                    Task {
                        await uploadVideo()
                    }
                }
                .font(.caption2)
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }

            if let error = uploadError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.caption)
                    .help(error)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }

    private func uploadVideo() async {
        guard let athlete = athlete else {
            uploadError = "No athlete associated with clip"
            return
        }

        isUploading = true
        uploadError = nil
        uploadProgress = 0.0

        do {
            let cloudURL = try await VideoCloudManager.shared.uploadVideo(clip, athlete: athlete)

            // Update clip in model context
            await MainActor.run {
                clip.cloudURL = cloudURL
                clip.isUploaded = true
                clip.lastSyncDate = Date()

                do {
                    try modelContext.save()
                    print("✅ Successfully uploaded and saved clip: \(clip.fileName)")
                } catch {
                    uploadError = "Failed to save: \(error.localizedDescription)"
                    print("🔴 Error saving clip after upload: \(error)")
                }

                isUploading = false
            }
        } catch {
            await MainActor.run {
                uploadError = error.localizedDescription
                isUploading = false
                print("🔴 Upload failed: \(error)")
            }
        }
    }
    
    private var cloudStatusIcon: String {
        if clip.isUploaded && clip.isAvailableOffline {
            return "icloud.and.arrow.down.fill"
        } else if clip.isUploaded {
            return "icloud.fill"
        } else if clip.needsUpload {
            return "icloud.and.arrow.up"
        } else {
            return "externaldrive.fill"
        }
    }
    
    private var cloudStatusColor: Color {
        if clip.isUploaded && clip.isAvailableOffline {
            return .green
        } else if clip.isUploaded {
            return .blue
        } else if clip.needsUpload {
            return .orange
        } else {
            return .gray
        }
    }
    
    private var cloudStatusText: String {
        if clip.isUploaded && clip.isAvailableOffline {
            return "Available Offline"
        } else if clip.isUploaded {
            return "In Cloud"
        } else if clip.needsUpload {
            return "Ready to Upload"
        } else {
            return "Local Only"
        }
    }
}



// MARK: - Simple Cloud Storage View
struct SimpleCloudStorageView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var pendingUploads: [VideoClip]

    @State private var uploadingClips = Set<UUID>()
    @State private var isBulkUploading = false
    @State private var uploadErrors: [UUID: String] = [:]

    init() {
        self._pendingUploads = Query(
            filter: #Predicate<VideoClip> { $0.needsUpload },
            sort: [SortDescriptor(\VideoClip.createdAt, order: .reverse)]
        )
    }

    var body: some View {
        NavigationStack {
            List {
                if pendingUploads.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "checkmark.icloud")
                            .font(.system(size: 50))
                            .foregroundColor(.green)
                        
                        Text("All videos are up to date")
                            .font(.title3)
                            .fontWeight(.medium)
                        
                        Text("Your highlights and videos are synchronized with cloud storage.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .listRowBackground(Color.clear)
                } else {
                    Section("Videos Ready to Upload") {
                        ForEach(pendingUploads) { clip in
                            HStack {
                                // Thumbnail placeholder
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 50, height: 38)
                                    .overlay(
                                        Image(systemName: "video")
                                            .foregroundColor(.gray)
                                    )
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    if let playResult = clip.playResult {
                                        Text(playResult.type.displayName)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                    } else {
                                        Text(clip.fileName)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                    }
                                    
                                    if let game = clip.game {
                                        Text("vs \(game.opponent)")
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                    } else {
                                        Text("Practice")
                                            .font(.caption)
                                            .foregroundColor(.green)
                                    }
                                }
                                
                                Spacer()

                                if uploadingClips.contains(clip.id) {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Button("Upload") {
                                        Task {
                                            await uploadClip(clip)
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }

                                if let error = uploadErrors[clip.id] {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.red)
                                        .help(error)
                                }
                            }
                        }
                    }
                    
                    Section {
                        Button {
                            Task {
                                await uploadAll()
                            }
                        } label: {
                            HStack {
                                if isBulkUploading {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Uploading...")
                                } else {
                                    Text("Upload All Videos (\(pendingUploads.count))")
                                }
                            }
                        }
                        .disabled(pendingUploads.isEmpty || isBulkUploading)
                    }
                }
            }
            .navigationTitle("Cloud Storage")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private func uploadClip(_ clip: VideoClip) async {
        guard let athlete = clip.athlete else {
            uploadErrors[clip.id] = "No athlete associated with clip"
            print("🔴 Cannot upload clip: no athlete")
            return
        }

        uploadingClips.insert(clip.id)
        uploadErrors.removeValue(forKey: clip.id)

        do {
            let cloudURL = try await VideoCloudManager.shared.uploadVideo(clip, athlete: athlete)

            await MainActor.run {
                clip.cloudURL = cloudURL
                clip.isUploaded = true
                clip.lastSyncDate = Date()

                do {
                    try modelContext.save()
                    print("✅ Successfully uploaded clip: \(clip.fileName)")
                } catch {
                    uploadErrors[clip.id] = "Failed to save: \(error.localizedDescription)"
                    print("🔴 Error saving clip after upload: \(error)")
                }

                uploadingClips.remove(clip.id)
            }
        } catch {
            await MainActor.run {
                uploadErrors[clip.id] = error.localizedDescription
                uploadingClips.remove(clip.id)
                print("🔴 Upload failed for \(clip.fileName): \(error)")
            }
        }
    }

    private func uploadAll() async {
        isBulkUploading = true
        uploadErrors.removeAll()

        // Upload clips in parallel (max 3 concurrent uploads)
        await withTaskGroup(of: Void.self) { group in
            var activeUploads = 0
            var clipIndex = 0
            let maxConcurrent = 3

            // Start initial batch
            while clipIndex < pendingUploads.count && activeUploads < maxConcurrent {
                let clip = pendingUploads[clipIndex]
                group.addTask {
                    await uploadClip(clip)
                }
                activeUploads += 1
                clipIndex += 1
            }

            // As tasks complete, start new ones
            for await _ in group {
                if clipIndex < pendingUploads.count {
                    let clip = pendingUploads[clipIndex]
                    group.addTask {
                        await uploadClip(clip)
                    }
                    clipIndex += 1
                }
            }
        }

        await MainActor.run {
            isBulkUploading = false
            print("✅ Bulk upload completed")
        }
    }
}

extension DateFormatter {
    static let pp_shortDate: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .none
        return df
    }()
}

// MARK: - Game Highlight Group Model

struct GameHighlightGroup: Identifiable {
    let id: UUID
    let game: Game?
    let clips: [VideoClip]
    var isExpanded: Bool

    var displayTitle: String {
        if let game = game {
            return "vs \(game.opponent)"
        } else {
            return "Practice"
        }
    }

    var displayDate: String {
        if let game = game, let date = game.date {
            return date.formatted(date: .abbreviated, time: .omitted)
        } else if let firstClip = clips.first, let date = firstClip.createdAt {
            return date.formatted(date: .abbreviated, time: .omitted)
        }
        return ""
    }

    var hitCount: Int {
        clips.count
    }
}

// MARK: - Game Highlight Section View

struct GameHighlightSection: View {
    let group: GameHighlightGroup
    let editMode: EditMode
    @Binding var selection: Set<UUID>
    let onToggleExpand: () -> Void
    let onClipTap: (VideoClip) -> Void
    let onDeleteClip: (VideoClip) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section Header (always visible)
            if group.clips.count > 1 {
                Button(action: {
                    Haptics.selection()
                    withAnimation {
                        onToggleExpand()
                    }
                }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.displayTitle)
                                .font(.headline)
                                .foregroundColor(.primary)

                            HStack(spacing: 12) {
                                Text(group.displayDate)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)

                                HStack(spacing: 4) {
                                    Image(systemName: "video.fill")
                                        .font(.caption2)
                                    Text("\(group.hitCount) hit\(group.hitCount == 1 ? "" : "s")")
                                        .font(.caption)
                                }
                                .foregroundColor(.blue)
                            }
                        }

                        Spacer()

                        Image(systemName: group.isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                            .font(.title3)
                            .foregroundColor(.blue)
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }

            // Clips Grid (shown when expanded or single clip)
            if group.isExpanded {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 140), spacing: 15, alignment: .top)],
                    spacing: 15
                ) {
                    ForEach(group.clips) { clip in
                        highlightItemView(
                            clip: clip,
                            editMode: editMode,
                            isSelected: selection.contains(clip.id),
                            onTap: { onClipTap(clip) },
                            onDelete: { onDeleteClip(clip) }
                        )
                    }
                }
                .padding(.leading, group.clips.count > 1 ? 12 : 0)
            }
        }
    }

    private func highlightItemView(
        clip: VideoClip,
        editMode: EditMode,
        isSelected: Bool,
        onTap: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) -> some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 8) {
                HighlightCard(
                    clip: clip,
                    editMode: editMode,
                    onTap: onTap
                )
                .contextMenu {
                    Button {
                        onTap()
                    } label: {
                        Label("Play", systemImage: "play.fill")
                    }
                    Button {
                        onDelete()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }

                if editMode == .inactive {
                    SimpleCloudProgressView(clip: clip, athlete: clip.athlete)
                }
            }

            if editMode == .active {
                Button(action: onTap) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .symbolRenderingMode(.hierarchical)
                        .font(.title2)
                        .foregroundStyle(isSelected ? .blue : .secondary)
                        .padding(8)
                }
            }
        }
    }
}

#Preview {
    HighlightsView(athlete: nil)
}
