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

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.circle.fill")
                .font(.title2)
                .foregroundColor(.brandNavy)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(coach.name)
                        .font(.headline)

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

                if coach.isInvitationExpired || coach.lastInvitationStatus == "declined" {
                    Text(coach.isInvitationExpired ? "Invitation expired — swipe right to re-invite" : "Invitation declined — swipe right to re-invite")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                if !coach.role.isEmpty {
                    Text(coach.role)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if !coach.phone.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "phone.fill")
                            .font(.caption)
                        Text(coach.phone)
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                } else if !coach.email.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "envelope.fill")
                            .font(.caption)
                        Text(coach.email)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if coach.hasFolderAccess {
                VStack(alignment: .trailing, spacing: 4) {
                    Image(systemName: "folder.badge.person.crop")
                        .font(.title3)
                        .foregroundColor(.brandNavy)
                    Text("\(coach.sharedFolderIDs.count) folder\(coach.sharedFolderIDs.count == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.brandNavy.opacity(0.1))
                    .frame(width: 100, height: 100)

                Image(systemName: "person.2.badge.gearshape")
                    .font(.system(size: 45))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.brandNavy, Color.brandNavy.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: 12) {
                Text("No Coaches Yet")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Add coach contact info or invite coaches to share videos and get feedback")
                    .font(.body)
                    .foregroundStyle(.secondary)
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
                            .fontWeight(.semibold)
                        if !hasCoachingAccess {
                            Image(systemName: "crown.fill")
                                .font(.caption)
                                .foregroundColor(.yellow)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color.brandNavy)
                    .foregroundColor(.white)
                    .cornerRadius(14)
                }
                .buttonStyle(.plain)

                // Secondary: Add Contact
                Button(action: onAddCoach) {
                    HStack(spacing: 10) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.title3)
                        Text("Add Coach Contact")
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color(.systemGray6))
                    .foregroundColor(.primary)
                    .cornerRadius(14)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }
}

// MARK: - Shared Helper

/// Converts a Coach's connectionStatusColor string to a SwiftUI Color.
/// Used by CoachRow, CoachDetailView, and anywhere coach status is displayed.
func coachStatusColor(for colorName: String) -> Color {
    switch colorName {
    case "green": return .green
    case "orange": return .orange
    case "red": return .red
    default: return .gray
    }
}
