//
//  EditGameSheet.swift
//  PlayerPath
//
//  Sheet for editing an existing game's details.
//

import SwiftUI
import SwiftData

// MARK: - Edit Game Sheet

struct EditGameSheet: View {
    @Bindable var game: Game
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var opponent: String = ""
    @State private var date: Date = Date()
    @State private var location: String = ""
    @State private var notes: String = ""

    enum Field: Hashable { case opponent, location, notes }
    @FocusState private var focusedField: Field?
    @State private var showingSaveError = false

    private var isValidOpponent: Bool {
        let trimmed = opponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 2 && trimmed.count <= 50
    }

    private var hasChanges: Bool {
        opponent != game.opponent ||
        date != (game.date ?? Date()) ||
        location != (game.location ?? "") ||
        notes != (game.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Game Details") {
                    TextField("Opponent", text: $opponent)
                        .focused($focusedField, equals: .opponent)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .location }
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()

                    if !opponent.isEmpty && !isValidOpponent {
                        Label("Opponent name must be 2-50 characters", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }

                    DatePicker("Date & Time", selection: $date)
                }

                Section("Location (Optional)") {
                    TextField("Location", text: $location)
                        .focused($focusedField, equals: .location)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .notes }
                        .textInputAutocapitalization(.words)
                }

                Section("Notes (Optional)") {
                    TextField("Game notes", text: $notes, axis: .vertical)
                        .focused($focusedField, equals: .notes)
                        .submitLabel(.done)
                        .lineLimit(3...6)
                }

                if game.isLive {
                    Section {
                        Label("This game is currently live", systemImage: "circle.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                } else if game.isComplete {
                    Section {
                        Label("This game has been completed", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Edit Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                        .fontWeight(.semibold)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                    .disabled(!isValidOpponent || !hasChanges)
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                // Initialize with current values
                opponent = game.opponent
                date = game.date ?? Date()
                location = game.location ?? ""
                notes = game.notes ?? ""
            }
            .alert("Save Error", isPresented: $showingSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Failed to save changes. Please try again.")
            }
        }
    }

    private func saveChanges() {
        let dateChanged = date != (game.date ?? Date())
        let gameId = game.id.uuidString
        let newOpponent = opponent.trimmingCharacters(in: .whitespacesAndNewlines)

        game.opponent = newOpponent
        game.date = date
        game.location = location.isEmpty ? nil : location.trimmingCharacters(in: .whitespacesAndNewlines)
        game.notes = notes.isEmpty ? nil : notes.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                try modelContext.save()

                // Reschedule game reminder if date changed
                if dateChanged && (try? modelContext.fetch(FetchDescriptor<UserPreferences>()).first)?.enableGameReminders ?? true {
                    PushNotificationService.shared.cancelNotifications(withIdentifiers: ["game_reminder_\(gameId)"])
                    if date > Date().addingTimeInterval(60 * 60) {
                        await PushNotificationService.shared.scheduleGameReminder(
                            gameId: gameId,
                            opponent: newOpponent,
                            scheduledTime: date
                        )
                    }
                }

                Haptics.success()
                dismiss()
            } catch {
                showingSaveError = true
                ErrorHandlerService.shared.handle(error, context: "GamesView.saveGame", showAlert: false)
            }
        }
    }
}
