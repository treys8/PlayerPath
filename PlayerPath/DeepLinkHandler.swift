//
//  DeepLinkHandler.swift
//  PlayerPath
//
//  Deep link routing is handled by DeepLinkIntent in PlayerPathApp.swift.
//  This file contains InvitationDetailView, which is presented by PlayerPathApp
//  when an invitation deep link is opened. Supports both athlete-to-coach and
//  coach-to-athlete invitation types.
//

import SwiftUI
import SwiftData

/// View that displays a specific invitation from a deep link.
/// Determines the invitation type automatically and shows the appropriate UI.
struct InvitationDetailView: View {
    let invitationId: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var authManager: ComprehensiveAuthManager

    // Which type of invitation was loaded
    @State private var athleteToCoachInvitation: CoachInvitation?
    @State private var coachToAthleteInvitation: CoachToAthleteInvitation?

    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isAccepting = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading invitation...")
                } else if let error = errorMessage {
                    errorView(error)
                } else if let invitation = athleteToCoachInvitation {
                    athleteToCoachView(invitation)
                } else if let invitation = coachToAthleteInvitation {
                    coachToAthleteView(invitation)
                } else {
                    notFoundView
                }
            }
            .navigationTitle("Invitation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await loadInvitation() }
        }
    }

    // MARK: - Athlete-to-Coach View (coach is viewing)

    @ViewBuilder
    private func athleteToCoachView(_ invitation: CoachInvitation) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Image(systemName: "envelope.open.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.brandNavy)
                    Text("You're Invited!")
                        .font(.title).fontWeight(.bold)
                    Text("from \(invitation.athleteName)")
                        .font(.title3).foregroundColor(.secondary)
                }
                .padding(.top)

                if let folderName = invitation.folderName {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Folder")
                            .font(.caption).foregroundColor(.secondary).textCase(.uppercase)
                        HStack {
                            Image(systemName: "folder.fill").foregroundColor(.brandNavy)
                            Text(folderName).font(.headline)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Your Permissions")
                        .font(.caption).foregroundColor(.secondary).textCase(.uppercase)
                    Text("As a coach, you'll be able to view and collaborate on videos in this folder.")
                        .font(.subheadline).foregroundColor(.secondary)
                }
                .padding(.horizontal)

                acceptButton
                Spacer()
            }
        }
    }

    // MARK: - Coach-to-Athlete View (athlete is viewing)

    @ViewBuilder
    private func coachToAthleteView(_ invitation: CoachToAthleteInvitation) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Image(systemName: "envelope.open.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.green)
                    Text("Coach Invitation")
                        .font(.title).fontWeight(.bold)
                    Text("from \(invitation.coachName)")
                        .font(.title3).foregroundColor(.secondary)
                }
                .padding(.top)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Coach Info")
                        .font(.caption).foregroundColor(.secondary).textCase(.uppercase)
                    HStack {
                        Image(systemName: "person.fill").foregroundColor(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(invitation.coachName).font(.headline)
                            Text(invitation.coachEmail).font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                .padding(.horizontal)

                if let message = invitation.message, !message.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Message")
                            .font(.caption).foregroundColor(.secondary).textCase(.uppercase)
                        Text(message)
                            .font(.subheadline).foregroundColor(.secondary)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                }

                Text("Accept to connect with this coach. If you have a Pro plan, a shared folder will be created automatically.")
                    .font(.subheadline).foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                acceptButton
                Spacer()
            }
        }
    }

    // MARK: - Shared Components

    private var acceptButton: some View {
        Button {
            Task { await acceptInvitation() }
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
    }

    @ViewBuilder
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60)).foregroundColor(.orange)
            Text("Error Loading Invitation")
                .font(.title2).fontWeight(.bold)
            Text(error)
                .font(.subheadline).foregroundColor(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal)
            Button("Close") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var notFoundView: some View {
        VStack(spacing: 16) {
            Image(systemName: "envelope.badge.fill")
                .font(.system(size: 60)).foregroundColor(.brandNavy)
            Text("Invitation Not Found")
                .font(.title2).fontWeight(.bold)
            Text("This invitation may have expired or been removed.")
                .font(.subheadline).foregroundColor(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal)
            Button("Close") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Load

    private func loadInvitation() async {
        isLoading = true
        errorMessage = nil

        guard let userEmail = authManager.userEmail else {
            errorMessage = "Please sign in to view this invitation"
            isLoading = false
            return
        }

        do {
            // Try athlete-to-coach first (user is a coach receiving from athlete)
            let coachInvitations = try await SharedFolderManager.shared.checkPendingInvitations(forEmail: userEmail)
            if let found = coachInvitations.first(where: { $0.id == invitationId }) {
                if let expiresAt = found.expiresAt, expiresAt < Date() {
                    errorMessage = "This invitation has expired. Ask the athlete to send a new one."
                } else {
                    athleteToCoachInvitation = found
                }
                isLoading = false
                return
            }

            // Try coach-to-athlete (user is an athlete receiving from coach)
            let athleteInvitations = await AthleteInvitationManager.shared.fetchPendingInvitations(forEmail: userEmail)
            if let found = athleteInvitations.first(where: { $0.id == invitationId }) {
                if let expiresAt = found.expiresAt, expiresAt < Date() {
                    errorMessage = "This invitation has expired. Ask your coach to send a new one."
                } else {
                    coachToAthleteInvitation = found
                }
                isLoading = false
                return
            }

            // Neither type found
        } catch {
            errorMessage = "Failed to load invitation: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - Accept

    private func acceptInvitation() async {
        isAccepting = true

        if let invitation = athleteToCoachInvitation {
            await acceptAthleteToCoach(invitation)
        } else if let invitation = coachToAthleteInvitation {
            await acceptCoachToAthlete(invitation)
        }

        isAccepting = false
    }

    private func acceptAthleteToCoach(_ invitation: CoachInvitation) async {
        if let expiresAt = invitation.expiresAt, expiresAt < Date() {
            errorMessage = "This invitation has expired. Ask the athlete to send a new one."
            return
        }

        do {
            try await SharedFolderManager.shared.acceptInvitation(invitation, authManager: authManager)
            Haptics.success()
            try? await Task.sleep(for: .milliseconds(500))
            dismiss()
        } catch SharedFolderError.coachAthleteLimitReached {
            errorMessage = "You've reached your athlete limit. Upgrade your plan to add more athletes."
            ErrorHandlerService.shared.handle(SharedFolderError.coachAthleteLimitReached, context: "InvitationDetailView.acceptAthleteToCoach", showAlert: false)
        } catch {
            handleInvitationError(error, sender: "the athlete")
        }
    }

    private func acceptCoachToAthlete(_ invitation: CoachToAthleteInvitation) async {
        if let expiresAt = invitation.expiresAt, expiresAt < Date() {
            errorMessage = "This invitation has expired. Ask your coach to send a new one."
            return
        }

        guard let currentUID = authManager.userID, !currentUID.isEmpty else {
            errorMessage = "Not signed in. Please sign in and try again."
            return
        }

        do {
            let _ = try await AthleteInvitationManager.shared.acceptInvitation(
                invitation,
                userID: currentUID,
                modelContext: modelContext
            )
            Haptics.success()
            try? await Task.sleep(for: .milliseconds(500))
            dismiss()
        } catch {
            handleInvitationError(error, sender: "your coach")
        }
    }

    private func handleInvitationError(_ error: Error, sender: String) {
        let nsError = error as NSError
        switch nsError.code {
        case InvitationErrorCode.expired.rawValue:
            errorMessage = "This invitation has expired. Ask \(sender) to send a new one."
        case InvitationErrorCode.alreadyProcessed.rawValue:
            errorMessage = "This invitation has already been processed."
        default:
            errorMessage = "Failed to accept invitation: \(error.localizedDescription)"
        }
        ErrorHandlerService.shared.handle(error, context: "InvitationDetailView.acceptInvitation", showAlert: false)
    }
}
