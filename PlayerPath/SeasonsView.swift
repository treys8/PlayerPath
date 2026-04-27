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
            LazyVStack(spacing: 16) {
                noActiveSeasonAlert
                activeSeasonBanner
                seasonsList
            }
            .padding(.vertical)
        }
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
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.title3)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("No Active Season")
                            .font(.headingMedium)

                        Text("Create or activate a season to track your progress")
                            .font(.bodySmall)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: .cornerXLarge)
                    .fill(.orange.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: .cornerXLarge)
                    .stroke(.orange.opacity(0.3), lineWidth: 1.5)
            )
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var activeSeasonBanner: some View {
        if let activeSeason = athlete.activeSeason {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "calendar.circle.fill")
                        .font(.title2)
                        .foregroundColor(.brandNavy)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Active Season")
                            .font(.labelSmall)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        Text(activeSeason.displayName)
                            .font(.headingLarge)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 20) {
                    SeasonStatBadge(
                        value: activeSeason.totalGames,
                        label: "Games",
                        icon: "baseball.diamond.bases"
                    )
                    SeasonStatBadge(
                        value: activeSeason.totalVideos,
                        label: "Videos",
                        icon: "video"
                    )
                    SeasonStatBadge(
                        value: (activeSeason.practices ?? []).count,
                        label: "Practices",
                        icon: "figure.run"
                    )
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: .cornerXLarge)
                    .fill(Color.brandNavy.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: .cornerXLarge)
                    .stroke(Color.brandNavy.opacity(0.3), lineWidth: 1.5)
            )
            .padding(.horizontal)
            .contentShape(RoundedRectangle(cornerRadius: .cornerXLarge))
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
                HStack {
                    Text("All Seasons")
                        .font(.headingLarge)
                    Spacer()
                }
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
            // Season icon
            Image(systemName: season.status.icon)
                .font(.title3)
                .foregroundStyle(seasonStatusColor)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(season.displayName)
                        .font(.headingMedium)

                    // Status Badge
                    Text(season.status.displayName.uppercased())
                        .font(.custom("Inter18pt-Bold", size: 11, relativeTo: .caption2))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(seasonStatusColor)
                        .clipShape(Capsule())
                }
                
                HStack(spacing: 12) {
                    Label("\(season.totalGames)", systemImage: "baseball.diamond.bases")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Label("\(season.totalVideos)", systemImage: "video")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Label("\((season.practices ?? []).count)", systemImage: "figure.run")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: .cornerLarge)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: .cornerLarge)
                .stroke(Color(.systemGray5), lineWidth: 1)
        )
        .padding(.horizontal)
    }

    private var seasonStatusColor: Color {
        switch season.status {
        case .active:
            return .brandNavy
        case .ended:
            return .gray
        case .inactive:
            return .orange
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
                .foregroundStyle(.purple)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                if let playResult = video.playResult {
                    Text(playResult.type.displayName)
                        .font(.labelLarge)
                } else {
                    Text("Practice Video")
                        .font(.bodyMedium)
                }

                if let created = video.createdAt {
                    Text(created.formatted(date: .abbreviated, time: .shortened))
                        .font(.bodySmall)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            if video.isHighlight {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
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
                .foregroundColor(.brandNavy)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("vs \(game.opponent)")
                    .font(.labelLarge)

                if let date = game.date {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.bodySmall)
                        .foregroundStyle(.secondary)
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
