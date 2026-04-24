//
//  GameSelectionForStatsView.swift
//  PlayerPath
//
//  Created by Trey Schilling on 3/21/26.
//

import SwiftUI
import SwiftData

// MARK: - Game Selection For Stats View
struct GameSelectionForStatsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let athlete: Athlete?

    @State private var showingManualEntry = false
    @State private var selectedGame: Game?
    @State private var showingCreateGame = false

    private var availableGames: [Game] {
        let games = athlete?.games ?? []
        return games.sorted { lhs, rhs in
            switch (lhs.date, rhs.date) {
            case let (l?, r?):
                return l > r // newest first
            case (nil, _?):
                return false // nil goes after any non-nil
            case (_?, nil):
                return true  // non-nil comes before nil
            case (nil, nil):
                return false // maintain relative order for two nils
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Select a Game") {
                    if availableGames.isEmpty {
                        VStack(spacing: 15) {
                            Text("No games found")
                                .foregroundColor(.secondary)

                            Button("Create a New Game") {
                                showingCreateGame = true
                            }
                            .buttonStyle(.bordered)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    } else {
                        ForEach(availableGames) { game in
                            Button(action: {
                                selectedGame = game
                                showingManualEntry = true
                            }) {
                                GameRowForStats(game: game)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section {
                    Button("Create New Game for Statistics") {
                        showingCreateGame = true
                    }
                    .foregroundColor(.blue)
                }
            }
            .navigationTitle("Select Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingManualEntry) {
            if let game = selectedGame {
                ManualStatisticsEntryView(game: game)
            }
        }
        .sheet(isPresented: $showingCreateGame) {
            AddGameView(athlete: athlete)
        }
    }
}

struct GameRowForStats: View {
    let game: Game

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("vs \(game.opponent)")
                    .font(.headline)
                    .fontWeight(.semibold)

                if let date = game.date {
                    Text(date, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("No date")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack {
                    switch game.displayStatus {
                    case .live:
                        Text("LIVE")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .cornerRadius(4)
                    case .completed:
                        Text("COMPLETED")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.gray)
                            .cornerRadius(4)
                    case .scheduled:
                        Text("SCHEDULED")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue)
                            .cornerRadius(4)
                    }

                    Spacer()
                }
            }

            Spacer()

            VStack(alignment: .trailing) {
                if let stats = game.gameStats {
                    Text("\(stats.hits)/\(stats.atBats)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)

                    if stats.atBats > 0 {
                        Text(StatisticsService.shared.formatBattingAverage(Double(stats.hits) / Double(stats.atBats)))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("No stats")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding(.vertical, 4)
    }
}
