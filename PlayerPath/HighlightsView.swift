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
    let currentTier: SubscriptionTier
    let hasCoachingAccess: Bool
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var autoHighlightSettings = AutoHighlightSettings.shared
    @State private var selectedClip: VideoClip?
    @State private var showingVideoPlayer = false
    @State private var showingDeleteAlert = false
    @State private var clipToDelete: VideoClip?
    @State private var editMode: EditMode = .inactive
    @State private var showingAutoHighlightSettings = false

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

    // Cached highlights — recomputed via recomputeAll() when inputs change
    @State private var cachedHighlights: [VideoClip] = []
    @State private var recomputeTask: Task<Void, Never>?

    var highlights: [VideoClip] { cachedHighlights }

    /// Single entry point that debounces and calls both recompute functions.
    private func recomputeAll() {
        recomputeTask?.cancel()
        recomputeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms debounce
            guard !Task.isCancelled else { return }
            recomputeHighlights()
            recomputeGroupedHighlights()
        }
    }

    private func recomputeHighlights() {
        guard let athlete = athlete, let videoClips = athlete.videoClips else {
            cachedHighlights = []
            return
        }
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
        cachedHighlights = filtered.sorted { lhs, rhs in
            let l = lhs.createdAt ?? .distantPast
            let r = rhs.createdAt ?? .distantPast
            return sortOrder == .newest ? (l > r) : (l < r)
        }
    }

    // Cached grouped highlights — recomputed only when inputs change
    @State private var cachedGroupedHighlights: [GameHighlightGroup] = []
    @State private var lastGroupInputHash: Int = 0

    // Group highlights by game for better organization
    var groupedHighlights: [GameHighlightGroup] {
        cachedGroupedHighlights
    }

    private func recomputeGroupedHighlights() {
        let clips = highlights

        // Build a lightweight hash from the inputs that affect grouping
        var hasher = Hasher()
        hasher.combine(clips.count)
        hasher.combine(sortOrder)
        hasher.combine(expandedGroups)
        for clip in clips.prefix(20) { hasher.combine(clip.id) }
        let inputHash = hasher.finalize()
        guard inputHash != lastGroupInputHash else { return }
        lastGroupInputHash = inputHash

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

        // Add practice clips as individual groups
        for clip in practiceClips {
            groups.append(GameHighlightGroup(
                id: clip.id,
                game: nil,
                clips: [clip],
                isExpanded: true
            ))
        }

        // Sort ALL groups together — use clip createdAt as fallback for practice groups
        groups.sort { lhs, rhs in
            let lDate = lhs.game?.date ?? lhs.clips.first?.createdAt ?? .distantPast
            let rDate = rhs.game?.date ?? rhs.clips.first?.createdAt ?? .distantPast
            return sortOrder == .newest ? (lDate > rDate) : (lDate < rDate)
        }

        // Auto-expand single-clip game groups
        groups = groups.map { group in
            var updatedGroup = group
            if group.clips.count == 1 {
                updatedGroup.isExpanded = true
            }
            return updatedGroup
        }

        cachedGroupedHighlights = groups
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
        .fullScreenCover(isPresented: $showingVideoPlayer) {
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
        .sheet(isPresented: $showingAutoHighlightSettings) {
            if let athlete = athlete {
                AutoHighlightSettingsView(athlete: athlete)
            }
        }
        .onAppear {
            AnalyticsService.shared.trackScreenView(screenName: "Highlights", screenClass: "HighlightsView")
            Task { @MainActor in
                migrateHitVideosToHighlights()
            }
            recomputeHighlights()
            recomputeGroupedHighlights()
        }
        .onChange(of: athlete?.videoClips?.count) { _, _ in recomputeAll() }
        .onChange(of: selectedSeasonFilter) { _, _ in recomputeAll() }
        .onChange(of: filter) { _, _ in recomputeAll() }
        .onChange(of: searchText) { _, _ in recomputeAll() }
        .onChange(of: sortOrder) { _, _ in recomputeAll() }
        .onChange(of: expandedGroups) { _, _ in recomputeGroupedHighlights() }
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
                video.needsSync = true
                migrationCount += 1
            }
        }

        // Save if we migrated any videos
        if migrationCount > 0 {
            do {
                try modelContext.save()
                hasCompletedMigration = true
            } catch {
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
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 16, alignment: .top)
                ],
                spacing: 16
            ) {
                ForEach(highlights) { clip in
                    HighlightCard(
                        clip: clip,
                        editMode: editMode,
                        onTap: {
                            if editMode == .inactive {
                                selectedClip = clip
                                showingVideoPlayer = true
                            } else {
                                toggleSelection(clip)
                            }
                        },
                        hasCoachingAccess: hasCoachingAccess
                    )
                    .contextMenu {
                        Button {
                            selectedClip = clip
                            showingVideoPlayer = true
                        } label: {
                            Label("Play", systemImage: "play.fill")
                        }
                        Button {
                            shareClip(clip)
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        Divider()
                        Button {
                            removeClipFromHighlights(clip)
                        } label: {
                            Label("Remove from Highlights", systemImage: "star.slash")
                        }
                        Divider()
                        Button(role: .destructive) {
                            clipToDelete = clip
                            showingDeleteAlert = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if editMode == .active {
                            Button {
                                toggleSelection(clip)
                            } label: {
                                Image(systemName: selection.contains(clip.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title2)
                                    .foregroundColor(selection.contains(clip.id) ? .blue : .white)
                                    .shadow(color: .black.opacity(0.3), radius: 4)
                            }
                            .padding(8)
                        }
                    }
                }
            }
            .padding()
        }
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
        if !highlights.isEmpty {
            ToolbarItem(placement: .topBarLeading) {
                SeasonFilterMenu(
                    selectedSeasonID: $selectedSeasonFilter,
                    availableSeasons: availableSeasons,
                    showNoSeasonOption: cachedHighlights.contains(where: { $0.season == nil })
                )
            }
        }

        // Combined Filter & Sort menu
        if !highlights.isEmpty {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section("Filter") {
                        Picker("Type", selection: $filter) {
                            Label("All", systemImage: "square.grid.2x2").tag(Filter.all)
                            Label("Games", systemImage: "baseball.diamond.bases").tag(Filter.game)
                            Label("Practice", systemImage: "figure.baseball").tag(Filter.practice)
                        }
                    }
                    Section("Sort") {
                        Picker("Sort", selection: $sortOrder) {
                            Label("Newest", systemImage: "arrow.down").tag(SortOrder.newest)
                            Label("Oldest", systemImage: "arrow.up").tag(SortOrder.oldest)
                        }
                    }
                } label: {
                    Image(systemName: (filter != .all || sortOrder != .newest) ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("Filter and sort highlights")
            }
        }

        // Auto-highlight settings (Plus+ only)
        if currentTier >= .plus {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.light()
                    showingAutoHighlightSettings = true
                } label: {
                    Image(systemName: "wand.and.stars")
                }
                .accessibilityLabel("Auto-Highlight Settings")
            }
        }

        // Edit button
        if !highlights.isEmpty {
            ToolbarItem(placement: .topBarTrailing) {
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
        Haptics.medium()

        // Capture references before deletion — accessing SwiftData object properties after
        // context.delete() is undefined behavior.
        let clipID = clip.id.uuidString
        let clipGame = clip.game
        let clipAthlete = clip.athlete

        withAnimation {
            // Use the canonical delete method which handles local files, thumbnails,
            // cloud storage, and play result cleanup.
            clip.delete(in: modelContext)

            do {
                try modelContext.save()

                // Track video deletion analytics
                AnalyticsService.shared.trackVideoDeleted(videoID: clipID)

                // Recalculate game statistics first (if clip belonged to a game),
                // then athlete statistics which aggregate from game stats.
                if let game = clipGame {
                    try StatisticsService.shared.recalculateGameStatistics(for: game, context: modelContext)
                }
                if let athlete = clipAthlete {
                    try StatisticsService.shared.recalculateAthleteStatistics(for: athlete, context: modelContext)
                }

            } catch {
                print("[HighlightsView] Failed to save or recalculate stats after deleting clip \(clipID): \(error)")
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

        // Capture references before deletion — accessing SwiftData object properties after
        // context.delete() is undefined behavior.
        let deletedIDs = clips.map { $0.id.uuidString }
        let affectedGames = Set(clips.compactMap { $0.game })
        let clipAthlete = clips.first?.athlete

        withAnimation {
            for clip in clips {
                // Use the canonical delete method which handles local files, thumbnails,
                // cloud storage, and play result cleanup.
                clip.delete(in: modelContext)
            }
            do {
                try modelContext.save()
                deletedIDs.forEach { AnalyticsService.shared.trackVideoDeleted(videoID: $0) }

                // Recalculate game statistics first for any affected games,
                // then athlete statistics which aggregate from game stats.
                for game in affectedGames {
                    try StatisticsService.shared.recalculateGameStatistics(for: game, context: modelContext)
                }
                if let athlete = clipAthlete {
                    try StatisticsService.shared.recalculateAthleteStatistics(for: athlete, context: modelContext)
                }

                Haptics.success()
            } catch {
                Haptics.error()
            }
        }

        selection.removeAll()
        withAnimation { editMode = .inactive }
    }

    private func removeClipFromHighlights(_ clip: VideoClip) {
        clip.isHighlight = false
        clip.needsSync = true
        do {
            try modelContext.save()
            Haptics.success()
        } catch {
            Haptics.error()
        }
    }

    private func shareClip(_ clip: VideoClip) {
        guard FileManager.default.fileExists(atPath: clip.resolvedFilePath) else {
            return
        }
        let fileURL = clip.resolvedFileURL
        let activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            activityVC.popoverPresentationController?.sourceView = rootVC.view
            rootVC.present(activityVC, animated: true)
        }
        Haptics.light()
    }

    private func batchRemoveFromHighlights() {
        let clips = highlights.filter { selection.contains($0.id) }
        guard !clips.isEmpty else { return }

        withAnimation {
            for clip in clips {
                clip.isHighlight = false
                clip.needsSync = true
            }

            do {
                try modelContext.save()
                Haptics.success()
            } catch {
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
            var failedCount = 0
            for clip in clips {
                guard clip.needsUpload else { continue }

                do {
                    let cloudURL = try await VideoCloudManager.shared.uploadVideo(clip, athlete: athlete)

                    await MainActor.run {
                        clip.cloudURL = cloudURL
                        clip.isUploaded = true
                        clip.lastSyncDate = Date()
                        // Update storage counter
                        if let user = athlete.user {
                            let fileSize = (try? FileManager.default.attributesOfItem(atPath: clip.resolvedFilePath)[.size] as? Int64) ?? 0
                            user.cloudStorageUsedBytes += fileSize
                        }
                    }
                } catch {
                    failedCount += 1
                }
            }

            await MainActor.run {
                do {
                    try modelContext.save()
                    if failedCount > 0 {
                        Haptics.error()
                    } else {
                        Haptics.success()
                    }
                } catch {
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
            guard FileManager.default.fileExists(atPath: clip.resolvedFilePath) else { return nil }
            return clip.resolvedFileURL
        }

        guard !fileURLs.isEmpty else {
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
    @State private var isAnimating = false
    @State private var floatOffset: CGFloat = 0

    var body: some View {
        ZStack {
            // Subtle background glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.yellow.opacity(0.1), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 180
                    )
                )
                .frame(width: 360, height: 360)
                .blur(radius: 50)
                .offset(y: -40)

            VStack(spacing: 28) {
                // Floating star with glow
                ZStack {
                    Image(systemName: "star.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.yellow.opacity(0.3))
                        .blur(radius: 15)

                    Image(systemName: "star.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.yellow, .orange.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .offset(y: floatOffset)
                .scaleEffect(isAnimating ? 1.0 : 0.8)
                .opacity(isAnimating ? 1.0 : 0.0)

                VStack(spacing: 10) {
                    Text("No Highlights Yet")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)

                    Text("Star your best plays!\nHits automatically become highlights")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }
                .opacity(isAnimating ? 1.0 : 0.0)
                .offset(y: isAnimating ? 0 : 10)

                Button {
                    Haptics.medium()
                    NotificationCenter.default.post(name: .switchToVideosTab, object: nil)
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "video.fill")
                            .font(.body)
                        Text("Go to Videos")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: 200)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [.blue, .blue.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(Capsule())
                    .shadow(color: .blue.opacity(0.3), radius: 12, x: 0, y: 6)
                }
                .buttonStyle(PremiumButtonStyle())
                .opacity(isAnimating ? 1.0 : 0.0)
                .offset(y: isAnimating ? 0 : 20)
            }
            .padding(.horizontal, 40)
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                isAnimating = true
            }
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                floatOffset = -8
            }
        }
    }
}

extension Notification.Name {
    static let switchToVideosTab = Notification.Name("switchToVideosTab")
}

struct HighlightCard: View {
    let clip: VideoClip
    let editMode: EditMode
    let onTap: () -> Void
    let hasCoachingAccess: Bool
    @Environment(\.modelContext) private var modelContext
    @State private var showingShareToFolder = false

    var body: some View {
        Button(action: {
            Haptics.light()
            onTap()
        }) {
            VStack(spacing: 0) {
                // Video thumbnail area — uses shared VideoThumbnailView for consistency with VideoClipsView
                ZStack {
                    VideoThumbnailView(
                        clip: clip,
                        size: CGSize(width: 200, height: 112),
                        cornerRadius: 0,
                        showPlayButton: editMode == .inactive,
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
                        .frame(height: 40)
                    }

                    // Duration badge (bottom-left)
                    VStack {
                        Spacer()
                        HStack {
                            if let duration = clip.duration, duration > 0 {
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
                }
                .aspectRatio(16/9, contentMode: .fit)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 12))

                // Info section at bottom
                VStack(alignment: .leading, spacing: 6) {
                    if let playResult = clip.playResult {
                        Text(playResult.type.displayName)
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    if let game = clip.game {
                        HStack(spacing: 6) {
                            Text("vs \(game.opponent)")
                                .font(.caption)
                                .foregroundColor(.blue)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer()
                            if let season = clip.season {
                                SeasonBadge(season: season, fontSize: 8)
                            }
                        }

                        Text((game.date ?? Date()), style: .date)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        HStack(spacing: 6) {
                            Text("Practice")
                                .font(.caption)
                                .foregroundColor(.green)
                            Spacer()
                            if let season = clip.season {
                                SeasonBadge(season: season, fontSize: 8)
                            }
                        }

                        Text((clip.createdAt ?? Date()), style: .date)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6))
            }
        }
        .buttonStyle(PressableCardButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(editMode == .active ? "Tap to select. Use bottom toolbar to delete." : "Tap to play the highlight.")
        .clipShape(RoundedRectangle(cornerRadius: .cornerLarge, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
        .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
        .scaleEffect(editMode == .active ? 0.96 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: editMode)
        .contextMenu {
            if hasCoachingAccess && editMode == .inactive {
                Button {
                    showingShareToFolder = true
                } label: {
                    Label("Share to Coach Folder", systemImage: "folder.badge.person.fill")
                }
            }
        }
        .sheet(isPresented: $showingShareToFolder) {
            ShareToCoachFolderView(clip: clip)
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
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
        .cornerRadius(.cornerMedium)
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
                // Update storage counter
                if let user = athlete.user {
                    let fileSize = (try? FileManager.default.attributesOfItem(atPath: clip.resolvedFilePath)[.size] as? Int64) ?? 0
                    user.cloudStorageUsedBytes += fileSize
                }

                do {
                    try modelContext.save()
                } catch {
                    uploadError = "Failed to save: \(error.localizedDescription)"
                }

                isUploading = false
            }
        } catch {
            await MainActor.run {
                uploadError = error.localizedDescription
                isUploading = false
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
            filter: #Predicate<VideoClip> { !$0.isUploaded && $0.cloudURL == nil },
            sort: [SortDescriptor(\VideoClip.createdAt, order: .reverse)]
        )
    }

    var body: some View {
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
                                        Image(systemName: "video.fill")
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

    private func uploadClip(_ clip: VideoClip) async {
        guard let athlete = clip.athlete else {
            uploadErrors[clip.id] = "No athlete associated with clip"
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
                // Update storage counter
                if let user = athlete.user {
                    let fileSize = (try? FileManager.default.attributesOfItem(atPath: clip.resolvedFilePath)[.size] as? Int64) ?? 0
                    user.cloudStorageUsedBytes += fileSize
                }

                do {
                    try modelContext.save()
                } catch {
                    uploadErrors[clip.id] = "Failed to save: \(error.localizedDescription)"
                }

                uploadingClips.remove(clip.id)
            }
        } catch {
            await MainActor.run {
                uploadErrors[clip.id] = error.localizedDescription
                uploadingClips.remove(clip.id)
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
    let onRemoveFromHighlights: (VideoClip) -> Void
    let onShareClip: (VideoClip) -> Void
    let hasCoachingAccess: Bool

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
                                    Text("\(group.hitCount) clip\(group.hitCount == 1 ? "" : "s")")
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
                    .cornerRadius(.cornerLarge)
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
                            onDelete: { onDeleteClip(clip) },
                            onRemoveFromHighlights: { onRemoveFromHighlights(clip) },
                            onShare: { onShareClip(clip) }
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
        onDelete: @escaping () -> Void,
        onRemoveFromHighlights: @escaping () -> Void,
        onShare: @escaping () -> Void
    ) -> some View {
        ZStack(alignment: .topLeading) {
            HighlightCard(
                clip: clip,
                editMode: editMode,
                onTap: onTap,
                hasCoachingAccess: hasCoachingAccess
            )
            .contextMenu {
                Button {
                    onTap()
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                Button {
                    onShare()
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                Divider()
                Button {
                    onRemoveFromHighlights()
                } label: {
                    Label("Remove from Highlights", systemImage: "star.slash")
                }
                Divider()
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
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

// MARK: - Auto-Highlight Settings View

struct AutoHighlightSettingsView: View {
    let athlete: Athlete
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var settings = AutoHighlightSettings.shared

    @State private var isScanningLibrary = false
    @State private var scanResult: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Auto-Highlight Enabled", isOn: $settings.enabled)
                        .tint(.yellow)
                } footer: {
                    Text("When enabled, clips are automatically marked as highlights based on their play result when saved.")
                }

                if settings.enabled {
                    Section("Batting") {
                        Toggle("Home Run", isOn: $settings.includeHomeRuns)
                        Toggle("Triple",   isOn: $settings.includeTriples)
                        Toggle("Double",   isOn: $settings.includeDoubles)
                        Toggle("Single",   isOn: $settings.includeSingles)
                    }

                    Section("Pitching") {
                        Toggle("Strikeout",  isOn: $settings.includePitcherStrikeouts)
                        Toggle("Ground Out", isOn: $settings.includePitcherGroundOuts)
                        Toggle("Fly Out",    isOn: $settings.includePitcherFlyOuts)
                    }
                }

                Section {
                    Button {
                        Task { await scanLibrary() }
                    } label: {
                        HStack {
                            Label("Scan Library", systemImage: "wand.and.stars")
                            Spacer()
                            if isScanningLibrary {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isScanningLibrary)

                    if let result = scanResult {
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Re-applies your current rules to all existing clips. Previously tagged highlights will be updated to match.")
                }
            }
            .navigationTitle("Auto-Highlight Rules")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func scanLibrary() async {
        isScanningLibrary = true
        scanResult = nil
        do {
            let changed = try await MainActor.run {
                try AutoHighlightSettings.shared.scanLibrary(for: athlete, context: modelContext)
            }
            scanResult = changed == 0
                ? "All clips are already up to date."
                : "\(changed) clip\(changed == 1 ? "" : "s") updated."
        } catch {
            scanResult = "Scan failed: \(error.localizedDescription)"
        }
        isScanningLibrary = false
    }
}

#Preview {
    HighlightsView(athlete: nil, currentTier: .free, hasCoachingAccess: false)
}
