//
//  CoachInvitationsView.swift
//  PlayerPath
//
//  Created by Assistant on 11/21/25.
//  Manage pending invitations from athletes
//

import SwiftUI
import Combine

struct CoachInvitationsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @StateObject private var viewModel = CoachInvitationsViewModel()
    
    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading invitations...")
                } else if viewModel.invitations.isEmpty {
                    EmptyInvitationsView()
                } else {
                    List {
                        Section {
                            ForEach(viewModel.pendingInvitations) { invitation in
                                InvitationRow(
                                    invitation: invitation,
                                    onAccept: {
                                        await viewModel.acceptInvitation(invitation)
                                    },
                                    onDecline: {
                                        await viewModel.declineInvitation(invitation)
                                    }
                                )
                            }
                        } header: {
                            Text("Pending Invitations")
                        }
                        
                        if !viewModel.acceptedInvitations.isEmpty {
                            Section {
                                ForEach(viewModel.acceptedInvitations) { invitation in
                                    AcceptedInvitationRow(invitation: invitation)
                                }
                            } header: {
                                Text("Accepted")
                            }
                        }
                        
                        if !viewModel.declinedInvitations.isEmpty {
                            Section {
                                ForEach(viewModel.declinedInvitations) { invitation in
                                    DeclinedInvitationRow(invitation: invitation)
                                }
                            } header: {
                                Text("Declined")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Invitations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadInvitations()
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") {
                    viewModel.errorMessage = nil
                }
            } message: {
                if let error = viewModel.errorMessage {
                    Text(error)
                }
            }
        }
    }
    
    private func loadInvitations() async {
        guard let email = authManager.userEmail else { return }
        await viewModel.loadInvitations(forCoachEmail: email)
    }
}

// MARK: - Invitation Row

struct InvitationRow: View {
    let invitation: CoachInvitation
    let onAccept: () async -> Void
    let onDecline: () async -> Void

    @State private var isProcessing = false
    @State private var showingAcceptConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.title2)
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 4) {
                    Text(invitation.athleteName)
                        .font(.headline)

                    Text("Wants to share: \(invitation.folderName)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            Text("Sent \(invitation.createdAt.formatted(.relative(presentation: .named)))")
                .font(.caption)
                .foregroundColor(.secondary)

            if isProcessing {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Processing...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
            } else {
                HStack(spacing: 12) {
                    Button {
                        Task {
                            isProcessing = true
                            await onDecline()
                            isProcessing = false
                        }
                    } label: {
                        Text("Decline")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color(.systemGray5))
                            .foregroundColor(.primary)
                            .cornerRadius(8)
                    }
                    .disabled(isProcessing)

                    Button {
                        Haptics.light()
                        showingAcceptConfirmation = true
                    } label: {
                        Text("Accept")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .disabled(isProcessing)
                }
            }
        }
        .padding(.vertical, 8)
        .alert("Accept Invitation", isPresented: $showingAcceptConfirmation) {
            Button("Cancel", role: .cancel) {
                Haptics.light()
            }
            Button("Accept") {
                Task {
                    isProcessing = true
                    await onAccept()
                    isProcessing = false
                }
            }
        } message: {
            Text("\(invitation.athleteName) wants to share \"\(invitation.folderName)\" with you. You'll be able to view and interact with their videos based on the permissions they grant.")
        }
    }
}

// MARK: - Accepted Invitation Row

struct AcceptedInvitationRow: View {
    let invitation: CoachInvitation
    
    var body: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(invitation.athleteName)
                    .font(.subheadline)
                Text(invitation.folderName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text("Accepted")
                .font(.caption2)
                .foregroundColor(.green)
        }
    }
}

// MARK: - Declined Invitation Row

struct DeclinedInvitationRow: View {
    let invitation: CoachInvitation
    
    var body: some View {
        HStack {
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.gray)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(invitation.athleteName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(invitation.folderName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text("Declined")
                .font(.caption2)
                .foregroundColor(.gray)
        }
    }
}

// MARK: - Empty State

struct EmptyInvitationsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "envelope.open")
                .font(.system(size: 70))
                .foregroundColor(.gray.opacity(0.5))
            
            Text("No Invitations")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("When athletes invite you to view their content, the invitations will appear here.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }
}

// MARK: - View Model

@MainActor
class CoachInvitationsViewModel: ObservableObject {
    @Published var invitations: [CoachInvitation] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    var pendingInvitations: [CoachInvitation] {
        invitations.filter { $0.status == .pending }
    }

    var acceptedInvitations: [CoachInvitation] {
        invitations.filter { $0.status == .accepted }
    }

    var declinedInvitations: [CoachInvitation] {
        invitations.filter { $0.status == .declined }
    }
    
    func loadInvitations(forCoachEmail email: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            invitations = try await SharedFolderManager.shared.checkPendingInvitations(forEmail: email)
        } catch {
            errorMessage = "Failed to load invitations: \(error.localizedDescription)"
            print("❌ Failed to load invitations: \(error)")
        }
        
        isLoading = false
    }
    
    func acceptInvitation(_ invitation: CoachInvitation) async {
        do {
            // Step 1: Accept invitation in Firestore
            try await SharedFolderManager.shared.acceptInvitation(invitation)

            // Step 2: Verify the operation completed by checking invitations list exists
            guard let index = invitations.firstIndex(where: { $0.id == invitation.id }) else {
                throw NSError(
                    domain: "CoachInvitationsView",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Invitation was accepted but local state is out of sync. Please refresh."]
                )
            }

            // Step 3: Update local state
            invitations[index] = CoachInvitation(
                id: invitation.id,
                folderID: invitation.folderID,
                folderName: invitation.folderName,
                athleteID: invitation.athleteID,
                athleteName: invitation.athleteName,
                coachEmail: invitation.coachEmail,
                permissions: invitation.permissions,
                createdAt: invitation.createdAt,
                status: .accepted
            )

            // Step 4: Only show success if everything completed
            Haptics.success()
            print("✅ Successfully accepted invitation for folder: \(invitation.folderName)")

        } catch {
            // Show user-friendly error message
            if error.localizedDescription.contains("Network") {
                errorMessage = "Network error. Please check your connection and try again."
            } else if error.localizedDescription.contains("sync") {
                errorMessage = "Invitation accepted, but please refresh to see updates."
            } else {
                errorMessage = "Failed to accept invitation: \(error.localizedDescription)"
            }

            print("❌ Failed to accept invitation: \(error)")
            Haptics.error()
        }
    }
    
    func declineInvitation(_ invitation: CoachInvitation) async {
        do {
            // Step 1: Decline invitation in Firestore
            try await SharedFolderManager.shared.declineInvitation(invitation)

            // Step 2: Verify the operation completed
            guard let index = invitations.firstIndex(where: { $0.id == invitation.id }) else {
                throw NSError(
                    domain: "CoachInvitationsView",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Invitation was declined but local state is out of sync. Please refresh."]
                )
            }

            // Step 3: Update local state
            invitations[index] = CoachInvitation(
                id: invitation.id,
                folderID: invitation.folderID,
                folderName: invitation.folderName,
                athleteID: invitation.athleteID,
                athleteName: invitation.athleteName,
                coachEmail: invitation.coachEmail,
                permissions: invitation.permissions,
                createdAt: invitation.createdAt,
                status: .declined
            )

            // Step 4: Only show success if everything completed
            Haptics.success()
            print("✅ Successfully declined invitation for folder: \(invitation.folderName)")

        } catch {
            // Show user-friendly error message
            if error.localizedDescription.contains("Network") {
                errorMessage = "Network error. Please check your connection and try again."
            } else if error.localizedDescription.contains("sync") {
                errorMessage = "Invitation declined, but please refresh to see updates."
            } else {
                errorMessage = "Failed to decline invitation: \(error.localizedDescription)"
            }

            print("❌ Failed to decline invitation: \(error)")
            Haptics.error()
        }
    }
}

// MARK: - Preview

#Preview {
    CoachInvitationsView()
        .environmentObject(ComprehensiveAuthManager())
}
