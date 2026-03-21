//
//  CoachInvitationManager.swift
//  PlayerPath
//
//  Real-time listener for pending coach invitations.
//  Singleton used by CoachDashboardView and CoachInvitationsView.
//

import Foundation
import Combine
import FirebaseFirestore
import os

private let invitationLog = Logger(subsystem: "com.playerpath.app", category: "CoachInvitations")

@MainActor
class CoachInvitationManager: ObservableObject {
    static let shared = CoachInvitationManager()

    @Published var pendingInvitationsCount: Int = 0
    @Published var pendingInvitations: [CoachInvitation] = []
    @Published var listenerError: String?

    private var invitationsListener: ListenerRegistration?

    private init() {}

    deinit {
        invitationsListener?.remove()
        invitationsListener = nil
    }

    /// Starts a real-time listener for pending invitations.
    @MainActor
    func startInvitationsListener(forCoachEmail email: String) {
        guard invitationsListener == nil else { return }
        let db = Firestore.firestore()
        invitationsListener = db.collection("invitations")
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
    }

    @MainActor
    func checkPendingInvitations(forCoachEmail email: String) async {
        do {
            let invitations = try await FirestoreManager.shared.fetchPendingInvitations(forEmail: email)
            pendingInvitations = invitations
            pendingInvitationsCount = invitations.count
        } catch {
            pendingInvitationsCount = 0
            pendingInvitations = []
        }
    }

    @MainActor
    func acceptInvitation(_ invitation: CoachInvitation, authManager: ComprehensiveAuthManager? = nil) async throws {
        try await SharedFolderManager.shared.acceptInvitation(invitation, authManager: authManager)
        await checkPendingInvitations(forCoachEmail: invitation.coachEmail)
        Haptics.success()
    }

    @MainActor
    func declineInvitation(_ invitation: CoachInvitation) async throws {
        try await SharedFolderManager.shared.declineInvitation(invitation)
        await checkPendingInvitations(forCoachEmail: invitation.coachEmail)
        Haptics.light()
    }
}
