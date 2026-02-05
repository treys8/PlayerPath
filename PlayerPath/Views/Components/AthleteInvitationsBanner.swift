//
//  AthleteInvitationsBanner.swift
//  PlayerPath
//
//  Shows pending coach invitations to athletes
//

import SwiftUI
import SwiftData

struct AthleteInvitationsBanner: View {
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @State private var pendingInvitations: [CoachToAthleteInvitation] = []
    @State private var isLoading = false
    @State private var showingInvitations = false

    var body: some View {
        Group {
            if !pendingInvitations.isEmpty {
                Button {
                    Haptics.light()
                    showingInvitations = true
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.green.opacity(0.15))
                                .frame(width: 44, height: 44)

                            Image(systemName: "envelope.badge.fill")
                                .font(.title3)
                                .foregroundColor(.green)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(pendingInvitations.count) Coach Invitation\(pendingInvitations.count == 1 ? "" : "s")")
                                .font(.headline)
                                .foregroundColor(.primary)

                            Text("Tap to view and respond")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.green.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.green.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .task {
            await checkForInvitations()
        }
        .sheet(isPresented: $showingInvitations) {
            AthleteInvitationsSheet(
                invitations: pendingInvitations,
                onInvitationsChanged: {
                    Task { await checkForInvitations() }
                }
            )
        }
    }

    private func checkForInvitations() async {
        guard let email = authManager.userEmail else { return }

        isLoading = true
        do {
            let invitations = try await FirestoreManager.shared.fetchPendingCoachInvitations(forAthleteEmail: email)
            await MainActor.run {
                pendingInvitations = invitations
                isLoading = false
            }
        } catch {
            print("Failed to fetch coach invitations: \(error)")
            await MainActor.run {
                isLoading = false
            }
        }
    }
}

// MARK: - Invitations Sheet

struct AthleteInvitationsSheet: View {
    let invitations: [CoachToAthleteInvitation]
    let onInvitationsChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @Environment(\.modelContext) private var modelContext

    @State private var processingInvitationID: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if invitations.isEmpty {
                    ContentUnavailableView(
                        "No Pending Invitations",
                        systemImage: "envelope.open",
                        description: Text("You'll see invitations from coaches here")
                    )
                } else {
                    ForEach(invitations) { invitation in
                        CoachInvitationCard(
                            invitation: invitation,
                            isProcessing: processingInvitationID == invitation.id,
                            onAccept: { await acceptInvitation(invitation) },
                            onDecline: { await declineInvitation(invitation) }
                        )
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Coach Invitations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Error", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func acceptInvitation(_ invitation: CoachToAthleteInvitation) async {
        processingInvitationID = invitation.id

        do {
            // Update invitation status in Firestore
            try await FirestoreManager.shared.acceptCoachToAthleteInvitation(
                invitationID: invitation.id,
                athleteUserID: authManager.userID ?? ""
            )

            // Create coach record locally
            let coach = Coach(
                name: invitation.coachName,
                email: invitation.coachEmail
            )
            coach.invitationAcceptedAt = Date()
            coach.firebaseCoachID = invitation.coachID
            coach.lastInvitationStatus = "accepted"

            // TODO: Link to athlete properly
            modelContext.insert(coach)
            try modelContext.save()

            await MainActor.run {
                processingInvitationID = nil
                Haptics.success()
                onInvitationsChanged()
            }
        } catch {
            await MainActor.run {
                processingInvitationID = nil
                errorMessage = "Failed to accept invitation: \(error.localizedDescription)"
                Haptics.error()
            }
        }
    }

    private func declineInvitation(_ invitation: CoachToAthleteInvitation) async {
        processingInvitationID = invitation.id

        do {
            try await FirestoreManager.shared.declineCoachToAthleteInvitation(invitationID: invitation.id)

            await MainActor.run {
                processingInvitationID = nil
                Haptics.light()
                onInvitationsChanged()
            }
        } catch {
            await MainActor.run {
                processingInvitationID = nil
                errorMessage = "Failed to decline invitation: \(error.localizedDescription)"
                Haptics.error()
            }
        }
    }
}

// MARK: - Invitation Card

struct CoachInvitationCard: View {
    let invitation: CoachToAthleteInvitation
    let isProcessing: Bool
    let onAccept: () async -> Void
    let onDecline: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Coach info
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 50, height: 50)

                    Image(systemName: "person.fill")
                        .font(.title2)
                        .foregroundColor(.green)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(invitation.coachName)
                        .font(.headline)

                    Text(invitation.coachEmail)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let sentAt = invitation.sentAt {
                        Text("Sent \(sentAt.formatted(.relative(presentation: .named)))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Message if present
            if let message = invitation.message, !message.isEmpty {
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
            }

            // Action buttons
            HStack(spacing: 12) {
                Button {
                    Task { await onDecline() }
                } label: {
                    Text("Decline")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color(.systemGray5))
                        .foregroundColor(.primary)
                        .cornerRadius(10)
                }
                .disabled(isProcessing)

                Button {
                    Task { await onAccept() }
                } label: {
                    HStack {
                        if isProcessing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("Accept")
                        }
                    }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(isProcessing)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowSeparator(.hidden)
    }
}

#Preview {
    AthleteInvitationsBanner()
        .environmentObject(ComprehensiveAuthManager())
        .padding()
}
