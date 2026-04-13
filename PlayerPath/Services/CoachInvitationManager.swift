//
//  CoachInvitationManager.swift
//  PlayerPath
//
//  Real-time listener for pending coach invitations.
//  Singleton used by CoachDashboardView and CoachInvitationsView.
//

import Foundation
import FirebaseFirestore
import os

private let invitationLog = Logger(subsystem: "com.playerpath.app", category: "CoachInvitations")

@MainActor
@Observable
class CoachInvitationManager {
    static let shared = CoachInvitationManager()

    var pendingInvitationsCount: Int = 0
    var pendingInvitations: [CoachInvitation] = []
    var listenerError: String?

    private var listener: ListenerRegistration?
    private var listeningEmail: String?

    private init() {}

    /// Starts a real-time listener for pending athlete-to-coach invitations.
    /// Idempotent: restarts if the email changes, no-op if already listening to the same email.
    func startListening(forEmail email: String) {
        let normalized = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        if listener != nil, listeningEmail == normalized { return }
        stopListening()
        listeningEmail = normalized
        listener = FirestoreManager.shared.listenPendingAthleteInvitations(forCoachEmail: normalized) { [weak self] invitations in
            guard let self else { return }
            self.pendingInvitations = invitations
            self.pendingInvitationsCount = invitations.count
        }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
        listeningEmail = nil
    }

    func checkPendingInvitations(forCoachEmail email: String) async {
        do {
            let invitations = try await FirestoreManager.shared.fetchPendingInvitations(forEmail: email)
            pendingInvitations = invitations
            pendingInvitationsCount = invitations.count
        } catch {
            invitationLog.error("Failed to check pending invitations: \(error.localizedDescription)")
            pendingInvitationsCount = 0
            pendingInvitations = []
        }
    }

    func acceptInvitation(_ invitation: CoachInvitation, authManager: ComprehensiveAuthManager? = nil) async throws {
        try await SharedFolderManager.shared.acceptInvitation(invitation, authManager: authManager)
        // Optimistic removal — listener will converge when Firestore reflects status change
        if let id = invitation.id {
            pendingInvitations.removeAll { $0.id == id }
            pendingInvitationsCount = pendingInvitations.count
        }
        Haptics.success()
    }

    func declineInvitation(_ invitation: CoachInvitation) async throws {
        try await SharedFolderManager.shared.declineInvitation(invitation)
        if let id = invitation.id {
            pendingInvitations.removeAll { $0.id == id }
            pendingInvitationsCount = pendingInvitations.count
        }
        Haptics.light()
    }
}
