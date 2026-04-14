//
//  GameCreationView.swift
//  PlayerPath
//
//  Game creation form with opponent autocomplete and validation.
//

import SwiftUI
import SwiftData
import Foundation

struct GameCreationView: View {
    @Environment(\.dismiss) private var dismiss
    let athlete: Athlete?
    let onSave: (String, Date, Bool) -> Void

    @State private var opponent = ""
    @State private var date = Date()
    @State private var makeGameLive = false
    @State private var showingValidationError = false
    @State private var validationMessage = ""

    // Get previous opponents for autocomplete
    private var previousOpponents: [String] {
        guard let athlete = athlete else { return [] }
        let opponents = (athlete.games ?? [])
            .map { $0.opponent }
            .filter { !$0.isEmpty }
        // Deduplicate and sort by frequency
        let frequency = opponents.reduce(into: [:]) { counts, name in
            counts[name, default: 0] += 1
        }
        return Array(Set(opponents))
            .sorted { frequency[$0, default: 0] > frequency[$1, default: 0] }
    }

    // Filter opponents by current input
    private var filteredOpponents: [String] {
        guard !opponent.isEmpty else { return previousOpponents.prefix(5).map { $0 } }
        return previousOpponents.filter {
            $0.localizedCaseInsensitiveContains(opponent)
        }.prefix(5).map { $0 }
    }

    // Validation
    private var isValidOpponent: Bool {
        let trimmed = opponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 2 && trimmed.count <= 50
    }

    private var canSave: Bool {
        isValidOpponent
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Game Details") {
                    TextField("Opponent", text: $opponent)
                        .submitLabel(.done)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()

                    // Show validation feedback
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

                // Opponent Suggestions
                if !filteredOpponents.isEmpty && (opponent.count < 3 || !filteredOpponents.filter({ $0.localizedCaseInsensitiveContains(opponent) && $0 != opponent }).isEmpty) {
                    Section("Recent Opponents") {
                        ForEach(filteredOpponents, id: \.self) { suggestion in
                            Button {
                                opponent = suggestion
                            } label: {
                                HStack {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .foregroundColor(.brandNavy)
                                        .font(.caption)
                                    Text(suggestion)
                                        .foregroundColor(.primary)
                                    Spacer()
                                }
                            }
                        }
                    }
                }

                Section("Game Options") {
                    Toggle("Start as Live Game", isOn: $makeGameLive)

                    if makeGameLive {
                        Label {
                            Text("Game becomes active for recording")
                                .font(.caption)
                        } icon: {
                            Image(systemName: "info.circle")
                                .foregroundColor(.brandNavy)
                        }
                    }
                }

                Section {
                    Label {
                        Text("Add stats and videos after creating the game")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } icon: {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.yellow)
                    }
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
                    .disabled(!canSave)
                }
            }
            // Removed onAppear that sets selectedTournament
        }
        .alert("Validation Error", isPresented: $showingValidationError) {
            Button("OK") { }
        } message: {
            Text(validationMessage)
        }
    }

    private func saveGame() {
        // Final validation
        guard isValidOpponent else {
            validationMessage = "Please enter a valid opponent name (2-50 characters)"
            showingValidationError = true
            return
        }

        // Check for reasonable date (not too far in past/future)
        let yearFromNow = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
        let yearAgo = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()

        if date > yearFromNow {
            validationMessage = "Game date cannot be more than 1 year in the future"
            showingValidationError = true
            return
        }

        if date < yearAgo {
            validationMessage = "Game date cannot be more than 1 year in the past"
            showingValidationError = true
            return
        }

        #if DEBUG
        print("🎮 GameCreationView: Saving game | Opponent: '\(opponent.trimmingCharacters(in: .whitespacesAndNewlines))' | makeGameLive: \(makeGameLive)")
        #endif

        onSave(opponent.trimmingCharacters(in: .whitespacesAndNewlines), date, makeGameLive)
        dismiss()
    }
}

// DateFormatter.shortDate and .shortTime are defined in DateFormatters.swift
