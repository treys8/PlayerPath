//
//  FirestoreManager+Invitations.swift
//  PlayerPath
//
//  Invitation operations for FirestoreManager
//

import Foundation
import FirebaseAuth
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
    case proRequired = -6
}

/// Expiration constant for invitations (30 days)
private let invitationExpirationInterval: TimeInterval = 30 * 24 * 60 * 60

/// Normalizes an email for storage and lookup: lowercased + trimmed.
/// Coach input frequently includes trailing spaces (autocomplete, paste) which
/// would otherwise cause the invitation to be orphaned from the athlete's signup record.
func normalizeInvitationEmail(_ email: String) -> String {
    email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
}

extension FirestoreManager {

    // MARK: - Invitations

    /// Creates an invitation for a coach to join a shared folder.
    /// folderID/folderName are optional — folders are now created server-side on acceptance.
    func createInvitation(
        athleteID: String,
        athleteName: String,
        athleteUUID: String,
        coachEmail: String,
        folderID: String? = nil,
        folderName: String? = nil,
        permissions: FolderPermissions = .default
    ) async throws -> String {

        let normalizedCoachEmail = normalizeInvitationEmail(coachEmail)
        var invitationData: [String: Any] = [
            "type": "athlete_to_coach",
            "athleteID": athleteID,
            "athleteName": athleteName,
            "athleteUUID": athleteUUID,
            "coachEmail": normalizedCoachEmail,
            "permissions": permissions.toDictionary(),
            "status": "pending",
            "sentAt": FieldValue.serverTimestamp(),
            "expiresAt": Date().addingTimeInterval(invitationExpirationInterval)
        ]
        if let folderID { invitationData["folderID"] = folderID }
        if let folderName { invitationData["folderName"] = folderName }

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

    /// Checks if the current athlete already has a pending or accepted invitation with this coach
    /// in EITHER direction (athlete→coach or coach→athlete).
    func hasPendingInvitation(athleteID: String, coachEmail: String) async throws -> Bool {
        let normalizedCoachEmail = normalizeInvitationEmail(coachEmail)
        let currentEmail = Auth.auth().currentUser?.email.map(normalizeInvitationEmail)

        // Fire all three checks in parallel rather than serially — on cellular,
        // three sequential round trips was the bulk of the perceived latency.
        // Any one match means "already invited," so we still OR the results.
        async let acceptedA2C = db.collection(FC.invitations)
            .whereField("athleteID", isEqualTo: athleteID)
            .whereField("coachEmail", isEqualTo: normalizedCoachEmail)
            .whereField("status", isEqualTo: "accepted")
            .whereField("type", isEqualTo: "athlete_to_coach")
            .limit(to: 1)
            .getDocuments()

        async let pendingA2C = db.collection(FC.invitations)
            .whereField("athleteID", isEqualTo: athleteID)
            .whereField("coachEmail", isEqualTo: normalizedCoachEmail)
            .whereField("status", isEqualTo: "pending")
            .whereField("type", isEqualTo: "athlete_to_coach")
            .whereField("expiresAt", isGreaterThan: Timestamp(date: Date()))
            .limit(to: 1)
            .getDocuments()

        // Third query is conditional on having the current user's email. When
        // absent, resolve to an empty document set so the `await` tuple below
        // still type-checks and short-circuits correctly.
        async let acceptedC2ADocs: [QueryDocumentSnapshot] = {
            guard let currentEmail else { return [] }
            let snap = try await db.collection(FC.invitations)
                .whereField("athleteEmail", isEqualTo: currentEmail)
                .whereField("coachEmail", isEqualTo: normalizedCoachEmail)
                .whereField("status", isEqualTo: "accepted")
                .whereField("type", isEqualTo: "coach_to_athlete")
                .limit(to: 1)
                .getDocuments()
            return snap.documents
        }()

        let (a1, a2, a3) = try await (acceptedA2C, pendingA2C, acceptedC2ADocs)
        return !a1.documents.isEmpty || !a2.documents.isEmpty || !a3.isEmpty
    }

    /// Fetches pending invitations for a coach (by email)
    func fetchPendingInvitations(forEmail email: String) async throws -> [CoachInvitation] {
        do {
            let snapshot = try await db.collection(FC.invitations)
                .whereField("type", isEqualTo: "athlete_to_coach")
                .whereField("coachEmail", isEqualTo: normalizeInvitationEmail(email))
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
            firestoreLog.error("Failed to fetch pending invitations: \(error.localizedDescription)")
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

    /// Accepts an athlete-to-coach invitation via direct HTTPS call to the Cloud Function.
    /// Uses URLSession instead of HTTPSCallable.call() — same iOS 26.4 workaround.
    func acceptInvitation(
        invitationID: String,
        coachID: String,
        permissions: FolderPermissions // kept for API compat; server reads from invitation
    ) async throws {
        guard let user = Auth.auth().currentUser else {
            throw NSError(domain: "FirestoreManager", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        let token = try await user.getIDToken()

        let url = FirestoreManager.cloudFunctionURL("acceptAthleteToCoachInvitation")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let body: [String: Any] = ["data": ["invitationID": invitationID]]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (responseData, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "FirestoreManager", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw NSError(domain: "FirestoreManager", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid response data"])
        }

        if let errorInfo = json["error"] as? [String: Any] {
            let message = errorInfo["message"] as? String ?? "Unknown error"
            let status = errorInfo["status"] as? String ?? ""

            if status == "NOT_FOUND" {
                throw NSError(domain: "FirestoreManager", code: InvitationErrorCode.invalidInvitation.rawValue,
                              userInfo: [NSLocalizedDescriptionKey: message])
            } else if status == "FAILED_PRECONDITION" {
                let errorCode = message.contains("expired") ? InvitationErrorCode.expired : InvitationErrorCode.alreadyProcessed
                throw NSError(domain: "FirestoreManager", code: errorCode.rawValue,
                              userInfo: [NSLocalizedDescriptionKey: message])
            } else if status == "PERMISSION_DENIED" {
                throw NSError(domain: "FirestoreManager", code: InvitationErrorCode.proRequired.rawValue,
                              userInfo: [NSLocalizedDescriptionKey: message])
            } else if status == "RESOURCE_EXHAUSTED" {
                throw SharedFolderError.coachAthleteLimitReached
            }
            throw NSError(domain: "FirestoreManager", code: httpResponse.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }

        guard httpResponse.statusCode == 200 else {
            throw NSError(domain: "FirestoreManager", code: httpResponse.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "Server error (\(httpResponse.statusCode))"])
        }

        guard let result = json["result"] as? [String: Any],
              result["success"] as? Bool == true else {
            throw NSError(domain: "FirestoreManager", code: InvitationErrorCode.invalidInvitation.rawValue,
                          userInfo: [NSLocalizedDescriptionKey: "Unexpected response from server."])
        }

        invitationLog.info("Accepted invitation \(invitationID) via Cloud Function")
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

        let normalizedAthleteEmail = normalizeInvitationEmail(athleteEmail)
        let normalizedCoachEmail = normalizeInvitationEmail(coachEmail)

        // Check for existing accepted invitation (already connected)
        let acceptedSnapshot = try await db.collection(FC.invitations)
            .whereField("type", isEqualTo: "coach_to_athlete")
            .whereField("coachID", isEqualTo: coachID)
            .whereField("athleteEmail", isEqualTo: normalizedAthleteEmail)
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
            .whereField("athleteEmail", isEqualTo: normalizedAthleteEmail)
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
            "coachEmail": normalizedCoachEmail,
            "coachName": coachName,
            "athleteEmail": normalizedAthleteEmail,
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
                .whereField("athleteEmail", isEqualTo: normalizeInvitationEmail(email))
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
            firestoreLog.error("Failed to fetch pending coach invitations: \(error.localizedDescription)")
            throw error
        }
    }

    /// Accepts a coach-to-athlete invitation via direct HTTPS call to the Cloud Function.
    /// Uses URLSession instead of HTTPSCallable.call() to work around a Swift concurrency
    /// runtime crash (asyncLet_finish_after_task_completion / SIGABRT) on iOS 26.4.
    /// Revert to HTTPSCallable when Firebase SDK ships a fix (tracked: firebase-ios-sdk #15974).
    func acceptCoachToAthleteInvitation(
        invitationID: String,
        athleteUserID: String,
        athleteName: String,
        athleteUUID: String
    ) async throws -> (gamesFolderID: String?, lessonsFolderID: String?) {
        guard let user = Auth.auth().currentUser else {
            throw NSError(domain: "FirestoreManager", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        let token = try await user.getIDToken()

        let url = FirestoreManager.cloudFunctionURL("acceptCoachToAthleteInvitation")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let payload: [String: Any] = [
            "invitationID": invitationID,
            "athleteName": athleteName,
            "athleteUUID": athleteUUID,
        ]
        let body: [String: Any] = ["data": payload]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (responseData, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "FirestoreManager", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw NSError(domain: "FirestoreManager", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid response data"])
        }

        if let errorInfo = json["error"] as? [String: Any] {
            let message = errorInfo["message"] as? String ?? "Unknown error"
            let status = errorInfo["status"] as? String ?? ""

            if status == "RESOURCE_EXHAUSTED" {
                throw SharedFolderError.coachAthleteLimitReached
            } else if status == "FAILED_PRECONDITION" {
                if message.contains("expired") {
                    throw NSError(domain: "FirestoreManager", code: InvitationErrorCode.expired.rawValue,
                                  userInfo: [NSLocalizedDescriptionKey: message])
                } else {
                    throw NSError(domain: "FirestoreManager", code: InvitationErrorCode.alreadyProcessed.rawValue,
                                  userInfo: [NSLocalizedDescriptionKey: message])
                }
            }
            throw NSError(domain: "FirestoreManager", code: httpResponse.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }

        guard httpResponse.statusCode == 200 else {
            throw NSError(domain: "FirestoreManager", code: httpResponse.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "Server error (\(httpResponse.statusCode))"])
        }

        invitationLog.info("Accepted coach-to-athlete invitation \(invitationID) via Cloud Function")

        if let result = json["result"] as? [String: Any] {
            let gamesID = result["gamesFolderID"] as? String
            let lessonsID = result["lessonsFolderID"] as? String
            return (gamesFolderID: gamesID, lessonsFolderID: lessonsID)
        }
        return (nil, nil)
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

    /// Returns athlete user IDs from accepted coach-to-athlete invitations for a given coach.
    /// Used to count connected athletes for limit enforcement.
    func fetchAcceptedCoachToAthleteAthleteIDs(coachID: String) async throws -> Set<String> {
        let snapshot = try await db.collection(FC.invitations)
            .whereField("type", isEqualTo: "coach_to_athlete")
            .whereField("coachID", isEqualTo: coachID)
            .whereField("status", isEqualTo: "accepted")
            .limit(to: 200)
            .getDocuments()
        var ids = Set<String>()
        for doc in snapshot.documents {
            // Prefer per-athlete UUID (matches folder.athleteUUID so the SubscriptionGate union dedupes
            // correctly); fall back to the account UID for legacy invitations accepted before that field.
            let data = doc.data()
            if let athleteUUID = data["athleteUUID"] as? String, !athleteUUID.isEmpty {
                ids.insert(athleteUUID)
            } else if let athleteUID = data["athleteUserID"] as? String, !athleteUID.isEmpty {
                ids.insert(athleteUID)
            }
        }
        return ids
    }

    /// Real-time listener for pending athlete-to-coach invitations sent to a given coach email.
    /// Returns a `ListenerRegistration` the caller is responsible for removing.
    func listenPendingAthleteInvitations(
        forCoachEmail email: String,
        onUpdate: @escaping @MainActor ([CoachInvitation]) -> Void
    ) -> ListenerRegistration {
        return db.collection(FC.invitations)
            .whereField("type", isEqualTo: "athlete_to_coach")
            .whereField("coachEmail", isEqualTo: normalizeInvitationEmail(email))
            .whereField("status", isEqualTo: "pending")
            .whereField("expiresAt", isGreaterThan: Timestamp(date: Date()))
            .limit(to: 100)
            .addSnapshotListener { snapshot, error in
                if let error {
                    invitationLog.warning("Pending athlete invitations listener error: \(error.localizedDescription)")
                    return
                }
                guard let snapshot else { return }
                let invitations = snapshot.documents.compactMap { doc -> CoachInvitation? in
                    do {
                        var invitation = try doc.data(as: CoachInvitation.self)
                        invitation.id = doc.documentID
                        return invitation
                    } catch {
                        invitationLog.warning("Failed to decode pending invitation \(doc.documentID): \(error.localizedDescription)")
                        return nil
                    }
                }
                Task { @MainActor in
                    onUpdate(invitations)
                }
            }
    }

    /// Real-time listener for pending coach-to-athlete invitations sent to a given email.
    /// Returns a `ListenerRegistration` the caller is responsible for removing.
    func listenPendingCoachInvitations(
        forAthleteEmail email: String,
        onUpdate: @escaping @MainActor ([CoachToAthleteInvitation]) -> Void
    ) -> ListenerRegistration {
        return db.collection(FC.invitations)
            .whereField("type", isEqualTo: "coach_to_athlete")
            .whereField("athleteEmail", isEqualTo: normalizeInvitationEmail(email))
            .whereField("status", isEqualTo: "pending")
            .whereField("expiresAt", isGreaterThan: Timestamp(date: Date()))
            .limit(to: 100)
            .addSnapshotListener { snapshot, error in
                if let error {
                    invitationLog.warning("Pending coach invitations listener error: \(error.localizedDescription)")
                    return
                }
                guard let snapshot else { return }
                let invitations = snapshot.documents.compactMap { doc -> CoachToAthleteInvitation? in
                    do {
                        var invitation = try doc.data(as: CoachToAthleteInvitation.self)
                        invitation.id = doc.documentID
                        return invitation
                    } catch {
                        invitationLog.warning("Failed to decode pending invitation \(doc.documentID): \(error.localizedDescription)")
                        return nil
                    }
                }
                Task { @MainActor in
                    onUpdate(invitations)
                }
            }
    }

    /// Counts pending outbound coach-to-athlete invitations for a given coach.
    func countPendingCoachToAthleteInvitations(coachID: String) async throws -> Int {
        let query = db.collection(FC.invitations)
            .whereField("type", isEqualTo: "coach_to_athlete")
            .whereField("coachID", isEqualTo: coachID)
            .whereField("status", isEqualTo: "pending")
        let countResult = try await query.count.getAggregation(source: .server)
        return Int(truncating: countResult.count)
    }
}
