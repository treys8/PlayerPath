//
//  EnterScoreSheet.swift
//  PlayerPath
//
//  Modal for entering or editing a golf tournament's final score (and par).
//  Per-hole entry is intentionally deferred — PR 2 stores totalScore only.
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

    private var parsedScore: Int? {
        Int(scoreText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var parsedPar: Int? {
        Int(parText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var isValid: Bool {
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

                    HStack {
                        Text("Total Score")
                        Spacer()
                        TextField("Required", text: $scoreText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }

                    if let score = parsedScore, let par = parsedPar {
                        let diff = score - par
                        HStack {
                            Text("vs Par")
                            Spacer()
                            Text(diff == 0 ? "E" : (diff > 0 ? "+\(diff)" : "\(diff)"))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(game.totalScore == nil ? "Enter Score" : "Edit Score")
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
        }
    }

    private func save() {
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
        if let par = parsedPar, !(par > 0 && par < 200) {
            validationMessage = "Par must be between 1 and 199."
            showingValidationError = true
            return
        }
        game.holes = holes
        game.par = parsedPar
        game.totalScore = score
        // Setting a score marks the round as effectively complete for stats.
        if !game.isComplete && !game.isLive { game.isComplete = true }
        game.needsSync = true
        ErrorHandlerService.shared.saveContext(modelContext, caller: "EnterScoreSheet.save")
        Haptics.success()
        dismiss()
    }
}
