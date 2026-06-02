//
//  SeasonsView.swift
//  PlayerPath
//
//  Created by Assistant on 11/14/25.
//

import SwiftUI
import SwiftData

struct SeasonsView: View {
    let athlete: Athlete
    @State private var showingCreateSeason = false
    @State private var selectedSeason: Season?
    @State private var seasons: [Season] = []

    var hasActiveSeason: Bool {
        seasons.contains(where: { $0.isActive })
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                noActiveSeasonAlert
                activeSeasonBanner
                seasonsList
            }
            .padding(.vertical)
        }
        .background(Theme.surface)
        .onAppear { AnalyticsService.shared.trackScreenView(screenName: "Seasons", screenClass: "SeasonsView") }
        .navigationTitle("Seasons")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { showingCreateSeason = true }) {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create new season")
            }
        }
        .sheet(isPresented: $showingCreateSeason) {
            CreateSeasonView(athlete: athlete)
        }
        .sheet(item: $selectedSeason) { season in
            NavigationStack {
                SeasonDetailView(season: season, athlete: athlete)
            }
        }
        .task {
            updateSeasons()
        }
        .onChange(of: athlete.seasons) { _, _ in
            updateSeasons()
        }
    }

    @ViewBuilder
    private var noActiveSeasonAlert: some View {
        if !seasons.isEmpty && !hasActiveSeason {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.accent)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 4) {
                    Text("No Active Season")
                        .font(.ppHeadline)
                        .foregroundStyle(Theme.textPrimary)

                    Text("Create or activate a season to track your progress")
                        .font(.ppSubheadline)
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer()
            }
            .padding()
            .ppCard()
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var activeSeasonBanner: some View {
        if let activeSeason = athlete.activeSeason {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Active Season")
                            .smallCapsLabel(color: Theme.accent)

                        Text(activeSeason.displayName)
                            .font(.ppTitle)
                            .foregroundStyle(Theme.textPrimary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.textTertiary)
                }

                HStack(alignment: .top, spacing: 20) {
                    SeasonStatBadge(
                        value: activeSeason.completedGames,
                        label: "Games Played",
                        icon: "baseball.diamond.bases"
                    )
                    SeasonStatBadge(
                        value: activeSeason.totalVideos,
                        label: "Videos",
                        icon: "video"
                    )
                    SeasonStatBadge(
                        value: activeSeason.practicesCount,
                        label: "Practices",
                        icon: "figure.run"
                    )
                }
            }
            .padding()
            .ppCard()
            .padding(.horizontal)
            .contentShape(RoundedRectangle(cornerRadius: .cornerXLarge, style: .continuous))
            .onTapGesture { selectedSeason = activeSeason }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Active Season: \(activeSeason.displayName)")
        }
    }

    @ViewBuilder
    private var seasonsList: some View {
        if seasons.isEmpty {
            EmptySeasonsView {
                showingCreateSeason = true
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                PPSectionHeader("All Seasons")
                    .padding(.horizontal)

                ForEach(seasons) { season in
                    Button {
                        selectedSeason = season
                    } label: {
                        SeasonRow(season: season)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func updateSeasons() {
        let allSeasons = athlete.seasons ?? []
        seasons = allSeasons.sorted { lhs, rhs in
            // Active season first
            if lhs.isActive != rhs.isActive {
                return lhs.isActive
            }

            // Then sort by start date (most recent first)
            return (lhs.startDate ?? .distantPast) > (rhs.startDate ?? .distantPast)
        }
    }
}

struct SeasonRow: View {
    let season: Season

    var body: some View {
        HStack(spacing: 12) {
            // Season icon — calendar glyph encodes status (active / ended / inactive)
            Image(systemName: season.status.icon)
                .font(.title3)
                .foregroundStyle(seasonStatusColor)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(season.displayName)
                        .font(.ppHeadline)
                        .foregroundStyle(Theme.textPrimary)

                    // Status Badge
                    Text(season.status.displayName.uppercased())
                        .font(.ppCaptionBold)
                        .foregroundStyle(Theme.surface)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(seasonStatusColor)
                        .clipShape(Capsule())
                }

                HStack(spacing: 12) {
                    Label("\(season.completedGames)", systemImage: "baseball.diamond.bases")
                        .font(.ppCaption)
                        .foregroundStyle(Theme.textSecondary)

                    Label("\(season.totalVideos)", systemImage: "video")
                        .font(.ppCaption)
                        .foregroundStyle(Theme.textSecondary)

                    Label("\(season.practicesCount)", systemImage: "figure.run")
                        .font(.ppCaption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .padding()
        .ppCard(cornerRadius: .cornerLarge)
        .padding(.horizontal)
    }

    private var seasonStatusColor: Color {
        switch season.status {
        case .active:
            // The lone accent — only the active season gets the highlight.
            return Theme.accent
        case .ended, .inactive:
            // Muted, but dark enough that the cream capsule text stays legible.
            return Theme.textSecondary
        }
    }
}

struct EmptySeasonsView: View {
    let onCreate: () -> Void

    var body: some View {
        EmptyStateView(
            systemImage: "calendar.badge.plus",
            title: "No Seasons Yet",
            message: "Create your first season to organize games and track progress",
            actionTitle: "Create Season",
            action: onCreate
        )
    }
}



struct SeasonVideoRow: View {
    let video: VideoClip
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "video.fill")
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                if let tag = video.displayTagName {
                    Text(tag)
                        .font(.ppHeadline)
                        .foregroundStyle(Theme.textPrimary)
                } else {
                    Text("Practice Video")
                        .font(.ppBody)
                        .foregroundStyle(Theme.textPrimary)
                }

                if let created = video.createdAt {
                    Text(created.formatted(date: .abbreviated, time: .shortened))
                        .font(.ppCaption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            Spacer()

            if video.isHighlight {
                Image(systemName: "star.fill")
                    .foregroundStyle(Theme.accent)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}

struct SeasonGameRow: View {
    let game: Game
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "baseball.diamond.bases")
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(game.opponentLabel)
                    .font(.ppHeadline)
                    .foregroundStyle(Theme.textPrimary)

                if let date = game.date {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.ppCaption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            Spacer()

            if game.displayStatus == .completed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    guard let container = try? ModelContainer(for: Athlete.self, Season.self, configurations: config) else {
        return Text("Preview Error")
    }
    
    let athlete = Athlete(name: "Test Player")
    let season = Season(name: "Spring 2025", startDate: Date(), sport: .baseball)
    season.activate()
    season.athlete = athlete
    
    container.mainContext.insert(athlete)
    container.mainContext.insert(season)
    
    return SeasonsView(athlete: athlete)
        .modelContainer(container)
}
