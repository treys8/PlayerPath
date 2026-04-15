//
//  RenameFolderSheet.swift
//  PlayerPath
//
//  Sheet for athletes to rename a shared folder.
//

import SwiftUI

struct RenameFolderSheet: View {
    let folder: SharedFolder
    let athleteID: String

    @Environment(\.dismiss) private var dismiss
    private var folderManager: SharedFolderManager { .shared }

    @State private var newName: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(folder: SharedFolder, athleteID: String) {
        self.folder = folder
        self.athleteID = athleteID
        _newName = State(initialValue: folder.name)
    }

    private var trimmed: String {
        newName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValid: Bool {
        !trimmed.isEmpty && trimmed.count <= 50 && trimmed != folder.name
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Folder name", text: $newName)
                        .autocorrectionDisabled()
                } footer: {
                    Text("1–50 characters.")
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Rename Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { save() }
                            .disabled(!isValid)
                    }
                }
            }
        }
    }

    private func save() {
        guard let folderID = folder.id, isValid else { return }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await folderManager.renameFolder(
                    folderID: folderID,
                    newName: trimmed,
                    athleteID: athleteID
                )
                Haptics.success()
                dismiss()
            } catch {
                isSaving = false
                errorMessage = error.localizedDescription
                ErrorHandlerService.shared.handle(error, context: "RenameFolderSheet.save", showAlert: false)
            }
        }
    }
}
