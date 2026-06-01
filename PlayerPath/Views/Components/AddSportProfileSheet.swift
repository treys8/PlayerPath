//
//  AddSportProfileSheet.swift
//  PlayerPath
//
//  The flow for SPINNING OFF a second sport-variant profile of the same human.
//  The new profile shares the source's `personGroupID`, so both count as ONE
//  subscription slot. Correcting an initial wrong-sport choice still happens
//  via EditAthleteView.
//
//  Entry points: the Dashboard athlete-picker menu ("Add Another Sport for
//  [name]") and the AthleteSelectionView card context menu. This used to be a
//  persistent nav-bar chip (SportContextChip) on every tab; it was consolidated
//  because the chip duplicated the sport label the picker already shows and the
//  spinoff is a rare setup action.
//

import SwiftUI
import SwiftData

/// Sheet for creating a new athlete profile in a different sport, linked to
/// the source via `personGroupID` so both count as one subscription slot.
struct AddSportProfileSheet: View {
    let sourceAthlete: Athlete
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var selectedSport: Season.SportType
    @State private var newName: String
    @State private var showingConfirmation = false

    init(sourceAthlete: Athlete) {
        self.sourceAthlete = sourceAthlete
        _selectedSport = State(initialValue: sourceAthlete.sportType)
        _newName = State(initialValue: sourceAthlete.name)
    }

    private var trimmedName: String {
        newName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isSportTaken(_ sport: Season.SportType) -> Bool {
        // Sports already represented in this person's group (source + prior
        // spinoffs) — disables picking a sport that would duplicate a profile.
        sourceAthlete.personGroupSports.contains(sport)
    }

    private var isValid: Bool {
        !isSportTaken(selectedSport) && !trimmedName.isEmpty
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Adds a separate profile for tracking another sport. Both profiles share your subscription slot — stats, seasons, and coach connections stay separate.")
                .font(.bodyMedium)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                // Force full height so the medium detent can't truncate this to
                // a single clipped line.
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 6) {
                Text("Profile name")
                    .font(.labelMedium)
                    .foregroundStyle(.secondary)
                TextField("Profile name", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
            }
            .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 6) {
                Text("Sport")
                    .font(.labelMedium)
                    .foregroundStyle(.secondary)
                VStack(spacing: 10) {
                    ForEach(Season.SportType.allCases, id: \.self) { sport in
                        sportRow(sport)
                    }
                }
            }
            .padding(.horizontal, 20)

            Spacer(minLength: 0)
        }
        // Short, fixed title — the athlete name lived here before but always
        // truncated in the inline bar; the prefilled "Profile name" field below
        // already carries that context.
        .navigationTitle("Add Another Sport")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { showingConfirmation = true }
                    .fontWeight(.semibold)
                    .disabled(!isValid)
            }
        }
        .confirmationDialog(
            "Create new \(selectedSport.displayName) profile for \(sourceAthlete.name)?",
            isPresented: $showingConfirmation,
            titleVisibility: .visible
        ) {
            Button("Create Profile") { createSpinoff() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Adds a separate profile for tracking \(selectedSport.displayName). Doesn't use an extra subscription slot.")
        }
    }

    @ViewBuilder
    private func sportRow(_ sport: Season.SportType) -> some View {
        let isSelected = selectedSport == sport
        let isSourceSport = sport == sourceAthlete.sportType
        let isTaken = isSportTaken(sport)
        Button {
            guard !isTaken else { return }
            selectedSport = sport
            Haptics.selection()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: sport.icon)
                    .font(.title3)
                    .frame(width: 28)
                    .foregroundColor(isSelected ? .brandNavy : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(sport.displayName)
                        .font(.bodyLarge)
                        .foregroundColor(.primary)
                    if isSourceSport {
                        Text("Current profile's sport")
                            .font(.labelSmall)
                            .foregroundStyle(.secondary)
                    } else if isTaken {
                        Text("Already tracked")
                            .font(.labelSmall)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.brandNavy)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.brandNavy.opacity(0.1) : Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.brandNavy.opacity(0.4) : .clear, lineWidth: 1)
            )
            .opacity(isTaken ? 0.5 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isTaken)
    }

    private func createSpinoff() {
        // Bridge SportType (capitalized) back to Athlete.Sport (lowercase).
        guard let mappedSport = Sport(rawValue: selectedSport.rawValue.lowercased()) else { return }

        // Claim a group ID for the source if it doesn't already have one.
        // First spinoff sets source.personGroupID = source.id; subsequent
        // spinoffs reuse the existing group.
        let groupID = sourceAthlete.personGroupID ?? sourceAthlete.id
        if sourceAthlete.personGroupID == nil {
            sourceAthlete.personGroupID = groupID
            sourceAthlete.needsSync = true
        }

        let new = Athlete(name: trimmedName)
        new.user = sourceAthlete.user
        new.sport = mappedSport
        new.personGroupID = groupID
        new.needsSync = true
        modelContext.insert(new)

        // Prime the new profile with a default active season so the user lands
        // on populated tab chrome (correct sport, valid quick-add) instead of an
        // empty state that depends on a later tab tap to lazy-create one.
        SeasonManager.ensureActiveSeason(for: new, in: modelContext)

        ErrorHandlerService.shared.saveContext(modelContext, caller: "AddSportProfileSheet.createSpinoff")

        if let user = sourceAthlete.user {
            Task { try? await SyncCoordinator.shared.syncAthletes(for: user) }
        }

        // Switch the active athlete to the newly created spinoff so the user
        // lands in their new sport's tab chrome immediately.
        NotificationCenter.default.post(name: .switchAthlete, object: new)

        Haptics.success()
        dismiss()
    }
}
