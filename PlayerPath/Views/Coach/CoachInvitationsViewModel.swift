//
//  CoachInvitationsViewModel.swift
//  PlayerPath
//
//  ViewModel for CoachInvitationsView — loads, accepts, declines,
//  and cancels invitations.
//

import Foundation
import Combine

@MainActor
class CoachInvitationsViewModel: ObservableObject {
    @Published var invitations: [CoachInvitation] = []
    @Published var sentInvitations: [CoachToAthleteInvitation] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var limitReached = false
    @Published var isAtAthleteLimit: Bool = false

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

    func updateAthleteLimit(authManager: ComprehensiveAuthManager) {
        var connectedAthleteIDs = Set(SharedFolderManager.shared.coachFolders.map { $0.ownerAthleteID })
        for invitation in acceptedSentInvitations {
            if let athleteUID = invitation.athleteUserID, !athleteUID.isEmpty {
                connectedAthleteIDs.insert(athleteUID)
            }
        }
        let pendingCoachToAthleteCount = pendingSentInvitations.count
        isAtAthleteLimit = connectedAthleteIDs.count + pendingCoachToAthleteCount >= authManager.coachAthleteLimit
    }

    func loadInvitations(forCoachEmail email: String, coachID: String) async {
        lastCoachEmail = email
        lastCoachID = coachID
        isLoading = true
        errorMessage = nil

        async let receivedTask: Result<[CoachInvitation], Error> = {
            do { return .success(try await SharedFolderManager.shared.checkPendingInvitations(forEmail: email)) }
            catch { return .failure(error) }
        }()
        async let sentTask: Result<[CoachToAthleteInvitation], Error> = {
            do { return .success(try await FirestoreManager.shared.fetchSentCoachInvitations(forCoachID: coachID)) }
            catch { return .failure(error) }
        }()

        let (receivedResult, sentResult) = await (receivedTask, sentTask)

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

            if let email = lastCoachEmail, let coachID = lastCoachID {
                await loadInvitations(forCoachEmail: email, coachID: coachID)
            }
            Haptics.success()

        } catch {
            errorMessage = invitationErrorMessage(error, action: "decline")
            ErrorHandlerService.shared.handle(error, context: "CoachInvitationsViewModel.declineInvitation", showAlert: false)
        }
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
