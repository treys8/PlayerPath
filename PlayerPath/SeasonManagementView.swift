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
    
    // Query all games to force refresh when games complete
    @Query private var allGames: [Game]
    @Query private var allVideos: [VideoClip]
    
    @State private var showingCreateSeason = false
    @State private var showingArchiveConfirmation = false
    @State private var seasonToArchive: Season?
    @State private var showingSeasonDetail: Season?
    
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
    }
    
    private func archiveSeason(_ season: Season) {
        withAnimation {
            season.archive()
            try? modelContext.save()
        }
        Haptics.medium()
    }
}

// MARK: - Active Season Card

struct ActiveSeasonCard: View {
    let season: Season
    let athlete: Athlete
    
    // Query games and videos to force UI updates
    @Query private var allGames: [Game]
    @Query private var allVideos: [VideoClip]
    
    // Compute stats based on current data
    private var completedGames: Int {
        allGames.filter { $0.season?.id == season.id && $0.isComplete }.count
    }
    
    private var totalVideos: Int {
        allVideos.filter { $0.season?.id == season.id }.count
    }
    
    private var highlights: Int {
        allVideos.filter { $0.season?.id == season.id && $0.isHighlight }.count
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
    
    // Query games and videos for live counts
    @Query private var allGames: [Game]
    @Query private var allVideos: [VideoClip]
    
    private var completedGames: Int {
        allGames.filter { $0.season?.id == season.id && $0.isComplete }.count
    }
    
    private var totalVideos: Int {
        allVideos.filter { $0.season?.id == season.id }.count
    }
    
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
        if athlete.seasons == nil {
            athlete.seasons = []
        }
        athlete.seasons?.append(newSeason)
        
        // Save
        modelContext.insert(newSeason)
        
        do {
            try modelContext.save()
            Haptics.medium()
            dismiss()
        } catch {
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
    
    // Query all data to get live updates
    @Query private var allGames: [Game]
    @Query private var allVideos: [VideoClip]
    @Query private var allPractices: [Practice]
    @Query private var allTournaments: [Tournament]
    
    @State private var showingDeleteConfirmation = false
    @State private var showingReactivateConfirmation = false
    
    // Computed properties for live stats
    private var completedGames: Int {
        allGames.filter { $0.season?.id == season.id && $0.isComplete }.count
    }
    
    private var totalVideos: Int {
        allVideos.filter { $0.season?.id == season.id }.count
    }
    
    private var highlights: Int {
        allVideos.filter { $0.season?.id == season.id && $0.isHighlight }.count
    }
    
    private var practices: Int {
        allPractices.filter { $0.season?.id == season.id }.count
    }
    
    private var tournaments: Int {
        allTournaments.filter { $0.season?.id == season.id }.count
    }
    
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
                    LabeledContent("Batting Average", value: String(format: ".%.3d", Int(stats.battingAverage * 1000)))
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
    }
    
    private func deleteSeason() {
        // Delink relationships (SwiftData will handle cascade)
        season.games?.forEach { $0.season = nil }
        season.practices?.forEach { $0.season = nil }
        season.videoClips?.forEach { $0.season = nil }
        season.tournaments?.forEach { $0.season = nil }
        
        modelContext.delete(season)
        
        do {
            try modelContext.save()
            Haptics.medium()
            dismiss()
        } catch {
            print("Error deleting season: \(error)")
        }
    }
    
    private func reactivateSeason() {
        // Archive current active season if exists
        if let currentActive = athlete.activeSeason {
            currentActive.archive()
        }
        
        // Reactivate this season
        season.activate()
        
        do {
            try modelContext.save()
            Haptics.medium()
        } catch {
            print("Error reactivating season: \(error)")
        }
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: User.self, Athlete.self, Season.self, configurations: config)
    
    let user = User(username: "testuser", email: "test@example.com")
    let athlete = Athlete(name: "Test Athlete")
    athlete.user = user
    
    let season1 = Season(name: "Spring 2025", startDate: Date(), sport: .baseball)
    season1.activate()
    season1.athlete = athlete
    
    let season2 = Season(name: "Fall 2024", startDate: Calendar.current.date(byAdding: .month, value: -6, to: Date())!, sport: .baseball)
    season2.archive(endDate: Calendar.current.date(byAdding: .month, value: -1, to: Date())!)
    season2.athlete = athlete
    
    container.mainContext.insert(user)
    container.mainContext.insert(athlete)
    container.mainContext.insert(season1)
    container.mainContext.insert(season2)
    
    return NavigationStack {
        SeasonManagementView(athlete: athlete)
    }
    .modelContainer(container)
}
