//
//  AthleteInvitationsBanner.swift
//  PlayerPath
//
//  Shows pending coach invitations to athletes
//

import SwiftUI
import SwiftData
import FirebaseAuth
import os

private let log = Logger(subsystem: "com.playerpath.app", category: "AthleteInvitationsBanner")

struct AthleteInvitationsBanner: View {
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    private var invitationManager: AthleteInvitationManager { .shared }
    @State private var showingInvitations = false

    var body: some View {
        Group {
            if !invitationManager.pendingInvitations.isEmpty {
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
                            Text("\(invitationManager.pendingCount) Coach Invitation\(invitationManager.pendingCount == 1 ? "" : "s")")
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
                        RoundedRectangle(cornerRadius: .cornerXLarge)
                            .fill(Color.green.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: .cornerXLarge)
                                    .stroke(Color.green.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showingInvitations) {
            AthleteInvitationsSheet(
                invitations: invitationManager.pendingInvitations,
                onInvitationsChanged: { }  // Real-time listener handles updates
            )
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
        guard processingInvitationID == nil else {
            log.warning("ACCEPT blocked: already processing \(processingInvitationID ?? "nil")")
            return
        }
        guard let currentUID = authManager.userID, !currentUID.isEmpty else {
            log.warning("ACCEPT blocked: no userID")
            errorMessage = "Not signed in. Please sign in and try again."
            Haptics.error()
            return
        }
        log.debug("ACCEPT starting for invitation \(invitation.id ?? "nil") from coach \(invitation.coachName, privacy: .private)")
        processingInvitationID = invitation.id

        do {
            let result = try await AthleteInvitationManager.shared.acceptInvitation(
                invitation,
                userID: currentUID,
                modelContext: modelContext
            )
            log.info("ACCEPT succeeded for coach: \(result.coachName, privacy: .private)")
            Haptics.success()
            onInvitationsChanged()
        } catch {
            log.warning("ACCEPT failed: \(error.localizedDescription)")
            errorMessage = AthleteInvitationManager.errorMessage(for: error, action: "accept")
            Haptics.error()
        }
        processingInvitationID = nil
    }

    private func declineInvitation(_ invitation: CoachToAthleteInvitation) async {
        guard processingInvitationID == nil else {
            log.warning("DECLINE blocked: already processing \(processingInvitationID ?? "nil")")
            return
        }
        log.debug("DECLINE starting for invitation \(invitation.id ?? "nil") from coach \(invitation.coachName, privacy: .private)")
        processingInvitationID = invitation.id

        do {
            try await AthleteInvitationManager.shared.declineInvitation(invitation)
            Haptics.light()
            onInvitationsChanged()
        } catch {
            errorMessage = AthleteInvitationManager.errorMessage(for: error, action: "decline")
            Haptics.error()
        }
        processingInvitationID = nil
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
                    .cornerRadius(.cornerMedium)
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
                .buttonStyle(.borderless)
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
                .buttonStyle(.borderless)
                .disabled(isProcessing)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(.cornerXLarge)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowSeparator(.hidden)
    }
}

#Preview {
    AthleteInvitationsBanner()
        .environmentObject(ComprehensiveAuthManager())
        .padding()
}
