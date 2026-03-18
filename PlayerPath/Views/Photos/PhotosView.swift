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

    private var hasActiveFilters: Bool {
        selectedDateRange != .allTime || selectedSeasonFilter != nil
    }

    private var columns: [GridItem] {
        let count = horizontalSizeClass == .regular ? 5 : 3
        return Array(repeating: GridItem(.flexible(), spacing: 2), count: count)
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
                emptyState
            } else {
                photosGrid
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search photos")
        .onAppear { AnalyticsService.shared.trackScreenView(screenName: "Photos", screenClass: "PhotosView") }
        .task { updatePhotosCache() }
        .onChange(of: activeFilter) { _, _ in updatePhotosCache() }
        .onChange(of: selectedSeasonFilter) { _, _ in updatePhotosCache() }
        .onChange(of: selectedDateRange) { _, _ in updatePhotosCache() }
        .onChange(of: searchText) { _, _ in updatePhotosCache() }
        .onChange(of: allPhotos) { _, _ in updatePhotosCache() }
        .navigationTitle("Photos")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingFilterSheet = true
                } label: {
                    Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingSourcePicker = true
                } label: {
                    Image(systemName: "plus")
                }
            }
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
            importPhotos(items)
            selectedPhotoItems = []
        }
        .overlay {
            if isImporting {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(.white)
                        Text("Importing...")
                            .font(.subheadline)
                            .foregroundColor(.white)
                    }
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
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
                                .fill(activeFilter == filter ? Color.blue : Color(.systemGray5))
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
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(cachedPhotos) { photo in
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
                }
            }
            .padding(.horizontal, 2)
        }
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
                Haptics.error()
            }
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) {
        Task {
            isImporting = true
            defer { isImporting = false }

            let service = PhotoPersistenceService()
            var savedCount = 0
            var failedCount = 0
            for item in items {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else {
                        failedCount += 1
                        continue
                    }
                    _ = try await service.savePhoto(
                        image: image,
                        context: modelContext,
                        athlete: athlete
                    )
                    savedCount += 1
                } catch {
                    failedCount += 1
                }
            }
            if failedCount > 0 && savedCount == 0 {
                Haptics.error()
            } else {
                Haptics.success()
            }
        }
    }

    private func deletePhoto(_ photo: Photo) {
        Task {
            PhotoPersistenceService().deletePhoto(photo, context: modelContext)
            Haptics.light()
        }
    }
}
