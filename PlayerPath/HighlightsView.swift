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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject private var autoHighlightSettings = AutoHighlightSettings.shared
    @State private var selectedClip: VideoClip?
    @State private var showingVideoPlayer = false
    @State private var showingDeleteAlert = false
    @State private var clipToDelete: VideoClip?
    @State private var editMode: EditMode = .inactive
    @State private var showingAutoHighlightSettings = false

    @State private var clipToShareToFolder: VideoClip?
    @State private var clipToMove: VideoClip?
    @State private var viewModel = HighlightsViewModel()
    @State private var selection = Set<VideoClip.ID>()
    @AppStorage("hasCompletedHighlightMigration") private var hasCompletedMigration = false

    @State private var recomputeTask: Task<Void, Never>?
    @State private var errorAlertShown = false
    @State private var errorAlertMessage = ""

    /// Single entry point that debounces and recomputes the flat highlights list.
    private func recomputeAll() {
        recomputeTask?.cancel()
        recomputeTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            viewModel.refilter()
        }
    }
    
    var body: some View {
        contentView
            .navigationTitle("\(athlete?.name ?? "Highlights") (\(viewModel.totalCount))")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $viewModel.searchText, placement: .navigationBarDrawer(displayMode: .always))
            .toolbar {
                toolbarContent
            }
            .environment(\.editMode, $editMode)
        .fullScreenCover(isPresented: $showingVideoPlayer) {
            if let clip: VideoClip = selectedClip {
                VideoPlayerView(clip: clip)
            }
        }
        .sheet(item: $clipToShareToFolder) { clip in
            ShareToCoachFolderView(clip: clip)
        }
        .sheet(item: $clipToMove) { clip in
            MoveClipSheet(clip: clip)
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
        .task {
            migrateHitVideosToHighlights()
            viewModel.update(videoClips: athlete?.videoClips ?? [])
        }
        .onDisappear {
            recomputeTask?.cancel()
        }
        .onChange(of: athlete?.id) { _, _ in
            selection.removeAll()
        }
        .onAppear {
            AnalyticsService.shared.trackScreenView(screenName: "Highlights", screenClass: "HighlightsView")
        }
        .onChange(of: athlete?.videoClips?.count) { _, _ in recomputeAll() }
        .onChange(of: viewModel.selectedSeasonFilter) { _, _ in recomputeAll() }
        .onChange(of: viewModel.filter) { _, _ in recomputeAll() }
        .onChange(of: viewModel.searchText) { _, _ in
            // Search uses longer debounce since it fires on every keystroke
            recomputeTask?.cancel()
            recomputeTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                viewModel.refilter()
            }
        }
        .onChange(of: viewModel.sortOrder) { _, _ in recomputeAll() }
        .alert("Error", isPresented: $errorAlertShown) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorAlertMessage)
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
                #if DEBUG
                print("⚠️ Failed to save highlight migration: \(error.localizedDescription)")
                #endif
            }
        } else {
            // No videos to migrate, mark as complete anyway
            hasCompletedMigration = true
        }
    }

    // Check if filters are active
    private var hasActiveFilters: Bool {
        viewModel.selectedSeasonFilter != nil ||
        viewModel.filter != .all ||
        !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // Check if we have any highlights at all (before filtering)
    private var hasAnyHighlights: Bool {
        guard let athlete = athlete, let videoClips = athlete.videoClips else { return false }
        return videoClips.contains(where: { $0.isHighlight })
    }

    @ViewBuilder
    private var contentView: some View {
        if viewModel.isLoading {
            VideoGridSkeletonView()
        } else if viewModel.highlights.isEmpty {
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

        if let seasonID = viewModel.selectedSeasonFilter {
            if seasonID == "no_season" {
                parts.append("season: None")
            } else if let season = viewModel.availableSeasons.first(where: { $0.id.uuidString == seasonID }) {
                parts.append("season: \(season.displayName)")
            }
        }

        if viewModel.filter != .all {
            parts.append("type: \(viewModel.filter == .game ? "Games" : "Practice")")
        }

        if !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("search: \"\(viewModel.searchText)\"")
        }

        return parts.isEmpty ? "your filters" : parts.joined(separator: ", ")
    }

    private func clearAllFilters() {
        Haptics.light()
        withAnimation {
            viewModel.selectedSeasonFilter = nil
            viewModel.filter = .all
            viewModel.searchText = ""
        }
    }

    private var highlightGridView: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: horizontalSizeClass == .regular ? 200 : 160, maximum: horizontalSizeClass == .regular ? 280 : 220), spacing: 16, alignment: .top)
                ],
                spacing: 16
            ) {
                ForEach(viewModel.highlights) { clip in
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
                        Button {
                            clipToShareToFolder = clip
                        } label: {
                            Label("Share to Coach Folder", systemImage: hasCoachingAccess ? "folder.badge.person.crop" : "lock.fill")
                        }
                        Button {
                            clipToMove = clip
                        } label: {
                            Label("Move to Athlete", systemImage: "arrow.right.arrow.left")
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
                                    .foregroundColor(selection.contains(clip.id) ? .brandNavy : .white)
                                    .shadow(color: .black.opacity(0.3), radius: 4)
                            }
                            .padding(8)
                        }
                    }
                    .onAppear { viewModel.onItemAppear(clip) }
                }
            }
            .padding(.vertical)
            .padding(.horizontal, horizontalSizeClass == .regular ? 32 : 16)
        }
        .refreshable {
            viewModel.update(videoClips: athlete?.videoClips ?? [])
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Season filter (only show if we have highlights)
        if !viewModel.highlights.isEmpty {
            ToolbarItem(placement: .topBarLeading) {
                SeasonFilterMenu(
                    selectedSeasonID: $viewModel.selectedSeasonFilter,
                    availableSeasons: viewModel.availableSeasons,
                    showNoSeasonOption: viewModel.hasNoSeasonClips
                )
            }
        }

        // Combined Filter & Sort menu
        if !viewModel.highlights.isEmpty {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section("Filter") {
                        Picker("Type", selection: $viewModel.filter) {
                            Label("All", systemImage: "square.grid.2x2").tag(HighlightsViewModel.Filter.all)
                            Label("Games", systemImage: "baseball.diamond.bases").tag(HighlightsViewModel.Filter.game)
                            Label("Practice", systemImage: "figure.baseball").tag(HighlightsViewModel.Filter.practice)
                        }
                    }
                    Section("Sort") {
                        Picker("Sort", selection: $viewModel.sortOrder) {
                            Label("Newest", systemImage: "arrow.down").tag(HighlightsViewModel.SortOrder.newest)
                            Label("Oldest", systemImage: "arrow.up").tag(HighlightsViewModel.SortOrder.oldest)
                        }
                    }
                } label: {
                    Image(systemName: (viewModel.filter != .all || viewModel.sortOrder != .newest) ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
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
        if !viewModel.highlights.isEmpty {
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
        .disabled(viewModel.highlights.isEmpty)

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
                ErrorHandlerService.shared.handle(error, context: "HighlightsView.deleteClip(\(clipID))", showAlert: false)
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
        selection = Set(viewModel.highlights.map { $0.id })
    }

    private func batchDeleteSelected() {
        let clips = viewModel.highlights.filter { selection.contains($0.id) }
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
                ErrorHandlerService.shared.handle(error, context: "HighlightsView.batchDeleteSelected", showAlert: false)
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
            ErrorHandlerService.shared.handle(error, context: "HighlightsView.removeClipFromHighlights", showAlert: false)
        }
    }

    private func shareClip(_ clip: VideoClip) {
        guard FileManager.default.fileExists(atPath: clip.resolvedFilePath) else {
            ErrorHandlerService.shared.reportWarning(
                "Video file is missing.",
                context: "HighlightsView.shareClip",
                message: $errorAlertMessage,
                isPresented: $errorAlertShown
            )
            return
        }
        presentShareSheet(items: [clip.resolvedFileURL])
        Haptics.light()
    }

    private func presentShareSheet(items: [Any]) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
                    ?? scene.windows.first?.rootViewController else { return }
        let topVC = sequence(first: rootVC, next: { $0.presentedViewController })
            .first(where: { $0.presentedViewController == nil }) ?? rootVC
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let pop = vc.popoverPresentationController {
            pop.sourceView = topVC.view
            pop.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 0, height: 0)
            pop.permittedArrowDirections = []
        }
        topVC.present(vc, animated: true)
    }

    private func batchRemoveFromHighlights() {
        let clips = viewModel.highlights.filter { selection.contains($0.id) }
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
                ErrorHandlerService.shared.handle(error, context: "HighlightsView.batchRemoveFromHighlights", showAlert: false)
            }
        }

        selection.removeAll()
        withAnimation { editMode = .inactive }
    }

    private func batchUploadSelected() {
        let clips = viewModel.highlights.filter { selection.contains($0.id) }
        guard !clips.isEmpty, let athlete = athlete else { return }

        var queuedCount = 0
        for clip in clips {
            guard clip.needsUpload,
                  VideoCloudManager.shared.isUploading[clip.id] != true else { continue }
            UploadQueueManager.shared.enqueue(clip, athlete: athlete, priority: .high)
            queuedCount += 1
        }

        if queuedCount > 0 {
            Haptics.success()
        } else {
            Haptics.light()
        }

        selection.removeAll()
        withAnimation { editMode = .inactive }
    }

    private func batchShareSelected() {
        let clips = viewModel.highlights.filter { selection.contains($0.id) }
        guard !clips.isEmpty else { return }

        let fileURLs = clips.compactMap { clip -> URL? in
            guard FileManager.default.fileExists(atPath: clip.resolvedFilePath) else { return nil }
            return clip.resolvedFileURL
        }

        guard !fileURLs.isEmpty else {
            ErrorHandlerService.shared.reportWarning(
                "No video files are available to share.",
                context: "HighlightsView.batchShareSelected",
                message: $errorAlertMessage,
                isPresented: $errorAlertShown
            )
            return
        }

        presentShareSheet(items: fileURLs)
        Haptics.light()
    }
}

#Preview {
    HighlightsView(athlete: nil, currentTier: .free, hasCoachingAccess: false)
}
