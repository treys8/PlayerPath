//
//  CoachSavePermissionSection.swift
//  PlayerPath
//
//  Athlete-side toggle for whether a coach may save this athlete's videos to
//  the coach's own Photos library (FolderPermissions.canDownload). Applies to
//  every folder shared with the coach. The coach's own recordings are always
//  saveable by them — the copy says so.
//

import SwiftUI

struct CoachSavePermissionSection: View {
    let coachID: String
    let coachName: String
    let folders: [SharedFolder]

    @State private var allowed = true
    @State private var isSaving = false

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { allowed }, set: { update(to: $0) })) {
                Label("Save Videos to Their Device", systemImage: "square.and.arrow.down")
            }
            .disabled(isSaving || folders.isEmpty)
        } header: {
            Text("Permissions").smallCapsLabel()
        } footer: {
            Text(allowed
                 ? "\(coachName) can save your videos to their Photos library. Turn this off to keep your videos in PlayerPath only."
                 : "\(coachName) can watch and comment but can't save your videos. They can still save clips they recorded themselves.")
        }
        .onAppear { allowed = currentValue }
        .onChange(of: currentValue) { _, value in if !isSaving { allowed = value } }
    }

    /// On only if every shared folder allows it, so a mixed state reads as
    /// restricted and one tap makes all folders agree.
    private var currentValue: Bool {
        folders.allSatisfy { $0.getPermissions(for: coachID)?.canDownload ?? true }
    }

    private func update(to newValue: Bool) {
        let previous = allowed
        allowed = newValue
        isSaving = true
        Haptics.light()
        Task {
            defer { isSaving = false }
            do {
                try await FirestoreManager.shared.setCoachCanDownload(
                    folderIDs: folders.compactMap(\.id),
                    coachID: coachID,
                    allowed: newValue
                )
            } catch {
                allowed = previous
                ErrorHandlerService.shared.handle(error, context: "CoachSavePermission.update", showAlert: true)
            }
        }
    }
}
