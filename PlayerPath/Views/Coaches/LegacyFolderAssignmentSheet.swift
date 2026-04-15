//
//  LegacyFolderAssignmentSheet.swift
//  PlayerPath
//
//  Shown once to multi-athlete users who have coach folders created before
//  per-athlete scoping shipped. Asks them to pick which athlete owns each folder.
//

import SwiftUI

/// Presents `LegacyFolderAssignmentSheet` whenever the migration service flags unassigned folders
/// and the user has 2+ athletes. Extracted from UserMainFlow to keep body type-checking cheap.
struct LegacyFolderAssignmentSheetModifier: ViewModifier {
    let userID: String?
    let athletes: [Athlete]
    @Bindable private var migration = FolderAthleteMigrationService.shared

    private var isPresented: Binding<Bool> {
        Binding(
            get: { migration.needsAssignment && athletes.count >= 2 },
            set: { if !$0 { migration.cancelAssignment() } }
        )
    }

    func body(content: Content) -> some View {
        content.sheet(isPresented: isPresented) {
            if let uid = userID {
                LegacyFolderAssignmentSheet(
                    folders: migration.unassignedFolders,
                    athletes: athletes,
                    userID: uid
                )
            }
        }
    }
}

struct LegacyFolderAssignmentSheet: View {
    let folders: [SharedFolder]
    let athletes: [Athlete]
    let userID: String

    @Environment(\.dismiss) private var dismiss
    @State private var selections: [String: Athlete.ID] = [:]
    @State private var isSaving = false

    private var allAssigned: Bool {
        folders.allSatisfy { folder in
            guard let id = folder.id else { return true }
            return selections[id] != nil
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("You've added more than one athlete since creating these coach folders. Pick which athlete each folder belongs to so coaches only see the right videos.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                ForEach(folders, id: \.id) { folder in
                    Section(folder.name) {
                        ForEach(athletes) { athlete in
                            Button {
                                if let id = folder.id {
                                    selections[id] = athlete.id
                                }
                            } label: {
                                HStack {
                                    Text(athlete.name)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if let fid = folder.id, selections[fid] == athlete.id {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.brandNavy)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Assign Folders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(!allAssigned || isSaving)
                }
            }
            .overlay {
                if isSaving {
                    ProgressView("Saving…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .interactiveDismissDisabled(true)
        }
    }

    private func save() async {
        isSaving = true
        var assignments: [(folder: SharedFolder, athleteUUID: String)] = []
        for folder in folders {
            guard let fid = folder.id, let athleteID = selections[fid] else { continue }
            assignments.append((folder, athleteID.uuidString))
        }
        await FolderAthleteMigrationService.shared.completeAssignments(assignments, userID: userID)
        isSaving = false
        dismiss()
    }
}
