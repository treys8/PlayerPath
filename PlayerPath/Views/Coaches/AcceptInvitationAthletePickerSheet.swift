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

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Which athlete is \(invitation.coachName) working with?")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
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
                                    .foregroundColor(.brandNavy)
                                Text(athlete.name)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
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
