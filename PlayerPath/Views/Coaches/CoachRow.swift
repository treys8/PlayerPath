//
//  CoachRow.swift
//  PlayerPath
//
//  Extracted from CoachesView.swift
//

import SwiftUI

// MARK: - Coach Row

struct CoachRow: View {
    let coach: Coach

    @Environment(\.ppAccent) private var ppAccent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.circle.fill")
                .font(.title2)
                .foregroundColor(ppAccent)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(coach.name)
                        .font(.headingMedium)
                        .foregroundColor(Theme.textPrimary)

                    // Connection status badge
                    if coach.hasFirebaseAccount {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                            Text(coach.connectionStatus)
                                .font(.caption2)
                        }
                        .foregroundStyle(coachStatusColor(for: coach.connectionStatusColor))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(coachStatusColor(for: coach.connectionStatusColor).opacity(0.15))
                        .cornerRadius(4)
                    } else if coach.invitationSentAt != nil {
                        HStack(spacing: 4) {
                            Image(systemName: coach.isInvitationExpired ? "exclamationmark.circle.fill" : "clock.fill")
                                .font(.caption2)
                            Text(coach.connectionStatus)
                                .font(.caption2)
                        }
                        .foregroundStyle(coachStatusColor(for: coach.connectionStatusColor))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(coachStatusColor(for: coach.connectionStatusColor).opacity(0.15))
                        .cornerRadius(4)
                    }
                }

                if coach.lastInvitationStatus == "rejected_limit" {
                    Text("Coach is at their athlete capacity — they'll need to upgrade or free a slot before they can accept")
                        .font(.caption2)
                        .foregroundStyle(Theme.warning)
                } else if coach.isInvitationExpired || coach.lastInvitationStatus == "declined" {
                    Text(coach.isInvitationExpired ? "Invitation expired — swipe right to re-invite" : "Invitation declined — swipe right to re-invite")
                        .font(.caption2)
                        .foregroundStyle(Theme.warning)
                }

                if !coach.role.isEmpty {
                    Text(coach.role)
                        .font(.ppSubheadline)
                        .foregroundStyle(Theme.textSecondary)
                }

                if !coach.phone.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "phone.fill")
                            .font(.caption)
                        Text(coach.phone)
                            .font(.caption)
                    }
                    .foregroundStyle(Theme.textSecondary)
                } else if !coach.email.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "envelope.fill")
                            .font(.caption)
                        Text(coach.email)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .foregroundStyle(Theme.textSecondary)
                }
            }

            Spacer()

            if coach.hasFolderAccess {
                VStack(alignment: .trailing, spacing: 4) {
                    Image(systemName: "folder.badge.person.crop")
                        .font(.title3)
                        .foregroundColor(ppAccent)
                    Text("\(coach.sharedFolderIDs.count) folder\(coach.sharedFolderIDs.count == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Empty State

struct EmptyCoachesView: View {
    let onAddCoach: () -> Void
    let onInviteCoach: () -> Void
    let hasCoachingAccess: Bool

    @Environment(\.ppAccent) private var ppAccent

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(ppAccent.opacity(0.12))
                    .frame(width: 100, height: 100)

                Image(systemName: "person.2.badge.gearshape")
                    .font(.system(size: 45))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [ppAccent, ppAccent.opacity(0.75)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: 12) {
                Text("No Coaches Yet")
                    .font(.headingLarge)
                    .foregroundColor(Theme.textPrimary)

                Text("Add coach contact info or invite coaches to share videos and get feedback")
                    .font(.bodyMedium)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            VStack(spacing: 12) {
                // Primary: Invite Coach (Premium)
                Button(action: onInviteCoach) {
                    HStack(spacing: 10) {
                        Image(systemName: "paperplane.fill")
                            .font(.title3)
                        Text("Invite Coach to Share")
                            .font(.headingMedium)
                        if !hasCoachingAccess {
                            Image(systemName: "crown.fill")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .foregroundColor(.white)
                    .background(
                        RoundedRectangle(cornerRadius: .cornerXLarge, style: .continuous)
                            .fill(ppAccent)
                    )
                    .shadow(color: ppAccent.opacity(0.3), radius: 12, x: 0, y: 6)
                }
                .buttonStyle(PremiumButtonStyle())

                // Secondary: Add Contact
                Button(action: onAddCoach) {
                    HStack(spacing: 10) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.title3)
                        Text("Add Coach Contact")
                            .font(.headingMedium)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .foregroundColor(Theme.textPrimary)
                    .background(
                        RoundedRectangle(cornerRadius: .cornerXLarge, style: .continuous)
                            .fill(Theme.card)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: .cornerXLarge, style: .continuous)
                            .strokeBorder(Theme.divider, lineWidth: 1)
                    )
                }
                .buttonStyle(PremiumButtonStyle())
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface)
    }
}

// MARK: - Shared Helper

/// Converts a Coach's connectionStatusColor string to a SwiftUI Color.
/// Used by CoachRow, CoachDetailView, and anywhere coach status is displayed.
/// Retinted to the calm palette: forest green = connected, amber = pending/
/// attention, system red kept for hard errors.
func coachStatusColor(for colorName: String) -> Color {
    switch colorName {
    case "green": return Theme.chipGreenText
    case "orange": return Theme.warning
    case "red": return .red
    default: return Theme.textTertiary
    }
}
