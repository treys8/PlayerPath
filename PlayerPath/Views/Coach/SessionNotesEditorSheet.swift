//
//  SessionNotesEditorSheet.swift
//  PlayerPath
//
//  Editor sheet for session-level lesson notes. Presented from
//  UpcomingSessionCard and LiveSessionCard on the coach dashboard.
//

import SwiftUI

struct SessionNotesEditorSheet: View {
    let initialNotes: String
    let onSave: (String?) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    private let charLimit = 500

    init(initialNotes: String, onSave: @escaping (String?) async throws -> Void) {
        self.initialNotes = initialNotes
        self.onSave = onSave
        _text = State(initialValue: initialNotes)
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasExistingNotes: Bool { !initialNotes.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Observations, goals, reminders...", text: $text, axis: .vertical)
                        .lineLimit(4...10)
                        .focused($focused)
                        .onChange(of: text) { _, new in
                            if new.count > charLimit {
                                text = String(new.prefix(charLimit))
                            }
                        }
                    HStack {
                        Spacer()
                        Text("\(text.count)/\(charLimit)")
                            .font(.caption2)
                            .foregroundColor(text.count >= charLimit ? .red : .secondary)
                    }
                } header: {
                    Text("Session Notes")
                } footer: {
                    Text("Notes for your own reference during and after the session. Not shared with athletes.")
                }

                if hasExistingNotes {
                    Section {
                        Button(role: .destructive) {
                            clearNotes()
                        } label: {
                            Label("Clear Notes", systemImage: "trash")
                        }
                        .disabled(isSaving)
                    }
                }
            }
            .navigationTitle(hasExistingNotes ? "Edit Session Notes" : "Add Session Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save").fontWeight(.semibold)
                        }
                    }
                    .disabled(isSaving || trimmed == initialNotes.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = false }.fontWeight(.semibold)
                }
            }
            .alert("Couldn't Save Notes", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .onAppear { focused = true }
        }
    }

    private func save() {
        isSaving = true
        Task {
            do {
                try await onSave(trimmed.isEmpty ? nil : trimmed)
                Haptics.success()
                isSaving = false
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                ErrorHandlerService.shared.handle(error, context: "SessionNotesEditor.save", showAlert: false)
                isSaving = false
            }
        }
    }

    private func clearNotes() {
        isSaving = true
        Task {
            do {
                try await onSave(nil)
                Haptics.success()
                isSaving = false
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                ErrorHandlerService.shared.handle(error, context: "SessionNotesEditor.clear", showAlert: false)
                isSaving = false
            }
        }
    }
}
