//
//  AdvancedSearchView.swift
//  PlayerPath
//
//  Advanced search and filtering across videos, games, and practices
//

import SwiftUI
import SwiftData

struct AdvancedSearchView: View {
    let athlete: Athlete

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var selectedContentType: ContentType = .videos
    @State private var selectedDateRange: DateRange = .allTime
    @State private var selectedSeason: Season?
    @State private var selectedGame: Game?
    @State private var selectedPlayResults: Set<PlayResultType> = []
    @State private var highlightsOnly = false
    @State private var showingFilters = false
    @State private var savedSearches: [SavedSearch] = []
    @State private var showingSaveSearch = false
    @State private var newSearchName = ""

    // Cached filtered results (updated via updateFilteredResults)
    @State private var cachedFilteredVideos: [VideoClip] = []
    @State private var cachedFilteredGames: [Game] = []
    @State private var cachedFilteredPractices: [Practice] = []
    @State private var cachedFilteredPhotos: [Photo] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search Bar
                searchBarView

                // Content Type Selector
                contentTypeSelectorView

                // Active Filters Summary
                if hasActiveFilters {
                    activeFiltersSummaryView
                }

                // Results
                resultsView
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingFilters.toggle()
                    } label: {
                        Image(systemName: showingFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .sheet(isPresented: $showingFilters) {
                filtersSheet
            }
            .sheet(isPresented: $showingSaveSearch) {
                saveSearchSheet
            }
            .onAppear {
                loadSavedSearches()
                updateFilteredResults()
            }
            .onChange(of: searchText) { _, _ in
                updateFilteredResults()
            }
            .onChange(of: selectedContentType) { _, _ in
                updateFilteredResults()
            }
            .onChange(of: selectedDateRange) { _, _ in
                updateFilteredResults()
            }
            .onChange(of: selectedSeason) { _, _ in
                updateFilteredResults()
            }
            .onChange(of: selectedGame) { _, _ in
                updateFilteredResults()
            }
            .onChange(of: selectedPlayResults) { _, _ in
                updateFilteredResults()
            }
            .onChange(of: highlightsOnly) { _, _ in
                updateFilteredResults()
            }
        }
    }

    // MARK: - Search Bar

    private var searchBarView: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search \(selectedContentType.displayName.lowercased())...", text: $searchText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { updateFilteredResults() }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding()
    }

    // MARK: - Content Type Selector

    private var contentTypeSelectorView: some View {
        Picker("Content Type", selection: $selectedContentType) {
            ForEach(ContentType.allCases) { type in
                Label(type.displayName, systemImage: type.icon)
                    .tag(type)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }

    // MARK: - Active Filters

    private var hasActiveFilters: Bool {
        selectedDateRange != .allTime ||
        selectedSeason != nil ||
        (selectedContentType == .videos && (selectedGame != nil || !selectedPlayResults.isEmpty || highlightsOnly))
    }

    private var activeFiltersSummaryView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if selectedDateRange != .allTime {
                    FilterChip(text: selectedDateRange.displayName) {
                        selectedDateRange = .allTime
                    }
                }

                if let season = selectedSeason {
                    FilterChip(text: season.displayName) {
                        selectedSeason = nil
                    }
                }

                if selectedContentType == .videos {
                    if let game = selectedGame {
                        FilterChip(text: "vs \(game.opponent)") {
                            selectedGame = nil
                        }
                    }

                    if highlightsOnly {
                        FilterChip(text: "Highlights only") {
                            highlightsOnly = false
                        }
                    }

                    if !selectedPlayResults.isEmpty {
                        FilterChip(text: "\(selectedPlayResults.count) play types") {
                            selectedPlayResults.removeAll()
                        }
                    }
                }

                Button {
                    clearAllFilters()
                } label: {
                    Text("Clear all")
                        .font(.labelMedium)
                        .foregroundColor(.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(16)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.systemGray6).opacity(0.5))
    }

    // MARK: - Results

    private var resultsView: some View {
        Group {
            switch selectedContentType {
            case .videos:
                videosResultsView
            case .games:
                gamesResultsView
            case .practices:
                practicesResultsView
            case .photos:
                photosResultsView
            }
        }
    }

    private var videosResultsView: some View {
        let results = cachedFilteredVideos

        return Group {
            if results.isEmpty {
                emptyResultsView
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        // Results header with count and save button
                        resultsHeaderView(count: results.count)

                        ForEach(results) { video in
                            VideoSearchResultCard(video: video)
                        }
                    }
                    .padding()
                }
            }
        }
    }

    private var gamesResultsView: some View {
        let results = cachedFilteredGames

        return Group {
            if results.isEmpty {
                emptyResultsView
            } else {
                List {
                    Section {
                        resultsHeaderView(count: results.count)
                    }

                    ForEach(results) { game in
                        NavigationLink {
                            GameDetailView(game: game)
                        } label: {
                            GameSearchResultRow(game: game)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private var practicesResultsView: some View {
        let results = cachedFilteredPractices

        return Group {
            if results.isEmpty {
                emptyResultsView
            } else {
                List {
                    Section {
                        resultsHeaderView(count: results.count)
                    }

                    ForEach(results) { practice in
                        PracticeSearchResultRow(practice: practice)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private var photosResultsView: some View {
        let results = cachedFilteredPhotos

        return Group {
            if results.isEmpty {
                emptyResultsView
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        resultsHeaderView(count: results.count)

                        ForEach(results) { photo in
                            PhotoSearchResultCard(photo: photo)
                        }
                    }
                    .padding()
                }
            }
        }
    }

    private func resultsHeaderView(count: Int) -> some View {
        HStack {
            Text("\(count) result\(count == 1 ? "" : "s")")
                .font(.bodyMedium)
                .foregroundColor(.secondary)

            Spacer()

            if hasActiveFilters && count > 0 {
                Button {
                    showingSaveSearch = true
                } label: {
                    Label("Save Search", systemImage: "bookmark")
                        .font(.labelMedium)
                }
            }
        }
    }

    private var emptyResultsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No results found")
                .font(.headingLarge)
                .foregroundColor(.secondary)

            Text("Try adjusting your search or filters")
                .font(.bodyMedium)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if hasActiveFilters {
                Button {
                    clearAllFilters()
                } label: {
                    Text("Clear filters")
                        .font(.labelLarge)
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Filters Sheet

    private var filtersSheet: some View {
        NavigationStack {
            Form {
                // Date Range
                Section("Date Range") {
                    Picker("Range", selection: $selectedDateRange) {
                        ForEach(DateRange.allCases) { range in
                            Text(range.displayName).tag(range)
                        }
                    }
                    .pickerStyle(.inline)
                }

                // Season Filter
                let seasons = athlete.seasons ?? []
                if !seasons.isEmpty {
                    Section("Season") {
                        Picker("Season", selection: $selectedSeason) {
                            Text("All Seasons").tag(nil as Season?)
                            ForEach(seasons.sorted(by: { ($0.startDate ?? Date.distantPast) > ($1.startDate ?? Date.distantPast) })) { season in
                                Text(season.displayName).tag(season as Season?)
                            }
                        }
                    }
                }

                // Game Filter (for videos)
                if selectedContentType == .videos {
                    let games = athlete.games ?? []
                    if !games.isEmpty {
                        Section("Game") {
                            Picker("Game", selection: $selectedGame) {
                                Text("All Games").tag(nil as Game?)
                                ForEach(games.sorted(by: { ($0.date ?? Date.distantPast) > ($1.date ?? Date.distantPast) }).prefix(20)) { game in
                                    Text("vs \(game.opponent)").tag(game as Game?)
                                }
                            }
                        }
                    }

                    // Play Result Filter
                    Section("Play Results") {
                        ForEach(PlayResultType.allCases, id: \.self) { resultType in
                            Toggle(resultType.displayName, isOn: Binding(
                                get: { selectedPlayResults.contains(resultType) },
                                set: { isOn in
                                    if isOn {
                                        selectedPlayResults.insert(resultType)
                                    } else {
                                        selectedPlayResults.remove(resultType)
                                    }
                                }
                            ))
                        }
                    }

                    // Highlights Only
                    Section {
                        Toggle("Highlights Only", isOn: $highlightsOnly)
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        showingFilters = false
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button("Reset") {
                        clearAllFilters()
                    }
                }
            }
        }
    }

    // MARK: - Save Search Sheet

    private var saveSearchSheet: some View {
        NavigationStack {
            Form {
                Section("Search Name") {
                    TextField("My saved search", text: $newSearchName)
                }

                Section("Filters") {
                    if selectedDateRange != .allTime {
                        Label(selectedDateRange.displayName, systemImage: "calendar")
                    }
                    if let season = selectedSeason {
                        Label(season.displayName, systemImage: "calendar.badge.checkmark")
                    }
                    if highlightsOnly {
                        Label("Highlights only", systemImage: "star.fill")
                    }
                }
            }
            .navigationTitle("Save Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingSaveSearch = false
                        newSearchName = ""
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button("Save") {
                        saveSearch()
                    }
                    .disabled(newSearchName.isEmpty)
                }
            }
        }
    }

    // MARK: - Filtering Logic

    private func updateFilteredResults() {
        cachedFilteredVideos = filteredVideos()
        cachedFilteredGames = filteredGames()
        cachedFilteredPractices = filteredPractices()
        cachedFilteredPhotos = filteredPhotos()
    }

    // MARK: - Filtering Helpers

    private func matchesDateRange(_ date: Date?) -> Bool {
        guard selectedDateRange != .allTime, let date else { return selectedDateRange == .allTime }
        let range = selectedDateRange.dateRange
        return date >= range.start && date <= range.end
    }

    private func matchesSeason(_ seasonId: UUID?) -> Bool {
        guard let selected = selectedSeason else { return true }
        return seasonId == selected.id
    }

    private func filteredVideos() -> [VideoClip] {
        var videos = athlete.videoClips ?? []
        if !searchText.isEmpty {
            videos = videos.filter {
                $0.fileName.localizedCaseInsensitiveContains(searchText) ||
                $0.playResult?.type.displayName.localizedCaseInsensitiveContains(searchText) == true ||
                $0.game?.opponent.localizedCaseInsensitiveContains(searchText) == true
            }
        }
        if selectedDateRange != .allTime { videos = videos.filter { matchesDateRange($0.createdAt) } }
        if selectedSeason != nil { videos = videos.filter { matchesSeason($0.season?.id) } }
        if let game = selectedGame { videos = videos.filter { $0.game?.id == game.id } }
        if !selectedPlayResults.isEmpty { videos = videos.filter { $0.playResult.map { selectedPlayResults.contains($0.type) } ?? false } }
        if highlightsOnly { videos = videos.filter { $0.isHighlight } }
        return videos.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    private func filteredGames() -> [Game] {
        var games = athlete.games ?? []
        if !searchText.isEmpty { games = games.filter { $0.opponent.localizedCaseInsensitiveContains(searchText) } }
        if selectedDateRange != .allTime { games = games.filter { matchesDateRange($0.date) } }
        if selectedSeason != nil { games = games.filter { matchesSeason($0.season?.id) } }
        return games.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    private func filteredPractices() -> [Practice] {
        var practices = athlete.practices ?? []
        if selectedDateRange != .allTime { practices = practices.filter { matchesDateRange($0.date) } }
        if selectedSeason != nil { practices = practices.filter { matchesSeason($0.season?.id) } }
        return practices.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    private func filteredPhotos() -> [Photo] {
        var photos = athlete.photos ?? []
        if !searchText.isEmpty {
            photos = photos.filter {
                ($0.game?.opponent.localizedCaseInsensitiveContains(searchText) ?? false) ||
                ($0.caption?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        if selectedDateRange != .allTime { photos = photos.filter { matchesDateRange($0.createdAt) } }
        if selectedSeason != nil { photos = photos.filter { matchesSeason($0.season?.id) } }
        return photos.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    // MARK: - Actions

    private func clearAllFilters() {
        selectedDateRange = .allTime
        selectedSeason = nil
        selectedGame = nil
        selectedPlayResults.removeAll()
        highlightsOnly = false
    }

    private func saveSearch() {
        let search = SavedSearch(
            name: newSearchName,
            contentType: selectedContentType,
            dateRange: selectedDateRange,
            seasonID: selectedSeason?.id,
            gameID: selectedGame?.id,
            playResults: selectedPlayResults,
            highlightsOnly: highlightsOnly
        )
        savedSearches.append(search)
        showingSaveSearch = false
        newSearchName = ""
        persistSavedSearches()
    }

    private func persistSavedSearches() {
        if let data = try? JSONEncoder().encode(savedSearches) {
            UserDefaults.standard.set(data, forKey: "savedSearches")
        }
    }

    private func loadSavedSearches() {
        guard let data = UserDefaults.standard.data(forKey: "savedSearches"),
              let decoded = try? JSONDecoder().decode([SavedSearch].self, from: data) else { return }
        savedSearches = decoded
    }
}

// MARK: - Supporting Types

enum ContentType: String, CaseIterable, Identifiable, Codable {
    case videos = "videos"
    case games = "games"
    case practices = "practices"
    case photos = "photos"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .videos: return "Videos"
        case .games: return "Games"
        case .practices: return "Practices"
        case .photos: return "Photos"
        }
    }

    var icon: String {
        switch self {
        case .videos: return "video"
        case .games: return "baseball.fill"
        case .practices: return "figure.run"
        case .photos: return "photo.fill"
        }
    }
}

enum DateRange: String, CaseIterable, Identifiable, Codable {
    case allTime = "all_time"
    case today = "today"
    case thisWeek = "this_week"
    case thisMonth = "this_month"
    case last30Days = "last_30_days"
    case last90Days = "last_90_days"
    case thisYear = "this_year"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .allTime: return "All Time"
        case .today: return "Today"
        case .thisWeek: return "This Week"
        case .thisMonth: return "This Month"
        case .last30Days: return "Last 30 Days"
        case .last90Days: return "Last 90 Days"
        case .thisYear: return "This Year"
        }
    }

    var dateRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()
        let endDate = now

        switch self {
        case .allTime:
            return (Date.distantPast, endDate)
        case .today:
            let startOfDay = calendar.startOfDay(for: now)
            return (startOfDay, endDate)
        case .thisWeek:
            let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            return (startOfWeek, endDate)
        case .thisMonth:
            let startOfMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
            return (startOfMonth, endDate)
        case .last30Days:
            let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now) ?? now
            return (thirtyDaysAgo, endDate)
        case .last90Days:
            let ninetyDaysAgo = calendar.date(byAdding: .day, value: -90, to: now) ?? now
            return (ninetyDaysAgo, endDate)
        case .thisYear:
            let startOfYear = calendar.dateInterval(of: .year, for: now)?.start ?? now
            return (startOfYear, endDate)
        }
    }
}

struct SavedSearch: Identifiable, Codable {
    let id: UUID
    let name: String
    let contentType: ContentType
    let dateRange: DateRange
    let seasonID: UUID?
    let gameID: UUID?
    let playResults: Set<PlayResultType>
    let highlightsOnly: Bool

    init(name: String, contentType: ContentType, dateRange: DateRange, seasonID: UUID?, gameID: UUID?, playResults: Set<PlayResultType>, highlightsOnly: Bool) {
        self.id = UUID()
        self.name = name
        self.contentType = contentType
        self.dateRange = dateRange
        self.seasonID = seasonID
        self.gameID = gameID
        self.playResults = playResults
        self.highlightsOnly = highlightsOnly
    }
}

// MARK: - Supporting Views

struct FilterChip: View {
    let text: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.labelMedium)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
            }
        }
        .foregroundColor(.brandNavy)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.brandNavy.opacity(0.1))
        .cornerRadius(16)
    }
}

/// Shared card layout for search results with a thumbnail and detail content.
private struct SearchResultCard<Content: View>: View {
    let thumbnailPath: String?
    let placeholderIcon: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 12) {
            if let thumbnailPath {
                AsyncThumbnailView(path: thumbnailPath, size: .thumbnailSmall)
                    .frame(width: CGSize.thumbnailSmall.width, height: CGSize.thumbnailSmall.height)
                    .cornerRadius(8)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: CGSize.thumbnailSmall.width, height: CGSize.thumbnailSmall.height)
                    .cornerRadius(8)
                    .overlay(
                        Image(systemName: placeholderIcon)
                            .foregroundColor(.white)
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                content
            }

            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 1)
    }
}

struct VideoSearchResultCard: View {
    let video: VideoClip

    var body: some View {
        SearchResultCard(thumbnailPath: video.thumbnailPath, placeholderIcon: "video.fill") {
            HStack {
                if let result = video.playResult {
                    Text(result.type.displayName)
                        .font(.headingMedium)
                }
                if video.isHighlight {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundColor(.yellow)
                }
            }
            if let game = video.game {
                Text("vs \(game.opponent)")
                    .font(.bodySmall)
                    .foregroundColor(.secondary)
            }
            if let createdAt = video.createdAt {
                Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.labelSmall)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct GameSearchResultRow: View {
    let game: Game

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("vs \(game.opponent)")
                    .font(.headingLarge)

                Spacer()

                switch game.displayStatus {
                case .live:
                    Text("LIVE")
                        .font(.custom("Inter18pt-Bold", size: 11, relativeTo: .caption2))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red)
                        .cornerRadius(4)
                case .completed:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                case .scheduled:
                    EmptyView()
                }
            }

            if let date = game.date {
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.bodySmall)
                    .foregroundColor(.secondary)
            }

            if let stats = game.gameStats {
                Text("\(stats.hits)-\(stats.atBats), \(StatisticsService.shared.formatBattingAverage(stats.battingAverage)) AVG")
                    .font(.bodySmall)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct PracticeSearchResultRow: View {
    let practice: Practice

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Practice")
                .font(.headingLarge)

            if let date = practice.date {
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(.bodySmall)
                    .foregroundColor(.secondary)
            }

            let notesCount = practice.notes?.count ?? 0
            if notesCount > 0 {
                Text("\(notesCount) note\(notesCount == 1 ? "" : "s")")
                    .font(.labelSmall)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct PhotoSearchResultCard: View {
    let photo: Photo

    var body: some View {
        SearchResultCard(thumbnailPath: photo.thumbnailPath, placeholderIcon: "photo") {
            if let caption = photo.caption, !caption.isEmpty {
                Text(caption)
                    .font(.headingMedium)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if let game = photo.game {
                Text("vs \(game.opponent)")
                    .font(.bodySmall)
                    .foregroundColor(.secondary)
            } else if photo.practice != nil {
                Text("Practice")
                    .font(.bodySmall)
                    .foregroundColor(.secondary)
            }
            if let createdAt = photo.createdAt {
                Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.labelSmall)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct AsyncThumbnailView: View {
    let path: String
    let size: CGSize

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.gray.opacity(0.3)
                    .overlay(
                        ProgressView()
                    )
            }
        }
        .task {
            do {
                image = try await ThumbnailCache.shared.loadThumbnail(at: path, targetSize: size)
            } catch {
                // Failed to load thumbnail
            }
        }
    }
}

// MARK: - Preview

#Preview {
    AdvancedSearchView(athlete: Athlete(name: "Sample Player"))
}
