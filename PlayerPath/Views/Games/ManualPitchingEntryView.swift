//
//  ManualPitchingEntryView.swift
//  PlayerPath
//
//  Manual entry of a pitching box-score line for a game. Pitchers throw far more
//  pitches than they film, so this — not video tagging — is the primary source for
//  pitching stats. Mirrors ManualStatisticsEntryView (additive: current + new = total,
//  sticky hasManualEntry flag, recalc + sync on save).
//
//  KNOWN LIMITATION (shared with manual batting entry): hasManualEntry is a single
//  game-level flag, so once set it makes the WHOLE game's recalc a no-op. Consequences:
//    1. Velocity (Avg FB / Off-Speed) comes only from filmed clips, so this game's clip
//       velocities are not counted — velocity aggregates come from non-manual games and
//       practice clips.
//    2. For a two-way player, manually entering a pitching line also FREEZES that game's
//       video-derived batting line at its current value (future batting-clip edits won't
//       update it). Low practical impact since manual entry targets completed past games.
//  A proper fix (split batting/pitching manual flags + partial recalc) is blocked by the
//  shared `hitByPitches` field, which feeds both OBP and opponent-AVG — it can't be reset
//  per-side cleanly. Deferred; revisit alongside splitting batter-HBP vs pitcher-HBP.
//

import SwiftUI
import SwiftData

struct ManualPitchingEntryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let game: Game

    @State private var inningsWhole: String = ""
    @State private var partialOuts: Int = 0          // 0, 1 (⅓), or 2 (⅔)
    @State private var hitsAllowed: String = ""
    @State private var runs: String = ""
    @State private var earnedRuns: String = ""
    @State private var homeRunsAllowed: String = ""
    @State private var walks: String = ""
    @State private var strikeouts: String = ""
    @State private var hitByPitches: String = ""
    @State private var wildPitches: String = ""
    @State private var battersFaced: String = ""
    @State private var pitchCount: String = ""
    @State private var strikes: String = ""
    @State private var showingValidationAlert = false
    @State private var alertMessage = ""

    @FocusState private var keyboardActive: Bool

    // Use game.gameStats directly — never a throwaway uninserted GameStatistics().
    private var existingGameStats: GameStatistics? { game.gameStats }

    // MARK: - Parsed new input
    private var newInningsWhole: Int { Int(inningsWhole) ?? 0 }
    private var newOuts: Int { newInningsWhole * 3 + partialOuts }
    private var newHitsAllowed: Int { Int(hitsAllowed) ?? 0 }
    private var newRuns: Int { Int(runs) ?? 0 }
    private var newEarnedRuns: Int { Int(earnedRuns) ?? 0 }
    private var newHomeRunsAllowed: Int { Int(homeRunsAllowed) ?? 0 }
    private var newWalks: Int { Int(walks) ?? 0 }
    private var newStrikeouts: Int { Int(strikeouts) ?? 0 }
    private var newHitByPitches: Int { Int(hitByPitches) ?? 0 }
    private var newWildPitches: Int { Int(wildPitches) ?? 0 }
    private var newBattersFaced: Int { Int(battersFaced) ?? 0 }
    private var newPitchCount: Int { Int(pitchCount) ?? 0 }
    private var newStrikes: Int { Int(strikes) ?? 0 }
    private var newBalls: Int { max(0, newPitchCount - newStrikes) }

    // MARK: - Preview totals (existing + new)
    private var totalOuts: Int { (existingGameStats?.outsRecorded ?? 0) + newOuts }
    private var totalEarnedRuns: Int { (existingGameStats?.earnedRuns ?? 0) + newEarnedRuns }
    private var totalHitsAllowed: Int { (existingGameStats?.hitsAllowed ?? 0) + newHitsAllowed }
    private var totalWalks: Int { (existingGameStats?.pitchingWalks ?? 0) + newWalks }
    private var totalStrikeouts: Int { (existingGameStats?.pitchingStrikeouts ?? 0) + newStrikeouts }

    private func ip(_ outs: Int) -> String { "\(outs / 3).\(outs % 3)" }
    private var previewERA: Double {
        totalOuts > 0 ? Double(totalEarnedRuns) * 27.0 / Double(totalOuts) : 0
    }
    private var previewWHIP: Double {
        totalOuts > 0 ? Double(totalWalks + totalHitsAllowed) * 3.0 / Double(totalOuts) : 0
    }

    private var hasAnyInput: Bool {
        newOuts > 0 || !hitsAllowed.isEmpty || !runs.isEmpty || !earnedRuns.isEmpty ||
        !homeRunsAllowed.isEmpty || !walks.isEmpty || !strikeouts.isEmpty ||
        !hitByPitches.isEmpty || !wildPitches.isEmpty || !battersFaced.isEmpty ||
        !pitchCount.isEmpty || !strikes.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Game Information").smallCapsLabel()) {
                    HStack {
                        Text("Opponent:").font(.headingMedium)
                        Spacer()
                        Text(game.opponent).foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Date:").font(.headingMedium)
                        Spacer()
                        if let date = game.date {
                            Text(date, style: .date).foregroundColor(.secondary)
                        } else {
                            Text("Unknown Date").foregroundColor(.secondary)
                        }
                    }
                }

                Section(header: Text("Innings Pitched").smallCapsLabel()) {
                    HStack {
                        Image(systemName: "circle.dashed")
                            .foregroundColor(.purple)
                            .frame(width: 25)
                        Text("Full Innings").font(.labelLarge)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        TextField("0", text: $inningsWhole)
                            .focused($keyboardActive)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .multilineTextAlignment(.center)
                    }
                    Picker("Plus Outs", selection: $partialOuts) {
                        Text("+0").tag(0)
                        Text("+⅓").tag(1)
                        Text("+⅔").tag(2)
                    }
                    .pickerStyle(.segmented)
                }

                Section(header: Text("Pitching Line").smallCapsLabel()) {
                    PitchNumberRow(title: "Hits Allowed", value: $hitsAllowed, icon: "baseball.fill", color: .red, focus: $keyboardActive)
                    PitchNumberRow(title: "Runs", value: $runs, icon: "figure.run", color: .orange, focus: $keyboardActive)
                    PitchNumberRow(title: "Earned Runs", value: $earnedRuns, icon: "flame.fill", color: .red, focus: $keyboardActive)
                    PitchNumberRow(title: "Home Runs Allowed", value: $homeRunsAllowed, icon: "arrow.up.forward.circle.fill", color: .red, focus: $keyboardActive)
                    PitchNumberRow(title: "Walks (BB)", value: $walks, icon: "figure.walk", color: .cyan, focus: $keyboardActive)
                    PitchNumberRow(title: "Strikeouts (K)", value: $strikeouts, icon: "k.circle.fill", color: .green, focus: $keyboardActive)
                    PitchNumberRow(title: "Hit By Pitch", value: $hitByPitches, icon: "exclamationmark.circle.fill", color: .purple, focus: $keyboardActive)
                    PitchNumberRow(title: "Wild Pitches", value: $wildPitches, icon: "tornado", color: .red, focus: $keyboardActive)
                }

                Section(header: Text("Optional Detail").smallCapsLabel()) {
                    PitchNumberRow(title: "Batters Faced", value: $battersFaced, icon: "person.2.fill", color: .brandNavy, focus: $keyboardActive)
                    PitchNumberRow(title: "Pitch Count", value: $pitchCount, icon: "number.circle.fill", color: .purple, focus: $keyboardActive)
                    PitchNumberRow(title: "Strikes", value: $strikes, icon: "scope", color: .green, focus: $keyboardActive)
                }

                if let stats = existingGameStats, stats.hasPitchingData {
                    Section(header: Text("Current Game Pitching").smallCapsLabel()) {
                        HStack {
                            Text("Innings Pitched").font(.labelLarge)
                            Spacer()
                            Text(ip(stats.outsRecorded)).font(.ppStatSmall).monospacedDigit().foregroundColor(.purple)
                        }
                        CurrentStatRow(title: "Strikeouts", current: stats.pitchingStrikeouts, color: .green)
                        CurrentStatRow(title: "Walks", current: stats.pitchingWalks, color: .cyan)
                        CurrentStatRow(title: "Hits Allowed", current: stats.hitsAllowed, color: .red)
                        CurrentStatRow(title: "Earned Runs", current: stats.earnedRuns, color: .red)
                    }
                }

                if hasAnyInput {
                    Section(header: Text("Preview New Totals").smallCapsLabel()) {
                        HStack {
                            Text("Innings Pitched").font(.labelLarge)
                            Spacer()
                            Text(ip(totalOuts)).font(.ppStatSmall).monospacedDigit().foregroundColor(.purple)
                        }
                        HStack {
                            Text("ERA").font(.labelLarge)
                            Spacer()
                            Text(String(format: "%.2f", previewERA)).font(.ppStatSmall).monospacedDigit().foregroundColor(.green)
                        }
                        HStack {
                            Text("WHIP").font(.labelLarge)
                            Spacer()
                            Text(String(format: "%.2f", previewWHIP)).font(.ppStatSmall).monospacedDigit().foregroundColor(.green)
                        }
                    }
                }
            }
            .ppDetailBackground()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Enter Pitching Stats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { keyboardActive = false }
                        .font(.headingMedium)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveStatistics() }
                        .disabled(!hasAnyInput)
                }
            }
        }
        .alert("Validation Error", isPresented: $showingValidationAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
    }

    private func saveStatistics() {
        // Earned runs can never exceed total runs allowed. Rather than block on a
        // half-filled form (a user may enter ER for ERA without bothering with total
        // runs), clamp runs up to earned runs so RA >= ER always holds.
        let effectiveRuns = max(newRuns, newEarnedRuns)

        var stats = game.gameStats
        if stats == nil {
            let newStats = GameStatistics()
            // Insert BEFORE wiring the relationship (order-fragile across SwiftData versions).
            modelContext.insert(newStats)
            newStats.game = game
            stats = newStats
        }

        if let gameStats = stats {
            // Sticky flag set before counters so the recalc guard protects them.
            gameStats.hasManualEntry = true

            gameStats.addManualPitchingStatistic(
                outsRecorded: newOuts,
                hitsAllowed: newHitsAllowed,
                runsAllowed: effectiveRuns,
                earnedRuns: newEarnedRuns,
                homeRunsAllowed: newHomeRunsAllowed,
                walks: newWalks,
                strikeouts: newStrikeouts,
                hitByPitches: newHitByPitches,
                wildPitches: newWildPitches,
                battersFaced: newBattersFaced,
                pitches: newPitchCount,
                strikes: newStrikes,
                balls: newBalls
            )

            // A past-dated, non-live game keeps isComplete == false (it shows a
            // "PAST" badge). Saving a box score for it is effectively completing
            // it — flip the flag so it reads "COMPLETED" and the recalc below
            // includes it. Silent: completion side effects belong to
            // GameService.complete / "Mark Complete".
            if !game.isLive && !game.isComplete && game.displayStatus == .completed {
                game.isComplete = true
            }

            if let athlete = game.athlete {
                do {
                    try StatisticsService.shared.recalculateAthleteStatistics(
                        for: athlete, context: modelContext, skipSave: true
                    )
                } catch {
                    ErrorHandlerService.shared.handle(
                        error, context: "ManualPitchingEntryView.recalculate", showAlert: false
                    )
                }
            }
        }

        game.needsSync = true

        if ErrorHandlerService.shared.saveContext(modelContext, caller: "ManualPitchingEntryView.save") {
            if let user = game.athlete?.user {
                Task {
                    do {
                        try await SyncCoordinator.shared.syncGames(for: user)
                    } catch {
                        ErrorHandlerService.shared.handle(error, context: "ManualPitchingEntryView.syncGames", showAlert: false)
                    }
                }
            }
            dismiss()
        } else {
            alertMessage = "Failed to save statistics. Please try again."
            showingValidationAlert = true
        }
    }
}

// Numeric entry row with a shared keyboard-dismiss focus binding.
private struct PitchNumberRow: View {
    let title: String
    @Binding var value: String
    let icon: String
    let color: Color
    var focus: FocusState<Bool>.Binding

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var fieldWidth: CGFloat { horizontalSizeClass == .regular ? 100 : 60 }

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 25)
            Text(title)
                .font(.labelLarge)
                .frame(maxWidth: .infinity, alignment: .leading)
            TextField("0", text: $value)
                .focused(focus)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .frame(width: fieldWidth)
                .multilineTextAlignment(.center)
        }
    }
}
