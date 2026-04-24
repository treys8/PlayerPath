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

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var playResultType: PlayResultType = .single
    @State private var numberOfPlays: String = "1"
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var showingSuccessToast = false
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
                            .frame(width: horizontalSizeClass == .regular ? 120 : 80)
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
        .alert("Unable to Record Statistics", isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .toast(isPresenting: $showingSuccessToast, message: "Statistics Recorded")
        .onChange(of: showingSuccessToast) { _, new in
            if !new { dismiss() }
        }
    }

    private func pluralizedPlayType(_ playType: PlayResultType, count: Int) -> String {
        if count == 1 { return playType.displayName }
        switch playType {
        case .homeRun: return "Home Runs"
        case .groundOut: return "Ground Outs"
        case .flyOut: return "Fly Outs"
        case .hitByPitch, .batterHitByPitch: return "Hit By Pitches"
        case .wildPitch: return "Wild Pitches"
        case .pitchingStrikeout: return "Strikeouts"
        case .pitchingWalk: return "Walks"
        default: return playType.displayName + "s"
        }
    }

    private func updateGameStatistics(_ gameStats: GameStatistics, playResultType: PlayResultType, playCount: Int) {
        for _ in 0..<playCount {
            gameStats.addPlayResult(playResultType)
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

        // Flag this game as manual-entry before writing counters so the recalc
        // guard protects them from video-sync events (sticky flag).
        gameStats.hasManualEntry = true

        updateGameStatistics(gameStats, playResultType: playResultType, playCount: playCount)

        // Flag game for Firestore sync — without this, quick-entered stats stay
        // local-only until another mutation path triggers a sync.
        game.needsSync = true

        // Recalculate career + season statistics from scratch so they
        // stay consistent with game stats (also repairs any prior corruption).
        try? StatisticsService.shared.recalculateAthleteStatistics(
            for: athlete, context: modelContext, skipSave: true
        )

        do {
            try modelContext.save()
            showingSuccessToast = true

            if let user = game.athlete?.user {
                Task {
                    do {
                        try await SyncCoordinator.shared.syncGames(for: user)
                    } catch {
                        ErrorHandlerService.shared.handle(error, context: "QuickStatisticsEntryView.syncGames", showAlert: false)
                    }
                }
            }
        } catch {
            alertMessage = "Failed to save statistics. Please try again."
            showingAlert = true
        }
    }
}
