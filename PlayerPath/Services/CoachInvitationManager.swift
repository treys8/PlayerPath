//
//  CoachInvitationManager.swift
//  PlayerPath
//
//  Real-time listener for pending athlete-to-coach invitations.
//  Singleton used by CoachDashboardView and CoachInvitationsView.
//
//  Accept/decline are NOT handled here — callers go through
//  CoachInvitationsViewModel → SharedFolderManager directly, which
//  also handles marking the paired activity notification as read.
//

import Foundation
import FirebaseFirestore
import os

private let invitationLog = Logger(subsystem: "com.playerpath.app", category: "CoachInvitations")

@MainActor
@Observable
class CoachInvitationManager {
    static let shared = CoachInvitationManager()

    var pendingInvitations: [CoachInvitation] = []
    var pendingInvitationsCount: Int { pendingInvitations.count }

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
        }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
        listeningEmail = nil
        // Clear cached invitations so a subsequent role switch or login on the
        // same device doesn't briefly render the previous session's data.
        pendingInvitations = []
    }

    func checkPendingInvitations(forCoachEmail email: String) async {
        do {
            pendingInvitations = try await FirestoreManager.shared.fetchPendingInvitations(forEmail: email)
        } catch {
            invitationLog.error("Failed to check pending invitations: \(error.localizedDescription)")
            // Keep existing cached data on transient failures; the real-time
            // listener will converge when the network recovers.
        }
    }
}
