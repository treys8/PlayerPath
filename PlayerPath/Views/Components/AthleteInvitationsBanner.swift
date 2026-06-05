//
//  AthleteInvitationsBanner.swift
//  PlayerPath
//
//  A thin nudge on the Journal feed when there are pending coach invitations.
//  Tapping routes to the Coaches page (More tab), which is the canonical home
//  for incoming invitations — see PendingCoachInvitationsView. The accept/decline
//  UI lives there, not in a sheet hung off this banner.
//

import SwiftUI

struct AthleteInvitationsBanner: View {
    @Environment(\.ppAccent) private var ppAccent
    private var invitationManager: AthleteInvitationManager { .shared }

    var body: some View {
        if !invitationManager.pendingInvitations.isEmpty {
            Button {
                Haptics.light()
                // Routes to the Coaches page (handled in MainTabView). Reuses the
                // shared .openInvitations route also used by push/activity taps.
                NotificationCenter.default.post(name: .openInvitations, object: nil)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "envelope.badge.fill")
                        .font(.subheadline)
                        .foregroundColor(ppAccent)

                    Text("\(invitationManager.pendingCount) coach invitation\(invitationManager.pendingCount == 1 ? "" : "s")")
                        .font(.labelLarge)
                        .foregroundColor(Theme.textPrimary)

                    Spacer(minLength: 0)

                    Text("Respond")
                        .font(.labelSmall)
                        .foregroundColor(Theme.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(Theme.textTertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: .cornerLarge)
                        .fill(ppAccent.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: .cornerLarge)
                                .stroke(ppAccent.opacity(0.3), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    AthleteInvitationsBanner()
        .padding()
}
