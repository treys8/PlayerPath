//
//  GameCreationView.swift
//  PlayerPath
//
//  Game creation form with opponent autocomplete and validation.
//

import SwiftUI
import SwiftData
import Foundation

/// Golf-specific fields collected at tournament creation time.
struct GolfRoundDetails: Equatable {
    var holes: Int
    var par: Int?
    var totalScore: Int?
}

struct GameCreationView: View {
    @Environment(\.dismiss) private var dismiss
    let athlete: Athlete?
    let onSave: (String, Date, Bool, Season?, GolfRoundDetails?, String?) -> Void
    private var activeSport: Season.SportType { athlete?.sportType ?? .baseball }

    @State private var opponent = ""
    @State private var date = Date()
    @State private var makeGameLive = false
    @State private var selectedSeason: Season?
    @State private var didInitSeason = false
    @State private var showingValidationError = false
    @State private var validationMessage = ""

    // Golf-only state
    @State private var golfHoles: Int = 18
    @State private var golfParText: String = ""
    @State private var golfScoreText: String = ""
    @State private var golfLocation: String = ""

    private var isGolf: Bool { activeSport == .golf }
    private var primaryLabel: String { isGolf ? "Course" : "Opponent" }
    private var sectionTitle: String { isGolf ? "Tournament Details" : "Game Details" }
    private var titleText: String { isGolf ? "New Tournament" : "New Game" }
    private var recentLabel: String { isGolf ? "Recent Courses" : "Recent Opponents" }
    private var validationSubject: String { isGolf ? "Course" : "Opponent" }
    private var liveLabel: String { isGolf ? "Start as Live Round" : "Start as Live Game" }
    private var liveInfo: String { isGolf ? "Round becomes active for recording" : "Game becomes active for recording" }
    private var liveDisabledInfo: String { isGolf ? "Live mode isn't available for past seasons." : "Live mode isn't available for past seasons." }

    private var hasMultipleSeasons: Bool {
        (athlete?.seasons?.count ?? 0) > 1
    }

    // Get previous opponents for autocomplete. Scoped to the active sport so the
    // golf "Recent Courses" list doesn't surface baseball opponents (and vice
    // versa). Seasonless legacy games are treated as baseball — the sport
    // concept didn't exist before v6.0.
    private var previousOpponents: [String] {
        guard let athlete = athlete else { return [] }
        let opponents = (athlete.games ?? [])
            .filter { game in
                guard let season = game.season else { return activeSport == .baseball }
                return season.sport == activeSport
            }
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
        let maxLen = isGolf ? 80 : 50
        return trimmed.count >= 2 && trimmed.count <= maxLen
    }

    private var canSave: Bool {
        isValidOpponent
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(sectionTitle) {
                    TextField(primaryLabel, text: $opponent)
                        .submitLabel(.done)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()

                    // Show validation feedback
                    if !opponent.isEmpty && !isValidOpponent {
                        Label {
                            Text("\(validationSubject) name must be 2-\(isGolf ? 80 : 50) characters")
                                .font(.bodySmall)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                        }
                    }

                    DatePicker("Date & Time", selection: $date)

                    if isGolf {
                        TextField("Location (Optional)", text: $golfLocation)
                            .textInputAutocapitalization(.words)
                    }
                }

                if isGolf {
                    Section("Round") {
                        Picker("Holes", selection: $golfHoles) {
                            Text("9").tag(9)
                            Text("18").tag(18)
                        }
                        .pickerStyle(.segmented)

                        HStack {
                            Text("Par")
                            Spacer()
                            TextField("e.g. 72", text: $golfParText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                        }

                        HStack {
                            Text("Total Score")
                            Spacer()
                            TextField("Optional", text: $golfScoreText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                        }
                    }
                }

                // Opponent Suggestions — show when there are matches and at least one differs from the current input.
                if !filteredOpponents.isEmpty && !filteredOpponents.allSatisfy({ $0 == opponent }) {
                    Section(recentLabel) {
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

                if hasMultipleSeasons {
                    Section {
                        SeasonPickerRow(athlete: athlete, selection: $selectedSeason)
                    } header: {
                        Text("Season")
                    } footer: {
                        if let selectedSeason, !selectedSeason.isActive {
                            Text("This game will be filed on a past season and won't affect your current season's stats.")
                        }
                    }
                }

                Section(isGolf ? "Round Options" : "Game Options") {
                    Toggle(liveLabel, isOn: $makeGameLive)
                        .disabled(selectedSeason?.isActive == false)

                    if makeGameLive {
                        Label {
                            Text(liveInfo)
                                .font(.bodySmall)
                        } icon: {
                            Image(systemName: "info.circle")
                                .foregroundColor(.brandNavy)
                        }
                    } else if selectedSeason?.isActive == false {
                        Label {
                            Text(liveDisabledInfo)
                                .font(.bodySmall)
                        } icon: {
                            Image(systemName: "info.circle")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section {
                    Label {
                        Text(isGolf
                             ? "Add videos and the final score after creating the round"
                             : "Add stats and videos after creating the game")
                            .font(.bodySmall)
                            .foregroundColor(.secondary)
                    } icon: {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.yellow)
                    }
                }
            }
            .navigationTitle(titleText)
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
            .onAppear {
                guard !didInitSeason else { return }
                selectedSeason = athlete?.activeSeason
                didInitSeason = true
            }
            .onChange(of: selectedSeason) { _, newValue in
                // Live mode is only valid on the active season
                if newValue?.isActive == false { makeGameLive = false }
            }
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
            let maxLen = isGolf ? 80 : 50
            validationMessage = "Please enter a valid \(validationSubject.lowercased()) name (2-\(maxLen) characters)"
            showingValidationError = true
            return
        }

        // Bound the game date by the selected season when one is chosen, otherwise
        // fall back to the legacy ±1yr guardrails. This lets users file historical
        // games onto a past season (e.g., "Spring 2024") without bumping the year cap.
        if let selectedSeason {
            let start = selectedSeason.startDate ?? .distantPast
            // Active season has nil endDate; don't cap at "now" — users can schedule later today.
            let end = selectedSeason.endDate ?? .distantFuture
            if date < start {
                validationMessage = "Game date is before the selected season starts."
                showingValidationError = true
                return
            }
            if date > end {
                validationMessage = "Game date is after the selected season ends."
                showingValidationError = true
                return
            }
        } else {
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
        }

        #if DEBUG
        print("🎮 GameCreationView: Saving game | Opponent: '\(opponent.trimmingCharacters(in: .whitespacesAndNewlines))' | makeGameLive: \(makeGameLive) | season: \(selectedSeason?.name ?? "none") | isGolf: \(isGolf)")
        #endif

        let golf: GolfRoundDetails? = isGolf ? GolfRoundDetails(
            holes: golfHoles,
            par: Int(golfParText.trimmingCharacters(in: .whitespacesAndNewlines)),
            totalScore: Int(golfScoreText.trimmingCharacters(in: .whitespacesAndNewlines))
        ) : nil

        let locationTrimmed = golfLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        let location: String? = (isGolf && !locationTrimmed.isEmpty) ? locationTrimmed : nil

        onSave(opponent.trimmingCharacters(in: .whitespacesAndNewlines), date, makeGameLive, selectedSeason, golf, location)
        dismiss()
    }
}

// DateFormatter.shortDate and .shortTime are defined in DateFormatters.swift
