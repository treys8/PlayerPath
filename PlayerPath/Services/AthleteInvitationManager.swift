//
//  AthleteInvitationManager.swift
//  PlayerPath
//
//  Manages athlete-side invitation acceptance/decline flow.
//  Extracted from AthleteInvitationsBanner to separate business logic from views.
//

import Foundation
import SwiftData
import FirebaseAuth
import FirebaseFirestore
import os

private let invitationLog = Logger(subsystem: "com.playerpath.app", category: "AthleteInvitations")

@MainActor
@Observable
class AthleteInvitationManager {
    static let shared = AthleteInvitationManager()

    var pendingInvitations: [CoachToAthleteInvitation] = []
    var pendingCount: Int { pendingInvitations.count }
    var listenerError: String?

    private var listener: ListenerRegistration?
    private var listeningEmail: String?

    private init() {}

    // MARK: - Listener

    /// Starts a real-time listener for pending coach-to-athlete invitations for `email`.
    /// Idempotent: restarts if the email changes, no-op if already listening to the same email.
    func startListening(forEmail email: String) {
        let normalized = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        if listener != nil, listeningEmail == normalized { return }
        stopListening()
        listeningEmail = normalized
        listener = FirestoreManager.shared.listenPendingCoachInvitations(forAthleteEmail: normalized) { [weak self] invitations in
            guard let self else { return }
            self.pendingInvitations = invitations
        }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
        listeningEmail = nil
    }

    // MARK: - Result Type

    struct AcceptanceResult {
        let coachName: String
        let gamesFolderID: String?
        let lessonsFolderID: String?
    }

    // MARK: - Fetch

    func fetchPendingInvitations(forEmail email: String) async -> [CoachToAthleteInvitation] {
        do {
            let invitations = try await FirestoreManager.shared.fetchPendingCoachInvitations(forAthleteEmail: email)
            pendingInvitations = invitations
            return invitations
        } catch {
            invitationLog.error("Failed to fetch pending invitations: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Accept

    /// Accepts a coach-to-athlete invitation: validates and accepts via Cloud Function,
    /// which creates shared folders server-side (requires Pro tier). Then creates/updates
    /// the local Coach record in SwiftData and notifies the coach.
    func acceptInvitation(
        _ invitation: CoachToAthleteInvitation,
        userID: String,
        targetAthlete: Athlete? = nil,
        modelContext: ModelContext
    ) async throws -> AcceptanceResult {
        guard let invitationID = invitation.id else {
            throw NSError(domain: "PlayerPath", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid invitation"])
        }

        // 1. Resolve the athlete this invitation is for.
        // Prefer the caller-specified target (from the athlete-picker sheet on multi-athlete accounts).
        // Falls back to the first athlete on the user for single-athlete accounts.
        let optionalUserID: String? = userID
        let athleteDescriptor = FetchDescriptor<Athlete>(
            predicate: #Predicate { $0.user?.firebaseAuthUid == optionalUserID }
        )
        let fetched = (try? modelContext.fetch(athleteDescriptor)) ?? []
        let athlete = targetAthlete ?? fetched.first
        let athleteName = athlete?.name ?? Auth.auth().currentUser?.displayName ?? "Athlete"
        let athleteUUID = athlete?.id.uuidString

        // 2. Accept invitation + create folders server-side via Cloud Function.
        //    Folders are created regardless of athlete subscription tier (Admin SDK
        //    bypasses security rules). Coach athlete limit is enforced server-side.
        let (gamesFolderID, lessonsFolderID) = try await FirestoreManager.shared.acceptCoachToAthleteInvitation(
            invitationID: invitationID,
            athleteUserID: userID,
            athleteName: athleteName,
            athleteUUID: athleteUUID
        )

        // 3. Create or update Coach record in SwiftData
        // Wrap in optionals so #Predicate compares String? == String? (not String? == String),
        // preventing a potential SwiftData EXC_BAD_ACCESS on entities with nil firebaseCoachID.
        let optionalCoachID: String? = invitation.coachID
        let coachEmail = invitation.coachEmail
        let existingCoachDescriptor = FetchDescriptor<Coach>(
            predicate: #Predicate<Coach> { coach in
                coach.firebaseCoachID == optionalCoachID || coach.email == coachEmail
            }
        )
        let existingCoaches = (try? modelContext.fetch(existingCoachDescriptor)) ?? []
        let existingCoach = existingCoaches.first { $0.athlete?.id == athlete?.id }

        if let existingCoach {
            existingCoach.name = invitation.coachName
            existingCoach.email = invitation.coachEmail
            existingCoach.firebaseCoachID = invitation.coachID
            existingCoach.lastInvitationStatus = "accepted"
            existingCoach.invitationAcceptedAt = Date()
            existingCoach.needsSync = true
            for id in [gamesFolderID, lessonsFolderID].compactMap({ $0 }) {
                if !existingCoach.sharedFolderIDs.contains(id) {
                    existingCoach.sharedFolderIDs.append(id)
                }
            }
        } else {
            let coach = Coach(name: invitation.coachName, email: invitation.coachEmail)
            coach.needsSync = true
            coach.invitationAcceptedAt = Date()
            coach.firebaseCoachID = invitation.coachID
            coach.lastInvitationStatus = "accepted"
            coach.sharedFolderIDs = [gamesFolderID, lessonsFolderID].compactMap { $0 }
            if let athlete {
                coach.athlete = athlete
            }
            modelContext.insert(coach)
        }

        // 4. Save SwiftData context
        ErrorHandlerService.shared.saveContext(modelContext, caller: "AthleteInvitationManager.acceptInvitation")

        // 5. Notify the coach
        let folderID = gamesFolderID ?? lessonsFolderID
        let folderName = gamesFolderID != nil ? "\(athleteName)'s Games" : lessonsFolderID != nil ? "\(athleteName)'s Lessons" : nil
        if let folderName, let folderID {
            await ActivityNotificationService.shared.postAthleteAcceptedInvitationNotification(
                folderName: folderName,
                folderID: folderID,
                athleteID: userID,
                athleteName: athleteName,
                coachUserID: invitation.coachID
            )
        } else {
            await ActivityNotificationService.shared.postConnectionAcceptedNotification(
                invitationID: invitationID,
                athleteID: userID,
                athleteName: athleteName,
                coachUserID: invitation.coachID
            )
        }

        // Optimistically drop from the local list so UI updates immediately; the
        // Firestore listener will converge (status transitions to accepted → query no
        // longer matches).
        pendingInvitations.removeAll { $0.id == invitationID }

        // Mark any "invitation_received" activity notification as read for this
        // invitation — accepting should clear the bell/banner without waiting for
        // the user to open the notification list.
        await ActivityNotificationService.shared.markInvitationRead(
            invitationID: invitationID,
            forUserID: userID
        )

        invitationLog.info("Accepted invitation \(invitationID) from coach \(invitation.coachName)")

        return AcceptanceResult(
            coachName: invitation.coachName,
            gamesFolderID: gamesFolderID,
            lessonsFolderID: lessonsFolderID
        )
    }

    // MARK: - Decline

    func declineInvitation(_ invitation: CoachToAthleteInvitation) async throws {
        guard let invitationID = invitation.id else { return }
        try await FirestoreManager.shared.declineCoachToAthleteInvitation(invitationID: invitationID)

        pendingInvitations.removeAll { $0.id == invitationID }

        if let uid = Auth.auth().currentUser?.uid {
            await ActivityNotificationService.shared.markInvitationRead(
                invitationID: invitationID,
                forUserID: uid
            )
        }

        invitationLog.info("Declined invitation \(invitationID) from coach \(invitation.coachName)")
    }

    // MARK: - Error Mapping

    static func errorMessage(for error: Error, action: String) -> String {
        let nsError = error as NSError
        switch nsError.code {
        case InvitationErrorCode.expired.rawValue:
            return "This invitation has expired. Ask your coach to send a new one."
        case InvitationErrorCode.alreadyProcessed.rawValue:
            return "This invitation has already been processed."
        case InvitationErrorCode.proRequired.rawValue:
            return "A Pro subscription is required to accept coach invitations. Upgrade to Pro to connect with your coach."
        default:
            return "Failed to \(action) invitation: \(error.localizedDescription)"
        }
    }
}
