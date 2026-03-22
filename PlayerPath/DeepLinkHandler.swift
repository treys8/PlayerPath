//
//  DeepLinkHandler.swift
//  PlayerPath
//
//  Deep link routing is handled by DeepLinkIntent in PlayerPathApp.swift.
//  This file contains InvitationDetailView, which is presented by PlayerPathApp
//  when an invitation deep link is opened.
//

import SwiftUI

/// View that displays a specific invitation from a deep link
struct InvitationDetailView: View {
    let invitationId: String

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    private var folderManager: SharedFolderManager { .shared }

    @State private var invitation: CoachInvitation?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isAccepting = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading invitation...")
                } else if let error = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.orange)

                        Text("Error Loading Invitation")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        Button("Close") {
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else if let invitation = invitation {
                    invitationView(invitation)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "envelope.badge.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.brandNavy)

                        Text("Invitation Not Found")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("This invitation may have expired or been removed.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        Button("Close") {
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                }
            }
            .navigationTitle("Coach Invitation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadInvitation()
            }
        }
    }

    @ViewBuilder
    private func invitationView(_ invitation: CoachInvitation) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "envelope.open.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.brandNavy)

                    Text("You're Invited!")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("from \(invitation.athleteName)")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .padding(.top)

                // Folder info
                VStack(alignment: .leading, spacing: 8) {
                    Text("Folder")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)

                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundColor(.brandNavy)
                        Text(invitation.folderName)
                            .font(.headline)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                .padding(.horizontal)

                // Permissions (if available)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your Permissions")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)

                    Text("As a coach, you'll be able to view and collaborate on videos in this folder.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)

                // Accept button
                Button {
                    Task {
                        await acceptInvitation()
                    }
                } label: {
                    if isAccepting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text("Accept Invitation")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isAccepting)
                .padding(.horizontal)

                Spacer()
            }
        }
    }

    private func loadInvitation() async {
        isLoading = true
        errorMessage = nil

        do {
            guard let coachEmail = authManager.userEmail else {
                errorMessage = "Please sign in to view this invitation"
                isLoading = false
                return
            }

            // Fetch the specific invitation
            let invitations = try await folderManager.checkPendingInvitations(forEmail: coachEmail)

            // Find the matching invitation
            if let foundInvitation = invitations.first(where: { $0.id == invitationId }) {
                // Check if expired client-side
                if let expiresAt = foundInvitation.expiresAt, expiresAt < Date() {
                    errorMessage = "This invitation has expired. Ask the athlete to send a new one."
                } else {
                    invitation = foundInvitation
                }
            } else {
                errorMessage = "Invitation not found or already accepted"
            }

        } catch {
            errorMessage = "Failed to load invitation: \(error.localizedDescription)"
        }

        isLoading = false
    }

    private func acceptInvitation() async {
        guard let invitation = invitation else { return }

        // Client-side expiration check
        if let expiresAt = invitation.expiresAt, expiresAt < Date() {
            errorMessage = "This invitation has expired. Ask the athlete to send a new one."
            return
        }

        isAccepting = true

        do {
            try await folderManager.acceptInvitation(invitation, authManager: authManager)

            Haptics.success()

            // Show success briefly then dismiss
            try? await Task.sleep(for: .milliseconds(500))
            dismiss()

        } catch SharedFolderError.coachAthleteLimitReached {
            errorMessage = "You've reached your athlete limit. Upgrade your plan in your Profile to add more athletes."
            ErrorHandlerService.shared.handle(SharedFolderError.coachAthleteLimitReached, context: "InvitationDetailView.acceptInvitation.limitReached", showAlert: false)
        } catch {
            let nsError = error as NSError
            switch nsError.code {
            case InvitationErrorCode.expired.rawValue:
                errorMessage = "This invitation has expired. Ask the athlete to send a new one."
            case InvitationErrorCode.alreadyProcessed.rawValue:
                errorMessage = "This invitation has already been processed."
            default:
                errorMessage = "Failed to accept invitation: \(error.localizedDescription)"
            }
            ErrorHandlerService.shared.handle(error, context: "InvitationDetailView.acceptInvitation", showAlert: false)
        }

        isAccepting = false
    }
}
