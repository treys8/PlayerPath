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

struct PhotosView: View {
    let athlete: Athlete
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

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

    // State
    @State private var activeFilter: PhotoFilter = .all
    @State private var searchText = ""
    @State private var selectedDateRange: DateRange = .allTime
    @State private var selectedSeasonFilter: String? = nil
    @State private var showingFilterSheet = false
    @State private var showingSourcePicker = false
    @State private var showingCamera = false
    @State private var showingLibraryPicker = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var isImporting = false
    @State private var importProgress: (current: Int, total: Int) = (0, 0)
    @State private var importTask: Task<Void, Never>?
    @State private var showImportToast = false
    @State private var importToastMessage = ""
    @State private var importToastType: ToastType = .success
    @State private var isSelecting = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var showingBulkDeleteConfirm = false
    @State private var tipsEnabled: Bool = true

    private var hasActiveFilters: Bool {
        selectedDateRange != .allTime || selectedSeasonFilter != nil
    }

    private var columns: [GridItem] {
        let count = horizontalSizeClass == .regular ? 3 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: count)
    }

    enum PhotoFilter: String, CaseIterable {
        case all = "All"
        case games = "Games"
        case practice = "Practice"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter chips
            filterBar

            if cachedPhotos.isEmpty {
                ScrollView {
                    emptyState
                }
                .refreshable { await refreshPhotos() }
            } else {
                photosGrid
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search photos")
        .onAppear { AnalyticsService.shared.trackScreenView(screenName: "Photos", screenClass: "PhotosView") }
        .task {
            loadTipsEnabled()
            updatePhotosCache()
        }
        .onChange(of: activeFilter) { _, _ in updatePhotosCache() }
        .onChange(of: selectedSeasonFilter) { _, _ in updatePhotosCache() }
        .onChange(of: selectedDateRange) { _, _ in updatePhotosCache() }
        .onChange(of: searchText) { _, _ in updatePhotosCache() }
        .onChange(of: allPhotos) { _, _ in updatePhotosCache() }
        .navigationTitle("Photos")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if isSelecting {
                    Button("Cancel") { exitSelectionMode() }
                } else {
                    Button("Done") { dismiss() }
                }
            }
            if isSelecting {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(selectedIDs.count == cachedPhotos.count ? "Deselect All" : "Select All") {
                        if selectedIDs.count == cachedPhotos.count {
                            selectedIDs.removeAll()
                        } else {
                            selectedIDs = Set(cachedPhotos.map { $0.id })
                        }
                    }
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
                        Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingCamera = true
                        } label: {
                            Label("Take Photo", systemImage: "camera")
                        }
                        Button {
                            showingLibraryPicker = true
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
                        Image(systemName: "ellipsis.circle")
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
        .confirmationDialog("Add Photo", isPresented: $showingSourcePicker) {
            Button("Take Photo") {
                showingCamera = true
            }
            Button("Choose from Library") {
                showingLibraryPicker = true
            }
            Button("Cancel", role: .cancel) { }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            ImagePicker(sourceType: .camera, allowsEditing: false) { image in
                savePhoto(image)
            }
            .ignoresSafeArea()
        }
        .photosPicker(
            isPresented: $showingLibraryPicker,
            selection: $selectedPhotoItems,
            maxSelectionCount: 20,
            matching: .images
        )
        .onChange(of: selectedPhotoItems) { _, items in
            guard !items.isEmpty else { return }
            startImport(items)
            selectedPhotoItems = []
        }
        .overlay {
            if isImporting {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView(
                            value: Double(importProgress.current),
                            total: Double(max(importProgress.total, 1))
                        )
                        .tint(.white)
                        .frame(width: 160)

                        Text("Importing \(importProgress.current) of \(importProgress.total)")
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .monospacedDigit()

                        Button(role: .destructive) {
                            importTask?.cancel()
                        } label: {
                            Text("Cancel")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .toast(isPresenting: $showImportToast, type: importToastType, message: importToastMessage, duration: 3.0)
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 8) {
            ForEach(PhotoFilter.allCases, id: \.self) { filter in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        activeFilter = filter
                    }
                } label: {
                    Text(filter.rawValue)
                        .font(.subheadline)
                        .fontWeight(activeFilter == filter ? .semibold : .regular)
                        .foregroundColor(activeFilter == filter ? .white : .secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(activeFilter == filter ? Color.brandNavy : Color(.systemGray5))
                        )
                }
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: - Photos Grid

    private var photosGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(cachedPhotos) { photo in
                    Group {
                        if isSelecting {
                            Button {
                                toggleSelection(photo.id)
                            } label: {
                                PhotoThumbnailCell(photo: photo) {
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
                            NavigationLink {
                                PhotoDetailView(photo: photo) {
                                    deletePhoto(photo)
                                }
                            } label: {
                                PhotoThumbnailCell(photo: photo) {
                                    deletePhoto(photo)
                                }
                            }
                            .buttonStyle(.plain)
                            .photoOptionsTip(isFirst: photo.id == cachedPhotos.first?.id, tipsEnabled: tipsEnabled)
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
        }
        .refreshable { await refreshPhotos() }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        EmptyStateView(
            systemImage: "photo.on.rectangle.angled",
            title: "No Photos Yet",
            message: "Tap + to take a photo or choose from your library",
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

                let seasons = athlete.seasons ?? []
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
            try? await SyncCoordinator.shared.syncPhotos(for: user)
        }
        updatePhotosCache()
    }

    private func loadTipsEnabled() {
        if let prefs = try? modelContext.fetch(FetchDescriptor<UserPreferences>()).first {
            tipsEnabled = prefs.showOnboardingTips
        } else {
            tipsEnabled = true
        }
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
            filtered = filtered.filter { photo in
                (photo.game?.opponent.lowercased().contains(query) ?? false) ||
                (photo.caption?.lowercased().contains(query) ?? false)
            }
        }

        cachedPhotos = filtered
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

    private func startImport(_ items: [PhotosPickerItem]) {
        importProgress = (0, items.count)
        isImporting = true
        importTask = Task {
            await importPhotos(items)
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        let service = PhotoPersistenceService()
        var savedCount = 0
        var failedCount = 0

        for (index, item) in items.enumerated() {
            if Task.isCancelled { break }
            importProgress = (index + 1, items.count)

            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    failedCount += 1
                    continue
                }
                // CGImageSource pipeline: writes raw data to disk and converts
                // via ImageIO — never decodes a full UIImage bitmap into memory.
                _ = try await service.savePhotoFromData(
                    data,
                    context: modelContext,
                    athlete: athlete
                )
                savedCount += 1
            } catch {
                ErrorHandlerService.shared.handle(error, context: "PhotosView.importPhoto", showAlert: false)
                failedCount += 1
            }
        }

        isImporting = false
        importTask = nil
        showImportResult(saved: savedCount, failed: failedCount)
    }

    private func showImportResult(saved: Int, failed: Int) {
        if saved == 0 && failed == 0 {
            return // cancelled before any work
        } else if saved > 0 && failed == 0 {
            importToastType = .success
            importToastMessage = saved == 1 ? "Photo imported" : "\(saved) photos imported"
        } else if saved > 0 && failed > 0 {
            importToastType = .warning
            importToastMessage = "Imported \(saved) photos. \(failed) failed."
        } else {
            importToastType = .warning
            importToastMessage = "Could not import photos."
        }
        showImportToast = true
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
                             isSelected ? Color.brandNavy : Color.black.opacity(0.35))
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
}
