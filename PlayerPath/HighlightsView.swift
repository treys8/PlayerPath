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
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var autoHighlightSettings = AutoHighlightSettings.shared
    @State private var selectedClip: VideoClip?
    @State private var selectedReel: HighlightReel?
    @State private var showingDeleteAlert = false
    @State private var clipToDelete: VideoClip?
    @State private var editMode: EditMode = .inactive
    @State private var showingAutoHighlightSettings = false
    @State private var stitchedReel: IdentifiableURL?

    /// Live source for v6.1 reels. Filtering to non-deleted at the @Query
    /// level keeps the view model out of stale-reel handling — soft-deleted
    /// rows just disappear from the grid the next time the SwiftData store
    /// invalidates this query (e.g. after ScoreHoleSheet saves).
    @Query(filter: #Predicate<HighlightReel> { !$0.isDeletedRemotely },
           sort: \HighlightReel.date, order: .reverse)
    private var allReels: [HighlightReel]

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

    /// Forwards the current athlete's clips + the athlete-scoped reels into
    /// the view model. Reels come from the @Query (cross-athlete); we filter
    /// here so the view model stays athlete-agnostic.
    private func updateViewModel() {
        let scopedReels: [HighlightReel]
        if let athleteID = athlete?.id {
            scopedReels = allReels.filter { $0.athleteID == athleteID }
        } else {
            scopedReels = []
        }
        viewModel.update(
            videoClips: athlete?.videoClips ?? [],
            reels: scopedReels
        )
    }

    /// Composite key for `.onChange` that reacts to highlight membership changes,
    /// not just add/remove. A count-only key misses an in-view "Remove from
    /// Highlights" or an unstar from the full-screen player — both flip
    /// `isHighlight` without changing the total clip count. Mirrors
    /// VideoClipsView.videoClipsChangeKey; Hasher avoids a per-body string alloc.
    private var highlightsChangeKey: Int {
        var hasher = Hasher()
        for clip in (athlete?.videoClips ?? []) {
            hasher.combine(clip.id)
            hasher.combine(clip.isHighlight)
            hasher.combine(clip.playResult?.type.rawValue)
        }
        return hasher.finalize()
    }

    /// Large-title text. Names the screen as "Highlights" (the old title was a
    /// bare "Name (count)" that never said what the screen was) while keeping
    /// the athlete context and count.
    private var navigationTitleText: String {
        guard let name = athlete?.name else { return "Highlights" }
        return "\(name)'s Highlights (\(viewModel.totalCount))"
    }

    var body: some View {
        contentView
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.surface)
            .navigationTitle(navigationTitleText)
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $viewModel.searchText, placement: .navigationBarDrawer(displayMode: .always))
            .toolbar {
                toolbarContent
            }
            .environment(\.editMode, $editMode)
        .fullScreenCover(item: $selectedClip) { clip in
            VideoPlayerView(clip: clip)
        }
        .fullScreenCover(item: $selectedReel) { reel in
            ReelPlayerView(reel: reel)
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
        .fullScreenCover(item: $stitchedReel) { item in
            StitchedReelPlayerView(url: item.url)
        }
        .task {
            migrateHitVideosToHighlights()
            updateViewModel()
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
        .onChange(of: highlightsChangeKey) { _, _ in updateViewModel() }
        .onChange(of: allReels.count) { _, _ in updateViewModel() }
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
        .onChange(of: scenePhase) { _, newPhase in
            // Re-evaluate today's reel eligibility when the app returns from
            // background — catches midnight rollover without a dedicated timer.
            if newPhase == .active { recomputeAll() }
        }
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

        var migratedVideos: [VideoClip] = []
        for video in allVideos {
            // Check if video has a hit play result but isn't marked as highlight
            if let playResult = video.playResult,
               playResult.type.isHighlight,
               !video.isHighlight {
                video.isHighlight = true
                video.needsSync = true
                migratedVideos.append(video)
            }
        }

        // Save if we migrated any videos
        if !migratedVideos.isEmpty {
            do {
                try modelContext.save()
                hasCompletedMigration = true
                // These legacy clips just became highlights; re-run the auto-upload gate so
                // any the save-time path skipped (e.g. "Highlights Only") upload now.
                for video in migratedVideos {
                    UploadQueueManager.shared.reevaluateAutoUploadAfterHighlightChange(video, context: modelContext)
                }
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

    private var isGolf: Bool { athlete?.sport == .golf }

    /// First reel in the current feed — anchors the one-time golf reel-grouping
    /// tip so it appears once content exists (when the "why is this one card?"
    /// confusion actually surfaces), not on the empty state.
    private var firstReelID: UUID? {
        for item in viewModel.feed {
            if case .reel(let reel) = item { return reel.id }
        }
        return nil
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
        } else if viewModel.feed.isEmpty {
            if hasActiveFilters && hasAnyHighlights {
                // Filtered empty state - user has highlights but filters exclude them
                FilteredEmptyStateView(
                    filterDescription: filterDescription,
                    onClearFilters: clearAllFilters
                )
            } else {
                // True empty state - no highlights at all
                EmptyHighlightsView(sport: athlete?.sport)
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
            if currentTier >= .plus,
               let athlete = athlete,
               athlete.sport != .golf,
               viewModel.todaysHighlightClips.count >= 2 {
                // Golf relies on its per-hole reels + per-round/per-season reels
                // instead of the baseball "Today's Reel" hero, so the two reel
                // models don't double-surface on the same screen.
                TodaysReelHeroCard(
                    athleteId: athlete.id,
                    clips: viewModel.todaysHighlightClips,
                    onPlay: { url in
                        stitchedReel = IdentifiableURL(url)
                    }
                )
                .padding(.horizontal, horizontalSizeClass == .regular ? 32 : 16)
                .padding(.top, 12)
            }
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: horizontalSizeClass == .regular ? 200 : 160, maximum: horizontalSizeClass == .regular ? 280 : 220), spacing: 16, alignment: .top)
                ],
                spacing: 16
            ) {
                ForEach(viewModel.feed) { item in
                    switch item {
                    case .clip(let clip):
                        VideoClipCard(
                            video: clip,
                            isSelectionMode: editMode == .active,
                            isSelected: selection.contains(clip.id),
                            showHighlight: false,
                            onPlay: {
                                if editMode == .inactive {
                                    selectedClip = clip
                                } else {
                                    toggleSelection(clip)
                                }
                            },
                            onDelete: {
                                clipToDelete = clip
                                showingDeleteAlert = true
                            },
                            onToggleSelection: { toggleSelection(clip) }
                        )
                        .onAppear { viewModel.onItemAppear(.clip(clip)) }
                    case .reel(let reel):
                        HighlightReelCard(
                            reel: reel,
                            onPlay: {
                                guard editMode == .inactive else { return }
                                selectedReel = reel
                            },
                            isDimmed: editMode == .active
                        )
                        .onboardingTip(GolfReelTip(), also: isGolf && reel.id == firstReelID)
                        .onAppear { viewModel.onItemAppear(.reel(reel)) }
                    }
                }
            }
            .padding(.vertical)
            .padding(.horizontal, horizontalSizeClass == .regular ? 32 : 16)
        }
        .refreshable {
            updateViewModel()
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Combined Season / Filter / Sort menu. Season lives here (rather than a
        // separate leading button) so the screen never shows two identical
        // filter glyphs competing for the same meaning.
        if !viewModel.feed.isEmpty {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section("Season") {
                        Picker("Season", selection: $viewModel.selectedSeasonFilter) {
                            Text("All Seasons").tag(String?.none)
                            ForEach(viewModel.availableSeasons) { season in
                                Text(season.displayName).tag(Optional(season.id.uuidString))
                            }
                            if viewModel.hasNoSeasonClips {
                                Text("No Season").tag(Optional("no_season"))
                            }
                        }
                    }
                    Section("Filter") {
                        let isGolf = athlete?.sport == .golf
                        Picker("Type", selection: $viewModel.filter) {
                            Label("All", systemImage: "square.grid.2x2").tag(HighlightsViewModel.Filter.all)
                            Label(isGolf ? "Rounds" : "Games", systemImage: isGolf ? "figure.golf" : "baseball.diamond.bases").tag(HighlightsViewModel.Filter.game)
                            Label("Practice", systemImage: "figure.run").tag(HighlightsViewModel.Filter.practice)
                        }
                    }
                    Section("Sort") {
                        Picker("Sort", selection: $viewModel.sortOrder) {
                            Label("Newest", systemImage: "arrow.down").tag(HighlightsViewModel.SortOrder.newest)
                            Label("Oldest", systemImage: "arrow.up").tag(HighlightsViewModel.SortOrder.oldest)
                        }
                    }
                } label: {
                    Image(systemName: (viewModel.selectedSeasonFilter != nil || viewModel.filter != .all || viewModel.sortOrder != .newest) ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("Filter and sort highlights")
            }
        }

        // Auto-highlight settings (Plus+, baseball/softball only — the panel
        // is batting/pitching rules; golf is manual-highlights-only).
        if currentTier >= .plus && athlete?.sport != .golf {
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
        if !viewModel.feed.isEmpty {
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
        vc.completionWithItemsHandler = { _, completed, _, _ in
            if completed {
                ReviewPromptManager.shared.requestReviewIfAppropriate()
            }
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

/// Wraps a URL so it can drive `.fullScreenCover(item:)`, which requires an
/// Identifiable. Identity is the URL itself so re-presenting the same reel is
/// stable. Using `item:` (vs. `isPresented:` + a separate optional) guarantees
/// the URL is non-nil when the cover renders — no content-less blank cover.
private struct IdentifiableURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
    init(_ url: URL) { self.url = url }
}

#Preview {
    HighlightsView(athlete: nil, currentTier: .free)
}
