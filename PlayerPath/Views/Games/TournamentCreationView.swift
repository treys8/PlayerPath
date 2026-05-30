//
//  TournamentCreationView.swift
//  PlayerPath
//
//  Creates a multi-round golf tournament (SchemaV27). The container only — rounds
//  are added afterward from the tournament detail screen ("Add Round"). Mirrors
//  the lightweight create flow used elsewhere: insert + saveContext + kick a sync.
//

import SwiftUI
import SwiftData

struct TournamentCreationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let athlete: Athlete?
    /// Called with the newly created tournament so the caller can navigate into
    /// it (e.g. to immediately add the first round).
    var onCreated: ((GolfTournament) -> Void)?

    @State private var name = ""
    @State private var location = ""
    @State private var startDate = Date()
    @State private var notes = ""
    @State private var isSaving = false

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var canSave: Bool { trimmedName.count >= 2 && trimmedName.count <= 80 }

    var body: some View {
        NavigationStack {
            Form {
                Section("Tournament") {
                    TextField("Name (e.g. City Open)", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                    TextField("Location (Optional)", text: $location)
                        .textInputAutocapitalization(.words)
                    DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                }

                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }

                Section {
                    Label {
                        Text("Add each round after creating the tournament — scores roll up automatically.")
                            .font(.bodySmall)
                            .foregroundColor(.secondary)
                    } icon: {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.yellow)
                    }
                }
            }
            .navigationTitle("New Tournament")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave || isSaving)
                }
            }
        }
    }

    private func save() {
        guard let athlete, canSave, !isSaving else { return }
        isSaving = true

        let tournament = GolfTournament(name: trimmedName, startDate: startDate)
        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        tournament.location = trimmedLocation.isEmpty ? nil : trimmedLocation
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        tournament.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
        tournament.athlete = athlete
        tournament.needsSync = true

        modelContext.insert(tournament)
        ErrorHandlerService.shared.saveContext(modelContext, caller: "TournamentCreationView.save")

        // Kick a tournament sync so the container reaches Firestore promptly
        // (rounds added next will then resolve their parent on other devices).
        if let user = athlete.user {
            Task { try? await SyncCoordinator.shared.syncGolfTournaments(for: user) }
        }

        onCreated?(tournament)
        dismiss()
    }
}
