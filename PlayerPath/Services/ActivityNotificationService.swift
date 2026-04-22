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
import UserNotifications
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

extension ActivityNotification {
    /// Title with raw video filenames rewritten to "your <date> clip" / "your clip".
    /// Covers legacy notifications whose server-generated titles embedded UUID or
    /// ISO-date filenames (e.g. "Coach Feedback on F9FB5711-…mov").
    var displayTitle: String { NotificationTextSanitizer.sanitize(title) }

    /// Body with trailing " — <filename>.ext" fragments rewritten the same way.
    var displayBody: String { NotificationTextSanitizer.sanitize(body) }
}

/// Rewrites raw `.mov`/`.mp4` filename fragments embedded in notification
/// title/body strings into a friendlier "your Mar 28, 2026 clip" phrase.
/// Needed because Cloud Functions historically inlined `video.fileName` directly
/// into notification records — UUID-named clips produced unreadable text.
enum NotificationTextSanitizer {
    /// Matches a filename token preceded by a connector (" on ", " — ", etc.)
    /// and captures the filename for date extraction.
    private static let regex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(\s+(?:on|to|from|in|for)\s+|\s*[—–\-:]\s*)([A-Za-z0-9_\-]+)\.(?:mov|mp4|m4v)"#,
        options: [.caseInsensitive]
    )

    /// Parses `instruction_YYYY-MM-DD_…` filenames produced by coach recording.
    private static let dateInFilename: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(?:^|_)(\d{4})-(\d{2})-(\d{2})(?:_|$)"#
    )

    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    private static let parseFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    static func sanitize(_ text: String) -> String {
        guard let regex else { return text }
        let ns = text as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        let matches = regex.matches(in: text, range: fullRange)
        guard !matches.isEmpty else { return text }

        var result = text
        // Replace from the tail so earlier match ranges remain valid.
        for match in matches.reversed() {
            let connectorRange = match.range(at: 1)
            let fileStem = ns.substring(with: match.range(at: 2))
            let connector = ns.substring(with: connectorRange).lowercased()
            let replacement = phrase(forConnector: connector, fileStem: fileStem)
            if let swiftRange = Range(match.range, in: result) {
                result.replaceSubrange(swiftRange, with: replacement)
            }
        }
        return result
    }

    private static func phrase(forConnector connector: String, fileStem: String) -> String {
        let clipPhrase: String = {
            if let date = extractDate(from: fileStem) {
                return "your \(displayFormatter.string(from: date)) clip"
            }
            return "your clip"
        }()
        // Preserve the connector word when it carries meaning; collapse bare
        // dashes/em-dashes into a natural "— <clip>" fragment.
        let trimmed = connector.trimmingCharacters(in: .whitespaces)
        switch trimmed {
        case "on", "to", "from", "in", "for":
            return " \(trimmed) \(clipPhrase)"
        default:
            return " — \(clipPhrase)"
        }
    }

    private static func extractDate(from fileStem: String) -> Date? {
        guard let dateInFilename else { return nil }
        let ns = fileStem as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = dateInFilename.firstMatch(in: fileStem, range: range) else { return nil }
        let iso = ns.substring(with: match.range).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return parseFormatter.date(from: iso)
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

    /// Most recent moment the app transitioned into the `.active` scene phase.
    /// Used to suppress the in-app banner for notifications the user already
    /// saw as an FCM lock-screen banner while the app was backgrounded.
    private var lastForegroundAt: Date = Date()
    /// Grace window so notifications created in the brief gap between
    /// foregrounding and the listener's first callback still surface as banners.
    private static let foregroundBannerGrace: TimeInterval = 2

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
                if let error {
                    log.error("Notification listener error: \(error.localizedDescription)")
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
                    // Athletes-tab badge reflects athlete-initiated actions pending
                    // the coach's attention. Upload failures are the coach's own
                    // problem and surface through the Dashboard tab's unreadCount
                    // and per-folder indicators instead.
                    // Covers both forms the Cloud Function emits:
                    //   - Coach-side: targetType == .folder, targetID == folderID
                    //   - Athlete-side: targetType == .video, folderID set alongside
                    self.unreadFolderVideoCount = unread.filter { n in
                        guard n.type == .newVideo || n.type == .coachComment else { return false }
                        return n.folderID != nil || (n.targetType == .folder && n.targetID != nil)
                    }.count
                    Self.syncAppIconBadge(to: self.unreadCount)

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

                    // Surface in-app banner for any genuinely new (unseen) notification.
                    // Suppress banners for notifications that arrived before the most
                    // recent foreground transition — the user already saw them as FCM
                    // lock-screen banners while the app was backgrounded; re-showing
                    // them in-app produces a duplicate prompt. The grace window covers
                    // the gap between foregrounding and this listener firing.
                    let currentIDs = Set(notifications.compactMap { $0.id })
                    if !self.previousIDs.isEmpty {
                        let bannerCutoff = self.lastForegroundAt
                            .addingTimeInterval(-Self.foregroundBannerGrace)
                        if let newest = notifications.first(where: {
                            guard let id = $0.id else { return false }
                            guard !self.previousIDs.contains(id), !$0.isRead else { return false }
                            // createdAt nil (still pending server timestamp) → show it;
                            // otherwise require the notification to be newer than the cutoff.
                            guard let created = $0.createdAt else { return true }
                            return created > bannerCutoff
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
        unreadCount = 0
        unreadVideoCount = 0
        unreadFolderVideoCount = 0
        unreadCountByFolder = [:]
        unreadVideoIDs = []
        Self.syncAppIconBadge(to: 0)
    }

    /// Mirrors the current unread count onto the home-screen app icon badge.
    /// Uses `UNUserNotificationCenter.setBadgeCount` (the `UIApplication`
    /// equivalent is deprecated on iOS 17+). Silently no-ops if authorization
    /// hasn't been granted.
    private static func syncAppIconBadge(to count: Int) {
        UNUserNotificationCenter.current().setBadgeCount(count)
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

    /// Call when the app transitions to `.active` scene phase. Marks the
    /// moment so the next listener callback can decide whether a fresh
    /// notification should surface as an in-app banner (true) or be suppressed
    /// because the user already saw it as an FCM banner on the lock screen (false).
    func noteAppDidBecomeActive() {
        lastForegroundAt = Date()
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

    /// Marks every unread notification as read. Backs the "Mark All Read" action
    /// in NotificationInboxView. Queries Firestore directly (not the 50-item
    /// listener cache) so users with large backlogs don't get left with stragglers.
    func markAllRead(forUserID userID: String) async {
        do {
            let snapshot = try await db
                .collection(FC.notifications)
                .document(userID)
                .collection(FC.items)
                .whereField("isRead", isEqualTo: false)
                .getDocuments()

            let docs = snapshot.documents
            guard !docs.isEmpty else { return }

            // Firestore caps batches at 500 writes; chunk for safety.
            var index = 0
            while index < docs.count {
                let end = min(index + 450, docs.count)
                let batch = db.batch()
                for doc in docs[index..<end] {
                    batch.updateData(["isRead": true], forDocument: doc.reference)
                }
                try await batch.commit()
                index = end
            }
        } catch {
            log.error("Failed to mark all notifications read: \(error.localizedDescription)")
        }
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
    //
    // Most notification types are written exclusively by Cloud Functions —
    // clients only READ the notifications/{userID}/items/ collection. The
    // remaining client-side writers in this file cover two cases the server
    // can't observe from Firestore state alone:
    //   1. Coach-initiated tier downgrades that affect athlete access
    //      (postCoachAccessLostNotification, postAccessLapsedNotification)
    //   2. Client-only upload failures triggered by runtime conditions
    //      (postClipUploadFailedPermissionNotification,
    //       postClipUploadFailedNotification)
    //
    // Everything else (new videos, comments, annotations, drill cards, coach
    // notes, invitations, folder-access revocations) goes through source-
    // triggered Cloud Functions in firebase/functions/src/index.ts.

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
            deterministicIDFor: { _ in "upload_failed_\(uploadID)" }
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
        deterministicIDFor: ((String) -> String)? = nil
    ) async {
        // Filter out the sender so users don't notify themselves
        let senderID = data["senderID"] as? String
        let recipients = userIDs.filter { $0 != senderID }
        guard !recipients.isEmpty else { return }

        // Batch writes to reduce Firestore operations. When deterministicIDFor is supplied,
        // each recipient gets a stable per-user doc ID. This lets the paired server-side
        // Cloud Function write with the same ID and collapse client+server writes into
        // one notification doc. Without it, Firestore auto-generates an ID (fan-outs
        // that don't coordinate with a CF).
        let batch = db.batch()
        for userID in recipients {
            let collection = db
                .collection(FC.notifications)
                .document(userID)
                .collection(FC.items)
            let ref = deterministicIDFor.map { collection.document($0(userID)) } ?? collection.document()
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
            log.error("User lookup by email failed: \(error.localizedDescription)")
            return nil
        }
    }
}
