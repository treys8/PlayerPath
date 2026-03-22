//
//  FirestoreManager+Invitations.swift
//  PlayerPath
//
//  Invitation operations for FirestoreManager
//

import Foundation
import FirebaseFirestore
import FirebaseFunctions
import os

private let invitationLog = Logger(subsystem: "com.playerpath.app", category: "Invitations")

/// Invitation-specific error codes for distinguishing failure reasons
enum InvitationErrorCode: Int {
    case invalidInvitation = -1
    case duplicateInvitation = -2
    case alreadyProcessed = -3
    case selfInvitation = -4
    case expired = -5
}

/// Expiration constant for invitations (30 days)
private let invitationExpirationInterval: TimeInterval = 30 * 24 * 60 * 60

extension FirestoreManager {

    // MARK: - Invitations

    /// Creates an invitation for a coach to join a shared folder
    func createInvitation(
        athleteID: String,
        athleteName: String,
        coachEmail: String,
        folderID: String,
        folderName: String,
        permissions: FolderPermissions = .default
    ) async throws -> String {

        let invitationData: [String: Any] = [
            "type": "athlete_to_coach",
            "athleteID": athleteID,
            "athleteName": athleteName,
            "coachEmail": coachEmail.lowercased(),
            "folderID": folderID,
            "folderName": folderName,
            "permissions": permissions.toDictionary(),
            "status": "pending",
            "sentAt": FieldValue.serverTimestamp(),
            "expiresAt": Date().addingTimeInterval(invitationExpirationInterval)
        ]

        do {
            let docRef = try await db.collection(FC.invitations).addDocument(data: invitationData)
            invitationLog.info("Created athlete-to-coach invitation \(docRef.documentID) for coach \(coachEmail)")
            return docRef.documentID
        } catch {
            invitationLog.error("Failed to create athlete-to-coach invitation: \(error.localizedDescription)")
            errorMessage = "Failed to send invitation."
            throw error
        }
    }

    /// Checks if the current athlete already has a pending or accepted athlete-to-coach invitation
    func hasPendingInvitation(athleteID: String, coachEmail: String) async throws -> Bool {
        // Check for accepted invitation (already connected)
        let acceptedSnapshot = try await db.collection(FC.invitations)
            .whereField("athleteID", isEqualTo: athleteID)
            .whereField("coachEmail", isEqualTo: coachEmail.lowercased())
            .whereField("status", isEqualTo: "accepted")
            .whereField("type", isEqualTo: "athlete_to_coach")
            .limit(to: 1)
            .getDocuments()
        if !acceptedSnapshot.documents.isEmpty { return true }

        // Check for pending non-expired invitation
        let pendingSnapshot = try await db.collection(FC.invitations)
            .whereField("athleteID", isEqualTo: athleteID)
            .whereField("coachEmail", isEqualTo: coachEmail.lowercased())
            .whereField("status", isEqualTo: "pending")
            .whereField("type", isEqualTo: "athlete_to_coach")
            .whereField("expiresAt", isGreaterThan: Timestamp(date: Date()))
            .limit(to: 1)
            .getDocuments()
        return !pendingSnapshot.documents.isEmpty
    }

    /// Fetches pending invitations for a coach (by email)
    func fetchPendingInvitations(forEmail email: String) async throws -> [CoachInvitation] {
        do {
            let snapshot = try await db.collection(FC.invitations)
                .whereField("coachEmail", isEqualTo: email.lowercased())
                .whereField("status", isEqualTo: "pending")
                .whereField("expiresAt", isGreaterThan: Timestamp(date: Date()))
                .limit(to: 100)
                .getDocuments()

            let invitations = snapshot.documents.compactMap { doc -> CoachInvitation? in
                do {
                    var invitation = try doc.data(as: CoachInvitation.self)
                    invitation.id = doc.documentID
                    return invitation
                } catch {
                    firestoreLog.warning("Failed to decode CoachInvitation from doc \(doc.documentID): \(error.localizedDescription)")
                    return nil
                }
            }

            return invitations
        } catch {
            throw error
        }
    }

    /// Fetches invitations sent by a specific athlete to check their current status.
    /// Used by the athlete's CoachesView to detect when a coach has accepted/declined.
    func fetchInvitations(forAthleteID athleteID: String) async throws -> [CoachInvitation] {
        let snapshot = try await db.collection(FC.invitations)
            .whereField("athleteID", isEqualTo: athleteID)
            .limit(to: 100)
            .getDocuments()

        return snapshot.documents.compactMap { doc -> CoachInvitation? in
            do {
                var invitation = try doc.data(as: CoachInvitation.self)
                invitation.id = doc.documentID
                return invitation
            } catch {
                invitationLog.warning("Failed to decode CoachInvitation from doc \(doc.documentID): \(error.localizedDescription)")
                return nil
            }
        }
    }

    /// Accepts an athlete-to-coach invitation via server-side Cloud Function.
    /// The server reads permissions from the invitation document to prevent
    /// client-side privilege escalation.
    func acceptInvitation(
        invitationID: String,
        coachID: String,
        permissions: FolderPermissions // kept for API compat; server reads from invitation
    ) async throws {

        do {
            let callable = Functions.functions().httpsCallable("acceptAthleteToCoachInvitation")
            let result = try await callable.call(["invitationID": invitationID])

            guard let data = result.data as? [String: Any],
                  data["success"] as? Bool == true else {
                throw NSError(domain: "FirestoreManager", code: InvitationErrorCode.invalidInvitation.rawValue,
                              userInfo: [NSLocalizedDescriptionKey: "Unexpected response from server."])
            }
            invitationLog.info("Accepted invitation \(invitationID) via Cloud Function")

        } catch let error as NSError {
            // Map Cloud Function error codes to InvitationErrorCode for consistent client handling
            if error.domain == FunctionsErrorDomain {
                let code = FunctionsErrorCode(rawValue: error.code)
                switch code {
                case .notFound:
                    throw NSError(domain: "FirestoreManager", code: InvitationErrorCode.invalidInvitation.rawValue,
                                  userInfo: [NSLocalizedDescriptionKey: error.localizedDescription])
                case .failedPrecondition:
                    // Covers expired and already-processed
                    let msg = error.localizedDescription
                    let errorCode = msg.contains("expired") ? InvitationErrorCode.expired : InvitationErrorCode.alreadyProcessed
                    throw NSError(domain: "FirestoreManager", code: errorCode.rawValue,
                                  userInfo: [NSLocalizedDescriptionKey: msg])
                case .permissionDenied:
                    throw NSError(domain: "FirestoreManager", code: InvitationErrorCode.invalidInvitation.rawValue,
                                  userInfo: [NSLocalizedDescriptionKey: error.localizedDescription])
                default:
                    break
                }
            }
            invitationLog.error("Failed to accept invitation \(invitationID): \(error.localizedDescription)")
            errorMessage = "Failed to accept invitation."
            throw error
        }
    }

    /// Declines an invitation (only if still pending).
    /// Uses a Firestore transaction so the status check and update are atomic.
    func declineInvitation(invitationID: String) async throws {
        let invitationRef = db.collection(FC.invitations).document(invitationID)

        do {
            _ = try await db.runTransaction({ (transaction, errorPointer) -> Any? in
                let snapshot: DocumentSnapshot
                do {
                    snapshot = try transaction.getDocument(invitationRef)
                } catch let fetchError as NSError {
                    errorPointer?.pointee = fetchError
                    return nil
                }

                let data = snapshot.data()

                // Check expiration
                if let expiresAt = (data?["expiresAt"] as? Timestamp)?.dateValue(),
                   expiresAt < Date() {
                    let error = NSError(domain: "FirestoreManager", code: InvitationErrorCode.expired.rawValue,
                                        userInfo: [NSLocalizedDescriptionKey: "This invitation has expired."])
                    errorPointer?.pointee = error
                    return nil
                }

                guard data?["status"] as? String == "pending" else {
                    let error = NSError(domain: "FirestoreManager", code: InvitationErrorCode.alreadyProcessed.rawValue,
                                        userInfo: [NSLocalizedDescriptionKey: "This invitation has already been processed."])
                    errorPointer?.pointee = error
                    return nil
                }

                transaction.updateData([
                    "status": "declined",
                    "declinedAt": FieldValue.serverTimestamp()
                ], forDocument: invitationRef)

                return nil
            })
            invitationLog.info("Declined invitation \(invitationID)")
        } catch {
            invitationLog.error("Failed to decline invitation \(invitationID): \(error.localizedDescription)")
            errorMessage = "Failed to decline invitation."
            throw error
        }
    }

    /// Creates an invitation from a coach to an athlete (coach-initiated)
    /// This is for when coaches want to proactively invite athletes to connect
    @discardableResult
    func createCoachToAthleteInvitation(
        coachID: String,
        coachEmail: String,
        coachName: String,
        athleteEmail: String,
        athleteName: String,
        message: String?
    ) async throws -> String {

        // Check for existing accepted invitation (already connected)
        let acceptedSnapshot = try await db.collection(FC.invitations)
            .whereField("type", isEqualTo: "coach_to_athlete")
            .whereField("coachID", isEqualTo: coachID)
            .whereField("athleteEmail", isEqualTo: athleteEmail.lowercased())
            .whereField("status", isEqualTo: "accepted")
            .limit(to: 1)
            .getDocuments()

        if !acceptedSnapshot.documents.isEmpty {
            throw NSError(domain: "FirestoreManager", code: InvitationErrorCode.duplicateInvitation.rawValue, userInfo: [
                NSLocalizedDescriptionKey: "You are already connected with this athlete."
            ])
        }

        // Check for existing pending invitation to same athlete from this coach
        let pendingSnapshot = try await db.collection(FC.invitations)
            .whereField("type", isEqualTo: "coach_to_athlete")
            .whereField("coachID", isEqualTo: coachID)
            .whereField("athleteEmail", isEqualTo: athleteEmail.lowercased())
            .whereField("status", isEqualTo: "pending")
            .limit(to: 1)
            .getDocuments()

        if !pendingSnapshot.documents.isEmpty {
            throw NSError(domain: "FirestoreManager", code: InvitationErrorCode.duplicateInvitation.rawValue, userInfo: [
                NSLocalizedDescriptionKey: "An invitation has already been sent to this email address."
            ])
        }

        var invitationData: [String: Any] = [
            "type": "coach_to_athlete",
            "coachID": coachID,
            "coachEmail": coachEmail.lowercased(),
            "coachName": coachName,
            "athleteEmail": athleteEmail.lowercased(),
            "athleteName": athleteName,
            "status": "pending",
            "sentAt": FieldValue.serverTimestamp(),
            "expiresAt": Date().addingTimeInterval(invitationExpirationInterval)
        ]

        if let message = message {
            invitationData["message"] = message
        }

        do {
            let docRef = try await db.collection(FC.invitations).addDocument(data: invitationData)
            invitationLog.info("Created coach-to-athlete invitation \(docRef.documentID) for athlete \(athleteEmail)")
            return docRef.documentID
        } catch {
            invitationLog.error("Failed to create coach-to-athlete invitation: \(error.localizedDescription)")
            errorMessage = "Failed to send invitation."
            throw error
        }
    }

    /// Fetches pending invitations from coaches for an athlete (by email)
    func fetchPendingCoachInvitations(forAthleteEmail email: String) async throws -> [CoachToAthleteInvitation] {
        do {
            let snapshot = try await db.collection(FC.invitations)
                .whereField("type", isEqualTo: "coach_to_athlete")
                .whereField("athleteEmail", isEqualTo: email.lowercased())
                .whereField("status", isEqualTo: "pending")
                .whereField("expiresAt", isGreaterThan: Timestamp(date: Date()))
                .limit(to: 100)
                .getDocuments()

            let invitations = snapshot.documents.compactMap { doc -> CoachToAthleteInvitation? in
                do {
                    var invitation = try doc.data(as: CoachToAthleteInvitation.self)
                    invitation.id = doc.documentID
                    return invitation
                } catch {
                    firestoreLog.warning("Failed to decode CoachToAthleteInvitation from doc \(doc.documentID): \(error.localizedDescription)")
                    return nil
                }
            }

            return invitations
        } catch {
            throw error
        }
    }

    /// Accepts a coach-to-athlete invitation via Cloud Function (server-side validation).
    /// Validates caller identity, invitation state, expiration, and coach athlete limit.
    func acceptCoachToAthleteInvitation(invitationID: String, athleteUserID: String) async throws {
        let functions = Functions.functions()
        do {
            _ = try await functions.httpsCallable("acceptCoachToAthleteInvitation").call(["invitationID": invitationID])
            invitationLog.info("Accepted coach-to-athlete invitation \(invitationID) via Cloud Function")
        } catch {
            let nsError = error as NSError
            // Map Cloud Function error codes to invitation error codes for consistent UI handling
            if nsError.domain == FunctionsErrorDomain {
                let code = FunctionsErrorCode(rawValue: nsError.code)
                switch code {
                case .resourceExhausted:
                    throw SharedFolderError.coachAthleteLimitReached
                case .failedPrecondition:
                    let message = nsError.localizedDescription
                    if message.contains("expired") {
                        throw NSError(domain: "FirestoreManager", code: InvitationErrorCode.expired.rawValue,
                                      userInfo: [NSLocalizedDescriptionKey: message])
                    } else {
                        throw NSError(domain: "FirestoreManager", code: InvitationErrorCode.alreadyProcessed.rawValue,
                                      userInfo: [NSLocalizedDescriptionKey: message])
                    }
                default:
                    throw error
                }
            }
            throw error
        }
    }

    /// Declines a coach-to-athlete invitation (only if still pending).
    /// Uses a Firestore transaction so the status check and update are atomic.
    func declineCoachToAthleteInvitation(invitationID: String) async throws {
        let invitationRef = db.collection(FC.invitations).document(invitationID)

        _ = try await db.runTransaction({ (transaction, errorPointer) -> Any? in
            let snapshot: DocumentSnapshot
            do {
                snapshot = try transaction.getDocument(invitationRef)
            } catch let fetchError as NSError {
                errorPointer?.pointee = fetchError
                return nil
            }

            let data = snapshot.data()

            if let expiresAt = (data?["expiresAt"] as? Timestamp)?.dateValue(),
               expiresAt < Date() {
                let error = NSError(domain: "FirestoreManager", code: InvitationErrorCode.expired.rawValue,
                                    userInfo: [NSLocalizedDescriptionKey: "This invitation has expired."])
                errorPointer?.pointee = error
                return nil
            }

            guard data?["status"] as? String == "pending" else {
                let error = NSError(domain: "FirestoreManager", code: InvitationErrorCode.alreadyProcessed.rawValue,
                                    userInfo: [NSLocalizedDescriptionKey: "This invitation has already been processed."])
                errorPointer?.pointee = error
                return nil
            }

            transaction.updateData([
                "status": "declined",
                "declinedAt": FieldValue.serverTimestamp()
            ], forDocument: invitationRef)

            return nil
        })
        invitationLog.info("Declined coach-to-athlete invitation \(invitationID)")
    }

    /// Cancels a pending invitation (sender only).
    /// Uses a Firestore transaction so the status check and update are atomic.
    func cancelInvitation(invitationID: String) async throws {
        let invitationRef = db.collection(FC.invitations).document(invitationID)

        _ = try await db.runTransaction({ (transaction, errorPointer) -> Any? in
            let snapshot: DocumentSnapshot
            do {
                snapshot = try transaction.getDocument(invitationRef)
            } catch let fetchError as NSError {
                errorPointer?.pointee = fetchError
                return nil
            }

            guard snapshot.data()?["status"] as? String == "pending" else {
                let error = NSError(domain: "FirestoreManager", code: InvitationErrorCode.alreadyProcessed.rawValue,
                                    userInfo: [NSLocalizedDescriptionKey: "This invitation has already been processed and cannot be cancelled."])
                errorPointer?.pointee = error
                return nil
            }

            transaction.updateData([
                "status": "cancelled",
                "cancelledAt": FieldValue.serverTimestamp()
            ], forDocument: invitationRef)

            return nil
        })
        invitationLog.info("Cancelled invitation \(invitationID)")
    }

    /// Fetches invitations sent by a coach to athletes (coach-initiated)
    func fetchSentCoachInvitations(forCoachID coachID: String) async throws -> [CoachToAthleteInvitation] {
        let snapshot = try await db.collection(FC.invitations)
            .whereField("type", isEqualTo: "coach_to_athlete")
            .whereField("coachID", isEqualTo: coachID)
            .order(by: "sentAt", descending: true)
            .limit(to: 100)
            .getDocuments()

        return snapshot.documents.compactMap { doc -> CoachToAthleteInvitation? in
            do {
                var invitation = try doc.data(as: CoachToAthleteInvitation.self)
                invitation.id = doc.documentID
                return invitation
            } catch {
                firestoreLog.warning("Failed to decode sent CoachToAthleteInvitation from doc \(doc.documentID): \(error.localizedDescription)")
                return nil
            }
        }
    }

    /// Updates a coach-to-athlete invitation with the folder created on acceptance
    func updateCoachToAthleteInvitationWithFolder(
        invitationID: String,
        folderID: String,
        folderName: String
    ) async throws {
        try await db.collection(FC.invitations).document(invitationID).updateData([
            "folderID": folderID,
            "folderName": folderName
        ])
    }

    /// Returns athlete user IDs from accepted coach-to-athlete invitations for a given coach.
    /// Used to count connected athletes for limit enforcement.
    func fetchAcceptedCoachToAthleteAthleteIDs(coachID: String) async throws -> Set<String> {
        let snapshot = try await db.collection(FC.invitations)
            .whereField("type", isEqualTo: "coach_to_athlete")
            .whereField("coachID", isEqualTo: coachID)
            .whereField("status", isEqualTo: "accepted")
            .getDocuments()
        var ids = Set<String>()
        for doc in snapshot.documents {
            if let athleteUID = doc.data()["athleteUserID"] as? String, !athleteUID.isEmpty {
                ids.insert(athleteUID)
            }
        }
        return ids
    }

    /// Counts pending outbound coach-to-athlete invitations for a given coach.
    func countPendingCoachToAthleteInvitations(coachID: String) async throws -> Int {
        let snapshot = try await db.collection(FC.invitations)
            .whereField("type", isEqualTo: "coach_to_athlete")
            .whereField("coachID", isEqualTo: coachID)
            .whereField("status", isEqualTo: "pending")
            .getDocuments()
        return snapshot.documents.count
    }
}
