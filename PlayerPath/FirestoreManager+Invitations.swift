//
//  FirestoreManager+Invitations.swift
//  PlayerPath
//
//  Invitation operations for FirestoreManager
//

import Foundation
import FirebaseFirestore
import os

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
            "athleteID": athleteID,
            "athleteName": athleteName,
            "coachEmail": coachEmail.lowercased(),
            "folderID": folderID,
            "folderName": folderName,
            "permissions": permissions.toDictionary(),
            "status": "pending",
            "sentAt": FieldValue.serverTimestamp(),
            "expiresAt": Date().addingTimeInterval(30 * 24 * 60 * 60) // 30 days
        ]

        do {
            let docRef = try await db.collection("invitations").addDocument(data: invitationData)
            return docRef.documentID
        } catch {
            errorMessage = "Failed to send invitation."
            throw error
        }
    }

    /// Fetches pending invitations for a coach (by email)
    func fetchPendingInvitations(forEmail email: String) async throws -> [CoachInvitation] {
        do {
            let snapshot = try await db.collection("invitations")
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

    /// Accepts an invitation and adds coach to folder atomically.
    /// Uses a Firestore transaction so folder update + invitation status update
    /// either both succeed or both roll back.
    func acceptInvitation(
        invitationID: String,
        coachID: String,
        permissions: FolderPermissions
    ) async throws {

        do {
            let invitationRef = db.collection("invitations").document(invitationID)

            _ = try await db.runTransaction({ (transaction, errorPointer) -> Any? in
                // 1. Read invitation inside transaction
                let invitationSnapshot: DocumentSnapshot
                do {
                    invitationSnapshot = try transaction.getDocument(invitationRef)
                } catch let fetchError as NSError {
                    errorPointer?.pointee = fetchError
                    return nil
                }

                guard let data = invitationSnapshot.data(),
                      let folderID = data["folderID"] as? String else {
                    let error = NSError(domain: "FirestoreManager", code: -1,
                                        userInfo: [NSLocalizedDescriptionKey: "Invalid invitation"])
                    errorPointer?.pointee = error
                    return nil
                }

                let folderRef = self.db.collection("sharedFolders").document(folderID)

                // 2. Write folder update (add coach + permissions)
                transaction.updateData([
                    "sharedWithCoachIDs": FieldValue.arrayUnion([coachID]),
                    "permissions.\(coachID)": permissions.toDictionary(),
                    "updatedAt": FieldValue.serverTimestamp()
                ], forDocument: folderRef)

                // 3. Write invitation status update
                transaction.updateData([
                    "status": "accepted",
                    "acceptedAt": FieldValue.serverTimestamp()
                ], forDocument: invitationRef)

                return nil
            })

        } catch {
            errorMessage = "Failed to accept invitation."
            throw error
        }
    }

    /// Declines an invitation
    func declineInvitation(invitationID: String) async throws {

        do {
            try await db.collection("invitations").document(invitationID).updateData([
                "status": "declined",
                "declinedAt": FieldValue.serverTimestamp()
            ])

        } catch {
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

        // Check for existing pending invitation to same athlete from this coach
        let existingSnapshot = try await db.collection("invitations")
            .whereField("type", isEqualTo: "coach_to_athlete")
            .whereField("coachID", isEqualTo: coachID)
            .whereField("athleteEmail", isEqualTo: athleteEmail.lowercased())
            .whereField("status", isEqualTo: "pending")
            .limit(to: 1)
            .getDocuments()

        if !existingSnapshot.documents.isEmpty {
            throw NSError(domain: "FirestoreManager", code: -2, userInfo: [
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
            "expiresAt": Date().addingTimeInterval(30 * 24 * 60 * 60) // 30 days
        ]

        if let message = message {
            invitationData["message"] = message
        }

        do {
            let docRef = try await db.collection("invitations").addDocument(data: invitationData)

            return docRef.documentID
        } catch {
            errorMessage = "Failed to send invitation."
            throw error
        }
    }

    /// Fetches pending invitations from coaches for an athlete (by email)
    func fetchPendingCoachInvitations(forAthleteEmail email: String) async throws -> [CoachToAthleteInvitation] {
        do {
            let snapshot = try await db.collection("invitations")
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

    /// Accepts a coach-to-athlete invitation
    func acceptCoachToAthleteInvitation(invitationID: String, athleteUserID: String) async throws {

        do {
            try await db.collection("invitations").document(invitationID).updateData([
                "status": "accepted",
                "acceptedAt": FieldValue.serverTimestamp(),
                "athleteUserID": athleteUserID
            ])

        } catch {
            throw error
        }
    }

    /// Declines a coach-to-athlete invitation
    func declineCoachToAthleteInvitation(invitationID: String) async throws {

        do {
            try await db.collection("invitations").document(invitationID).updateData([
                "status": "declined",
                "declinedAt": FieldValue.serverTimestamp()
            ])

        } catch {
            throw error
        }
    }
}
