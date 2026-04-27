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
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint("View season details")
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
                            .font(.headingLarge)

                        Text("Start a new season to begin tracking games, practices, and videos.")
                            .font(.bodyMedium)
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
                        Haptics.warning()
                        seasonToArchive = athlete.activeSeason
                        showingArchiveConfirmation = true
                    } label: {
                        Label("End Current Season", systemImage: "archivebox")
                            .foregroundStyle(.orange)
                    }

                    Button {
                        showingCreateSeason = true
                    } label: {
                        Label("Start New Season", systemImage: AppIcon.addInline)
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
                            .accessibilityAddTraits(.isButton)
                            .accessibilityHint("View season details")
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
                Haptics.heavy()
                archiveSeason(season)
                seasonToArchive = nil
            }
        } message: { season in
            Text("Are you sure you want to end \(season.displayName)? This will archive all games, practices, and videos for this season. You can still view them later in season history.")
        }
        .alert("Unable to Update Season", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .alert("Season Archived", isPresented: $showingSuccess) {
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
                        .font(.headingMedium)

                    if let startDate = season.startDate {
                        Text("Started \(startDate.formatted(date: .abbreviated, time: .omitted))")
                            .font(.bodySmall)
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
                .font(.ppStatSmall)
                .monospacedDigit()

            Text(label)
                .font(.labelSmall)
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
                    .font(.headingMedium)

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
                        .font(.bodySmall)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(completedGames) games • \(totalVideos) videos")
                    .font(.bodySmall)
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
