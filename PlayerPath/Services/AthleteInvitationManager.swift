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
import os

private let invitationLog = Logger(subsystem: "com.playerpath.app", category: "AthleteInvitations")

@MainActor
class AthleteInvitationManager {
    static let shared = AthleteInvitationManager()

    private init() {}

    // MARK: - Result Type

    enum AcceptanceResult {
        case acceptedWithFolder(coachName: String)
        case acceptedWithoutFolder(coachName: String)
    }

    // MARK: - Fetch

    func fetchPendingInvitations(forEmail email: String) async -> [CoachToAthleteInvitation] {
        do {
            return try await FirestoreManager.shared.fetchPendingCoachInvitations(forAthleteEmail: email)
        } catch {
            invitationLog.error("Failed to fetch pending invitations: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Accept

    /// Accepts a coach-to-athlete invitation: updates Firestore, creates/updates local Coach record,
    /// optionally creates a shared folder (Pro tier), and notifies the coach.
    ///
    /// - Returns: `.acceptedWithFolder` or `.acceptedWithoutFolder` on success
    /// - Throws: On Firestore transaction failure (expired, already processed, network error)
    func acceptInvitation(
        _ invitation: CoachToAthleteInvitation,
        userID: String,
        modelContext: ModelContext,
        authManager: ComprehensiveAuthManager
    ) async throws -> AcceptanceResult {
        guard let invitationID = invitation.id else {
            throw NSError(domain: "PlayerPath", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid invitation"])
        }

        // 1. Update invitation status in Firestore (idempotent, point of no return)
        // Note: Coach athlete limit enforcement is handled server-side by the
        // enforceCoachAthleteLimitOnAccept Cloud Function.
        try await FirestoreManager.shared.acceptCoachToAthleteInvitation(
            invitationID: invitationID,
            athleteUserID: userID
        )

        // 2. Find the local athlete for this user
        let athleteDescriptor = FetchDescriptor<Athlete>(
            predicate: #Predicate { $0.user?.firebaseAuthUid == userID }
        )
        let athlete = (try? modelContext.fetch(athleteDescriptor))?.first
        let athleteName = athlete?.name ?? authManager.currentFirebaseUser?.displayName ?? "Athlete"

        // 3. Auto-create shared folder if athlete has Pro tier
        var folderID: String?
        var folderName: String?
        if authManager.hasCoachingAccess {
            do {
                let name = "\(athleteName)'s Videos"
                let permissions: [String: FolderPermissions] = [invitation.coachID: .default]

                let id = try await FirestoreManager.shared.createSharedFolder(
                    name: name,
                    ownerAthleteID: userID,
                    ownerAthleteName: athleteName,
                    permissions: permissions
                )
                folderID = id
                folderName = name

                try await FirestoreManager.shared.updateCoachToAthleteInvitationWithFolder(
                    invitationID: invitationID,
                    folderID: id,
                    folderName: name
                )
            } catch {
                // Folder creation failed — continue without folder. Coach still gets notified.
                ErrorHandlerService.shared.handle(error, context: "AthleteInvitationManager.createSharedFolder", showAlert: false)
            }
        }

        // 4. Create or update Coach record in SwiftData
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
            if let folderID, !existingCoach.sharedFolderIDs.contains(folderID) {
                existingCoach.sharedFolderIDs.append(folderID)
            }
        } else {
            let coach = Coach(name: invitation.coachName, email: invitation.coachEmail)
            coach.needsSync = true
            coach.invitationAcceptedAt = Date()
            coach.firebaseCoachID = invitation.coachID
            coach.lastInvitationStatus = "accepted"
            if let folderID {
                coach.sharedFolderIDs = [folderID]
            }
            if let athlete {
                coach.athlete = athlete
            }
            modelContext.insert(coach)
        }

        // 5. Save SwiftData context
        do {
            try modelContext.save()
        } catch {
            ErrorHandlerService.shared.handle(error, context: "AthleteInvitationManager.saveCoachRecord", showAlert: false)
        }

        // 6. Notify the coach
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

        if folderID != nil {
            return .acceptedWithFolder(coachName: invitation.coachName)
        } else {
            return .acceptedWithoutFolder(coachName: invitation.coachName)
        }
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
