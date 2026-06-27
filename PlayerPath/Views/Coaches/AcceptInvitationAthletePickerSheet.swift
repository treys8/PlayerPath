//
//  AcceptInvitationAthletePickerSheet.swift
//  PlayerPath
//
//  When a user with multiple athletes accepts a coach-to-athlete invitation,
//  we can't infer which athlete the coach is working with — the invitation
//  was keyed by parent/user email. This sheet asks the user to pick.
//

import SwiftUI

struct AcceptInvitationAthletePickerSheet: View {
    let invitation: CoachToAthleteInvitation
    let athletes: [Athlete]
    let onChoose: (Athlete) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.ppAccent) private var ppAccent

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Which athlete is \(invitation.coachName) working with?")
                        .font(.subheadline)
                        .foregroundColor(Theme.textSecondary)
                        .listRowBackground(Theme.card)
                } header: {
                    Text("Coach Invitation")
                }

                Section("Your Athletes") {
                    // Collapse linked sport-variant profiles into one person. A
                    // dual-sport person shows their name once, then a per-sport
                    // choice (the coach works with a specific sport profile), so
                    // the picker reads as one person rather than two strangers.
                    ForEach(athletes.groupedByPerson()) { group in
                        if group.isMultiSport {
                            Text(group.displayName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(Theme.textSecondary)
                                .listRowBackground(Theme.card)
                            ForEach(group.profiles) { profile in
                                athleteChoiceButton(
                                    profile,
                                    title: profile.sportType.displayName,
                                    icon: profile.sportType.icon
                                )
                            }
                        } else if let profile = group.profiles.first {
                            athleteChoiceButton(
                                profile,
                                title: profile.name,
                                icon: "person.crop.circle.fill"
                            )
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.surface)
            .navigationTitle("Choose Athlete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
            }
        }
    }

    /// One tappable athlete/sport choice row. `title` is the person's name for a
    /// singleton or the sport name for a linked profile under a person header.
    private func athleteChoiceButton(_ athlete: Athlete, title: String, icon: String) -> some View {
        Button {
            onChoose(athlete)
            dismiss()
        } label: {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(ppAccent)
                Text(title)
                    .font(.body)
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(Theme.textTertiary)
            }
        }
        .buttonStyle(.plain)
        .listRowBackground(Theme.card)
    }
}
