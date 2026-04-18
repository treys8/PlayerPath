//
//  CoachInvitationsViewModel.swift
//  PlayerPath
//
//  ViewModel for CoachInvitationsView — loads, accepts, declines,
//  and cancels invitations.
//

import Foundation
import FirebaseAuth

@MainActor
@Observable
class CoachInvitationsViewModel {
    var invitations: [CoachInvitation] = []
    var sentInvitations: [CoachToAthleteInvitation] = []
    var isLoading = false
    var errorMessage: String?
    var limitReached = false
    var isAtAthleteLimit: Bool = false

    private var lastCoachEmail: String?
    private var lastCoachID: String?

    // Received invitation filters
    var pendingInvitations: [CoachInvitation] {
        invitations.filter { $0.status == .pending }
    }

    var acceptedInvitations: [CoachInvitation] {
        invitations.filter { $0.status == .accepted }
    }

    var declinedInvitations: [CoachInvitation] {
        invitations.filter { $0.status == .declined }
    }

    // Sent invitation filters
    var pendingSentInvitations: [CoachToAthleteInvitation] {
        sentInvitations.filter { $0.status == .pending }
    }

    var acceptedSentInvitations: [CoachToAthleteInvitation] {
        sentInvitations.filter { $0.status == .accepted }
    }

    var declinedSentInvitations: [CoachToAthleteInvitation] {
        sentInvitations.filter { $0.status == .declined }
    }

    var limitReachedSentInvitations: [CoachToAthleteInvitation] {
        sentInvitations.filter { $0.status == .rejectedLimit }
    }

    func updateAthleteLimit(coachID: String, authManager: ComprehensiveAuthManager) async {
        isAtAthleteLimit = await SubscriptionGate.isAtAthleteLimit(
            coachID: coachID,
            authManager: authManager,
            includingPending: true
        )
    }

    func loadInvitations(forCoachEmail email: String, coachID: String) async {
        lastCoachEmail = email
        lastCoachID = coachID
        isLoading = true
        errorMessage = nil

        async let receivedTask = SharedFolderManager.shared.checkPendingInvitations(forEmail: email)
        async let sentTask = FirestoreManager.shared.fetchSentCoachInvitations(forCoachID: coachID)

        let receivedResult: Result<[CoachInvitation], Error>
        do { receivedResult = .success(try await receivedTask) }
        catch { receivedResult = .failure(error) }

        let sentResult: Result<[CoachToAthleteInvitation], Error>
        do { sentResult = .success(try await sentTask) }
        catch { sentResult = .failure(error) }

        var errors: [String] = []
        switch receivedResult {
        case .success(let received): invitations = received
        case .failure(let error): errors.append("received: \(error.localizedDescription)")
        }
        switch sentResult {
        case .success(let sent): sentInvitations = sent
        case .failure(let error): errors.append("sent: \(error.localizedDescription)")
        }

        if !errors.isEmpty {
            errorMessage = "Failed to load some invitations (\(errors.joined(separator: ", ")))"
        }

        isLoading = false
    }

    func acceptInvitation(_ invitation: CoachInvitation, authManager: ComprehensiveAuthManager? = nil) async {
        do {
            try await SharedFolderManager.shared.acceptInvitation(invitation, authManager: authManager)

            // Parity with AthleteInvitationManager: clear the coach's own
            // "invitation_received" activity notification so the bell/badge
            // updates immediately without waiting for the coach to open the
            // notifications list.
            await markInvitationNotificationRead(invitation)

            if let email = lastCoachEmail, let coachID = lastCoachID {
                await loadInvitations(forCoachEmail: email, coachID: coachID)
            }
            Haptics.success()

        } catch SharedFolderError.coachAthleteLimitReached {
            limitReached = true
            ErrorHandlerService.shared.handle(SharedFolderError.coachAthleteLimitReached, context: "CoachInvitationsViewModel.acceptInvitation.limitReached", showAlert: false)
        } catch {
            errorMessage = invitationErrorMessage(error, action: "accept")
            ErrorHandlerService.shared.handle(error, context: "CoachInvitationsViewModel.acceptInvitation", showAlert: false)
        }
    }

    func declineInvitation(_ invitation: CoachInvitation) async {
        do {
            try await SharedFolderManager.shared.declineInvitation(invitation)

            await markInvitationNotificationRead(invitation)

            if let email = lastCoachEmail, let coachID = lastCoachID {
                await loadInvitations(forCoachEmail: email, coachID: coachID)
            }
            Haptics.light()

        } catch {
            errorMessage = invitationErrorMessage(error, action: "decline")
            ErrorHandlerService.shared.handle(error, context: "CoachInvitationsViewModel.declineInvitation", showAlert: false)
        }
    }

    private func markInvitationNotificationRead(_ invitation: CoachInvitation) async {
        guard let invitationID = invitation.id,
              let uid = Auth.auth().currentUser?.uid else { return }
        await ActivityNotificationService.shared.markInvitationRead(
            invitationID: invitationID,
            forUserID: uid
        )
    }

    func cancelInvitation(_ invitation: CoachToAthleteInvitation) async {
        guard let invitationID = invitation.id else { return }
        do {
            try await FirestoreManager.shared.cancelInvitation(invitationID: invitationID)
            sentInvitations.removeAll { $0.id == invitationID }
            Haptics.success()
        } catch {
            errorMessage = invitationErrorMessage(error, action: "cancel")
            ErrorHandlerService.shared.handle(error, context: "CoachInvitationsViewModel.cancelInvitation", showAlert: false)
        }
    }

    private func invitationErrorMessage(_ error: Error, action: String) -> String {
        let nsError = error as NSError
        switch nsError.code {
        case InvitationErrorCode.expired.rawValue:
            return "This invitation has expired."
        case InvitationErrorCode.alreadyProcessed.rawValue:
            return "This invitation has already been processed."
        default:
            if nsError.localizedDescription.contains("Network") {
                return "Network error. Please check your connection and try again."
            }
            return "Failed to \(action) invitation: \(error.localizedDescription)"
        }
    }
}
