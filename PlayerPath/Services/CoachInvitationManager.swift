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

    private var invitationsListener: ListenerRegistration?

    private init() {}

    /// Starts a real-time listener for pending invitations.
    func startInvitationsListener(forCoachEmail email: String) {
        guard invitationsListener == nil else { return }
        let db = FirestoreManager.shared.db
        invitationsListener = db.collection(FC.invitations)
            .whereField("type", isEqualTo: "athlete_to_coach")
            .whereField("coachEmail", isEqualTo: email.lowercased())
            .whereField("status", isEqualTo: "pending")
            .whereField("expiresAt", isGreaterThan: Timestamp(date: Date()))
            .limit(to: 50)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if error != nil {
                    Task { @MainActor in
                        self.listenerError = "Unable to refresh invitations."
                    }
                    return
                }
                let invitations = snapshot?.documents.compactMap { doc -> CoachInvitation? in
                    do {
                        var inv = try doc.data(as: CoachInvitation.self)
                        inv.id = doc.documentID
                        return inv
                    } catch {
                        invitationLog.warning("Failed to decode invitation \(doc.documentID): \(error.localizedDescription)")
                        return nil
                    }
                } ?? []
                Task { @MainActor in
                    self.listenerError = nil
                    self.pendingInvitations = invitations
                    self.pendingInvitationsCount = invitations.count
                }
            }
    }

    func stopInvitationsListener() {
        invitationsListener?.remove()
        invitationsListener = nil
        listenerError = nil
        pendingInvitations = []
        pendingInvitationsCount = 0
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
        await checkPendingInvitations(forCoachEmail: invitation.coachEmail)
        Haptics.success()
    }

    func declineInvitation(_ invitation: CoachInvitation) async throws {
        try await SharedFolderManager.shared.declineInvitation(invitation)
        await checkPendingInvitations(forCoachEmail: invitation.coachEmail)
        Haptics.light()
    }
}
