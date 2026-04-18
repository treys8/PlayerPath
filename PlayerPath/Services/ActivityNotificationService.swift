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
import os

private let log = Logger(subsystem: "com.playerpath.app", category: "ActivityNotifications")

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
    let folderID: String?
    var isRead: Bool
    let createdAt: Date?

    enum NotificationType: String, Codable {
        case newVideo            = "new_video"
        case coachComment        = "coach_comment"
        case invitationReceived  = "invitation_received"
        case invitationAccepted  = "invitation_accepted"
        case accessRevoked       = "access_revoked"
        case accessLapsed        = "access_lapsed"
        case uploadFailed        = "upload_failed"
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
    /// Unread count for video-related notifications only (newVideo, coachComment).
    @Published private(set) var unreadVideoCount: Int = 0
    /// Unread count for folder-targeted video notifications (coach card badge).
    @Published private(set) var unreadFolderVideoCount: Int = 0
    /// Unread coach feedback grouped by folderID.
    @Published private(set) var unreadCountByFolder: [String: Int] = [:]
    /// Set of videoIDs that have unread coach feedback.
    @Published private(set) var unreadVideoIDs: Set<String> = []
    @Published private(set) var recentNotifications: [ActivityNotification] = []
    /// Most-recently-arrived notification, used to drive the in-app banner.
    @Published private(set) var incomingBanner: ActivityNotification?
    /// Set when the real-time listener encounters an error. Views can show a stale-data hint.
    @Published private(set) var listenerError: String?

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var previousIDs: Set<String> = []
    private var currentUserID: String?
    private var retryAttempt: Int = 0
    private static let maxRetryAttempts = 3

    private init() {}

    deinit {
        listener?.remove()
    }

    // MARK: - Listening

    func startListening(forUserID userID: String) {
        stopListening()
        currentUserID = userID
        retryAttempt = 0
        attachListener(forUserID: userID)
    }

    private func attachListener(forUserID userID: String) {
        listener?.remove()
        listener = db
            .collection(FC.notifications)
            .document(userID)
            .collection(FC.items)
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if error != nil {
                    Task { @MainActor in
                        self.listenerError = "Unable to refresh notifications."
                        self.scheduleListenerRetry()
                    }
                    return
                }
                guard let docs = snapshot?.documents else { return }

                let notifications = docs.compactMap { doc -> ActivityNotification? in
                    do {
                        var n = try doc.data(as: ActivityNotification.self)
                        n.id = doc.documentID
                        return n
                    } catch {
                        log.warning("Failed to decode notification \(doc.documentID): \(error.localizedDescription)")
                        return nil
                    }
                }

                Task { @MainActor in
                    self.listenerError = nil
                    self.retryAttempt = 0
                    self.recentNotifications = notifications
                    let unread = notifications.filter { !$0.isRead }
                    self.unreadCount = unread.count
                    self.unreadVideoCount = unread.filter { $0.type == .newVideo || $0.type == .coachComment }.count
                    self.unreadFolderVideoCount = unread.filter {
                        ($0.type == .newVideo || $0.type == .coachComment || $0.type == .uploadFailed) && $0.targetType == .folder
                    }.count

                    // Per-folder unread counts and per-video unread set
                    // Includes coachComment (folderID field), newVideo (targetID is folderID),
                    // and uploadFailed (folderID field set when the failed upload targets a folder)
                    let videoRelatedUnread = unread.filter { $0.type == .coachComment || $0.type == .newVideo || $0.type == .uploadFailed }
                    var folderCounts: [String: Int] = [:]
                    var videoIDs: Set<String> = []
                    for n in videoRelatedUnread {
                        let fid = n.folderID ?? (n.targetType == .folder ? n.targetID : nil)
                        if let fid { folderCounts[fid, default: 0] += 1 }
                        if let vid = n.targetID, n.targetType == .video { videoIDs.insert(vid) }
                    }
                    self.unreadCountByFolder = folderCounts
                    self.unreadVideoIDs = videoIDs

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
    }

    func stopListening() {
        listener?.remove()
        listener = nil
        previousIDs = []
        listenerError = nil
        currentUserID = nil
        retryAttempt = 0
    }

    private func scheduleListenerRetry() {
        guard retryAttempt < Self.maxRetryAttempts,
              let userID = currentUserID else { return }
        retryAttempt += 1
        let delay = pow(2.0, Double(retryAttempt))
        log.info("Retrying notification listener in \(delay)s (attempt \(self.retryAttempt)/\(Self.maxRetryAttempts))")
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, self.currentUserID == userID else { return }
            self.attachListener(forUserID: userID)
        }
    }

    func dismissBanner() {
        incomingBanner = nil
    }

    // MARK: - Mark Read

    /// Marks every unread notification matching `predicate` as read in a single Firestore batch.
    /// Operates on `recentNotifications` (the listener's local cache, capped at 50).
    private func markBatchRead(
        forUserID userID: String,
        label: String,
        where predicate: (ActivityNotification) -> Bool
    ) async {
        let matching = recentNotifications.filter { !$0.isRead && predicate($0) }
        guard !matching.isEmpty else { return }

        let batch = db.batch()
        for n in matching {
            guard let id = n.id else { continue }
            let ref = db.collection(FC.notifications).document(userID).collection(FC.items).document(id)
            batch.updateData(["isRead": true], forDocument: ref)
        }
        do {
            try await batch.commit()
        } catch {
            log.error("Failed to mark \(label) notifications read: \(error.localizedDescription)")
        }
    }

    func markNewVideoNotificationsRead(forUserID userID: String) async {
        await markBatchRead(forUserID: userID, label: "new-video") { $0.type == .newVideo }
    }

    func markFolderNotificationsRead(forUserID userID: String) async {
        await markBatchRead(forUserID: userID, label: "folder") {
            ($0.type == .newVideo || $0.type == .coachComment || $0.type == .uploadFailed) && $0.targetType == .folder
        }
    }

    /// Marks only dashboard-level notifications as read (invitations + access events),
    /// leaving folder/video notifications unread for the Athletes tab.
    func markDashboardNotificationsRead(forUserID userID: String) async {
        let dashboardTypes: Set<ActivityNotification.NotificationType> = [
            .invitationReceived, .invitationAccepted, .accessRevoked, .accessLapsed
        ]
        await markBatchRead(forUserID: userID, label: "dashboard") { dashboardTypes.contains($0.type) }
    }

    func markInvitationNotificationsRead(forUserID userID: String) async {
        await markBatchRead(forUserID: userID, label: "invitation") {
            $0.type == .invitationAccepted || $0.type == .invitationReceived
        }
    }

    func markFolderRead(folderID: String, forUserID userID: String) async {
        await markBatchRead(forUserID: userID, label: "folder \(folderID)") {
            $0.folderID == folderID || ($0.targetID == folderID && $0.targetType == .folder)
        }
    }

    func markVideoRead(videoID: String, forUserID userID: String) async {
        await markBatchRead(forUserID: userID, label: "video \(videoID)") {
            $0.targetID == videoID && $0.targetType == .video
        }
    }

    /// Marks any invitation-targeted notifications for a specific invitationID as read.
    /// Called after accept/decline so the bell/banner clears immediately without waiting
    /// for the user to open the notifications list.
    func markInvitationRead(invitationID: String, forUserID userID: String) async {
        await markBatchRead(forUserID: userID, label: "invitation \(invitationID)") {
            $0.targetType == .invitation && $0.targetID == invitationID
        }
    }

    func markRead(_ notifID: String, forUserID userID: String) async {
        do {
            try await db.collection(FC.notifications)
                .document(userID)
                .collection(FC.items)
                .document(notifID)
                .updateData(["isRead": true])
        } catch {
            log.error("Failed to mark notification \(notifID) read: \(error.localizedDescription)")
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
            "folderID": folderID,
            "isRead": false,
            "createdAt": FieldValue.serverTimestamp()
        ]
        await writeNotification(data, toUserIDs: coachIDs)
    }

    /// Coach published a clip from the Needs Review queue → notify the athlete who
    /// owns the folder that new coach-authored content is available. Uses `.newVideo`
    /// so it counts toward unread-video badges.
    func postCoachSharedClipNotification(
        videoFileName: String,
        videoID: String,
        folderID: String,
        folderName: String,
        coachID: String,
        coachName: String,
        athleteID: String
    ) async {
        let data: [String: Any] = [
            "type": ActivityNotification.NotificationType.newVideo.rawValue,
            "title": "New Clip from \(coachName)",
            "body": "\(coachName) shared a new clip in \(folderName)",
            "senderName": coachName,
            "senderID": coachID,
            "targetID": videoID,
            "targetType": ActivityNotification.TargetType.video.rawValue,
            "folderID": folderID,
            "isRead": false,
            "createdAt": FieldValue.serverTimestamp()
        ]
        await writeNotification(data, toUserIDs: [athleteID])
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
            "folderID": folderID,
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

    /// Athlete accepts coach's invitation → notify coach they now have folder access.
    func postAthleteAcceptedInvitationNotification(
        folderName: String,
        folderID: String,
        athleteID: String,
        athleteName: String,
        coachUserID: String
    ) async {
        let data: [String: Any] = [
            "type": ActivityNotification.NotificationType.invitationAccepted.rawValue,
            "title": "Athlete Accepted Your Invitation",
            "body": "\(athleteName) accepted your invitation and shared \"\(folderName)\" with you",
            "senderName": athleteName,
            "senderID": athleteID,
            "targetID": folderID,
            "targetType": ActivityNotification.TargetType.folder.rawValue,
            "isRead": false,
            "createdAt": FieldValue.serverTimestamp()
        ]
        await writeNotification(data, toUserIDs: [coachUserID])
    }

    /// Athlete accepts coach's invitation but doesn't have Pro → notify coach of connection only.
    func postConnectionAcceptedNotification(
        invitationID: String,
        athleteID: String,
        athleteName: String,
        coachUserID: String
    ) async {
        let data: [String: Any] = [
            "type": ActivityNotification.NotificationType.invitationAccepted.rawValue,
            "title": "Athlete Accepted Your Invitation",
            "body": "\(athleteName) accepted your invitation and is now connected with you",
            "senderName": athleteName,
            "senderID": athleteID,
            "targetID": invitationID,
            "targetType": ActivityNotification.TargetType.invitation.rawValue,
            "isRead": false,
            "createdAt": FieldValue.serverTimestamp()
        ]
        await writeNotification(data, toUserIDs: [coachUserID])
    }

    /// Coach creates a drill card on a video → notify the athlete who owns the folder.
    func postDrillCardNotification(
        videoFileName: String,
        folderID: String,
        videoID: String,
        coachID: String,
        coachName: String,
        athleteID: String,
        templateName: String
    ) async {
        let data: [String: Any] = [
            "type": ActivityNotification.NotificationType.coachComment.rawValue,
            "title": "New Drill Card",
            "body": "\(coachName) added a \(templateName) to \(videoFileName)",
            "senderName": coachName,
            "senderID": coachID,
            "targetID": videoID,
            "targetType": ActivityNotification.TargetType.video.rawValue,
            "folderID": folderID,
            "isRead": false,
            "createdAt": FieldValue.serverTimestamp()
        ]
        await writeNotification(data, toUserIDs: [athleteID])
    }

    /// Athlete revokes coach access → notify coach.
    func postAccessRevokedNotification(
        folderID: String,
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
            "targetID": folderID,
            "targetType": ActivityNotification.TargetType.folder.rawValue,
            "isRead": false,
            "createdAt": FieldValue.serverTimestamp()
        ]
        // Deterministic ID so the paired server trigger (onSharedFolderDeleted /
        // onSharedFolderUpdated) can write the same doc without producing a duplicate.
        await writeNotification(
            data,
            toUserIDs: [coachUserID],
            deterministicID: "revoked_\(folderID)_\(coachUserID)"
        )
    }

    /// Coach loses folder access (downgrade) → notify the affected athlete.
    func postCoachAccessLostNotification(
        folderID: String,
        folderName: String,
        coachName: String,
        coachID: String,
        athleteUserID: String
    ) async {
        let data: [String: Any] = [
            "type": ActivityNotification.NotificationType.accessRevoked.rawValue,
            "title": "Coach Access Ended",
            "body": "\(coachName) no longer has access to \"\(folderName)\"",
            "senderName": coachName,
            "senderID": coachID,
            "targetID": folderID,
            "targetType": ActivityNotification.TargetType.folder.rawValue,
            "isRead": false,
            "createdAt": FieldValue.serverTimestamp()
        ]
        await writeNotification(data, toUserIDs: [athleteUserID])
    }

    /// Coach recorded a clip but upload failed because they no longer have folder access.
    /// The clip is saved to `coach_failed_uploads/` on disk so the coach can recover it
    /// if access is restored.
    func postClipUploadFailedPermissionNotification(
        coachUserID: String,
        folderID: String,
        fileName: String
    ) async {
        let data: [String: Any] = [
            "type": ActivityNotification.NotificationType.accessRevoked.rawValue,
            "title": "Clip Not Uploaded",
            "body": "Your access to this athlete's folder was removed. \(fileName) is saved on your device and will not upload.",
            "senderName": "PlayerPath",
            "senderID": "",
            "targetID": folderID,
            "targetType": ActivityNotification.TargetType.folder.rawValue,
            "isRead": false,
            "createdAt": FieldValue.serverTimestamp()
        ]
        await writeNotification(data, toUserIDs: [coachUserID])
    }

    /// Coach's clip upload failed after exhausting retries (non-permission failure —
    /// network timeout, storage quota, corrupt file, etc.). Surfaces in the coach's
    /// activity feed so they know the clip is in the failed queue even if they didn't
    /// see the local push notification.
    func postClipUploadFailedNotification(
        uploadID: String,
        coachUserID: String,
        folderID: String?,
        fileName: String,
        reason: String
    ) async {
        var data: [String: Any] = [
            "type": ActivityNotification.NotificationType.uploadFailed.rawValue,
            "title": "Upload Failed",
            "body": "\(fileName) couldn't upload after multiple attempts. \(reason)",
            "senderName": "PlayerPath",
            "senderID": "",
            "isRead": false,
            "createdAt": FieldValue.serverTimestamp()
        ]
        if let folderID {
            data["targetID"] = folderID
            data["targetType"] = ActivityNotification.TargetType.folder.rawValue
            data["folderID"] = folderID
        }
        // Keyed by upload/clip ID so repeat failures on the same clip overwrite
        // rather than stacking duplicate entries in the coach's feed.
        await writeNotification(
            data,
            toUserIDs: [coachUserID],
            deterministicID: "upload_failed_\(uploadID)"
        )
    }

    /// Athlete's subscription lapsed → notify coaches that the sharing relationship is in limbo.
    func postAccessLapsedNotification(
        folderID: String,
        folderName: String,
        athleteName: String,
        athleteID: String,
        coachUserID: String
    ) async {
        let data: [String: Any] = [
            "type": ActivityNotification.NotificationType.accessLapsed.rawValue,
            "title": "Athlete Subscription Lapsed",
            "body": "\(athleteName)'s subscription has changed. Shared folders may be temporarily unavailable.",
            "senderName": athleteName,
            "senderID": athleteID,
            "targetID": folderID,
            "targetType": ActivityNotification.TargetType.folder.rawValue,
            "isRead": false,
            "createdAt": FieldValue.serverTimestamp()
        ]
        await writeNotification(data, toUserIDs: [coachUserID])
    }

    // MARK: - Internal Write

    private func writeNotification(
        _ data: [String: Any],
        toUserIDs userIDs: [String],
        deterministicID: String? = nil
    ) async {
        // Filter out the sender so users don't notify themselves
        let senderID = data["senderID"] as? String
        let recipients = userIDs.filter { $0 != senderID }
        guard !recipients.isEmpty else { return }

        // Batch writes to reduce Firestore operations. When deterministicID is supplied,
        // it's used as the doc ID on every recipient's items collection. This lets a
        // server-side Cloud Function (e.g. onSharedFolderDeleted) write with the same ID
        // and safely overwrite rather than producing a duplicate notification.
        let batch = db.batch()
        for userID in recipients {
            let collection = db
                .collection(FC.notifications)
                .document(userID)
                .collection(FC.items)
            let ref = deterministicID.map { collection.document($0) } ?? collection.document()
            batch.setData(data, forDocument: ref)
        }
        do {
            try await batch.commit()
        } catch {
            log.error("Failed to write notification batch: \(error.localizedDescription)")
        }
    }

    // MARK: - Lookup coach user ID by email

    /// Looks up a Firebase user ID from the users collection by email.
    /// Returns nil if the coach hasn't signed up yet.
    func lookupUserID(byEmail email: String) async -> String? {
        do {
            let snapshot = try await db.collection(FC.users)
                .whereField("email", isEqualTo: email.lowercased())
                .limit(to: 1)
                .getDocuments()
            return snapshot.documents.first?.documentID
        } catch {
            return nil
        }
    }
}
