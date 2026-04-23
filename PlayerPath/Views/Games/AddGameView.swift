//
//  AddGameView.swift
//  PlayerPath
//
//  View for adding a new game to an athlete's season.
//

import SwiftUI
import SwiftData
import os

private let log = Logger(subsystem: "com.playerpath.app", category: "AddGameView")

struct AddGameView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let athlete: Athlete?

    @State private var opponent = ""
    @State private var date = Date()
    @State private var startAsLive = false
    @State private var selectedSeason: Season?
    @State private var didInitSeason = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isSeasonError = false
    @State private var shouldPresentSeasonsOnDismiss = false

    init(athlete: Athlete? = nil) {
        self.athlete = athlete
    }

    private var hasMultipleSeasons: Bool {
        (athlete?.seasons?.count ?? 0) > 1
    }

    private var isValidOpponent: Bool {
        let trimmed = opponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 2 && trimmed.count <= 50
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Game Details") {
                    TextField("Opponent", text: $opponent)
                        .submitLabel(.done)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Opponent name")

                    if !opponent.isEmpty && !isValidOpponent {
                        Label {
                            Text("Opponent name must be 2-50 characters")
                                .font(.caption)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                        }
                    }

                    DatePicker("Date & Time", selection: $date)
                }

                // Removed tournament selection section

                if hasMultipleSeasons {
                    Section("Season") {
                        SeasonPickerRow(athlete: athlete, selection: $selectedSeason)
                    }
                }

                Section {
                    Toggle("Start as Live Game", isOn: $startAsLive)
                        .disabled(selectedSeason?.isActive == false)
                }
            }
            .navigationTitle("New Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveGame()
                    }
                    .disabled(!isValidOpponent)
                }
            }
            .onAppear {
                guard !didInitSeason else { return }
                selectedSeason = athlete?.activeSeason
                didInitSeason = true
            }
            .onChange(of: selectedSeason) { _, newValue in
                if newValue?.isActive == false { startAsLive = false }
            }
        }
        .alert(isSeasonError ? "No Active Season" : "Error", isPresented: $showingError) {
            if isSeasonError {
                Button("Create Season") {
                    shouldPresentSeasonsOnDismiss = true
                    dismiss()
                }
                Button("Add to Year Only") {
                    saveGameWithoutSeason()
                }
                Button("Cancel", role: .cancel) { }
            } else {
                Button("OK") { }
            }
        } message: {
            if isSeasonError {
                let calendar = Calendar.current
                let year = calendar.component(.year, from: date)
                Text("You don't have an active season. Create a season to organize your games, or add this game to year \(year) for basic tracking.")
            } else {
                Text(errorMessage)
            }
        }
        .onDisappear {
            if shouldPresentSeasonsOnDismiss {
                NotificationCenter.default.post(name: Notification.Name.presentSeasons, object: athlete)
            }
        }
    }

    private func saveGame() {
        guard let athlete = athlete else {
            errorMessage = "No athlete selected"
            showingError = true
            return
        }

        guard isValidOpponent else {
            errorMessage = "Please enter a valid opponent name (2-50 characters)"
            showingError = true
            return
        }

        // Bound the game date by the selected season when one is chosen.
        // Active season has nil endDate — use distantFuture so same-day games aren't rejected.
        if let selectedSeason {
            let start = selectedSeason.startDate ?? .distantPast
            let end = selectedSeason.endDate ?? .distantFuture
            if date < start {
                errorMessage = "Game date is before the selected season starts."
                isSeasonError = false
                showingError = true
                return
            }
            if date > end {
                errorMessage = "Game date is after the selected season ends."
                isSeasonError = false
                showingError = true
                return
            }
        }

        let trimmedOpponent = opponent.trimmingCharacters(in: .whitespacesAndNewlines)

        log.debug("saveGame() called for athlete: \(athlete.name, privacy: .private)")
        log.debug("Active season: \(athlete.activeSeason?.name ?? "none"), seasons count: \(athlete.seasons?.count ?? 0)")

        // Use GameService for consistent game creation
        let gameService = GameService(modelContext: modelContext)
        // Removed tournament parameter from call

        Task {
            let result = await gameService.createGame(
                for: athlete,
                opponent: trimmedOpponent,
                date: date,
                isLive: startAsLive,
                season: selectedSeason
            )

            await MainActor.run {
                switch result {
                case .success:
                    log.info("Game created successfully")
                    dismiss()
                case .failure(let error):
                    log.warning("Game creation failed: \(error.localizedDescription), isSeasonError: \(error == .noActiveSeason)")
                    // Show error alert
                    errorMessage = error.localizedDescription
                    isSeasonError = (error == .noActiveSeason)
                    showingError = true
                }
            }
        }
    }

    private func saveGameWithoutSeason() {
        guard let athlete = athlete else {
            errorMessage = "No athlete selected"
            showingError = true
            return
        }

        guard isValidOpponent else {
            errorMessage = "Please enter a valid opponent name (2-50 characters)"
            showingError = true
            return
        }

        let trimmedOpponent = opponent.trimmingCharacters(in: .whitespacesAndNewlines)

        // Use GameService with allowWithoutSeason flag
        let gameService = GameService(modelContext: modelContext)

        Task {
            let result = await gameService.createGame(
                for: athlete,
                opponent: trimmedOpponent,
                date: date,
                isLive: startAsLive,
                season: selectedSeason,
                allowWithoutSeason: true
            )

            await MainActor.run {
                switch result {
                case .success:
                    dismiss()
                case .failure(let error):
                    // Show error alert
                    errorMessage = error.localizedDescription
                    isSeasonError = false
                    showingError = true
                }
            }
        }
    }
}
