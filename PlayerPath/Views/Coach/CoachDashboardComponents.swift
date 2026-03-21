//
//  CoachDashboardComponents.swift
//  PlayerPath
//
//  Reusable UI components for the coach dashboard: athlete sections,
//  folder rows, empty state, and invitation banners.
//

import SwiftUI

// MARK: - Supporting Types

struct CoachAthleteGroup {
    let athleteID: String
    let athleteName: String
    let folders: [SharedFolder]
}

// MARK: - Athlete Section

struct AthleteSection: View {
    let athleteID: String
    let athleteName: String
    let folders: [SharedFolder]
    var isArchived: Bool = false

    @State private var isExpanded = true

    var body: some View {
        VStack(spacing: 12) {
            Button(action: {
                Haptics.selection()
                withAnimation {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    Image(systemName: "figure.baseball")
                        .font(.title3)
                        .foregroundColor(.green)
                        .frame(width: 40, height: 40)
                        .background(Color.green.opacity(0.1))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(athleteName)
                                .font(.headline)
                                .foregroundColor(isArchived ? .secondary : .primary)
                            if isArchived {
                                Image(systemName: "archivebox.fill")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Text("\(folders.count) shared folder\(folders.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.gray)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(.cornerLarge)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(athleteName)
            .accessibilityHint(isExpanded ? "Collapse" : "Expand")

            if isExpanded {
                VStack(spacing: 8) {
                    ForEach(folders) { folder in
                        NavigationLink(destination: CoachFolderDetailView(folder: folder)) {
                            CoachFolderRowView(folder: folder)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.leading, 12)
            }
        }
    }
}

// MARK: - Folder Row

struct CoachFolderRowView: View {
    let folder: SharedFolder
    @EnvironmentObject private var authManager: ComprehensiveAuthManager

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.title2)
                .foregroundColor(.brandNavy)

            VStack(alignment: .leading, spacing: 4) {
                Text(folder.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                HStack(spacing: 12) {
                    Label("\(folder.videoCount ?? 0)", systemImage: "video")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let coachID = authManager.userID,
                       let permissions = folder.getPermissions(for: coachID) {
                        if permissions.canUpload {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                        if permissions.canComment {
                            Image(systemName: "bubble.left.fill")
                                .font(.caption)
                                .foregroundColor(.brandNavy)
                        }
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(folder.name)
    }
}

// MARK: - Empty State

struct CoachEmptyStateView: View {
    @Binding var showingInvitations: Bool
    @State private var showingInviteAthlete = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.1))
                    .frame(width: 120, height: 120)

                Image(systemName: "person.3.sequence")
                    .font(.system(size: 50))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.green, .green.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: 12) {
                Text("Welcome, Coach!")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Connect with athletes to view their game videos, send practice drills, and provide feedback.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            VStack(spacing: 12) {
                Button(action: {
                    Haptics.medium()
                    showingInviteAthlete = true
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "person.badge.plus")
                            .font(.title3)
                        Text("Invite an Athlete")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(14)
                }
                .buttonStyle(.plain)

                Button(action: {
                    Haptics.light()
                    showingInvitations = true
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "envelope.open")
                            .font(.title3)
                        Text("Check Pending Invitations")
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
        .sheet(isPresented: $showingInviteAthlete) {
            InviteAthleteSheet()
        }
    }
}

// MARK: - Pending Invitations Banner

struct PendingInvitationsBanner: View {
    @Binding var showingInvitations: Bool
    @ObservedObject private var invitationManager = CoachInvitationManager.shared

    var body: some View {
        if invitationManager.pendingInvitationsCount > 0 {
            Button(action: {
                Haptics.light()
                showingInvitations = true
            }) {
                HStack {
                    Image(systemName: "envelope.badge.fill")
                        .foregroundColor(.green)

                    Text("You have \(invitationManager.pendingInvitationsCount) pending invitation\(invitationManager.pendingInvitationsCount == 1 ? "" : "s")")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                }
                .padding()
                .background(
                    LinearGradient(
                        colors: [Color.green.opacity(0.1), Color.green.opacity(0.05)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(.cornerLarge)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Pending Invitations")
            .accessibilityHint("Tap to view and respond to invitations")
        }
    }
}
