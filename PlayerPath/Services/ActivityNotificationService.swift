//
//  ActivityNotificationService.swift
//  PlayerPath
//
//  Firestore-backed in-app notification system.
//  Writes notification records when key events happen (video upload, coach comment,
//  invitation sent/accepted) and listens in real-time so the receiving user sees
//  badge counts and in-app banners without needing FCM.
//
//  Firestore path:  notifications/{userID}/items/{notifID}
//

import Foundation
import FirebaseFirestore
import Combine

// MARK: - Model

struct ActivityNotification: Identifiable, Codable {
    var id: String?
    let type: NotificationType
    let title: String
    let body: String
    let senderName: String
    let senderID: String
    let targetID: String?
    let targetType: TargetType?
    var isRead: Bool
    let createdAt: Date?

    enum NotificationType: String, Codable {
        case newVideo            = "new_video"
        case coachComment        = "coach_comment"
        case invitationReceived  = "invitation_received"
        case invitationAccepted  = "invitation_accepted"
        case accessRevoked       = "access_revoked"
    }

    enum TargetType: String, Codable {
        case folder     = "folder"
        case video      = "video"
        case invitation = "invitation"
    }
}

// MARK: - Service

@MainActor
final class ActivityNotificationService: ObservableObject {

    static let shared = ActivityNotificationService()

    @Published private(set) var unreadCount: Int = 0
    @Published private(set) var recentNotifications: [ActivityNotification] = []
    /// Most-recently-arrived notification, used to drive the in-app banner.
    @Published private(set) var incomingBanner: ActivityNotification?

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var previousIDs: Set<String> = []

    private init() {}

    // MARK: - Listening

    func startListening(forUserID userID: String) {
        stopListening()

        listener = db
            .collection("notifications")
            .document(userID)
            .collection("items")
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                guard let docs = snapshot?.documents else { return }

                let notifications = docs.compactMap { doc -> ActivityNotification? in
                    var n = try? doc.data(as: ActivityNotification.self)
                    n?.id = doc.documentID
                    return n
                }

                self.recentNotifications = notifications
                self.unreadCount = notifications.filter { !$0.isRead }.count

                // Surface in-app banner for any genuinely new (unseen) notification
                let currentIDs = Set(notifications.compactMap { $0.id })
                if !self.previousIDs.isEmpty {
                    if let newest = notifications.first(where: {
                        guard let id = $0.id else { return false }
                        return !self.previousIDs.contains(id) && !$0.isRead
                    }) {
                        self.incomingBanner = newest
                    }
                }
                self.previousIDs = currentIDs
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
        previousIDs = []
    }

    func dismissBanner() {
        incomingBanner = nil
    }

    // MARK: - Mark Read

    func markAllRead(forUserID userID: String) async {
        let unread = recentNotifications.filter { !$0.isRead }
        guard !unread.isEmpty else { return }

        let batch = db.batch()
        for n in unread {
            guard let id = n.id else { continue }
            let ref = db.collection("notifications").document(userID).collection("items").document(id)
            batch.updateData(["isRead": true], forDocument: ref)
        }
        do {
            try await batch.commit()
        } catch {
            print("❌ Failed to mark notifications as read: \(error)")
        }
    }

    func markRead(_ notifID: String, forUserID userID: String) async {
        do {
            try await db.collection("notifications")
                .document(userID)
                .collection("items")
                .document(notifID)
                .updateData(["isRead": true])
        } catch {
            print("❌ Failed to mark notification read: \(error)")
        }
    }

    // MARK: - Post Helpers

    /// Athlete uploads a video → notify all coaches with access to the folder.
    func postNewVideoNotification(
        folderID: String,
        folderName: String,
        uploaderID: String,
        uploaderName: String,
        coachIDs: [String],
        videoFileName: String
    ) async {
        let data: [String: Any] = [
            "type": ActivityNotification.NotificationType.newVideo.rawValue,
            "title": "New Video in \(folderName)",
            "body": "\(uploaderName) uploaded a new clip — \(videoFileName)",
            "senderName": uploaderName,
            "senderID": uploaderID,
            "targetID": folderID,
            "targetType": ActivityNotification.TargetType.folder.rawValue,
            "isRead": false,
            "createdAt": FieldValue.serverTimestamp()
        ]
        await writeNotification(data, toUserIDs: coachIDs)
    }

    /// Coach adds a comment → notify the athlete who owns the folder.
    func postCoachCommentNotification(
        videoFileName: String,
        folderID: String,
        videoID: String,
        coachID: String,
        coachName: String,
        athleteID: String,
        notePreview: String
    ) async {
        let preview = String(notePreview.prefix(80))
        let data: [String: Any] = [
            "type": ActivityNotification.NotificationType.coachComment.rawValue,
            "title": "Coach Feedback on \(videoFileName)",
            "body": "\(coachName): \(preview)",
            "senderName": coachName,
            "senderID": coachID,
            "targetID": videoID,
            "targetType": ActivityNotification.TargetType.video.rawValue,
            "isRead": false,
            "createdAt": FieldValue.serverTimestamp()
        ]
        await writeNotification(data, toUserIDs: [athleteID])
    }

    /// Athlete invites coach → notify coach (if they already have an account).
    func postInvitationReceivedNotification(
        invitationID: String,
        athleteID: String,
        athleteName: String,
        folderName: String,
        coachUserID: String
    ) async {
        let data: [String: Any] = [
            "type": ActivityNotification.NotificationType.invitationReceived.rawValue,
            "title": "New Folder Invitation",
            "body": "\(athleteName) invited you to view their folder \"\(folderName)\"",
            "senderName": athleteName,
            "senderID": athleteID,
            "targetID": invitationID,
            "targetType": ActivityNotification.TargetType.invitation.rawValue,
            "isRead": false,
            "createdAt": FieldValue.serverTimestamp()
        ]
        await writeNotification(data, toUserIDs: [coachUserID])
    }

    /// Coach accepts invitation → notify athlete.
    func postInvitationAcceptedNotification(
        folderName: String,
        coachID: String,
        coachName: String,
        athleteID: String,
        folderID: String
    ) async {
        let data: [String: Any] = [
            "type": ActivityNotification.NotificationType.invitationAccepted.rawValue,
            "title": "Coach Joined Your Folder",
            "body": "\(coachName) accepted your invitation to \"\(folderName)\"",
            "senderName": coachName,
            "senderID": coachID,
            "targetID": folderID,
            "targetType": ActivityNotification.TargetType.folder.rawValue,
            "isRead": false,
            "createdAt": FieldValue.serverTimestamp()
        ]
        await writeNotification(data, toUserIDs: [athleteID])
    }

    /// Athlete revokes coach access → notify coach.
    func postAccessRevokedNotification(
        folderName: String,
        athleteID: String,
        athleteName: String,
        coachUserID: String
    ) async {
        let data: [String: Any] = [
            "type": ActivityNotification.NotificationType.accessRevoked.rawValue,
            "title": "Folder Access Removed",
            "body": "\(athleteName) has removed your access to \"\(folderName)\"",
            "senderName": athleteName,
            "senderID": athleteID,
            "isRead": false,
            "createdAt": FieldValue.serverTimestamp()
        ]
        await writeNotification(data, toUserIDs: [coachUserID])
    }

    // MARK: - Internal Write

    private func writeNotification(_ data: [String: Any], toUserIDs userIDs: [String]) async {
        for userID in userIDs {
            do {
                try await db
                    .collection("notifications")
                    .document(userID)
                    .collection("items")
                    .addDocument(data: data)
            } catch {
                print("❌ Failed to write notification to \(userID): \(error)")
            }
        }
    }

    // MARK: - Lookup coach user ID by email

    /// Looks up a Firebase user ID from the users collection by email.
    /// Returns nil if the coach hasn't signed up yet.
    func lookupUserID(byEmail email: String) async -> String? {
        do {
            let snapshot = try await db.collection("users")
                .whereField("email", isEqualTo: email.lowercased())
                .limit(to: 1)
                .getDocuments()
            return snapshot.documents.first?.documentID
        } catch {
            print("⚠️ Could not look up user by email: \(error)")
            return nil
        }
    }
}
