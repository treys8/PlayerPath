//
//  Coach.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import Foundation
import SwiftData
import SwiftUI

// MARK: - Coach Model
@Model
final class Coach {
    var id: UUID = UUID()
    var name: String = ""
    var role: String = ""
    var phone: String = ""
    var email: String = ""
    var notes: String = ""
    var createdAt: Date?
    var athlete: Athlete?

    // MARK: - Firebase Integration

    /// Firebase user ID if this coach has accepted an invitation and has an account
    var firebaseCoachID: String?

    /// Firebase folder IDs that this coach has access to
    var sharedFolderIDs: [String] = []

    /// Invitation tracking
    var invitationSentAt: Date?
    var invitationAcceptedAt: Date?
    var lastInvitationStatus: String? // "pending", "accepted", "declined"

    // MARK: - Computed Properties

    /// Whether this coach has an active Firebase account linked
    var hasFirebaseAccount: Bool {
        firebaseCoachID != nil
    }

    /// Whether this coach has access to any shared folders
    var hasFolderAccess: Bool {
        !sharedFolderIDs.isEmpty
    }

    /// True when 30 days have passed since the invitation was sent and it hasn't been accepted
    var isInvitationExpired: Bool {
        guard lastInvitationStatus == "pending",
              let sentAt = invitationSentAt else { return false }
        return sentAt.addingTimeInterval(30 * 24 * 60 * 60) < Date()
    }

    /// Status badge text for UI
    var connectionStatus: String {
        if hasFirebaseAccount && hasFolderAccess {
            return "Connected"
        } else if hasFirebaseAccount {
            return "No Folders Shared"
        } else if isInvitationExpired {
            return "Invitation Expired"
        } else if invitationSentAt != nil && lastInvitationStatus == "pending" {
            return "Invitation Pending"
        } else if lastInvitationStatus == "declined" {
            return "Invitation Declined"
        } else {
            return "Not Connected"
        }
    }

    /// Status color for UI
    var connectionStatusColor: String {
        if hasFirebaseAccount && hasFolderAccess {
            return "green"
        } else if hasFirebaseAccount {
            return "orange"
        } else if isInvitationExpired {
            return "red"
        } else if invitationSentAt != nil && lastInvitationStatus == "pending" {
            return "orange"
        } else if lastInvitationStatus == "declined" {
            return "red"
        } else {
            return "gray"
        }
    }

    // MARK: - Firestore Sync Metadata
    var firestoreId: String?
    var needsSync: Bool = false

    init(name: String, role: String = "", phone: String = "", email: String = "", notes: String = "") {
        self.id = UUID()
        self.name = name
        self.role = role
        self.phone = phone
        self.email = email
        self.notes = notes
        self.createdAt = Date()
    }

    func toFirestoreData(athleteFirestoreId: String) -> [String: Any] {
        var data: [String: Any] = [
            "id": id.uuidString,
            "athleteId": athleteFirestoreId,
            "name": name,
            "role": role,
            "email": email,
            "createdAt": createdAt ?? Date(),
            "updatedAt": Date(),
            "isDeleted": false
        ]
        if !phone.isEmpty { data["phone"] = phone }
        if !notes.isEmpty { data["notes"] = notes }
        if let firebaseCoachID = firebaseCoachID { data["firebaseCoachID"] = firebaseCoachID }
        if let status = lastInvitationStatus { data["invitationStatus"] = status }
        return data
    }

    // MARK: - Firebase Sync Methods

    /// Updates Firebase connection status when coach accepts invitation
    func markInvitationAccepted(firebaseCoachID: String, folderID: String) {
        self.firebaseCoachID = firebaseCoachID
        self.invitationAcceptedAt = Date()
        self.lastInvitationStatus = "accepted"
        if !sharedFolderIDs.contains(folderID) {
            sharedFolderIDs.append(folderID)
        }
        self.needsSync = true
    }

    /// Removes folder access when athlete revokes permissions
    func removeFolderAccess(folderID: String) {
        sharedFolderIDs.removeAll { $0 == folderID }
        // Note: firebaseCoachID is intentionally preserved — it is a permanent identity
        // link and must survive losing folder access so re-sharing works without a new invite.
    }
}
