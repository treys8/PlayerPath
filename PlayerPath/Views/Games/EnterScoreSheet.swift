//
//  EnterScoreSheet.swift
//  PlayerPath
//
//  Modal for entering or editing a golf tournament's final score (and par).
//  Quick-entry path for rounds scored as a single total. When the round has
//  per-hole scores, the total is owned by ScoreHoleSheet's running-sum mirror,
//  so this sheet shows it read-only and only edits holes/par.
//

import SwiftUI
import SwiftData

struct EnterScoreSheet: View {
    @Bindable var game: Game
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var holes: Int = 18
    @State private var parText: String = ""
    @State private var scoreText: String = ""
    @State private var didInit = false
    @State private var showingValidationError = false
    @State private var validationMessage = ""
    @State private var showingSaveError = false

    private var parsedScore: Int? {
        Int(scoreText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var parsedPar: Int? {
        Int(parText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// When the round has per-hole scores, the total is derived from them and
    /// this sheet must not let the user type a conflicting value. We show the
    /// derived total read-only and only allow editing holes/par.
    private var hasPerHoleScores: Bool { !(game.holeScores ?? []).isEmpty }

    private var isValid: Bool {
        // Per-hole rounds: total is derived, so only par needs to be sane.
        if hasPerHoleScores {
            if let par = parsedPar, !(par > 0 && par < 200) { return false }
            return true
        }
        guard let score = parsedScore, score >= holes, score < 300 else { return false }
        // Par is optional but when present must be sensible.
        if let par = parsedPar, !(par > 0 && par < 200) { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Round") {
                    Picker("Holes", selection: $holes) {
                        Text("9").tag(9)
                        Text("18").tag(18)
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text("Par")
                        Spacer()
                        TextField("Optional", text: $parText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }

                    if hasPerHoleScores {
                        HStack {
                            Text("Total Score")
                            Spacer()
                            Text(game.effectiveTotalScore.map(String.init) ?? "—")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        HStack {
                            Text("Total Score")
                            Spacer()
                            TextField("Required", text: $scoreText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                        }
                    }

                    // Total comes from per-hole scores when present, else the
                    // typed value above.
                    let effectiveScore = hasPerHoleScores ? game.effectiveTotalScore : parsedScore
                    if let score = effectiveScore, let par = parsedPar {
                        let diff = score - par
                        HStack {
                            Text("vs Par")
                            Spacer()
                            Text(diff == 0 ? "E" : (diff > 0 ? "+\(diff)" : "\(diff)"))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }

                    if hasPerHoleScores {
                        Text("Calculated from per-hole scores. Edit a hole to change the total.")
                            .font(.bodySmall)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle(game.effectiveTotalScore == nil ? "Enter Score" : "Edit Score")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!isValid)
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                guard !didInit else { return }
                didInit = true
                holes = game.holes ?? 18
                if let par = game.par { parText = String(par) }
                if let score = game.totalScore { scoreText = String(score) }
            }
            .alert("Invalid Score", isPresented: $showingValidationError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(validationMessage)
            }
            .alert("Save Failed", isPresented: $showingSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Your score couldn't be saved. Please try again.")
            }
        }
    }

    private func save() {
        if let par = parsedPar, !(par > 0 && par < 200) {
            validationMessage = "Par must be between 1 and 199."
            showingValidationError = true
            return
        }

        // Per-hole rounds: the total is owned by ScoreHoleSheet's running-sum
        // mirror — never overwrite it here. Only persist holes/par.
        if !hasPerHoleScores {
            guard let score = parsedScore else {
                validationMessage = "Please enter a total score."
                showingValidationError = true
                return
            }
            guard score >= holes else {
                validationMessage = "Score can't be less than the number of holes (\(holes))."
                showingValidationError = true
                return
            }
            guard score < 300 else {
                validationMessage = "Score must be under 300."
                showingValidationError = true
                return
            }
            game.totalScore = score
        }

        game.holes = holes
        game.par = parsedPar
        // Setting a score marks the round as effectively complete for stats.
        if !game.isComplete && !game.isLive { game.isComplete = true }
        game.needsSync = true
        guard ErrorHandlerService.shared.saveContext(modelContext, caller: "EnterScoreSheet.save") else {
            modelContext.rollback()
            showingSaveError = true
            return
        }
        Haptics.success()
        dismiss()
    }
}
