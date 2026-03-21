//
//  EditClipNoteSheet.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import SwiftUI
import SwiftData
import os

private let log = Logger(subsystem: "com.playerpath.app", category: "Practices")

struct EditClipNoteSheet: View {
    let clip: VideoClip
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var noteText: String
    @State private var isSaving = false
    @FocusState private var isFocused: Bool

    init(clip: VideoClip) {
        self.clip = clip
        _noteText = State(initialValue: clip.note ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Your note is visible to your coach if you share this video.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .padding(.top, 4)

                    TextEditor(text: $noteText)
                        .focused($isFocused)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(minHeight: 140)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)
                        .padding(.horizontal)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(clip.note?.isEmpty == false ? "Edit Note" : "Add Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isFocused = false }
                        .fontWeight(.semibold)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveNote() }
                        .disabled(isSaving)
                }
            }
            .overlay {
                if isSaving {
                    ProgressView()
                }
            }
        }
    }

    private func saveNote() {
        isSaving = true
        let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        clip.note = trimmed.isEmpty ? nil : trimmed
        clip.needsSync = true
        ErrorHandlerService.shared.saveContext(modelContext, caller: "PracticesView.saveNote")

        // Sync to Firestore if the clip has been uploaded
        if let firestoreId = clip.firestoreId {
            Task {
                do {
                    try await VideoCloudManager.shared.updateVideoNote(clipId: firestoreId, note: clip.note)
                } catch {
                    log.error("Failed to sync video note to Firestore: \(error.localizedDescription)")
                }
            }
        }
        isSaving = false
        dismiss()
    }
}
