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

    private var invitationsListener: ListenerRegistration?

    private init() {}

    // MARK: - Result Type

    struct AcceptanceResult {
        let coachName: String
        let gamesFolderID: String?
        let lessonsFolderID: String?
    }

    // MARK: - Real-Time Listener

    func startInvitationsListener(forAthleteEmail email: String) {
        guard invitationsListener == nil else { return }
        let db = FirestoreManager.shared.db
        invitationsListener = db.collection(FC.invitations)
            .whereField("type", isEqualTo: "coach_to_athlete")
            .whereField("athleteEmail", isEqualTo: email.lowercased())
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
                let invitations = snapshot?.documents.compactMap { doc -> CoachToAthleteInvitation? in
                    do {
                        var inv = try doc.data(as: CoachToAthleteInvitation.self)
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
                }
            }
    }

    func stopInvitationsListener() {
        invitationsListener?.remove()
        invitationsListener = nil
        listenerError = nil
        pendingInvitations = []
    }

    // MARK: - Fetch (one-shot fallback)

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
    /// which creates shared folders server-side (any athlete tier). Then creates/updates
    /// the local Coach record in SwiftData and notifies the coach.
    func acceptInvitation(
        _ invitation: CoachToAthleteInvitation,
        userID: String,
        modelContext: ModelContext
    ) async throws -> AcceptanceResult {
        guard let invitationID = invitation.id else {
            throw NSError(domain: "PlayerPath", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid invitation"])
        }

        // 1. Find the local athlete for this user
        let athleteDescriptor = FetchDescriptor<Athlete>(
            predicate: #Predicate { $0.user?.firebaseAuthUid == userID }
        )
        let athlete = (try? modelContext.fetch(athleteDescriptor))?.first
        let athleteName = athlete?.name ?? Auth.auth().currentUser?.displayName ?? "Athlete"

        // 2. Accept invitation + create folders server-side via Cloud Function.
        //    Folders are created regardless of athlete subscription tier (Admin SDK
        //    bypasses security rules). Coach athlete limit is enforced server-side.
        let (gamesFolderID, lessonsFolderID) = try await FirestoreManager.shared.acceptCoachToAthleteInvitation(
            invitationID: invitationID,
            athleteUserID: userID,
            athleteName: athleteName
        )

        // 3. Create or update Coach record in SwiftData
        let coachID = invitation.coachID
        let coachEmail = invitation.coachEmail
        let existingCoachDescriptor = FetchDescriptor<Coach>(
            predicate: #Predicate<Coach> { coach in
                coach.firebaseCoachID == coachID || coach.email == coachEmail
            }
        )
        let existingCoaches = (try? modelContext.fetch(existingCoachDescriptor)) ?? []
        let existingCoach = existingCoaches.first { $0.athlete == athlete }

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
        default:
            return "Failed to \(action) invitation: \(error.localizedDescription)"
        }
    }
}
