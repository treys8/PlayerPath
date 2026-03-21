//
//  CoachInvitationsView.swift
//  PlayerPath
//
//  Created by Assistant on 11/21/25.
//  Manage received and sent invitations for coaches
//

import SwiftUI

struct CoachInvitationsView: View {
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @StateObject private var viewModel = CoachInvitationsViewModel()
    @State private var showingPaywall = false
    @State private var lastFetchDate: Date?
    @State private var selectedTab: InvitationTab = .received

    enum InvitationTab: String, CaseIterable {
        case received = "Received"
        case sent = "Sent"
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Invitations", selection: $selectedTab) {
                ForEach(InvitationTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            Group {
                if viewModel.isLoading {
                    Spacer()
                    ProgressView("Loading invitations...")
                    Spacer()
                } else if selectedTab == .received {
                    receivedInvitationsView
                } else {
                    sentInvitationsView
                }
            }
        }
        .navigationTitle("Invitations")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let lastFetch = lastFetchDate, Date().timeIntervalSince(lastFetch) < 60 { return }
            await loadInvitations()
            lastFetchDate = Date()
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
        .sheet(isPresented: $showingPaywall) {
            CoachPaywallView()
                .environmentObject(authManager)
        }
    }

    // MARK: - Received Invitations (from athletes)

    @ViewBuilder
    private var receivedInvitationsView: some View {
        if viewModel.invitations.isEmpty {
            EmptyInvitationsView(
                icon: "envelope.open",
                title: "No Received Invitations",
                message: "When athletes invite you to view their content, the invitations will appear here."
            )
        } else {
            List {
                if !viewModel.pendingInvitations.isEmpty {
                    Section {
                        ForEach(viewModel.pendingInvitations) { invitation in
                            InvitationRow(
                                invitation: invitation,
                                isAtLimit: viewModel.isAtAthleteLimit,
                                onAccept: {
                                    await viewModel.acceptInvitation(invitation, authManager: authManager)
                                    if viewModel.limitReached {
                                        showingPaywall = true
                                        viewModel.limitReached = false
                                    }
                                },
                                onDecline: {
                                    await viewModel.declineInvitation(invitation)
                                }
                            )
                        }
                    } header: {
                        Text("Pending")
                    }
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

    // MARK: - Sent Invitations (to athletes)

    @ViewBuilder
    private var sentInvitationsView: some View {
        if viewModel.sentInvitations.isEmpty {
            EmptyInvitationsView(
                icon: "paperplane",
                title: "No Sent Invitations",
                message: "Invitations you send to athletes will appear here so you can track their status."
            )
        } else {
            List {
                if !viewModel.pendingSentInvitations.isEmpty {
                    Section {
                        ForEach(viewModel.pendingSentInvitations) { invitation in
                            SentInvitationRow(invitation: invitation) {
                                await viewModel.cancelInvitation(invitation)
                            }
                        }
                    } header: {
                        Text("Awaiting Response")
                    }
                }

                if !viewModel.acceptedSentInvitations.isEmpty {
                    Section {
                        ForEach(viewModel.acceptedSentInvitations) { invitation in
                            SentInvitationRow(invitation: invitation)
                        }
                    } header: {
                        Text("Accepted")
                    }
                }

                if !viewModel.declinedSentInvitations.isEmpty {
                    Section {
                        ForEach(viewModel.declinedSentInvitations) { invitation in
                            SentInvitationRow(invitation: invitation)
                        }
                    } header: {
                        Text("Declined")
                    }
                }
            }
        }
    }

    private func loadInvitations() async {
        guard let email = authManager.userEmail,
              let coachID = authManager.userID else { return }
        await viewModel.loadInvitations(forCoachEmail: email, coachID: coachID)
        viewModel.updateAthleteLimit(authManager: authManager)
    }
}

// MARK: - Received Invitation Row

struct InvitationRow: View {
    let invitation: CoachInvitation
    var isAtLimit: Bool = false
    let onAccept: () async -> Void
    let onDecline: () async -> Void

    @State private var isProcessing = false
    @State private var showingAcceptConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.title2)
                    .foregroundColor(.brandNavy)

                VStack(alignment: .leading, spacing: 4) {
                    Text(invitation.athleteName)
                        .font(.headline)

                    Text("Wants to share: \(invitation.folderName)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            Text("Sent \((invitation.sentAt ?? invitation.createdAt ?? Date()).formatted(.relative(presentation: .named)))")
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
                        guard !isProcessing else { return }
                        isProcessing = true
                        Task {
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
                    .buttonStyle(.borderless)
                    .disabled(isProcessing)

                    VStack(spacing: 4) {
                        Button {
                            Haptics.light()
                            showingAcceptConfirmation = true
                        } label: {
                            Text("Accept")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(isAtLimit ? Color.gray : Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.borderless)
                        .disabled(isProcessing || isAtLimit)

                        if isAtLimit {
                            Text("Upgrade to add more athletes")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .alert("Accept Invitation", isPresented: $showingAcceptConfirmation) {
            Button("Cancel", role: .cancel) {
                Haptics.light()
            }
            Button("Accept") {
                guard !isProcessing else { return }
                isProcessing = true
                Task {
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

// MARK: - Sent Invitation Row

struct SentInvitationRow: View {
    let invitation: CoachToAthleteInvitation
    var onCancel: (() async -> Void)?

    /// Whether this pending invitation has expired
    private var isExpired: Bool {
        guard invitation.status == .pending,
              let expiresAt = invitation.expiresAt else { return false }
        return expiresAt < Date()
    }

    var body: some View {
        HStack(spacing: 12) {
            statusIcon

            VStack(alignment: .leading, spacing: 4) {
                Text(invitation.athleteName)
                    .font(.subheadline)

                Text(invitation.athleteEmail)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let sentAt = invitation.sentAt {
                    Text("Sent \(sentAt.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                if isExpired {
                    Text("Expired")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.red)
                }

                if let folderName = invitation.folderName {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.fill")
                            .font(.caption2)
                        Text(folderName)
                            .font(.caption)
                    }
                    .foregroundColor(.green)
                }
            }

            Spacer()

            if invitation.status == .pending && !isExpired, let onCancel {
                Button {
                    Task { await onCancel() }
                } label: {
                    Text("Cancel")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.1))
                        .foregroundColor(.red)
                        .cornerRadius(6)
                }
                .buttonStyle(.borderless)
            } else {
                statusBadge
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch invitation.status {
        case .pending:
            Image(systemName: "clock.fill")
                .foregroundColor(.orange)
        case .accepted:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .declined:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.gray)
        case .cancelled:
            Image(systemName: "minus.circle.fill")
                .foregroundColor(.gray)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch invitation.status {
        case .pending:
            Text("Pending")
                .font(.caption2)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.orange.opacity(0.15))
                .foregroundColor(.orange)
                .cornerRadius(6)
        case .accepted:
            Text("Connected")
                .font(.caption2)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.green.opacity(0.15))
                .foregroundColor(.green)
                .cornerRadius(6)
        case .declined:
            Text("Declined")
                .font(.caption2)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.gray.opacity(0.15))
                .foregroundColor(.gray)
                .cornerRadius(6)
        case .cancelled:
            Text("Cancelled")
                .font(.caption2)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.gray.opacity(0.15))
                .foregroundColor(.gray)
                .cornerRadius(6)
        }
    }
}

// MARK: - Empty State

struct EmptyInvitationsView: View {
    var icon: String = "envelope.open"
    var title: String = "No Invitations"
    var message: String = "When athletes invite you to view their content, the invitations will appear here."

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: icon)
                .font(.system(size: 70))
                .foregroundColor(.gray.opacity(0.5))

            Text(title)
                .font(.title2)
                .fontWeight(.semibold)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()
        }
        .padding()
    }
}

