//
//  SeasonManagementView.swift
//  PlayerPath
//
//  Created by Assistant on 11/13/25.
//

import SwiftUI
import SwiftData

/// View for managing seasons for an athlete - create, activate, archive, view history
struct SeasonManagementView: View {
    let athlete: Athlete
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showingCreateSeason = false
    @State private var showingArchiveConfirmation = false
    @State private var seasonToArchive: Season?
    @State private var showingSeasonDetail: Season?
    @State private var isProcessing = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingSuccess = false
    @State private var successMessage = ""

    var body: some View {
        List {
            // Active Season Section
            if let activeSeason = athlete.activeSeason {
                Section {
                    ActiveSeasonCard(season: activeSeason, athlete: athlete)
                        .onTapGesture {
                            showingSeasonDetail = activeSeason
                        }
                } header: {
                    Text("Active Season")
                } footer: {
                    Text("This is the current active season. All new games, practices, and videos will be added here.")
                }
            } else {
                Section {
                    VStack(spacing: 16) {
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 50))
                            .foregroundStyle(.secondary)
                        
                        Text("No Active Season")
                            .font(.headline)
                        
                        Text("Start a new season to begin tracking games, practices, and videos.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Button {
                            showingCreateSeason = true
                        } label: {
                            Label("Start New Season", systemImage: "play.fill")
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
            }
            
            // Quick Actions (if there's an active season)
            if athlete.activeSeason != nil {
                Section {
                    Button {
                        seasonToArchive = athlete.activeSeason
                        showingArchiveConfirmation = true
                    } label: {
                        Label("End Current Season", systemImage: "archivebox")
                            .foregroundStyle(.orange)
                    }
                    
                    Button {
                        showingCreateSeason = true
                    } label: {
                        Label("Start New Season", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Actions")
                }
            }
            
            // Season History
            if !athlete.archivedSeasons.isEmpty {
                Section {
                    ForEach(athlete.archivedSeasons) { season in
                        SeasonHistoryRow(season: season)
                            .onTapGesture {
                                showingSeasonDetail = season
                            }
                    }
                } header: {
                    Text("Season History")
                } footer: {
                    Text("\(athlete.archivedSeasons.count) archived season(s)")
                }
            }
        }
        .navigationTitle("Seasons")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingCreateSeason = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingCreateSeason) {
            CreateSeasonView(athlete: athlete)
        }
        .sheet(item: $showingSeasonDetail) { season in
            NavigationStack {
                SeasonDetailView(season: season, athlete: athlete)
            }
        }
        .alert("End Season", isPresented: $showingArchiveConfirmation, presenting: seasonToArchive) { season in
            Button("Cancel", role: .cancel) {
                seasonToArchive = nil
            }
            Button("End Season", role: .destructive) {
                archiveSeason(season)
                seasonToArchive = nil
            }
        } message: { season in
            Text("Are you sure you want to end \(season.displayName)? This will archive all games, practices, and videos for this season. You can still view them later in season history.")
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .alert("Success", isPresented: $showingSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(successMessage)
        }
        .disabled(isProcessing)
    }

    private func archiveSeason(_ season: Season) {
        isProcessing = true

        // Save state for rollback
        let wasActive = season.isActive
        let previousEndDate = season.endDate

        // Archive the season
        season.archive()

        // Mark for Firestore sync (Phase 2)
        season.needsSync = true

        Task {
            do {
                try modelContext.save()

                // Trigger immediate sync to Firestore
                if let user = season.athlete?.user {
                    do {
                        try await SyncCoordinator.shared.syncSeasons(for: user)
                    } catch {
                        ErrorHandlerService.shared.handle(error, context: "SeasonManagement.syncSeasons", showAlert: false)
                    }
                }

                // Success - animate the change
                withAnimation {
                    isProcessing = false
                }
                Haptics.medium()
                successMessage = "\(season.displayName) has been archived."
                showingSuccess = true
            } catch {
                // Rollback on failure
                if wasActive {
                    season.activate()
                }
                season.endDate = previousEndDate

                isProcessing = false
                errorMessage = "Failed to archive season: \(error.localizedDescription)"
                showingError = true
            }
        }
    }
}

// MARK: - Active Season Card

struct ActiveSeasonCard: View {
    let season: Season
    let athlete: Athlete

    @State private var completedGames: Int = 0
    @State private var totalVideos: Int = 0
    @State private var highlights: Int = 0

    // Use targeted queries with predicates instead of loading all records
    init(season: Season, athlete: Athlete) {
        self.season = season
        self.athlete = athlete
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: season.sport.icon)
                    .font(.title2)
                    .foregroundColor(.brandNavy)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(season.displayName)
                        .font(.headline)
                    
                    if let startDate = season.startDate {
                        Text("Started \(startDate.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
            }
            
            // Stats Grid - using computed values for live updates
            HStack(spacing: 20) {
                SeasonStatBadge(value: completedGames, label: "Games", icon: "figure.baseball")
                SeasonStatBadge(value: totalVideos, label: "Videos", icon: "video")
                SeasonStatBadge(value: highlights, label: "Highlights", icon: "star.fill")
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.brandNavy.opacity(0.1))
        }
        .task {
            updateStats()
        }
        .onChange(of: season.games) { _, _ in
            updateStats()
        }
        .onChange(of: season.videoClips) { _, _ in
            updateStats()
        }
    }

    private func updateStats() {
        completedGames = season.games?.filter { $0.isComplete }.count ?? 0
        totalVideos = season.videoClips?.count ?? 0
        highlights = season.videoClips?.filter { $0.isHighlight }.count ?? 0
    }
}

struct SeasonStatBadge: View {
    let value: Int
    let label: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text("\(value)")
                .font(.headline)
            
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Season History Row

struct SeasonHistoryRow: View {
    let season: Season

    @State private var completedGames: Int = 0
    @State private var totalVideos: Int = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: season.sport.icon)
                    .foregroundStyle(.secondary)
                
                Text(season.displayName)
                    .font(.headline)
                
                Spacer()
                
                if season.isArchived {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }
            
            // Date range
            HStack {
                if let start = season.startDate, let end = season.endDate {
                    Text("\(start.formatted(date: .abbreviated, time: .omitted)) - \(end.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Text("\(completedGames) games • \(totalVideos) videos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .task {
            updateStats()
        }
    }

    private func updateStats() {
        completedGames = season.games?.filter { $0.isComplete }.count ?? 0
        totalVideos = season.videoClips?.count ?? 0
    }
}

// MARK: - Create Season View

struct CreateSeasonView: View {
    let athlete: Athlete
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var seasonName = ""
    @State private var startDate = Date()
    @State private var selectedSport: Season.SportType = .baseball
    @State private var makeActive = true
    @State private var showingError = false
    @State private var errorMessage = ""
    
    // Season name suggestions
    private var suggestedSeasons: [String] {
        let year = Calendar.current.component(.year, from: startDate)
        let month = Calendar.current.component(.month, from: startDate)
        
        if month >= 2 && month <= 6 {
            return ["Spring \(year)", "Spring Season", "\(year) Season"]
        } else if month >= 7 && month <= 10 {
            return ["Fall \(year)", "Fall Season", "\(year) Season"]
        } else {
            return ["Winter \(year)", "\(year) Season", "Off-Season"]
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Season Name", text: $seasonName)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                    
                    // Quick suggestions
                    if seasonName.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Suggestions:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(suggestedSeasons, id: \.self) { suggestion in
                                        Button {
                                            seasonName = suggestion
                                        } label: {
                                            Text(suggestion)
                                                .font(.subheadline)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(Color.brandNavy.opacity(0.1))
                                                .foregroundColor(.brandNavy)
                                                .clipShape(Capsule())
                                        }
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Text("Season Information")
                } footer: {
                    Text("Give this season a name like 'Spring 2025' or 'Fall League'")
                }
                
                Section {
                    DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                } header: {
                    Text("When does this season start?")
                }
                
                Section {
                    Picker("Sport", selection: $selectedSport) {
                        ForEach(Season.SportType.allCases, id: \.self) { sport in
                            Label(sport.displayName, systemImage: sport.icon)
                                .tag(sport)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Sport")
                }
                
                if athlete.activeSeason != nil {
                    Section {
                        Toggle("Make this the active season", isOn: $makeActive)
                    } footer: {
                        Text("If enabled, this will end the current active season and make this one active. Otherwise, it will be created as an archived season.")
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("New Season")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createSeason()
                    }
                    .disabled(seasonName.isEmpty)
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func createSeason() {
        // Validate
        guard !seasonName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Please enter a season name"
            showingError = true
            return
        }

        // Capture before any mutations so rollback has the correct reference
        let previousActive = athlete.activeSeason
        let previousActiveWasActive = previousActive?.isActive ?? false
        let previousActiveEndDate = previousActive?.endDate

        // If making this active, archive the current active season
        if makeActive {
            previousActive?.archive()
        }

        // Create new season
        let newSeason = Season(name: seasonName.trimmingCharacters(in: .whitespacesAndNewlines),
                              startDate: startDate,
                              sport: selectedSport)

        if makeActive {
            newSeason.activate()
        }

        // Link to athlete
        newSeason.athlete = athlete
        athlete.seasons = athlete.seasons ?? []
        athlete.seasons?.append(newSeason)

        // Mark for Firestore sync (Phase 2)
        newSeason.needsSync = true

        // Insert and save
        modelContext.insert(newSeason)

        Task {
            do {
                try modelContext.save()

                // Track season creation analytics
                AnalyticsService.shared.trackSeasonCreated(
                    seasonID: newSeason.id.uuidString,
                    sport: selectedSport.rawValue,
                    isActive: makeActive
                )

                // Track season activation if making active
                if makeActive {
                    AnalyticsService.shared.trackSeasonActivated(seasonID: newSeason.id.uuidString)
                }

                // Trigger immediate sync to Firestore
                if let user = athlete.user {
                    do {
                        try await SyncCoordinator.shared.syncSeasons(for: user)
                    } catch {
                        ErrorHandlerService.shared.handle(error, context: "SeasonManagement.syncSeasons", showAlert: false)
                    }
                }

                // Success - provide feedback and dismiss
                Haptics.medium()
                dismiss()
            } catch {
                // Rollback on failure
                modelContext.delete(newSeason)
                athlete.seasons?.removeAll { $0.id == newSeason.id }

                if previousActiveWasActive {
                    previousActive?.activate()
                    previousActive?.endDate = previousActiveEndDate
                }

                errorMessage = "Failed to create season: \(error.localizedDescription)"
                showingError = true
            }
        }
    }
}

// MARK: - Season Detail View

enum SeasonContentFilter: String, CaseIterable {
    case all = "All"
    case games = "Games"
    case videos = "Videos"
    case highlights = "Highlights"
    case practices = "Practices"
}

struct SeasonDetailView: View {
    let season: Season
    let athlete: Athlete
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showingDeleteConfirmation = false
    @State private var showingReactivateConfirmation = false
    @State private var showingEndSeasonConfirmation = false
    @State private var showingRenameSheet = false
    @State private var editedSeasonName = ""
    @State private var isProcessing = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var selectedFilter: SeasonContentFilter = .all
    @State private var showingSuccess = false
    @State private var successMessage = ""

    // Cached stats - updated via relationships
    @State private var completedGames: Int = 0
    @State private var totalVideos: Int = 0
    @State private var highlights: Int = 0
    @State private var practices: Int = 0

    // Cached filtered content arrays to avoid expensive recomputation on every render
    @State private var filteredGames: [Game] = []
    @State private var filteredVideos: [VideoClip] = []
    @State private var filteredHighlights: [VideoClip] = []
    @State private var filteredPractices: [Practice] = []

    var body: some View {
        List {
            // Overview Section
            Section {
                HStack {
                    Image(systemName: season.sport.icon)
                        .font(.title)
                        .foregroundColor(.brandNavy)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(season.displayName)
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        if season.isActive {
                            Label("Active", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else {
                            Label("Archived", systemImage: "archivebox.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            
            // Date Range
            Section("Season Dates") {
                if let start = season.startDate {
                    LabeledContent("Started", value: start.formatted(date: .long, time: .omitted))
                }
                
                if let end = season.endDate {
                    LabeledContent("Ended", value: end.formatted(date: .long, time: .omitted))
                } else if season.isActive {
                    HStack {
                        Text("End Date")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("In Progress")
                            .foregroundColor(.brandNavy)
                    }
                }
            }
            
            // Content Filter
            Section {
                Picker("Filter", selection: $selectedFilter) {
                    ForEach(SeasonContentFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Statistics - using computed values for live updates (shown for All filter)
            if selectedFilter == .all {
                Section("Season Stats") {
                    LabeledContent("Total Games", value: "\(completedGames)")
                    LabeledContent("Total Videos", value: "\(totalVideos)")
                    LabeledContent("Highlights", value: "\(highlights)")
                    LabeledContent("Practices", value: "\(practices)")
                }

                // Baseball Stats (if available)
                if let stats = season.seasonStatistics, stats.atBats > 0 {
                    Section("Batting Statistics") {
                        LabeledContent("Batting Average", value: String(format: ".%03d", Int(stats.battingAverage * 1000)))
                        LabeledContent("At Bats", value: "\(stats.atBats)")
                        LabeledContent("Hits", value: "\(stats.hits)")
                        LabeledContent("Home Runs", value: "\(stats.homeRuns)")
                        LabeledContent("RBIs", value: "\(stats.rbis)")
                        LabeledContent("Walks", value: "\(stats.walks)")
                        LabeledContent("Strikeouts", value: "\(stats.strikeouts)")
                    }
                }

                // Notes
                if !season.notes.isEmpty {
                    Section("Notes") {
                        Text(season.notes)
                    }
                }
            }

            // Filtered Content
            filteredContent
            
            // Actions
            Section {
                Button {
                    editedSeasonName = season.name
                    showingRenameSheet = true
                } label: {
                    Label("Edit Season Name", systemImage: "pencil")
                }

                if season.isActive {
                    Button {
                        showingEndSeasonConfirmation = true
                    } label: {
                        Label("End Season", systemImage: "checkmark.circle")
                            .foregroundStyle(.orange)
                    }
                } else if season.isArchived {
                    Button {
                        showingReactivateConfirmation = true
                    } label: {
                        Label("Reactivate Season", systemImage: "arrow.counterclockwise")
                    }
                }

                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete Season", systemImage: "trash")
                }
            }
        }
        .navigationTitle("Season Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .alert("Delete Season", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteSeason()
            }
        } message: {
            Text("Are you sure you want to delete this season? This will not delete the games, practices, or videos, but they will no longer be associated with a season.")
        }
        .alert("End Season", isPresented: $showingEndSeasonConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("End Season", role: .destructive) {
                endSeason()
            }
        } message: {
            Text("Are you sure you want to end \(season.displayName)? This will archive the season and you won't be able to add new games or practices to it. You can reactivate it later if needed.")
        }
        .alert("Reactivate Season", isPresented: $showingReactivateConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reactivate") {
                reactivateSeason()
            }
        } message: {
            if athlete.activeSeason != nil {
                Text("This will end the current active season and make \(season.displayName) active again.")
            } else {
                Text("This will make \(season.displayName) the active season.")
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .alert("Success", isPresented: $showingSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(successMessage)
        }
        .sheet(isPresented: $showingRenameSheet) {
            NavigationStack {
                Form {
                    Section {
                        TextField("Season Name", text: $editedSeasonName)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                    } header: {
                        Text("Season Name")
                    } footer: {
                        Text("Enter a new name for this season")
                    }
                }
                .navigationTitle("Rename Season")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showingRenameSheet = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            showingRenameSheet = false
                            renameSeason(to: editedSeasonName)
                        }
                        .disabled(editedSeasonName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .overlay {
            if isProcessing {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    ProgressView()
                        .scaleEffect(1.2)
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .disabled(isProcessing)
        .task {
            updateStats()
            updateFilteredContent()
        }
        .onChange(of: selectedFilter) { _, _ in
            updateFilteredContent()
        }
        .onChange(of: season.games) { _, _ in
            updateStats()
            updateFilteredContent()
        }
        .onChange(of: season.videoClips) { _, _ in
            updateStats()
            updateFilteredContent()
        }
        .onChange(of: season.practices) { _, _ in
            updateStats()
            updateFilteredContent()
        }
    }

    // Extracted to a separate @ViewBuilder to keep body small enough for Swift's type checker.
    // Uses pre-computed @State arrays instead of filtering/sorting on every render.
    @ViewBuilder private var filteredContent: some View {
        if selectedFilter == .games || selectedFilter == .all {
            if !filteredGames.isEmpty {
                let totalGames = season.games?.count ?? 0
                let displayGames = selectedFilter == .all ? Array(filteredGames.prefix(5)) : filteredGames
                Section(selectedFilter == .all ? "Recent Games" : "Games (\(totalGames))") {
                    ForEach(displayGames) { game in
                        SeasonGameRow(game: game)
                    }
                    if selectedFilter == .all && totalGames > 5 {
                        Button("See All \(totalGames) Games") { selectedFilter = .games }
                            .font(.subheadline)
                            .foregroundColor(.brandNavy)
                    }
                }
            }
        }
        if selectedFilter == .videos || selectedFilter == .all {
            if !filteredVideos.isEmpty {
                Section("Videos (\(filteredVideos.count))") {
                    ForEach(selectedFilter == .all ? Array(filteredVideos.prefix(5)) : filteredVideos) { video in
                        SeasonVideoRow(video: video)
                    }
                    if selectedFilter == .all && filteredVideos.count > 5 {
                        Button("See All \(filteredVideos.count) Videos") { selectedFilter = .videos }
                            .font(.subheadline)
                            .foregroundColor(.brandNavy)
                    }
                }
            }
        }
        if selectedFilter == .highlights || selectedFilter == .all {
            if !filteredHighlights.isEmpty {
                Section("Highlights (\(filteredHighlights.count))") {
                    ForEach(selectedFilter == .all ? Array(filteredHighlights.prefix(5)) : filteredHighlights) { video in
                        SeasonVideoRow(video: video)
                    }
                    if selectedFilter == .all && filteredHighlights.count > 5 {
                        Button("See All \(filteredHighlights.count) Highlights") { selectedFilter = .highlights }
                            .font(.subheadline)
                            .foregroundColor(.brandNavy)
                    }
                }
            }
        }
        if selectedFilter == .practices || selectedFilter == .all {
            if !filteredPractices.isEmpty {
                Section("Practices (\(filteredPractices.count))") {
                    ForEach(selectedFilter == .all ? Array(filteredPractices.prefix(5)) : filteredPractices) { practice in
                        HStack {
                            Image(systemName: "figure.run")
                                .foregroundStyle(.green)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Practice")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                if let date = practice.date {
                                    Text(date.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            let videoCount = practice.videoClips?.count ?? 0
                            if videoCount > 0 {
                                Text("\(videoCount) videos")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    if selectedFilter == .all && filteredPractices.count > 5 {
                        Button("See All \(filteredPractices.count) Practices") { selectedFilter = .practices }
                            .font(.subheadline)
                            .foregroundColor(.brandNavy)
                    }
                }
            }
        }
    }

    private func updateFilteredContent() {
        filteredGames = (season.games ?? [])
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        filteredVideos = (season.videoClips ?? [])
            .filter { !$0.isHighlight }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        filteredHighlights = (season.videoClips ?? [])
            .filter { $0.isHighlight }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        filteredPractices = (season.practices ?? [])
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    private func updateStats() {
        completedGames = season.games?.filter { $0.isComplete }.count ?? 0
        totalVideos = season.videoClips?.count ?? 0
        highlights = season.videoClips?.filter { $0.isHighlight }.count ?? 0
        practices = season.practices?.count ?? 0
    }
    
    private func deleteSeason() {
        isProcessing = true

        // Sync deletion to Firestore before removing locally
        if let firestoreId = season.firestoreId,
           let user = season.athlete?.user {
            let userId = user.id.uuidString
            Task {
                await retryAsync {
                    try await FirestoreManager.shared.deleteSeason(userId: userId, seasonId: firestoreId)
                }
            }
        }

        // Store relationships for rollback
        let games = season.games
        let practices = season.practices
        let videoClips = season.videoClips

        // Delink relationships so games/practices/videos are not cascade-deleted
        season.games = nil
        season.practices = nil
        season.videoClips = nil

        modelContext.delete(season)

        Task {
            do {
                try modelContext.save()
                isProcessing = false
                Haptics.medium()
                dismiss()
            } catch {
                // Re-insert the season to undo the pending delete, then restore relationships
                modelContext.insert(season)
                season.games = games
                season.practices = practices
                season.videoClips = videoClips

                isProcessing = false
                errorMessage = "Failed to delete season: \(error.localizedDescription)"
                showingError = true
            }
        }
    }
    
    private func endSeason() {
        isProcessing = true

        // Save state for rollback
        let wasActive = season.isActive
        let previousEndDate = season.endDate

        // End the season
        season.archive()

        // Mark for Firestore sync (Phase 2)
        season.needsSync = true

        Task {
            do {
                try modelContext.save()

                // Track season end analytics
                let gameCount = season.games?.count ?? 0
                AnalyticsService.shared.trackSeasonEnded(
                    seasonID: season.id.uuidString,
                    totalGames: gameCount
                )

                // Trigger immediate sync to Firestore
                if let user = season.athlete?.user {
                    do {
                        try await SyncCoordinator.shared.syncSeasons(for: user)
                    } catch {
                        ErrorHandlerService.shared.handle(error, context: "SeasonManagement.syncSeasons", showAlert: false)
                    }
                }

                withAnimation {
                    isProcessing = false
                }
                Haptics.medium()
                successMessage = "\(season.displayName) has been ended and archived."
                showingSuccess = true
            } catch {
                // Rollback on failure
                if wasActive {
                    season.activate()
                }
                season.endDate = previousEndDate

                isProcessing = false
                errorMessage = "Failed to end season: \(error.localizedDescription)"
                showingError = true
            }
        }
    }

    private func renameSeason(to newName: String) {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        guard trimmedName != season.name else { return }

        isProcessing = true

        // Save state for rollback
        let oldName = season.name
        let oldClipSeasonNames: [(VideoClip, String)] = (season.videoClips ?? []).map { ($0, $0.seasonName ?? "") }

        // Update season name
        season.name = trimmedName
        season.needsSync = true

        // Batch-update all VideoClips with the new season name
        for clip in season.videoClips ?? [] {
            clip.seasonName = season.displayName
            if clip.firestoreId != nil {
                clip.needsSync = true
            }
        }

        Task {
            do {
                try modelContext.save()

                // Trigger sync for both season and video metadata
                if let user = season.athlete?.user {
                    do {
                        try await SyncCoordinator.shared.syncSeasons(for: user)
                    } catch {
                        ErrorHandlerService.shared.handle(error, context: "SeasonManagement.syncSeasons", showAlert: false)
                    }
                    do {
                        try await SyncCoordinator.shared.syncVideos(for: user)
                    } catch {
                        ErrorHandlerService.shared.handle(error, context: "SeasonManagement.syncVideos", showAlert: false)
                    }
                }

                withAnimation {
                    isProcessing = false
                }
                Haptics.medium()
                successMessage = "Season renamed to \"\(trimmedName)\"."
                showingSuccess = true
            } catch {
                // Rollback season name and clip seasonNames
                season.name = oldName
                for (clip, oldSeasonName) in oldClipSeasonNames {
                    clip.seasonName = oldSeasonName
                }

                isProcessing = false
                errorMessage = "Failed to rename season: \(error.localizedDescription)"
                showingError = true
            }
        }
    }

    private func reactivateSeason() {
        isProcessing = true

        // Capture before any mutations so rollback has the correct reference
        let previousActive = athlete.activeSeason
        let previousActiveWasActive = previousActive?.isActive ?? false
        let previousActiveEndDate = previousActive?.endDate
        let wasActive = season.isActive
        let previousEndDate = season.endDate

        // Archive current active season if exists
        previousActive?.archive()

        // Reactivate this season
        season.activate()

        // Mark for Firestore sync
        season.needsSync = true
        previousActive?.needsSync = true

        do {
            try modelContext.save()

            // Track season reactivation analytics
            AnalyticsService.shared.trackSeasonActivated(seasonID: season.id.uuidString)

            // Trigger immediate sync to Firestore
            Task {
                guard let user = season.athlete?.user else { return }
                do {
                    try await SyncCoordinator.shared.syncSeasons(for: user)
                } catch {
                    ErrorHandlerService.shared.handle(error, context: "SeasonManagement.syncSeasons", showAlert: false)
                }
            }

            withAnimation {
                isProcessing = false
            }
            Haptics.medium()
            successMessage = "\(season.displayName) is now active."
            showingSuccess = true
        } catch {
            // Rollback on failure
            if previousActiveWasActive {
                previousActive?.activate()
                previousActive?.endDate = previousActiveEndDate
            }

            if !wasActive {
                season.isActive = false
            }
            season.endDate = previousEndDate

            isProcessing = false
            errorMessage = "Failed to reactivate season: \(error.localizedDescription)"
            showingError = true
        }
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    guard let container = try? ModelContainer(for: User.self, Athlete.self, Season.self, configurations: config) else {
        return Text("Failed to create preview container")
    }

    let user = User(username: "testuser", email: "test@example.com")
    let athlete = Athlete(name: "Test Athlete")
    athlete.user = user

    let season1 = Season(name: "Spring 2025", startDate: Date(), sport: .baseball)
    season1.activate()
    season1.athlete = athlete

    if let pastDate = Calendar.current.date(byAdding: .month, value: -6, to: Date()),
       let endDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) {
        let season2 = Season(name: "Fall 2024", startDate: pastDate, sport: .baseball)
        season2.archive(endDate: endDate)
        season2.athlete = athlete
        container.mainContext.insert(season2)
    }

    container.mainContext.insert(user)
    container.mainContext.insert(athlete)
    container.mainContext.insert(season1)

    return NavigationStack {
        SeasonManagementView(athlete: athlete)
    }
    .modelContainer(container)
}
