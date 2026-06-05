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
                    ForEach(athletes) { athlete in
                        Button {
                            onChoose(athlete)
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(ppAccent)
                                Text(athlete.name)
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
}
