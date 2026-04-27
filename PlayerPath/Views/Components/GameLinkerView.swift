//
//  GameLinkerView.swift
//  PlayerPath
//
//  Sheet for linking a video clip to a game.
//

import SwiftUI
import SwiftData

struct GameLinkerView: View {
    let clip: VideoClip
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Game.date, order: .reverse) private var allGames: [Game]

    @State private var selectedGame: Game?
    @State private var hasChanges = false
    @State private var errorMessage: String?
    @State private var showingError = false

    private var athleteGames: [Game] {
        guard let athleteId = clip.athlete?.id else { return [] }
        return allGames.filter { $0.athlete?.id == athleteId }
    }

    var body: some View {
        NavigationStack {
            List {
                // Option to unlink
                Section {
                    Button {
                        selectedGame = nil
                        hasChanges = (clip.game != nil)
                    } label: {
                        HStack {
                            Label("No Game", systemImage: "minus.circle")
                                .foregroundColor(.primary)
                            Spacer()
                            if selectedGame == nil && clip.game == nil {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.brandNavy)
                            } else if selectedGame == nil && hasChanges {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.brandNavy)
                            }
                        }
                    }
                } footer: {
                    Text("Video will not be associated with any game")
                }

                // Games list
                if athleteGames.isEmpty {
                    Section {
                        Text("No games found for this athlete")
                            .foregroundColor(.secondary)
                    }
                } else {
                    Section("Games") {
                        ForEach(athleteGames) { game in
                            Button {
                                selectedGame = game
                                hasChanges = (clip.game?.id != game.id)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("vs \(game.opponent.isEmpty ? "Unknown" : game.opponent)")
                                            .foregroundColor(.primary)
                                        if let date = game.date {
                                            Text(date, format: .dateTime.month(.abbreviated).day().year())
                                                .font(.bodySmall)
                                                .foregroundColor(.secondary)
                                        }
                                        if let season = game.season {
                                            Text(season.displayName)
                                                .font(.labelSmall)
                                                .foregroundColor(.brandNavy)
                                        }
                                    }
                                    Spacer()
                                    if (selectedGame?.id == game.id) || (!hasChanges && clip.game?.id == game.id) {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.brandNavy)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Link to Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                    .disabled(!hasChanges)
                }
            }
            .onAppear {
                selectedGame = clip.game
            }
            .alert("Save Failed", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func saveChanges() {
        let oldGame = clip.game
        let prevSeason = clip.season
        let prevNeedsSync = clip.needsSync

        clip.game = selectedGame
        clip.needsSync = true
        if let game = selectedGame {
            clip.season = game.season
        }

        // Recalculate stats for affected games
        if let oldGame, oldGame != selectedGame {
            try? StatisticsService.shared.recalculateGameStatistics(for: oldGame, context: modelContext)
            if let athlete = oldGame.athlete {
                try? StatisticsService.shared.recalculateAthleteStatistics(for: athlete, context: modelContext, skipSave: true)
            }
        }
        if let newGame = selectedGame, newGame != oldGame {
            try? StatisticsService.shared.recalculateGameStatistics(for: newGame, context: modelContext)
        }

        do {
            try modelContext.save()
            Haptics.success()
            dismiss()
        } catch {
            // Roll back in-memory mutations
            clip.game = oldGame
            clip.season = prevSeason
            clip.needsSync = prevNeedsSync
            ErrorHandlerService.shared.handle(error, context: "GameLinkerView.saveClipAssignment", showAlert: false)
            errorMessage = "Could not save game assignment. Please try again."
            showingError = true
        }
    }
}
