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

    enum AcceptanceResult {
        case acceptedWithFolder(coachName: String)
        case acceptedWithoutFolder(coachName: String)
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

        // 1. Find the local athlete for this user
        let athleteDescriptor = FetchDescriptor<Athlete>(
            predicate: #Predicate { $0.user?.firebaseAuthUid == userID }
        )
        let athlete = (try? modelContext.fetch(athleteDescriptor))?.first
        let athleteName = athlete?.name ?? authManager.currentFirebaseUser?.displayName ?? "Athlete"

        // 2. Pre-check: verify the coach is not at their athlete limit
        do {
            let coachProfile = try await FirestoreManager.shared.fetchUserProfile(userID: invitation.coachID)
            let coachTier = CoachSubscriptionTier(rawValue: coachProfile?.coachSubscriptionTier ?? "coach_free") ?? .free
            let connectedCount = await SubscriptionGate.fullConnectedAthleteCount(coachID: invitation.coachID)
            if connectedCount >= coachTier.athleteLimit {
                throw SharedFolderError.coachAthleteLimitReached
            }
        } catch let error as SharedFolderError where error == .coachAthleteLimitReached {
            throw error
        } catch {
            // Non-limit errors (network, etc.) — log and continue, let the Cloud Function backstop handle it
            ErrorHandlerService.shared.handle(error, context: "AthleteInvitationManager.coachLimitPreCheck", showAlert: false)
        }

        // 3. Accept invitation in Firestore (do this BEFORE creating folders to avoid orphans)
        try await FirestoreManager.shared.acceptCoachToAthleteInvitation(
            invitationID: invitationID,
            athleteUserID: userID
        )

        // 4. Create shared folders AFTER acceptance succeeds
        //    Two folders: Games (athlete uploads game clips) + Lessons (coach uploads instruction clips)
        var gamesFolderID: String?
        var lessonsFolderID: String?
        var gamesFolderName: String?
        var lessonsFolderName: String?
        if authManager.hasCoachingAccess {
            let permissions: [String: FolderPermissions] = [invitation.coachID: .default]

            // Games folder
            do {
                let name = "\(athleteName)'s Games"
                let id = try await FirestoreManager.shared.createSharedFolder(
                    name: name,
                    ownerAthleteID: userID,
                    ownerAthleteName: athleteName,
                    permissions: permissions,
                    folderType: "games"
                )
                gamesFolderID = id
                gamesFolderName = name
            } catch {
                ErrorHandlerService.shared.handle(error, context: "AthleteInvitationManager.createGamesFolder", showAlert: false)
            }

            // Lessons folder
            do {
                let name = "\(athleteName)'s Lessons"
                let id = try await FirestoreManager.shared.createSharedFolder(
                    name: name,
                    ownerAthleteID: userID,
                    ownerAthleteName: athleteName,
                    permissions: permissions,
                    folderType: "lessons"
                )
                lessonsFolderID = id
                lessonsFolderName = name
            } catch {
                ErrorHandlerService.shared.handle(error, context: "AthleteInvitationManager.createLessonsFolder", showAlert: false)
            }
        }

        // Update invitation with folder info if folder was created
        let folderID = gamesFolderID ?? lessonsFolderID
        let folderName = gamesFolderName ?? lessonsFolderName
        let createdAnyFolder = gamesFolderID != nil || lessonsFolderID != nil

        if let folderID, let folderName {
            do {
                try await FirestoreManager.shared.updateCoachToAthleteInvitationWithFolder(
                    invitationID: invitationID,
                    folderID: folderID,
                    folderName: folderName
                )
            } catch {
                // Non-fatal: invitation is accepted, folder exists, just the link is missing
                ErrorHandlerService.shared.handle(error, context: "AthleteInvitationManager.updateInvitationWithFolder", showAlert: false)
            }
        }

        // 5. Create or update Coach record in SwiftData
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

        // 6. Save SwiftData context
        ErrorHandlerService.shared.saveContext(modelContext, caller: "AthleteInvitationManager.acceptInvitation")

        // 7. Notify the coach
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

        if createdAnyFolder {
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
