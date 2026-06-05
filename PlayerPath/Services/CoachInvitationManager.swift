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

    /// Count of *sent* coach→athlete invitations still awaiting a response.
    /// These consume athlete slots toward the coach's limit, so the UI surfaces
    /// them (Dashboard/Athletes banner) — otherwise a coach with outstanding
    /// invites hits "limit reached" with no visible explanation. Refreshed
    /// explicitly via `refreshSentPendingCount` (cheap server aggregation) on
    /// tab appear, pull-to-refresh, and after sending/cancelling an invite.
    var pendingSentCount: Int = 0

    private var listener: ListenerRegistration?
    private var listeningEmail: String?
    private var pendingCheckTask: Task<Void, Never>?

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
        // Cancel any in-flight one-shot check so a stale completion doesn't
        // clobber the next coach's state after a role switch.
        pendingCheckTask?.cancel()
        pendingCheckTask = nil
        // Clear cached invitations so a subsequent role switch or login on the
        // same device doesn't briefly render the previous session's data.
        pendingInvitations = []
        pendingSentCount = 0
    }

    /// Refreshes the count of sent coach→athlete invitations still awaiting a
    /// response. Best-effort: leaves the prior value on transient failure.
    func refreshSentPendingCount(coachID: String) async {
        do {
            pendingSentCount = try await FirestoreManager.shared.countPendingCoachToAthleteInvitations(coachID: coachID)
        } catch {
            invitationLog.error("Failed to refresh sent-pending count: \(error.localizedDescription)")
        }
    }

    func checkPendingInvitations(forCoachEmail email: String) async {
        // Cancel any prior in-flight check so two rapid invocations don't
        // race for the published `pendingInvitations` slot. The later result
        // is the one we want.
        pendingCheckTask?.cancel()
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await FirestoreManager.shared.fetchPendingInvitations(forEmail: email)
                if Task.isCancelled { return }
                self.pendingInvitations = result
            } catch {
                if Task.isCancelled { return }
                invitationLog.error("Failed to check pending invitations: \(error.localizedDescription)")
                // Keep existing cached data on transient failures; the real-time
                // listener will converge when the network recovers.
            }
        }
        pendingCheckTask = task
        await task.value
    }
}
