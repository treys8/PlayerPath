//
//  PendingSentInvitationsBanner.swift
//  PlayerPath
//
//  Surfaces *sent* coach→athlete invitations that are still awaiting a
//  response. These count toward the coach's athlete limit, so without this
//  banner a coach can hit "limit reached" while seeing only their connected
//  athletes — the outstanding invites are invisible. Tapping opens the
//  Invitations sheet on the Sent tab so the coach can cancel or wait.
//

import SwiftUI

struct PendingSentInvitationsBanner: View {
    private var invitationManager: CoachInvitationManager { .shared }

    /// Invoked on tap — the host opens the Invitations sheet to the Sent tab.
    let onView: () -> Void

    var body: some View {
        let count = invitationManager.pendingSentCount
        if count > 0 {
            Button {
                Haptics.light()
                onView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "paperplane")
                        .foregroundColor(.brandNavy)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(count) invitation\(count == 1 ? "" : "s") awaiting response")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        Text("These count toward your athlete limit")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.brandNavy.opacity(0.06))
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
        }
    }
}
