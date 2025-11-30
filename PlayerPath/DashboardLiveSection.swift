//
//  DashboardLiveSection.swift
//  PlayerPath
//
//  Uses @Query to observe live games directly for reliable updates
//

import SwiftUI
import SwiftData

struct DashboardLiveSection: View {
    let athlete: Athlete

    // Use @Query to directly observe live games - bypasses relationship refresh issues
    @Query(
        filter: #Predicate<Game> { game in
            game.isLive == true
        },
        sort: \Game.date,
        order: .reverse
    ) private var allLiveGames: [Game]

    // Filter to only this athlete's live games
    private var liveGames: [Game] {
        allLiveGames.filter { $0.athlete?.id == athlete.id }
    }

    var body: some View {
        if !liveGames.isEmpty {
            VStack(spacing: 12) {
                HStack {
                    Text("Live")
                        .font(.headline)
                        .fontWeight(.semibold)
                    Spacer()
                }

                // Display as vertical list for compactness
                VStack(spacing: 8) {
                    ForEach(liveGames, id: \.id) { game in
                        NavigationLink {
                            GameDetailView(game: game)
                        } label: {
                            HStack(spacing: 12) {
                                // Live indicator
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 8, height: 8)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(game.opponent.isEmpty ? "Unknown" : game.opponent)
                                        .font(.subheadline)
                                        .fontWeight(.medium)

                                    if let date = game.date {
                                        Text(date, style: .date)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                Spacer()

                                // End button
                                Button {
                                    endGame(game)
                                } label: {
                                    Text("End")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.red)
                                        .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.easeInOut(duration: 0.25), value: liveGames.count)
        }
    }

    @Environment(\.modelContext) private var modelContext

    private func endGame(_ game: Game) {
        game.isLive = false
        game.isComplete = true

        if let athlete = game.athlete {
            // Create athlete statistics if they don't exist
            if athlete.statistics == nil {
                let newStats = AthleteStatistics()
                newStats.athlete = athlete
                athlete.statistics = newStats
                modelContext.insert(newStats)
            }

            // Aggregate game statistics into athlete's overall statistics
            if let athleteStats = athlete.statistics, let gameStats = game.gameStats {
                athleteStats.atBats += gameStats.atBats
                athleteStats.hits += gameStats.hits
                athleteStats.singles += gameStats.singles
                athleteStats.doubles += gameStats.doubles
                athleteStats.triples += gameStats.triples
                athleteStats.homeRuns += gameStats.homeRuns
                athleteStats.runs += gameStats.runs
                athleteStats.rbis += gameStats.rbis
                athleteStats.strikeouts += gameStats.strikeouts
                athleteStats.walks += gameStats.walks
                athleteStats.updatedAt = Date()
            }

            // Increment total games
            if let athleteStats = athlete.statistics {
                athleteStats.addCompletedGame()
            }
        }

        do {
            try modelContext.save()
            print("✅ Game ended successfully")
        } catch {
            print("❌ Error ending game: \(error)")
        }
    }
}
