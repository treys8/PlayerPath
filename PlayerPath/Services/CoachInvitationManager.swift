//
//  CoachInvitationManager.swift
//  PlayerPath
//
//  Real-time listener for pending coach invitations.
//  Singleton used by CoachDashboardView and CoachInvitationsView.
//

import Foundation
import os

private let invitationLog = Logger(subsystem: "com.playerpath.app", category: "CoachInvitations")

@MainActor
@Observable
class CoachInvitationManager {
    static let shared = CoachInvitationManager()

    var pendingInvitationsCount: Int = 0
    var pendingInvitations: [CoachInvitation] = []
    var listenerError: String?

    private init() {}

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
