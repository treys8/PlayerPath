//
//  AddGameView.swift
//  PlayerPath
//
//  View for adding a new game to an athlete's season.
//

import SwiftUI
import SwiftData

struct AddGameView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let athlete: Athlete?

    @State private var opponent = ""
    @State private var date = Date()
    @State private var startAsLive = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isSeasonError = false

    init(athlete: Athlete? = nil) {
        self.athlete = athlete
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

                Section {
                    Toggle("Start as Live Game", isOn: $startAsLive)
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
            // Removed onAppear that sets selectedTournament
        }
        .alert(isSeasonError ? "No Active Season" : "Error", isPresented: $showingError) {
            if isSeasonError {
                Button("Create Season") {
                    dismiss()
                    // Post notification to open seasons view
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms for dismiss animation
                        NotificationCenter.default.post(name: Notification.Name.presentSeasons, object: athlete)
                    }
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

        let trimmedOpponent = opponent.trimmingCharacters(in: .whitespacesAndNewlines)

        #if DEBUG
        print("📱 AddGameView.saveGame() called")
        print("   Athlete: \(athlete.name)")
        print("   Active season: \(athlete.activeSeason?.name ?? "none")")
        print("   Seasons count: \(athlete.seasons?.count ?? 0)")
        #endif

        // Use GameService for consistent game creation
        let gameService = GameService(modelContext: modelContext)
        // Removed tournament parameter from call

        Task {
            let result = await gameService.createGame(
                for: athlete,
                opponent: trimmedOpponent,
                date: date,
                isLive: startAsLive
            )

            await MainActor.run {
                switch result {
                case .success(let createdGame):
                    #if DEBUG
                    print("   ✅ Game created successfully")
                    #endif
                    // Schedule a reminder if the game is in the future and reminders are enabled
                    if (try? modelContext.fetch(FetchDescriptor<UserPreferences>()).first)?.enableGameReminders ?? true,
                       let gameDate = createdGame.date,
                       gameDate > Date().addingTimeInterval(60 * 60) {
                        Task {
                            await PushNotificationService.shared.scheduleGameReminder(
                                gameId: createdGame.id.uuidString,
                                opponent: trimmedOpponent,
                                scheduledTime: gameDate
                            )
                        }
                    }
                    dismiss()
                case .failure(let error):
                    #if DEBUG
                    print("   ❌ Game creation failed: \(error)")
                    print("   Is season error: \(error == .noActiveSeason)")
                    #endif
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
                allowWithoutSeason: true
            )

            await MainActor.run {
                switch result {
                case .success(let createdGame):
                    // Success - dismiss
                    // Schedule a reminder if the game is in the future and reminders are enabled
                    if (try? modelContext.fetch(FetchDescriptor<UserPreferences>()).first)?.enableGameReminders ?? true,
                       let gameDate = createdGame.date,
                       gameDate > Date().addingTimeInterval(60 * 60) {
                        Task {
                            await PushNotificationService.shared.scheduleGameReminder(
                                gameId: createdGame.id.uuidString,
                                opponent: trimmedOpponent,
                                scheduledTime: gameDate
                            )
                        }
                    }
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
