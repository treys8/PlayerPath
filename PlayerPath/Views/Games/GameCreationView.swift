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
    /// Opt-in shot-by-shot tracking for this round. When true, scoring a hole
    /// opens ShotEntryView and the HoleScore is derived from the logged shots.
    var tracksShotByShot: Bool = false
}

struct GameCreationView: View {
    @Environment(\.dismiss) private var dismiss
    let athlete: Athlete?
    /// When set, this round is being added from a tournament's detail screen —
    /// the tournament link is fixed and shown read-only (no picker). SchemaV27.
    var preselectedTournament: GolfTournament? = nil
    let onSave: (String, Date, Bool, Season?, GolfRoundDetails?, String?, GolfTournament?) -> Void
    private var activeSport: Season.SportType { athlete?.sportType ?? .baseball }

    @State private var opponent = ""
    @State private var date = Date()
    @State private var makeGameLive = false
    @State private var selectedSeason: Season?
    @State private var didInitSeason = false
    @State private var showingValidationError = false
    @State private var validationMessage = ""
    @State private var isSaving = false
    /// Golf single-live confirmation before starting a new live tournament
    /// while another golf activity is live.
    @State private var showingSingleLiveConfirm = false

    // Golf-only state
    @State private var golfHoles: Int = 18
    @State private var golfParText: String = ""
    @State private var golfScoreText: String = ""
    @State private var golfLocation: String = ""
    /// Tournament this round joins (golf only). Initialized from
    /// `preselectedTournament`; otherwise chosen via the picker.
    @State private var selectedTournament: GolfTournament?
    @State private var didInitTournament = false

    private var isGolf: Bool { activeSport == .golf }
    private var primaryLabel: String { isGolf ? "Course" : "Opponent" }
    private var sectionTitle: String { isGolf ? "Round Details" : "Game Details" }
    private var titleText: String { isGolf ? "New Round" : "New Game" }

    /// Existing tournaments for this athlete, newest first — picker options.
    private var availableTournaments: [GolfTournament] {
        (athlete?.golfTournaments ?? [])
            .sorted { ($0.startDate ?? $0.createdAt ?? .distantPast) > ($1.startDate ?? $1.createdAt ?? .distantPast) }
    }
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
                return (season.sport ?? .baseball) == activeSport
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

    // Most recent prior golf game at the given course — source for pre-filling
    // round details (holes/par/location) when the user taps a recent course.
    // Sport-scoped to match previousOpponents so a baseball game sharing a
    // course-like name can't leak into golf pre-fill.
    private func mostRecentGame(forCourse course: String) -> Game? {
        guard let athlete = athlete else { return nil }
        return (athlete.games ?? [])
            .filter { game in
                guard game.opponent == course else { return false }
                guard let season = game.season else { return activeSport == .baseball }
                return (season.sport ?? .baseball) == activeSport
            }
            .max(by: { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) })
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
                                .foregroundColor(Theme.warning)
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

                    // Tournament link (SchemaV27). Read-only when added from a
                    // tournament's detail screen; otherwise an optional picker
                    // among the athlete's existing tournaments.
                    if let preselectedTournament {
                        Section("Tournament") {
                            LabeledContent("Tournament", value: preselectedTournament.name)
                        }
                    } else if !availableTournaments.isEmpty {
                        Section("Tournament") {
                            Picker("Tournament", selection: $selectedTournament) {
                                Text("None").tag(GolfTournament?.none)
                                ForEach(availableTournaments) { tournament in
                                    Text(tournament.name).tag(GolfTournament?.some(tournament))
                                }
                            }
                        }
                    }
                }

                // Opponent Suggestions — show when there are matches and at least one differs from the current input.
                if !filteredOpponents.isEmpty && !filteredOpponents.allSatisfy({ $0 == opponent }) {
                    Section(recentLabel) {
                        ForEach(filteredOpponents, id: \.self) { suggestion in
                            Button {
                                opponent = suggestion
                                // Golf: tapping a course the athlete has played
                                // before pre-fills its round details from the
                                // most recent prior round there. Score is never
                                // carried — it's per-round.
                                if isGolf, let prior = mostRecentGame(forCourse: suggestion) {
                                    if let h = prior.holes { golfHoles = h }
                                    if let p = prior.par { golfParText = String(p) }
                                    if let loc = prior.location, !loc.isEmpty { golfLocation = loc }
                                }
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
                    .disabled(!canSave || isSaving)
                }
            }
            .onAppear {
                if !didInitSeason {
                    selectedSeason = athlete?.activeSeason
                    didInitSeason = true
                }
                if !didInitTournament {
                    selectedTournament = preselectedTournament
                    didInitTournament = true
                }
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
        .confirmationDialog(
            "End your live \(athlete.flatMap { LiveActivityGuard.currentLiveGolfLabel(for: $0) } ?? "activity")?",
            isPresented: $showingSingleLiveConfirm,
            titleVisibility: .visible
        ) {
            Button("End & Start New", role: .destructive) { commitSave() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You already have a live \(athlete.flatMap { LiveActivityGuard.currentLiveGolfLabel(for: $0) } ?? "activity") going. Starting a new one will end it.")
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

        // Golf par/score bounds — both fields are optional, but when present
        // they must be sensible. Mirrors EnterScoreSheet's thresholds so the
        // two entry paths agree (par 1–199, score in holes...299).
        if isGolf {
            let parTrimmed = golfParText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !parTrimmed.isEmpty {
                guard let par = Int(parTrimmed), par > 0, par < 200 else {
                    validationMessage = "Par must be a number between 1 and 199."
                    showingValidationError = true
                    return
                }
            }
            let scoreTrimmed = golfScoreText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !scoreTrimmed.isEmpty {
                guard let total = Int(scoreTrimmed), total >= golfHoles, total < 300 else {
                    validationMessage = "Total score must be a number between \(golfHoles) and 299."
                    showingValidationError = true
                    return
                }
            }
        }

        // Golf single-live guard: if this tournament would go live and another
        // golf activity (tournament or practice) already is, confirm the
        // replacement first. Baseball keeps GameService's silent auto-end.
        if isGolf, makeGameLive, (selectedSeason?.isActive ?? true),
           let athlete, LiveActivityGuard.hasAnyLiveGolf(for: athlete) {
            showingSingleLiveConfirm = true
            return
        }

        commitSave()
    }

    private func commitSave() {
        // Terminal save path — guard against a double-tap committing twice.
        guard !isSaving else { return }
        isSaving = true
        #if DEBUG
        print("🎮 GameCreationView: Saving game | Opponent: '\(opponent.trimmingCharacters(in: .whitespacesAndNewlines))' | makeGameLive: \(makeGameLive) | season: \(selectedSeason?.name ?? "none") | isGolf: \(isGolf)")
        #endif

        let golf: GolfRoundDetails? = isGolf ? GolfRoundDetails(
            holes: golfHoles,
            par: Int(golfParText.trimmingCharacters(in: .whitespacesAndNewlines)),
            totalScore: Int(golfScoreText.trimmingCharacters(in: .whitespacesAndNewlines)),
            // Seed the round's default scoring mode from the remembered global
            // preference (set by the in-sheet Quick | Shot-by-shot switch). The
            // first Score Hole tap then opens in that mode; no creation toggle.
            tracksShotByShot: UserDefaults.standard.bool(forKey: GolfPrefs.preferredShotByShot)
        ) : nil

        let locationTrimmed = golfLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        let location: String? = (isGolf && !locationTrimmed.isEmpty) ? locationTrimmed : nil

        // Tournament link (SchemaV27): preselected wins, else the picker choice.
        let tournament: GolfTournament? = isGolf ? (preselectedTournament ?? selectedTournament) : nil

        onSave(opponent.trimmingCharacters(in: .whitespacesAndNewlines), date, makeGameLive, selectedSeason, golf, location, tournament)
        dismiss()
    }
}

// DateFormatter.shortDate and .shortTime are defined in DateFormatters.swift
