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
        selectedGame != nil ||
        !selectedPlayResults.isEmpty ||
        highlightsOnly
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

                Button {
                    clearAllFilters()
                } label: {
                    Text("Clear all")
                        .font(.caption)
                        .fontWeight(.medium)
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
            }
        }
    }

    private var videosResultsView: some View {
        let results = filteredVideos

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
        let results = filteredGames

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
        let results = filteredPractices

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

    private func resultsHeaderView(count: Int) -> some View {
        HStack {
            Text("\(count) result\(count == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()

            if hasActiveFilters && count > 0 {
                Button {
                    showingSaveSearch = true
                } label: {
                    Label("Save Search", systemImage: "bookmark")
                        .font(.caption)
                        .fontWeight(.medium)
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
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Try adjusting your search or filters")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if hasActiveFilters {
                Button {
                    clearAllFilters()
                } label: {
                    Text("Clear filters")
                        .fontWeight(.medium)
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

    private var filteredVideos: [VideoClip] {
        var videos = athlete.videoClips ?? []

        // Text search
        if !searchText.isEmpty {
            videos = videos.filter { video in
                video.fileName.localizedCaseInsensitiveContains(searchText) ||
                video.playResult?.type.displayName.localizedCaseInsensitiveContains(searchText) == true ||
                video.game?.opponent.localizedCaseInsensitiveContains(searchText) == true
            }
        }

        // Date range filter
        if selectedDateRange != .allTime {
            let dateRange = selectedDateRange.dateRange
            videos = videos.filter { video in
                guard let createdAt = video.createdAt else { return false }
                return createdAt >= dateRange.start && createdAt <= dateRange.end
            }
        }

        // Season filter
        if let season = selectedSeason {
            videos = videos.filter { $0.season?.id == season.id }
        }

        // Game filter
        if let game = selectedGame {
            videos = videos.filter { $0.game?.id == game.id }
        }

        // Play result filter
        if !selectedPlayResults.isEmpty {
            videos = videos.filter { video in
                guard let result = video.playResult else { return false }
                return selectedPlayResults.contains(result.type)
            }
        }

        // Highlights only filter
        if highlightsOnly {
            videos = videos.filter { $0.isHighlight }
        }

        return videos.sorted { ($0.createdAt ?? Date.distantPast) > ($1.createdAt ?? Date.distantPast) }
    }

    private var filteredGames: [Game] {
        var games = athlete.games ?? []

        // Text search
        if !searchText.isEmpty {
            games = games.filter { game in
                game.opponent.localizedCaseInsensitiveContains(searchText)
            }
        }

        // Date range filter
        if selectedDateRange != .allTime {
            let dateRange = selectedDateRange.dateRange
            games = games.filter { game in
                guard let date = game.date else { return false }
                return date >= dateRange.start && date <= dateRange.end
            }
        }

        // Season filter
        if let season = selectedSeason {
            games = games.filter { $0.season?.id == season.id }
        }

        return games.sorted { ($0.date ?? Date.distantPast) > ($1.date ?? Date.distantPast) }
    }

    private var filteredPractices: [Practice] {
        var practices = athlete.practices ?? []

        // Date range filter
        if selectedDateRange != .allTime {
            let dateRange = selectedDateRange.dateRange
            practices = practices.filter { practice in
                guard let date = practice.date else { return false }
                return date >= dateRange.start && date <= dateRange.end
            }
        }

        // Season filter
        if let season = selectedSeason {
            practices = practices.filter { $0.season?.id == season.id }
        }

        return practices.sorted { ($0.date ?? Date.distantPast) > ($1.date ?? Date.distantPast) }
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
        // TODO: Persist saved searches to UserDefaults or SwiftData
    }
}

// MARK: - Supporting Types

enum ContentType: String, CaseIterable, Identifiable {
    case videos = "videos"
    case games = "games"
    case practices = "practices"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .videos: return "Videos"
        case .games: return "Games"
        case .practices: return "Practices"
        }
    }

    var icon: String {
        switch self {
        case .videos: return "video"
        case .games: return "baseball.fill"
        case .practices: return "figure.run"
        }
    }
}

enum DateRange: String, CaseIterable, Identifiable {
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

struct SavedSearch: Identifiable {
    let id = UUID()
    let name: String
    let contentType: ContentType
    let dateRange: DateRange
    let seasonID: UUID?
    let gameID: UUID?
    let playResults: Set<PlayResultType>
    let highlightsOnly: Bool
}

// MARK: - Supporting Views

struct FilterChip: View {
    let text: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.caption)
                .fontWeight(.medium)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
            }
        }
        .foregroundColor(.blue)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(16)
    }
}

struct VideoSearchResultCard: View {
    let video: VideoClip

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            if let thumbnailPath = video.thumbnailPath {
                AsyncThumbnailView(path: thumbnailPath, size: CGSize(width: 80, height: 60))
                    .frame(width: 80, height: 60)
                    .cornerRadius(8)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 80, height: 60)
                    .cornerRadius(8)
                    .overlay(
                        Image(systemName: "video")
                            .foregroundColor(.white)
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if let result = video.playResult {
                        Text(result.type.displayName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }

                    if video.isHighlight {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundColor(.yellow)
                    }
                }

                if let game = video.game {
                    Text("vs \(game.opponent)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let createdAt = video.createdAt {
                    Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 1)
    }
}

struct GameSearchResultRow: View {
    let game: Game

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("vs \(game.opponent)")
                    .font(.headline)

                Spacer()

                if game.isLive {
                    Text("LIVE")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red)
                        .cornerRadius(4)
                } else if game.isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }

            if let date = game.date {
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let stats = game.gameStats {
                Text("\(stats.hits)-\(stats.atBats), \(StatisticsService.shared.formatBattingAverage(stats.battingAverage)) AVG")
                    .font(.caption)
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
                .font(.headline)

            if let date = practice.date {
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            let notesCount = practice.notes?.count ?? 0
            if notesCount > 0 {
                Text("\(notesCount) note\(notesCount == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
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
