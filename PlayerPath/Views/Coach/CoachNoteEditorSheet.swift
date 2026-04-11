//
//  CoachNoteEditorSheet.swift
//  PlayerPath
//
//  Inline editor for the coach-authored plain note attached to a video.
//  Used by CoachVideoPlayerView when the current viewer is a folder coach.
//

import SwiftUI

struct CoachNoteEditorSheet: View {
    let initialText: String
    let onSave: (String?) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var isSaving = false
    @State private var showingDeleteConfirm = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    init(initialText: String, onSave: @escaping (String?) async throws -> Void) {
        self.initialText = initialText
        self.onSave = onSave
        _text = State(initialValue: initialText)
    }

    private var charLimit: Int { CoachNoteLimits.plainNoteCharLimit }
    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasExistingNote: Bool { !initialText.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What should the athlete focus on?", text: $text, axis: .vertical)
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
                    Text("Coach Note")
                } footer: {
                    Text("This note appears on the video for both you and the athlete. Plain text — for timestamped feedback, use the Add Feedback button on the player.")
                }

                if hasExistingNote {
                    Section {
                        Button(role: .destructive) {
                            showingDeleteConfirm = true
                        } label: {
                            Label("Delete Note", systemImage: "trash")
                        }
                        .disabled(isSaving)
                    }
                }
            }
            .navigationTitle(hasExistingNote ? "Edit Coach Note" : "Add Coach Note")
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
                    .disabled(isSaving || trimmed == initialText.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = false }.fontWeight(.semibold)
                }
            }
            .alert("Delete this note?", isPresented: $showingDeleteConfirm) {
                Button("Delete", role: .destructive) { delete() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The athlete will no longer see this note on the video.")
            }
            .alert("Couldn't Save Note", isPresented: .init(
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
                isSaving = false
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }

    private func delete() {
        isSaving = true
        Task {
            do {
                try await onSave(nil)
                isSaving = false
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }
}
