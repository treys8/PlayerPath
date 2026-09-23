//
//  PhotosView.swift
//  PlayerPath
//
//  Grid view of all photos for an athlete. Supports camera capture
//  and photo library import with optional game/practice tagging.
//

import SwiftUI
import SwiftData
import PhotosUI
import TipKit

struct PhotosView: View {
    let athlete: Athlete
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.ppAccent) private var ppAccent
    private var activeSport: Season.SportType { athlete.sportType }

    private func chipLabel(for filter: PhotoFilter) -> String {
        switch filter {
        case .games where activeSport == .golf: return "Tournaments"
        default: return filter.rawValue
        }
    }

    // Query photos for the current athlete only
    private let athleteID: UUID
    @Query private var allPhotos: [Photo]

    init(athlete: Athlete) {
        self.athlete = athlete
        let id = athlete.id
        self.athleteID = id
        self._allPhotos = Query(
            filter: #Predicate<Photo> { $0.athlete?.id == id },
            sort: [SortDescriptor(\Photo.createdAt, order: .reverse)]
        )
    }

    @State private var cachedPhotos: [Photo] = []
    /// `cachedPhotos` bucketed by month. Built alongside the cache so the grid
    /// doesn't regroup on every body evaluation.
    @State private var cachedSections: [PhotoMonthSection] = []
    @State private var searchDebounceTask: Task<Void, Never>?

    // State
    @State private var activeFilter: PhotoFilter = .all
    @State private var searchText = ""
    @State private var selectedDateRange: DateRange = .allTime
    @State private var selectedSeasonFilter: String? = nil
    @State private var showingFilterSheet = false
    @State private var showingSourcePicker = false
    @State private var showingCamera = false
    /// Opens the shared bulk-import pipeline (`BulkPhotoImportAttach`), which
    /// resets this binding itself. Named to match JournalView's trigger.
    @State private var photoImportTrigger = false
    // Toast for in-place actions (tagging). Import results are rendered by
    // BulkPhotoImportAttach's own overlay, so the two can never collide — this
    // screen used to drive both through one set of state.
    @State private var showActionToast = false
    @State private var actionToastMessage = ""
    @State private var actionToastType: ToastType = .success
    @State private var isSelecting = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var showingBulkDeleteConfirm = false
    @State private var showingBatchTagSheet = false
    /// Photo tapped to open the full-screen swipeable viewer (over cachedPhotos).
    @State private var viewerPhoto: Photo?
    /// A property-only edit (star, tag, caption) landed while the viewer was
    /// open. Refreshing then could pull the visible page out of the pager, so
    /// the refresh waits until the viewer closes.
    @State private var needsRefreshAfterViewer = false
    @Namespace private var photoNS
    @AppStorage("photos.layoutMode") private var layoutModeRaw: String = LayoutMode.card.rawValue
    private let photoOptionsTip = PhotoOptionsTip()
    private let layoutModeTip = LayoutModeTip()

    private var layoutMode: LayoutMode {
        LayoutMode(rawValue: layoutModeRaw) ?? .card
    }

    private var hasActiveFilters: Bool {
        selectedDateRange != .allTime || selectedSeasonFilter != nil
    }

    /// Any narrowing at all — chip, sheet filters, or search. Decides between
    /// the "No Results" state and the true "No Photos Yet" empty state.
    private var isFiltering: Bool {
        activeFilter != .all
            || hasActiveFilters
            || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Whether the active sport has any photos before filtering. Same sport
    /// rule as `updatePhotosCache` (seasonless photos count for both sports).
    private var hasPhotosForSport: Bool {
        allPhotos.contains { photo in
            guard let season = photo.season else { return true }
            return (season.sport ?? .baseball) == activeSport
        }
    }

    private var filterDescription: String {
        var parts: [String] = []
        if activeFilter != .all { parts.append(chipLabel(for: activeFilter)) }
        if let seasonID = selectedSeasonFilter,
           let season = (athlete.seasons ?? []).first(where: { $0.id.uuidString == seasonID }) {
            parts.append("season: \(season.displayName)")
        }
        if selectedDateRange != .allTime { parts.append(selectedDateRange.displayName) }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty { parts.append("search: \"\(query)\"") }
        return parts.isEmpty ? "your filters" : parts.joined(separator: ", ")
    }

    private func clearAllFilters() {
        Haptics.light()
        withAnimation {
            activeFilter = .all
            selectedDateRange = .allTime
            selectedSeasonFilter = nil
            searchText = ""
        }
    }

    /// Change key over the properties the filters read. `onChange(of: allPhotos)`
    /// only fires when rows are added or removed — starring, tagging, or
    /// captioning one photo leaves the array equal, so the grid went stale.
    private var photosChangeKey: Int {
        var hasher = Hasher()
        for photo in allPhotos {
            hasher.combine(photo.id)
            hasher.combine(photo.isHighlight)
            hasher.combine(photo.game?.id)
            hasher.combine(photo.practice?.id)
            hasher.combine(photo.season?.id)
            hasher.combine(photo.caption)
        }
        return hasher.finalize()
    }

    private var shouldShowHero: Bool {
        activeFilter == .all
            && selectedDateRange == .allTime
            && selectedSeasonFilter == nil
            && searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isSelecting
            && layoutMode == .card
            && cachedPhotos.count >= 4
    }

    /// Month sections under the hero. The hero is `cachedPhotos.first`, so it
    /// is pulled out of the first section when shown.
    private var gridSections: [PhotoMonthSection] {
        if shouldShowHero, let hero = cachedPhotos.first {
            return PhotoMonthSection.removing(hero.id, from: cachedSections)
        }
        return cachedSections
    }

    private var gridSpacing: CGFloat {
        layoutMode == .dense ? 1 : 10
    }

    private var columns: [GridItem] {
        let count: Int
        switch layoutMode {
        case .card:
            count = horizontalSizeClass == .regular ? 3 : 2
        case .dense:
            count = horizontalSizeClass == .regular ? 5 : 3
        }
        return Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: count)
    }

    enum PhotoFilter: String, CaseIterable {
        case all = "All"
        case games = "Games"
        case practice = "Practice"
        case highlights = "Favorites"
        case untagged = "Untagged"
    }

    enum LayoutMode: String, CaseIterable {
        case card
        case dense
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter chips
            filterBar

            // Cloud storage is full and the last sync skipped photo uploads. Reading
            // the count here (SyncCoordinator is @Observable) refreshes the banner
            // automatically as passes run, and clears it once uploads resume.
            if SyncCoordinator.shared.photosBlockedByQuota > 0 {
                PhotoBackupBlockedBanner(count: SyncCoordinator.shared.photosBlockedByQuota) {
                    NotificationCenter.default.post(name: .navigateToCloudStorage, object: nil)
                }
                .padding(.bottom, 8)
            }

            if cachedPhotos.isEmpty {
                ScrollView {
                    if isFiltering && hasPhotosForSport {
                        FilteredEmptyStateView(
                            filterDescription: filterDescription,
                            onClearFilters: clearAllFilters
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    } else {
                        emptyState
                    }
                }
                .refreshable { await refreshPhotos() }
            } else {
                photosGrid
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search photos")
        .onAppear { AnalyticsService.shared.trackScreenView(screenName: "Photos", screenClass: "PhotosView") }
        .task {
            updatePhotosCache()
        }
        .onChange(of: activeFilter) { _, _ in updatePhotosCache() }
        .onChange(of: selectedSeasonFilter) { _, _ in updatePhotosCache() }
        .onChange(of: selectedDateRange) { _, _ in updatePhotosCache() }
        .onChange(of: searchText) { _, _ in debouncedSearchUpdate() }
        // Rows added/removed. With the viewer open, only strip deleted rows (a
        // deleted Photo left in the pager's array traps) and defer the full
        // refilter — refiltering now would apply any deferred edit (e.g. an
        // un-star under Favorites) and pull the visible page out of the pager.
        .onChange(of: allPhotos) { _, _ in
            if viewerPhoto != nil {
                removeDeletedPhotosFromCache()
                needsRefreshAfterViewer = true
            } else {
                updatePhotosCache()
            }
        }
        .onChange(of: photosChangeKey) { _, _ in
            if viewerPhoto != nil {
                needsRefreshAfterViewer = true
            } else {
                updatePhotosCache()
            }
        }
        .onChange(of: viewerPhoto) { _, newValue in
            if newValue == nil && needsRefreshAfterViewer {
                needsRefreshAfterViewer = false
                updatePhotosCache()
            }
        }
        .onChange(of: activeSport) { _, _ in updatePhotosCache() }
        .tabRootNavigationBar(title: "Photos")
        .toolbar {
            if isSelecting {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { exitSelectionMode() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button(selectedIDs.count == cachedPhotos.count ? "Deselect All" : "Select All") {
                        if selectedIDs.count == cachedPhotos.count {
                            selectedIDs.removeAll()
                        } else {
                            selectedIDs = Set(cachedPhotos.map { $0.id })
                        }
                    }
                }
            }
            if isSelecting {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        bulkToggleFavoriteSelected()
                    } label: {
                        Image(systemName: allSelectedAreFavorites ? "star.slash" : "star")
                    }
                    .disabled(selectedIDs.isEmpty)
                    .accessibilityLabel(allSelectedAreFavorites ? "Remove selected from favorites" : "Favorite selected photos")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingBatchTagSheet = true
                    } label: {
                        Image(systemName: "tag")
                    }
                    .disabled(selectedIDs.isEmpty)
                    .accessibilityLabel("Tag selected photos")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        showingBulkDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(selectedIDs.isEmpty)
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingFilterSheet = true
                    } label: {
                        Image(systemName: ToolbarSymbol.filter(active: hasActiveFilters))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        toggleLayoutMode()
                        layoutModeTip.invalidate(reason: .actionPerformed)
                    } label: {
                        Image(systemName: layoutMode == .card ? "square.grid.3x3.fill" : "square.grid.2x2")
                    }
                    .accessibilityLabel(layoutMode == .card ? "Switch to dense grid" : "Switch to card grid")
                    .onboardingTip(layoutModeTip, arrowEdge: .top, also: !cachedPhotos.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if PhotoCameraAvailability.isCameraAvailable {
                            Button {
                                showingCamera = true
                            } label: {
                                Label("Take Photo", systemImage: "camera")
                            }
                        }
                        Button {
                            photoImportTrigger = true
                        } label: {
                            Label("Choose from Library", systemImage: "photo.on.rectangle")
                        }
                        if !cachedPhotos.isEmpty {
                            Divider()
                            Button {
                                isSelecting = true
                            } label: {
                                Label("Select", systemImage: "checkmark.circle")
                            }
                        }
                    } label: {
                        Image(systemName: ToolbarSymbol.more)
                    }
                }
            }
        }
        .confirmationDialog(
            selectedIDs.count == 1 ? "Delete 1 photo?" : "Delete \(selectedIDs.count) photos?",
            isPresented: $showingBulkDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { bulkDeleteSelected() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This can't be undone.")
        }
        .sheet(isPresented: $showingFilterSheet) {
            filterSheet
        }
        .sheet(isPresented: $showingBatchTagSheet) {
            BatchPhotoTagSheet(athlete: athlete, photoCount: selectedIDs.count) { target in
                bulkTagSelected(target)
            }
        }
        .confirmationDialog("Add Photo", isPresented: $showingSourcePicker) {
            if PhotoCameraAvailability.isCameraAvailable {
                Button("Take Photo") {
                    showingCamera = true
                }
            }
            Button("Choose from Library") {
                photoImportTrigger = true
            }
            Button("Cancel", role: .cancel) { }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            PhotoCameraView(
                onPhotoCaptured: { image in
                    savePhoto(image)
                    showingCamera = false
                },
                onCancel: { showingCamera = false }
            )
        }
        // Athlete-only: no season/game/practice, which is exactly what gives this
        // screen capture-date season matching and the past-season backfill prompt
        // it never had. The private import path this replaced passed no season at
        // all, so every photo landed on the CURRENT season regardless of when it
        // was taken.
        .bulkPhotoImportAttach(athlete: athlete, trigger: $photoImportTrigger)
        .toast(isPresenting: $showActionToast, type: actionToastType, message: actionToastMessage, duration: 3.0)
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        PPFilterPillRow(
            options: PhotoFilter.allCases,
            title: { chipLabel(for: $0) },
            selection: $activeFilter
        )
        .padding(.bottom, 8)
    }

    // MARK: - Photos Grid

    private var photosGrid: some View {
        ScrollView {
            VStack(spacing: 16) {
                if shouldShowHero, let hero = cachedPhotos.first {
                    Button {
                        viewerPhoto = hero
                    } label: {
                        PhotoHeroCell(
                            photo: hero,
                            onDelete: { deletePhoto(hero) },
                            onContextMenuOpened: {
                                photoOptionsTip.invalidate(reason: .actionPerformed)
                            }
                        )
                        .photoTransitionSource(hero.id, in: photoNS)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                    .onboardingTip(photoOptionsTip, arrowEdge: .top)
                }

                LazyVGrid(columns: columns, spacing: gridSpacing, pinnedViews: [.sectionHeaders]) {
                    ForEach(gridSections) { section in
                        Section {
                            ForEach(section.photos) { photo in
                                gridCell(photo)
                            }
                        } header: {
                            monthHeader(section.title)
                        }
                    }
                }
                .padding(.horizontal, layoutMode == .dense ? 0 : 10)
            }
        }
        .refreshable { await refreshPhotos() }
        // Swipe spans the full ordered set (hero is cachedPhotos.first, grid is
        // the rest), so present the viewer over cachedPhotos for both entry points.
        .photoViewer($viewerPhoto, in: cachedPhotos, namespace: photoNS, onDelete: deletePhoto)
    }

    @ViewBuilder
    private func gridCell(_ photo: Photo) -> some View {
        if isSelecting {
            Button {
                toggleSelection(photo.id)
            } label: {
                PhotoThumbnailCell(photo: photo, style: cellStyle) {
                    deletePhoto(photo)
                }
                .overlay(alignment: .topTrailing) {
                    selectionIndicator(isSelected: selectedIDs.contains(photo.id))
                        .padding(8)
                }
                .opacity(selectedIDs.contains(photo.id) ? 0.75 : 1.0)
            }
            .buttonStyle(.plain)
        } else {
            Button {
                viewerPhoto = photo
            } label: {
                PhotoThumbnailCell(
                    photo: photo,
                    style: cellStyle,
                    onDelete: { deletePhoto(photo) },
                    onContextMenuOpened: {
                        photoOptionsTip.invalidate(reason: .actionPerformed)
                    }
                )
                .photoTransitionSource(photo.id, in: photoNS)
            }
            .buttonStyle(.plain)
            .onboardingTip(photoOptionsTip, arrowEdge: .top, also: !shouldShowHero && photo.id == cachedPhotos.first?.id)
        }
    }

    private func monthHeader(_ title: String) -> some View {
        Text(title)
            .font(.ppCallout)
            .fontWeight(.semibold)
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, layoutMode == .dense ? 12 : 2)
            .padding(.vertical, 8)
            .background(Theme.surface)
            .accessibilityAddTraits(.isHeader)
    }

    private var cellStyle: PhotoThumbnailCell.Style {
        layoutMode == .dense ? .dense : .card
    }

    private func toggleLayoutMode() {
        layoutModeRaw = (layoutMode == .card ? LayoutMode.dense : LayoutMode.card).rawValue
    }

    // MARK: - Empty State

    private var isMultiSport: Bool {
        Set((athlete.seasons ?? []).map { $0.sport ?? .baseball }).count > 1
    }

    private var emptyState: some View {
        EmptyStateView(
            systemImage: "photo.on.rectangle.angled",
            title: isMultiSport ? "No \(activeSport.displayName) Photos Yet" : "No Photos Yet",
            message: "Take a photo or add some from your library.",
            actionTitle: "Add Photo",
            action: { showingSourcePicker = true }
        )
        .frame(maxHeight: .infinity)
    }

    // MARK: - Filter Sheet

    private var filterSheet: some View {
        NavigationStack {
            Form {
                Section("Date Range") {
                    Picker("Range", selection: $selectedDateRange) {
                        ForEach(DateRange.allCases) { range in
                            Text(range.displayName).tag(range)
                        }
                    }
                    .pickerStyle(.inline)
                }

                // Scope the season dropdown to the active sport so a golf-mode
                // filter sheet doesn't list baseball seasons (and vice versa).
                let seasons = (athlete.seasons ?? []).filter { $0.sport == activeSport }
                if !seasons.isEmpty {
                    Section("Season") {
                        Picker("Season", selection: $selectedSeasonFilter) {
                            Text("All Seasons").tag(nil as String?)
                            ForEach(seasons.sorted(by: { ($0.startDate ?? Date.distantPast) > ($1.startDate ?? Date.distantPast) })) { season in
                                Text(season.displayName).tag(season.id.uuidString as String?)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Filter Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        selectedDateRange = .allTime
                        selectedSeasonFilter = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingFilterSheet = false }
                }
            }
        }
    }

    // MARK: - Cache

    private func refreshPhotos() async {
        if let user = athlete.user {
            do {
                try await SyncCoordinator.shared.syncPhotos(for: user)
            } catch {
                ErrorHandlerService.shared.handle(error, context: "PhotosView.refreshPhotos", showAlert: false)
            }
        }
        updatePhotosCache()
    }

    private func updatePhotosCache() {
        var filtered = Array(allPhotos)

        // Content type filter
        switch activeFilter {
        case .all:
            break
        case .games:
            filtered = filtered.filter { $0.game != nil }
        case .practice:
            filtered = filtered.filter { $0.practice != nil }
        case .highlights:
            filtered = filtered.filter { $0.isHighlight }
        case .untagged:
            filtered = filtered.filter { $0.game == nil && $0.practice == nil }
        }

        // Sport filter — hide photos belonging to seasons of the other sport.
        // Seasonless photos (headshots, trophies, no-season imports) pass through
        // under both sports so toggling doesn't make them disappear.
        filtered = filtered.filter { photo in
            guard let season = photo.season else { return true }
            return (season.sport ?? .baseball) == activeSport
        }

        // Season filter
        if let seasonFilter = selectedSeasonFilter {
            filtered = filtered.filter { photo in
                if seasonFilter == "no_season" {
                    return photo.season == nil
                } else {
                    return photo.season?.id.uuidString == seasonFilter
                }
            }
        }

        // Date range filter
        if selectedDateRange != .allTime {
            let range = selectedDateRange.dateRange
            filtered = filtered.filter { photo in
                guard let date = photo.createdAt else { return false }
                return date >= range.start && date <= range.end
            }
        }

        // Text search
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            filtered = filtered.filter { photoMatchesSearch($0, query: query) }
        }

        let sections = PhotoMonthSection.build(from: filtered)
        cachedSections = sections
        // Flatten back from the sections so the viewer pages in exactly the
        // order the grid shows (undated photos sit at the end in both).
        cachedPhotos = sections.flatMap(\.photos)

        // Drop selections the new filter hid, so the delete/tag/favorite counts
        // only ever cover photos the user can see.
        if isSelecting {
            selectedIDs.formIntersection(cachedPhotos.map(\.id))
        }
    }

    /// Drops rows deleted from the store without refiltering anything else.
    /// `isDeleted` / `modelContext` are safe to read on a deleted model, unlike
    /// its attributes. Closes the viewer if nothing is left to show.
    private func removeDeletedPhotosFromCache() {
        func isLive(_ photo: Photo) -> Bool { !photo.isDeleted && photo.modelContext != nil }
        guard cachedPhotos.contains(where: { !isLive($0) }) else { return }
        cachedPhotos = cachedPhotos.filter(isLive)
        cachedSections = PhotoMonthSection.build(from: cachedPhotos)
        if cachedPhotos.isEmpty { viewerPhoto = nil }
    }

    private static let searchDateFormatter = DateFormatter.mediumDate
    private static let searchShortFormatter = DateFormatter.compactDate

    /// Mirrors the Videos search: caption, event (opponent / course / location /
    /// tournament), season, "practice", and the date in two formats.
    private func photoMatchesSearch(_ photo: Photo, query: String) -> Bool {
        func has(_ text: String?) -> Bool { text?.lowercased().contains(query) ?? false }
        if has(photo.caption) { return true }
        if let game = photo.game {
            if has(game.opponent) || has(game.location) || has(game.tournament?.name) { return true }
        }
        if let practice = photo.practice {
            if "practice".contains(query) || has(practice.course) { return true }
        }
        if has(photo.season?.displayName) { return true }
        if let date = photo.createdAt {
            if has(Self.searchDateFormatter.string(from: date)) || has(Self.searchShortFormatter.string(from: date)) {
                return true
            }
        }
        return false
    }

    /// Debounce so typing doesn't refilter + regroup on every keystroke.
    private func debouncedSearchUpdate() {
        searchDebounceTask?.cancel()
        searchDebounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            updatePhotosCache()
        }
    }

    // MARK: - Actions

    private func savePhoto(_ image: UIImage) {
        Task {
            do {
                _ = try await PhotoPersistenceService().savePhoto(
                    image: image,
                    context: modelContext,
                    athlete: athlete
                )
                Haptics.success()
            } catch {
                ErrorHandlerService.shared.handle(error, context: "PhotosView.savePhoto", showAlert: false)
            }
        }
    }

    private func deletePhoto(_ photo: Photo) {
        Task {
            PhotoPersistenceService().deletePhoto(photo, context: modelContext)
            Haptics.light()
        }
    }

    // MARK: - Selection

    @ViewBuilder
    private func selectionIndicator(isSelected: Bool) -> some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title2)
            .symbolRenderingMode(.palette)
            .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.9),
                             isSelected ? ppAccent : Color.black.opacity(0.35))
            .background(Circle().fill(Color.black.opacity(0.15)).blur(radius: 2))
    }

    private func toggleSelection(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
        Haptics.light()
    }

    private func exitSelectionMode() {
        isSelecting = false
        selectedIDs.removeAll()
    }

    private func bulkDeleteSelected() {
        let ids = selectedIDs
        let toDelete = cachedPhotos.filter { ids.contains($0.id) }
        Task {
            let service = PhotoPersistenceService()
            for photo in toDelete {
                service.deletePhoto(photo, context: modelContext)
            }
            Haptics.success()
            exitSelectionMode()
        }
    }

    private var allSelectedAreFavorites: Bool {
        let selected = cachedPhotos.filter { selectedIDs.contains($0.id) }
        return !selected.isEmpty && selected.allSatisfy(\.isHighlight)
    }

    /// Favorite every selected photo, or un-favorite them all when every one
    /// already is — the same toggle rule as Photos.app.
    private func bulkToggleFavoriteSelected() {
        let toUpdate = cachedPhotos.filter { selectedIDs.contains($0.id) }
        guard !toUpdate.isEmpty else { exitSelectionMode(); return }
        let makeFavorite = !toUpdate.allSatisfy(\.isHighlight)
        for photo in toUpdate where photo.isHighlight != makeFavorite {
            photo.isHighlight = makeFavorite
            photo.needsSync = true
        }
        ErrorHandlerService.shared.saveContext(modelContext, caller: "PhotosView.bulkToggleFavorite")
        Haptics.success()

        let count = toUpdate.count
        actionToastType = .success
        actionToastMessage = makeFavorite
            ? (count == 1 ? "Added to favorites" : "\(count) photos added to favorites")
            : (count == 1 ? "Removed from favorites" : "\(count) photos removed from favorites")
        showActionToast = true

        exitSelectionMode()
        updatePhotosCache()
    }

    /// Apply one event target to every selected photo, then a single save.
    /// Synchronous on purpose (unlike bulkDeleteSelected) — setting the
    /// relationships + saveContext are @MainActor work with nothing to await.
    private func bulkTagSelected(_ target: EventTargetPicker.Target) {
        let ids = selectedIDs
        let toTag = cachedPhotos.filter { ids.contains($0.id) }
        guard !toTag.isEmpty else { exitSelectionMode(); return }

        var clearing = false
        for photo in toTag {
            switch target {
            case .game(let game):
                photo.game = game
                photo.practice = nil
                // Realign season only when the event has one, so we never blank
                // out a photo's season on an orphaned game/round (matches the
                // single-photo PhotoTagSheet rule).
                if let season = game.season { photo.season = season }
            case .practice(let practice):
                photo.practice = practice
                photo.game = nil
                if let season = practice.season { photo.season = season }
            case .clear:
                photo.game = nil
                photo.practice = nil
                clearing = true
            }
            photo.needsSync = true
        }

        ErrorHandlerService.shared.saveContext(modelContext, caller: "PhotosView.bulkTagSelected")
        Haptics.success()

        let count = toTag.count
        actionToastType = .success
        actionToastMessage = clearing
            ? (count == 1 ? "Removed from event" : "\(count) photos removed from event")
            : (count == 1 ? "Photo tagged" : "\(count) photos tagged")
        showActionToast = true

        exitSelectionMode()
        // A relationship-only mutation doesn't change the [Photo] query result,
        // so onChange(of: allPhotos) won't fire — refresh the cache explicitly
        // (bulkDeleteSelected dodges this because it removes rows).
        updatePhotosCache()
    }
}
