//
//  AddPracticeNoteView.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import SwiftUI
import SwiftData
import os

private let log = Logger(subsystem: "com.playerpath.app", category: "Practices")

struct AddPracticeNoteView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let practice: Practice

    @State private var noteContent = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Note") {
                    TextField("Enter your practice notes...", text: $noteContent, axis: .vertical)
                        .lineLimit(5...10)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Add Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveNote()
                    }
                    .disabled(noteContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func saveNote() {
        let note = PracticeNote(content: noteContent.trimmingCharacters(in: .whitespacesAndNewlines))
        note.needsSync = true
        note.practice = practice

        if practice.notes == nil {
            practice.notes = []
        }
        practice.notes?.append(note)
        modelContext.insert(note)

        do {
            try modelContext.save()

            // Track practice note added analytics
            AnalyticsService.shared.trackPracticeNoteAdded(practiceID: practice.id.uuidString)

            Haptics.success()
            dismiss()
        } catch {
            Haptics.error()
            log.error("Failed to save note: \(error.localizedDescription)")
        }
    }
}
