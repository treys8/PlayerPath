//
//  AthleteNameSection.swift
//  PlayerPath
//
//  Rename for EditAthleteView. Dual-sport people are several rows sharing a
//  personGroupID. The split tool copies the name, but AddSportProfileSheet lets
//  the user type a different one ("Zain Golf") — so a rename carries over only
//  to linked rows that still share THIS row's current name.
//  Coach-side denormalized copies (folder/invitation/session names) are NOT
//  rewritten — accepted drift, see memory project_edit_athlete_name_todo.
//

import SwiftUI
import SwiftData

struct AthleteNameSection: View {
    let athlete: Athlete

    @Environment(\.modelContext) private var modelContext
    @Environment(\.ppAccent) private var ppAccent
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    private var linkedProfiles: [Athlete] {
        let groupID = athlete.personGroupID ?? athlete.id
        return (athlete.user?.athletes ?? []).filter { ($0.personGroupID ?? $0.id) == groupID }
    }

    /// Linked rows that follow a rename: same person AND same current name.
    private var renameTargets: [Athlete] {
        linkedProfiles.filter { $0.name == athlete.name }
    }

    private var trimmed: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isChanged: Bool { trimmed != athlete.name }

    private var validationMessage: String? {
        guard isChanged else { return nil }
        guard Validation.isValidPersonName(trimmed, min: 2, max: 50) else {
            return "Use 2–50 letters, spaces, periods, hyphens, or apostrophes."
        }
        let linkedIDs = Set(linkedProfiles.map(\.id))
        let taken = (athlete.user?.athletes ?? []).contains {
            !linkedIDs.contains($0.id)
                && $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == trimmed.lowercased()
        }
        return taken ? "Another athlete already has this name." : nil
    }

    private var canSave: Bool { isChanged && validationMessage == nil }

    var body: some View {
        Section {
            TextField("Athlete name", text: $draft)
                .textContentType(.name)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit(save)
            if canSave {
                Button("Save Name", action: save)
                    .foregroundColor(ppAccent)
            }
        } header: {
            Text("Name")
        } footer: {
            if let validationMessage {
                Text(validationMessage).foregroundColor(Theme.warning)
            } else {
                Text(renameTargets.count > 1
                     ? "Also renames this athlete's other sport profiles. Coaches may see the old name on folders you've already shared."
                     : "Coaches may see the old name on folders you've already shared.")
            }
        }
        .onAppear { draft = athlete.name }
    }

    private func save() {
        guard canSave else { return }
        let newName = trimmed
        for profile in renameTargets {
            profile.name = newName
            profile.needsSync = true
        }
        _ = ErrorHandlerService.shared.saveContext(modelContext, caller: "AthleteNameSection.save")
        draft = newName
        isFocused = false
        Haptics.success()
    }
}
