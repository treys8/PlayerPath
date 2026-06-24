//
//  EditTournamentSheet.swift
//  PlayerPath
//
//  Edits an existing multi-round golf tournament's details (name, location,
//  start/optional end date, notes). Mirrors TournamentCreationView / EditGameSheet:
//  mutate + needsSync + saveContext + kick a tournament sync. Rounds are untouched.
//  The end date is settable here only — it powers the date-range display in
//  TournamentDetailView, which had no edit affordance before.
//

import SwiftUI
import SwiftData

struct EditTournamentSheet: View {
    @Bindable var tournament: GolfTournament
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var location = ""
    @State private var startDate = Date()
    @State private var hasEndDate = false
    @State private var endDate = Date()
    @State private var notes = ""
    @State private var didInit = false
    @State private var isSaving = false

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { trimmedName.count >= 2 && trimmedName.count <= 80 && !isSaving }

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
                    Toggle("Multi-day", isOn: $hasEndDate.animation())
                    if hasEndDate {
                        DatePicker("End Date", selection: $endDate, in: startDate..., displayedComponents: .date)
                    }
                }

                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .navigationTitle("Edit Tournament")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                // Seed once; guard against a sheet re-appearance wiping edits.
                guard !didInit else { return }
                didInit = true
                name = tournament.name
                location = tournament.location ?? ""
                startDate = tournament.startDate ?? Date()
                if let end = tournament.endDate {
                    hasEndDate = true
                    endDate = end
                }
                notes = tournament.notes ?? ""
            }
        }
    }

    private func save() {
        guard canSave else { return }
        isSaving = true

        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        tournament.name = trimmedName
        tournament.location = trimmedLocation.isEmpty ? nil : trimmedLocation
        tournament.startDate = startDate
        // Clamp so an untouched end picker can't land before the start.
        tournament.endDate = hasEndDate ? max(endDate, startDate) : nil
        tournament.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
        // Dirty so SyncCoordinator uploads the edit; the sync layer bumps version.
        tournament.needsSync = true

        guard ErrorHandlerService.shared.saveContext(modelContext, caller: "EditTournamentSheet.save") else {
            modelContext.rollback()
            isSaving = false
            return
        }

        if let user = tournament.athlete?.user {
            Task { try? await SyncCoordinator.shared.syncGolfTournaments(for: user) }
        }

        Haptics.success()
        dismiss()
    }
}
