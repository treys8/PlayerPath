//
//  AdvancedSearchView.swift
//  PlayerPath
//
//  Advanced search and filtering across videos, games, and practices
//

import SwiftUI
import SwiftData

struct AdvancedSearchView: View {
    @Environment(\.ppAccent) private var ppAccent
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

    // Cached filtered results (updated via updateFilteredResults)
    @State private var cachedFilteredVideos: [VideoClip] = []
    @State private var cachedFilteredGames: [Game] = []
    @State private var cachedFilteredPractices: [Practice] = []
    @State private var cachedFilteredPhotos: [Photo] = []

    // Result presentation — the pager takes IDs (never models) so a clip deleted
    // inside it can't be held here.
    @State private var playerSession: VideoPlayerSession?
    @State private var viewerPhoto: Photo?

    @State private var selectedClubs: Set<Club> = []

    private var isGolf: Bool { athlete.sport == .golf }

    /// Sport-aware tab label: golfers see "Rounds", not "Games".
    private func label(for type: ContentType) -> String {
        type == .games && isGolf ? "Rounds" : type.displayName
    }

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
            .background(Theme.surface)
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
                        Image(systemName: ToolbarSymbol.filter(active: showingFilters))
                    }
                }
            }
            .sheet(isPresented: $showingFilters) {
                filtersSheet
            }
            .fullScreenCover(item: $playerSession, onDismiss: updateFilteredResults) { session in
                VideoClipPagerView(athlete: athlete, session: session)
            }
            .photoViewer($viewerPhoto, in: cachedFilteredPhotos, onDelete: deletePhoto)
            .onChange(of: viewerPhoto) { _, photo in
                // Viewer closed: re-derive from the relationship so a photo
                // deleted (or re-tagged) inside it drops out of the results.
                if photo == nil { updateFilteredResults() }
            }
            .onAppear {
                UserDefaults.standard.removeObject(forKey: "savedSearches") // retired Save Search
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
            .onChange(of: selectedClubs) { _, _ in
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
                .foregroundStyle(Theme.textSecondary)

            TextField("Search \(label(for: selectedContentType).lowercased())...", text: $searchText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { updateFilteredResults() }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .font(.ppBody)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: .cornerLarge, style: .continuous)
                .fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: .cornerLarge, style: .continuous)
                .strokeBorder(Theme.divider, lineWidth: 1)
        )
        .tint(ppAccent)
        .padding()
    }

    // MARK: - Content Type Selector

    private var contentTypeSelectorView: some View {
        PPFilterPillRow(
            options: ContentType.allCases,
            title: { label(for: $0) },
            selection: $selectedContentType
        )
        .padding(.horizontal)
    }

    // MARK: - Active Filters

    private var hasActiveFilters: Bool {
        selectedDateRange != .allTime ||
        selectedSeason != nil ||
        (selectedContentType == .videos && (selectedGame != nil || !selectedPlayResults.isEmpty || !selectedClubs.isEmpty || highlightsOnly))
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

                    if !selectedClubs.isEmpty {
                        FilterChip(text: "\(selectedClubs.count) club\(selectedClubs.count == 1 ? "" : "s")") {
                            selectedClubs.removeAll()
                        }
                    }
                }

                Button {
                    clearAllFilters()
                } label: {
                    Text("Clear all")
                        .font(.ppCaptionBold)
                        .foregroundStyle(ppAccent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(ppAccent.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
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

                        ForEach(results.filter { $0.modelContext != nil }) { video in
                            Button {
                                playerSession = VideoPlayerSession(
                                    clipIDs: results.map(\.id),
                                    startID: video.id
                                )
                                Haptics.light()
                            } label: {
                                VideoSearchResultCard(video: video)
                            }
                            .buttonStyle(.plain)
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
                ScrollView {
                    LazyVStack(spacing: 12) {
                        resultsHeaderView(count: results.count)

                        ForEach(results.filter { $0.modelContext != nil }) { game in
                            NavigationLink {
                                GameDetailView(game: game)
                            } label: {
                                GameSearchResultRow(game: game)
                                    .padding()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .ppCard()
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
        }
    }

    private var practicesResultsView: some View {
        let results = cachedFilteredPractices

        return Group {
            if results.isEmpty {
                emptyResultsView
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        resultsHeaderView(count: results.count)

                        ForEach(results.filter { $0.modelContext != nil }) { practice in
                            NavigationLink {
                                PracticeDetailView(practice: practice)
                            } label: {
                                PracticeSearchResultRow(practice: practice, searchText: searchText)
                                    .padding()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .ppCard()
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
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

                        ForEach(results.filter { $0.modelContext != nil }) { photo in
                            Button {
                                viewerPhoto = photo
                            } label: {
                                PhotoSearchResultCard(photo: photo)
                            }
                            .buttonStyle(.plain)
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
                .font(.ppFootnote)
                .foregroundStyle(Theme.textSecondary)

            Spacer()
        }
    }

    private var emptyResultsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 60))
                .foregroundStyle(Theme.textTertiary)

            Text("No results found")
                .font(.ppTitle3)
                .foregroundStyle(Theme.textPrimary)

            Text("Try adjusting your search or filters")
                .font(.ppFootnote)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)

            if hasActiveFilters {
                Button {
                    clearAllFilters()
                } label: {
                    Text("Clear filters")
                        .font(.ppCallout)
                }
                .buttonStyle(.bordered)
                .tint(ppAccent)
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
                    let isGolfAthlete = athlete.sport == .golf
                    if !games.isEmpty {
                        Section(isGolfAthlete ? "Tournament" : "Game") {
                            Picker(isGolfAthlete ? "Tournament" : "Game", selection: $selectedGame) {
                                Text(isGolfAthlete ? "All Tournaments" : "All Games").tag(nil as Game?)
                                ForEach(games.sorted(by: { ($0.date ?? Date.distantPast) > ($1.date ?? Date.distantPast) })) { game in
                                    let isGolfGame = game.season?.sport == .golf
                                    Text("\(isGolfGame ? "at" : "vs") \(game.opponent)").tag(game as Game?)
                                }
                            }
                        }
                    }

                    // Tag filter: clubs for golf, play results otherwise
                    if isGolf {
                        Section("Clubs") {
                            ForEach(Club.allCases, id: \.self) { club in
                                Toggle(club.displayName, isOn: Binding(
                                    get: { selectedClubs.contains(club) },
                                    set: { isOn in
                                        if isOn { selectedClubs.insert(club) } else { selectedClubs.remove(club) }
                                    }
                                ))
                            }
                        }
                    } else {
                        Section("Play Results") {
                            ForEach(PlayResultType.allCases, id: \.self) { resultType in
                                Toggle(resultType.displayName, isOn: Binding(
                                    get: { selectedPlayResults.contains(resultType) },
                                    set: { isOn in
                                        if isOn { selectedPlayResults.insert(resultType) } else { selectedPlayResults.remove(resultType) }
                                    }
                                ))
                            }
                        }
                    }

                    // Highlights Only
                    Section {
                        Toggle("Highlights Only", isOn: $highlightsOnly)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.surface)
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
                $0.displayTagName?.localizedCaseInsensitiveContains(searchText) == true ||
                $0.note?.localizedCaseInsensitiveContains(searchText) == true ||
                $0.game?.opponent.localizedCaseInsensitiveContains(searchText) == true ||
                $0.season?.displayName.localizedCaseInsensitiveContains(searchText) == true ||
                $0.season?.notes.localizedCaseInsensitiveContains(searchText) == true
            }
        }
        if selectedDateRange != .allTime { videos = videos.filter { matchesDateRange($0.createdAt) } }
        if selectedSeason != nil { videos = videos.filter { matchesSeason($0.season?.id) } }
        if let game = selectedGame { videos = videos.filter { $0.game?.id == game.id } }
        if !selectedPlayResults.isEmpty { videos = videos.filter { $0.playResult.map { selectedPlayResults.contains($0.type) } ?? false } }
        if !selectedClubs.isEmpty { videos = videos.filter { $0.club.map { selectedClubs.contains($0) } ?? false } }
        if highlightsOnly { videos = videos.filter { $0.isHighlight } }
        return videos.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    private func filteredGames() -> [Game] {
        var games = athlete.games ?? []
        if !searchText.isEmpty {
            games = games.filter {
                $0.opponent.localizedCaseInsensitiveContains(searchText) ||
                $0.notes?.localizedCaseInsensitiveContains(searchText) == true ||
                $0.season?.displayName.localizedCaseInsensitiveContains(searchText) == true ||
                $0.season?.notes.localizedCaseInsensitiveContains(searchText) == true
            }
        }
        if selectedDateRange != .allTime { games = games.filter { matchesDateRange($0.date) } }
        if selectedSeason != nil { games = games.filter { matchesSeason($0.season?.id) } }
        return games.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    private func filteredPractices() -> [Practice] {
        var practices = athlete.practices ?? []
        if !searchText.isEmpty {
            practices = practices.filter { practice in
                // "Where did I write that?" — match the free text of any of the
                // practice's notes, plus the season name (more robust than the
                // UUID season filter, which dangles if the season is deleted).
                (practice.notes ?? []).contains { $0.content.localizedCaseInsensitiveContains(searchText) } ||
                practice.season?.displayName.localizedCaseInsensitiveContains(searchText) == true ||
                practice.season?.notes.localizedCaseInsensitiveContains(searchText) == true
            }
        }
        if selectedDateRange != .allTime { practices = practices.filter { matchesDateRange($0.date) } }
        if selectedSeason != nil { practices = practices.filter { matchesSeason($0.season?.id) } }
        return practices.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    private func filteredPhotos() -> [Photo] {
        var photos = athlete.photos ?? []
        if !searchText.isEmpty {
            photos = photos.filter {
                ($0.game?.opponent.localizedCaseInsensitiveContains(searchText) ?? false) ||
                ($0.caption?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                ($0.season?.displayName.localizedCaseInsensitiveContains(searchText) ?? false) ||
                ($0.season?.notes.localizedCaseInsensitiveContains(searchText) ?? false)
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
        selectedClubs.removeAll()
        highlightsOnly = false
    }

    private func deletePhoto(_ photo: Photo) {
        // Drop it from the cache BEFORE deleting so no render touches a dead model.
        cachedFilteredPhotos.removeAll { $0.id == photo.id }
        PhotoPersistenceService().deletePhoto(photo, context: modelContext)
        Haptics.light()
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

// MARK: - Preview

#Preview {
    AdvancedSearchView(athlete: Athlete(name: "Sample Player"))
}
