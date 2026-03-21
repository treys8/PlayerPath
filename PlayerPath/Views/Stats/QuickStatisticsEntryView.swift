//
//  QuickStatisticsEntryView.swift
//  PlayerPath
//
//  Created by Trey Schilling on 3/21/26.
//

import SwiftUI
import SwiftData

// MARK: - Quick Statistics Entry View
@MainActor
struct QuickStatisticsEntryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let game: Game
    let athlete: Athlete?

    @State private var playResultType: PlayResultType = .single
    @State private var numberOfPlays: String = "1"
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @FocusState private var isPlaysFieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Current Game") {
                    HStack {
                        Text("Opponent:")
                            .fontWeight(.semibold)
                        Spacer()
                        Text(game.opponent)
                            .foregroundColor(.secondary)
                    }

                    if game.isLive {
                        HStack {
                            Image(systemName: "circle.fill")
                                .foregroundColor(.red)
                                .font(.caption)
                            Text("LIVE GAME")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.red)
                        }
                    }
                }

                Section("Record Play Result") {
                    Picker("Play Result", selection: $playResultType) {
                        Section("Batting") {
                            ForEach(PlayResultType.battingCases, id: \.self) { playType in
                                Text(playType.displayName).tag(playType)
                            }
                        }
                        Section("Pitching") {
                            ForEach(PlayResultType.pitchingCases, id: \.self) { playType in
                                Text(playType.displayName).tag(playType)
                            }
                        }
                    }
                    .pickerStyle(.menu)

                    HStack {
                        Text("Number of plays")
                            .fontWeight(.medium)
                        TextField("1", text: $numberOfPlays)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .focused($isPlaysFieldFocused)
                    }
                }

                Section("Play Details") {
                    HStack {
                        Text("Result Type:")
                        Spacer()
                        Text(playResultType.displayName)
                            .fontWeight(.semibold)
                            .foregroundColor(playResultType.isHit ? .green : .orange)
                    }

                    if playResultType.isHit {
                        HStack {
                            Text("Bases:")
                            Spacer()
                            Text("\(playResultType.bases)")
                                .fontWeight(.semibold)
                                .foregroundColor(.blue)
                        }

                        if playResultType.isHighlight {
                            HStack {
                                Image(systemName: "star.fill")
                                    .foregroundColor(.yellow)
                                Text("This will be marked as a highlight")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Record Statistics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button("Save") {
                        savePlayResults()
                    }
                    .disabled(numberOfPlays.isEmpty)
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isPlaysFieldFocused = false
                    }
                }
            }
        }
        .alert("Statistics Recorded", isPresented: $showingAlert) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text(alertMessage)
        }
    }

    private func pluralizedPlayType(_ playType: PlayResultType, count: Int) -> String {
        if count == 1 { return playType.displayName }
        switch playType {
        case .homeRun: return "Home Runs"
        case .groundOut: return "Ground Outs"
        case .flyOut: return "Fly Outs"
        case .hitByPitch: return "Hit By Pitches"
        case .wildPitch: return "Wild Pitches"
        default: return playType.displayName + "s"
        }
    }

    private func updateGameStatistics(_ gameStats: GameStatistics, playResultType: PlayResultType, playCount: Int) {
        if playResultType.isHit {
            gameStats.hits += playCount
        }
        if playResultType.countsAsAtBat {
            gameStats.atBats += playCount
        }
        if playResultType == .strikeout {
            gameStats.strikeouts += playCount
        }
        if playResultType == .walk {
            gameStats.walks += playCount
        }
    }

    private func savePlayResults() {
        guard let playCount = Int(numberOfPlays), playCount > 0, playCount <= 99 else {
            alertMessage = "Please enter a valid number of plays (1-99)"
            showingAlert = true
            return
        }

        guard let athlete = athlete else {
            alertMessage = "No athlete selected"
            showingAlert = true
            return
        }

        // Update athlete statistics
        if let stats = athlete.statistics {
            for _ in 0..<playCount {
                stats.addPlayResult(playResultType)
            }
        } else {
            // Create statistics if they don't exist
            let newStats = AthleteStatistics()
            athlete.statistics = newStats
            newStats.athlete = athlete
            modelContext.insert(newStats)

            for _ in 0..<playCount {
                newStats.addPlayResult(playResultType)
            }
        }

        // Update game statistics
        let gameStats: GameStatistics
        if let existingStats = game.gameStats {
            gameStats = existingStats
        } else {
            let newGameStats = GameStatistics()
            game.gameStats = newGameStats
            newGameStats.game = game
            modelContext.insert(newGameStats)
            gameStats = newGameStats
        }

        updateGameStatistics(gameStats, playResultType: playResultType, playCount: playCount)

        do {
            try modelContext.save()
            alertMessage = "Recorded \(playCount) \(pluralizedPlayType(playResultType, count: playCount)) for \(game.opponent)"
            showingAlert = true
        } catch {
            alertMessage = "Failed to save statistics. Please try again."
            showingAlert = true
        }
    }
}
