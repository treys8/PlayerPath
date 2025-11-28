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
        .disabled(isProcessing)
    }
    
    private func archiveSeason(_ season: Season) {
        isProcessing = true

        // Save state for rollback
        let wasActive = season.isActive
        let previousEndDate = season.endDate

        // Archive the season
        season.archive()

        do {
            try modelContext.save()
            // Success - animate the change
            withAnimation {
                isProcessing = false
            }
            Haptics.medium()
        } catch {
            // Rollback on failure
            if wasActive {
                season.activate()
            }
            season.endDate = previousEndDate

            isProcessing = false
            errorMessage = "Failed to archive season: \(error.localizedDescription)"
            showingError = true
            print("Failed to archive season: \(error)")
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
                    .foregroundStyle(.blue)
                
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
                StatBadge(value: completedGames, label: "Games", icon: "figure.baseball")
                StatBadge(value: totalVideos, label: "Videos", icon: "video.fill")
                StatBadge(value: highlights, label: "Highlights", icon: "star.fill")
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.blue.opacity(0.1))
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

struct StatBadge: View {
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
                                                .background(.blue.opacity(0.1))
                                                .foregroundStyle(.blue)
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

        // Save state for rollback
        let previousActiveWasActive = athlete.activeSeason?.isActive ?? false
        let previousActiveEndDate = athlete.activeSeason?.endDate

        // If making this active, archive the current active season
        if makeActive, let currentActive = athlete.activeSeason {
            currentActive.archive()
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

        // Insert and save
        modelContext.insert(newSeason)

        do {
            try modelContext.save()
            // Success - provide feedback and dismiss
            Haptics.medium()
            dismiss()
        } catch {
            // Rollback on failure
            modelContext.delete(newSeason)
            athlete.seasons?.removeAll { $0.id == newSeason.id }

            if let previousActive = athlete.activeSeason, previousActiveWasActive {
                previousActive.activate()
                previousActive.endDate = previousActiveEndDate
            }

            errorMessage = "Failed to create season: \(error.localizedDescription)"
            showingError = true
        }
    }
}

// MARK: - Season Detail View

struct SeasonDetailView: View {
    let season: Season
    let athlete: Athlete
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showingDeleteConfirmation = false
    @State private var showingReactivateConfirmation = false
    @State private var isProcessing = false
    @State private var showingError = false
    @State private var errorMessage = ""

    // Cached stats - updated via relationships
    @State private var completedGames: Int = 0
    @State private var totalVideos: Int = 0
    @State private var highlights: Int = 0
    @State private var practices: Int = 0
    @State private var tournaments: Int = 0
    
    var body: some View {
        List {
            // Overview Section
            Section {
                HStack {
                    Image(systemName: season.sport.icon)
                        .font(.title)
                        .foregroundStyle(.blue)
                    
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
                            .foregroundStyle(.blue)
                    }
                }
            }
            
            // Statistics - using computed values for live updates
            Section("Season Stats") {
                LabeledContent("Total Games", value: "\(completedGames)")
                LabeledContent("Total Videos", value: "\(totalVideos)")
                LabeledContent("Highlights", value: "\(highlights)")
                LabeledContent("Practices", value: "\(practices)")
                LabeledContent("Tournaments", value: "\(tournaments)")
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
            
            // Actions
            Section {
                if season.isArchived {
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
        .disabled(isProcessing)
        .task {
            updateStats()
        }
        .onChange(of: season.games) { _, _ in
            updateStats()
        }
        .onChange(of: season.videoClips) { _, _ in
            updateStats()
        }
        .onChange(of: season.practices) { _, _ in
            updateStats()
        }
        .onChange(of: season.tournaments) { _, _ in
            updateStats()
        }
    }

    private func updateStats() {
        completedGames = season.games?.filter { $0.isComplete }.count ?? 0
        totalVideos = season.videoClips?.count ?? 0
        highlights = season.videoClips?.filter { $0.isHighlight }.count ?? 0
        practices = season.practices?.count ?? 0
        tournaments = season.tournaments?.count ?? 0
    }
    
    private func deleteSeason() {
        isProcessing = true

        // Store relationships for rollback
        let games = season.games
        let practices = season.practices
        let videoClips = season.videoClips
        let tournaments = season.tournaments

        // Delink relationships - let SwiftData handle updates efficiently
        season.games = nil
        season.practices = nil
        season.videoClips = nil
        season.tournaments = nil

        modelContext.delete(season)

        do {
            try modelContext.save()
            Haptics.medium()
            dismiss()
        } catch {
            // Rollback on failure
            season.games = games
            season.practices = practices
            season.videoClips = videoClips
            season.tournaments = tournaments

            isProcessing = false
            errorMessage = "Failed to delete season: \(error.localizedDescription)"
            showingError = true
            print("Error deleting season: \(error)")
        }
    }
    
    private func reactivateSeason() {
        isProcessing = true

        // Save state for rollback
        let previousActiveWasActive = athlete.activeSeason?.isActive ?? false
        let previousActiveEndDate = athlete.activeSeason?.endDate
        let wasActive = season.isActive
        let previousEndDate = season.endDate

        // Archive current active season if exists
        if let currentActive = athlete.activeSeason {
            currentActive.archive()
        }

        // Reactivate this season
        season.activate()

        do {
            try modelContext.save()
            withAnimation {
                isProcessing = false
            }
            Haptics.medium()
        } catch {
            // Rollback on failure
            if let previousActive = athlete.activeSeason, previousActiveWasActive {
                previousActive.activate()
                previousActive.endDate = previousActiveEndDate
            }

            if !wasActive {
                season.isActive = false
            }
            season.endDate = previousEndDate

            isProcessing = false
            errorMessage = "Failed to reactivate season: \(error.localizedDescription)"
            showingError = true
            print("Error reactivating season: \(error)")
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
