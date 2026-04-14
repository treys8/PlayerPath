//
//  ManualStatisticsEntryView.swift
//  PlayerPath
//
//  Views for manually entering game statistics.
//

import SwiftUI
import SwiftData

// MARK: - Manual Statistics Entry View
struct ManualStatisticsEntryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let game: Game

    @State private var singles: String = ""
    @State private var doubles: String = ""
    @State private var triples: String = ""
    @State private var homeRuns: String = ""
    @State private var runs: String = ""
    @State private var rbis: String = ""
    @State private var strikeouts: String = ""
    @State private var walks: String = ""
    @State private var groundOuts: String = ""
    @State private var flyOuts: String = ""
    @State private var hitByPitches: String = ""
    @State private var showingValidationAlert = false
    @State private var alertMessage = ""

    enum StatField: Int, Hashable, CaseIterable {
        case singles, doubles, triples, homeRuns, runs, rbis, strikeouts, groundOuts, flyOuts, walks, hitByPitches
    }
    @FocusState private var focusedStatField: StatField?

    // Use game.gameStats directly — never create a throwaway GameStatistics()
    // which would be an uninserted @Model object with misleading zero values.
    private var existingGameStats: GameStatistics? { game.gameStats }

    // Calculate totals for preview
    var newSingles: Int { Int(singles) ?? 0 }
    var newDoubles: Int { Int(doubles) ?? 0 }
    var newTriples: Int { Int(triples) ?? 0 }
    var newHomeRuns: Int { Int(homeRuns) ?? 0 }
    var newRuns: Int { Int(runs) ?? 0 }
    var newRbis: Int { Int(rbis) ?? 0 }
    var newStrikeouts: Int { Int(strikeouts) ?? 0 }
    var newWalks: Int { Int(walks) ?? 0 }
    var newGroundOuts: Int { Int(groundOuts) ?? 0 }
    var newFlyOuts: Int { Int(flyOuts) ?? 0 }
    var newHitByPitches: Int { Int(hitByPitches) ?? 0 }

    var newHits: Int { newSingles + newDoubles + newTriples + newHomeRuns }
    var newAtBats: Int { newHits + newStrikeouts + newGroundOuts + newFlyOuts }

    var totalHits: Int { (existingGameStats?.hits ?? 0) + newHits }
    var totalAtBats: Int { (existingGameStats?.atBats ?? 0) + newAtBats }
    var totalRuns: Int { (existingGameStats?.runs ?? 0) + newRuns }
    var totalRbis: Int { (existingGameStats?.rbis ?? 0) + newRbis }
    var totalStrikeouts: Int { (existingGameStats?.strikeouts ?? 0) + newStrikeouts }
    var totalWalks: Int { (existingGameStats?.walks ?? 0) + newWalks }

    var body: some View {
        NavigationStack {
            Form {
                Section("Game Information") {
                    HStack {
                        Text("Opponent:")
                            .fontWeight(.semibold)
                        Spacer()
                        Text(game.opponent)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Date:")
                            .fontWeight(.semibold)
                        Spacer()
                        if let date = game.date {
                            Text(date, style: .date)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Unknown Date")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section("Batting Statistics") {
                    StatEntryRow(title: "Singles", value: $singles, icon: "1.circle.fill", color: .green, field: .singles, focusedField: $focusedStatField)
                    StatEntryRow(title: "Doubles", value: $doubles, icon: "2.circle.fill", color: .brandNavy, field: .doubles, focusedField: $focusedStatField)
                    StatEntryRow(title: "Triples", value: $triples, icon: "3.circle.fill", color: .orange, field: .triples, focusedField: $focusedStatField)
                    StatEntryRow(title: "Home Runs", value: $homeRuns, icon: "4.circle.fill", color: .gold, field: .homeRuns, focusedField: $focusedStatField)
                }

                Section("Offensive Statistics") {
                    StatEntryRow(title: "Runs", value: $runs, icon: "figure.run", color: .purple, field: .runs, focusedField: $focusedStatField)
                    StatEntryRow(title: "RBIs", value: $rbis, icon: "arrow.up.right.circle.fill", color: .pink, field: .rbis, focusedField: $focusedStatField)
                }

                Section("Plate Appearance Outcomes") {
                    StatEntryRow(title: "Strikeouts (K's)", value: $strikeouts, icon: "k.circle.fill", color: .red, field: .strikeouts, focusedField: $focusedStatField)
                    StatEntryRow(title: "Ground Outs", value: $groundOuts, icon: "arrow.down.circle.fill", color: .red, field: .groundOuts, focusedField: $focusedStatField)
                    StatEntryRow(title: "Fly Outs", value: $flyOuts, icon: "arrow.up.circle.fill", color: .red, field: .flyOuts, focusedField: $focusedStatField)
                    StatEntryRow(title: "Walks (BB's)", value: $walks, icon: "figure.walk", color: .cyan, field: .walks, focusedField: $focusedStatField)
                    StatEntryRow(title: "Hit By Pitch", value: $hitByPitches, icon: "exclamationmark.circle.fill", color: .orange, field: .hitByPitches, focusedField: $focusedStatField)
                }

                Section("Current Game Statistics") {
                    CurrentStatRow(title: "Hits", current: existingGameStats?.hits ?? 0, color: .brandNavy)
                    CurrentStatRow(title: "At Bats", current: existingGameStats?.atBats ?? 0, color: .brandNavy)
                    CurrentStatRow(title: "Runs", current: existingGameStats?.runs ?? 0, color: .purple)
                    CurrentStatRow(title: "RBIs", current: existingGameStats?.rbis ?? 0, color: .pink)
                    CurrentStatRow(title: "Strikeouts", current: existingGameStats?.strikeouts ?? 0, color: .red)
                    CurrentStatRow(title: "Walks", current: existingGameStats?.walks ?? 0, color: .cyan)

                    if let stats = existingGameStats, stats.atBats > 0 {
                        HStack {
                            Text("Current Batting Average")
                                .fontWeight(.medium)
                            Spacer()
                            Text(String(format: "%.3f", Double(stats.hits) / Double(stats.atBats)))
                                .fontWeight(.semibold)
                                .foregroundColor(.green)
                        }
                    }
                }

                if hasAnyInput {
                    Section("Preview New Totals") {
                        PreviewStatRow(title: "Total Hits", current: existingGameStats?.hits ?? 0, new: newHits, total: totalHits)
                        PreviewStatRow(title: "Total At Bats", current: existingGameStats?.atBats ?? 0, new: newAtBats, total: totalAtBats)
                        PreviewStatRow(title: "Total Runs", current: existingGameStats?.runs ?? 0, new: newRuns, total: totalRuns)
                        PreviewStatRow(title: "Total RBIs", current: existingGameStats?.rbis ?? 0, new: newRbis, total: totalRbis)
                        PreviewStatRow(title: "Total Strikeouts", current: existingGameStats?.strikeouts ?? 0, new: newStrikeouts, total: totalStrikeouts)
                        PreviewStatRow(title: "Total Walks", current: existingGameStats?.walks ?? 0, new: newWalks, total: totalWalks)

                        if totalAtBats > 0 {
                            HStack {
                                Text("New Batting Average")
                                    .fontWeight(.semibold)
                                Spacer()
                                Text(String(format: "%.3f", Double(totalHits) / Double(totalAtBats)))
                                    .fontWeight(.bold)
                                    .foregroundColor(.green)
                                    .font(.headline)
                            }
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(.cornerMedium)
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Enter Statistics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    if let current = focusedStatField,
                       let nextField = StatField(rawValue: current.rawValue + 1) {
                        Button("Next") { focusedStatField = nextField }
                    }
                    Spacer()
                    Button("Done") { focusedStatField = nil }
                        .fontWeight(.semibold)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveStatistics()
                    }
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

    private var hasAnyInput: Bool {
        !singles.isEmpty || !doubles.isEmpty || !triples.isEmpty || !homeRuns.isEmpty ||
        !runs.isEmpty || !rbis.isEmpty || !strikeouts.isEmpty || !walks.isEmpty ||
        !groundOuts.isEmpty || !flyOuts.isEmpty || !hitByPitches.isEmpty
    }

    private func saveStatistics() {
        // Create game stats if they don't exist
        var stats = game.gameStats
        if stats == nil {
            let newStats = GameStatistics()
            game.gameStats = newStats
            newStats.game = game
            modelContext.insert(newStats)
            stats = newStats
        }

        // Add the new statistics
        if let gameStats = stats {
            gameStats.addManualStatistic(
                singles: newSingles,
                doubles: newDoubles,
                triples: newTriples,
                homeRuns: newHomeRuns,
                runs: newRuns,
                rbis: newRbis,
                strikeouts: newStrikeouts,
                walks: newWalks,
                groundOuts: newGroundOuts,
                flyOuts: newFlyOuts,
                hitByPitches: newHitByPitches
            )

            // Recalculate career + season statistics from scratch so they
            // stay consistent with game stats (also repairs any prior corruption).
            if let athlete = game.athlete {
                try? StatisticsService.shared.recalculateAthleteStatistics(
                    for: athlete, context: modelContext, skipSave: true
                )
            }
        }

        if ErrorHandlerService.shared.saveContext(modelContext, caller: "ManualStatisticsEntryView.save") {
            dismiss()
        } else {
            alertMessage = "Failed to save statistics. Please try again."
            showingValidationAlert = true
        }
    }
}

// Helper Views for Manual Statistics Entry
struct StatEntryRow: View {
    let title: String
    @Binding var value: String
    let icon: String
    let color: Color
    var field: ManualStatisticsEntryView.StatField? = nil
    var focusedField: FocusState<ManualStatisticsEntryView.StatField?>.Binding? = nil

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var fieldWidth: CGFloat { horizontalSizeClass == .regular ? 100 : 60 }

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 25)

            Text(title)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let field, let focusedField {
                TextField("0", text: $value)
                    .focused(focusedField, equals: field)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: fieldWidth)
                    .multilineTextAlignment(.center)
            } else {
                TextField("0", text: $value)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: fieldWidth)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

struct CurrentStatRow: View {
    let title: String
    let current: Int
    let color: Color

    var body: some View {
        HStack {
            Text(title)
                .fontWeight(.medium)
            Spacer()
            Text("\(current)")
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
    }
}

struct PreviewStatRow: View {
    let title: String
    let current: Int
    let new: Int
    let total: Int

    var body: some View {
        HStack {
            Text(title)
                .fontWeight(.medium)

            Spacer()

            if new > 0 {
                Text("\(current) + \(new) = ")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("\(total)")
                    .fontWeight(.bold)
                    .foregroundColor(.green)
            } else {
                Text("\(current)")
                    .foregroundColor(.secondary)
            }
        }
    }
}
