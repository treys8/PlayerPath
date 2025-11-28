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
    @Environment(\.modelContext) private var modelContext
    @State private var showingCreateSeason = false
    @State private var selectedSeason: Season?
    @State private var seasons: [Season] = []
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                    // Active Season Banner (if exists)
                    if let activeSeason = athlete.activeSeason {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "calendar.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.blue)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Active Season")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textCase(.uppercase)
                                    
                                    Text(activeSeason.displayName)
                                        .font(.title3)
                                        .fontWeight(.semibold)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                            
                            HStack(spacing: 20) {
                                SeasonStatBadge(
                                    icon: "sportscourt.fill",
                                    value: activeSeason.totalGames,
                                    label: "Games"
                                )
                                SeasonStatBadge(
                                    icon: "video.fill",
                                    value: activeSeason.totalVideos,
                                    label: "Videos"
                                )
                                SeasonStatBadge(
                                    icon: "figure.run",
                                    value: (activeSeason.practices ?? []).count,
                                    label: "Practices"
                                )
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.blue.opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(.blue.opacity(0.3), lineWidth: 1.5)
                        )
                        .padding(.horizontal)
                        .onTapGesture {
                            selectedSeason = activeSeason
                        }
                    }
                    
                    // All Seasons List
                    if seasons.isEmpty {
                        EmptySeasonsView {
                            showingCreateSeason = true
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("All Seasons")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                            .padding(.horizontal)
                            
                            ForEach(seasons) { season in
                                SeasonRow(season: season)
                                    .onTapGesture {
                                        selectedSeason = season
                                    }
                            }
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Seasons")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
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
                SeasonDetailView(season: season, athlete: athlete)
            }
            .onAppear {
                updateSeasons()
            }
            .onChange(of: athlete.seasons) { _, _ in
                updateSeasons()
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

struct SeasonStatBadge: View {
    let icon: String
    let value: Int
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text("\(value)")
                .font(.headline)
                .fontWeight(.bold)
            
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct SeasonRow: View {
    let season: Season
    
    var body: some View {
        HStack(spacing: 12) {
            // Season icon
            Image(systemName: season.isActive ? "calendar.circle.fill" : "calendar")
                .font(.title3)
                .foregroundStyle(season.isActive ? .blue : .secondary)
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(season.displayName)
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    if season.isActive {
                        Text("ACTIVE")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.blue)
                            .clipShape(Capsule())
                    }
                }
                
                HStack(spacing: 12) {
                    Label("\(season.totalGames)", systemImage: "sportscourt")
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
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray5), lineWidth: 1)
        )
        .padding(.horizontal)
    }
}

struct EmptySeasonsView: View {
    let onCreate: () -> Void
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 80))
                .foregroundStyle(.blue)
            
            Text("No Seasons Yet")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Create your first season to organize games, videos, and practices by year")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Create First Season", action: onCreate)
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .padding(.top, 60)
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
                        .font(.subheadline)
                        .fontWeight(.medium)
                } else {
                    Text("Practice Video")
                        .font(.subheadline)
                }
                
                if let created = video.createdAt {
                    Text(created.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
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
            Image(systemName: "sportscourt.fill")
                .foregroundStyle(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("vs \(game.opponent)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                if let date = game.date {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            if game.isComplete {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}

// Full list views for videos and games
struct SeasonVideosListView: View {
    let season: Season
    let videos: [VideoClip]
    @State private var selectedVideo: VideoClip?
    
    var body: some View {
        List(videos) { video in
            Button {
                selectedVideo = video
            } label: {
                SeasonVideoRow(video: video)
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("\(season.displayName) Videos")
        .sheet(item: $selectedVideo) { video in
            VideoPlayerView(clip: video)
        }
    }
}

struct SeasonGamesListView: View {
    let season: Season
    let games: [Game]
    
    var body: some View {
        List(games) { game in
            NavigationLink {
                GameDetailView(game: game)
            } label: {
                SeasonGameRow(game: game)
            }
        }
        .navigationTitle("\(season.displayName) Games")
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
