//
//  CoachFeedbackFeedItem.swift
//  PlayerPath
//
//  One coach-feedback event surfaced in the Journal feed. Resolved from the
//  athlete's existing `.coachComment` ActivityNotifications (which already carry
//  the delivery time + videoID) to a local clip — so the feed gets a distinct
//  "Coach Feedback" card with NO schema bump, NO sync-layer change, and NO new
//  Firestore field. Read-only: rebuilt each feed pass from the live notification
//  list; nothing is persisted.
//

import Foundation

struct CoachFeedbackFeedItem: Identifiable {
    /// The notification's document ID — the stable feed-row identity.
    let notifID: String
    /// The notification's `targetID` (the shared-folder/coach video doc ID).
    /// Used to mark the notification read when the card is opened, and passed to
    /// the player as `feedbackVideoIDOverride` so the card opens THIS coach's
    /// feedback rather than the clip's most recent share.
    let videoID: String
    /// The local clip the feedback is on (its thumbnail + the player target).
    let clip: VideoClip
    /// When the feedback was delivered — the feed sort key, so fresh feedback on
    /// an old clip still rises to the top.
    let deliveredAt: Date
    let isRead: Bool
    let coachName: String
    /// Render-ready one-line summary (the notification body, filename-sanitized).
    let summary: String

    var id: String { notifID }

    /// Resolve coach-feedback notifications to the active athlete's local clips.
    ///
    /// Filters to `.coachComment` video notifications, then matches each to a
    /// clip by the same key the existing "New Feedback" badge uses — the
    /// shared-folder/coach video doc ID — which on a local clip is either
    /// `firestoreId` (the athlete's own uploaded clip a coach annotated) or any of
    /// `VideoClip.allCoachFeedbackVideoIDs` (the coach session clip it was saved
    /// FROM, plus every folder copy it was shared TO). Collapses to one item per
    /// (clip, coach doc) — latest delivery wins — so a clip shared to two coaches
    /// yields one card per coach instead of silently dropping one. Drops any
    /// notification with no matching local clip — feedback on an unsaved
    /// coach-folder clip stays in the folder browser, already badged there.
    ///
    /// `clips` should be the athlete-scoped feed clips; passing another athlete's
    /// clips simply yields no matches, keeping the feed per-active-athlete.
    ///
    /// This is a RECENT-feedback surface, not a complete history: `notifications`
    /// is the listener's most-recent window (currently capped at 50 in
    /// `ActivityNotificationService`), so feedback older than that window won't
    /// carry a feed card even though the clip + its coach feedback still exist.
    @MainActor
    static func resolve(
        notifications: [ActivityNotification],
        clips: [VideoClip]
    ) -> [CoachFeedbackFeedItem] {
        // Index clips by every key a feedback notification can carry.
        var byKey: [String: VideoClip] = [:]
        for clip in clips {
            if let fid = clip.firestoreId { byKey[fid] = clip }
            for id in clip.allCoachFeedbackVideoIDs { byKey[id] = clip }
        }
        guard !byKey.isEmpty else { return [] }

        // Newest-first so the first item kept per clip is the latest feedback.
        let feedback = notifications
            .filter { $0.type == .coachComment && $0.targetType == .video }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }

        // Keyed by (clip, coach doc), not by clip: two coaches on the same clip are
        // two separate pieces of feedback living in two separate Firestore docs, and
        // collapsing per clip dropped whichever arrived second.
        var seenClipDocs = Set<String>()
        var items: [CoachFeedbackFeedItem] = []
        for n in feedback {
            guard let targetID = n.targetID,
                  let notifID = n.id,
                  let clip = byKey[targetID],
                  seenClipDocs.insert("\(clip.id.uuidString)_\(targetID)").inserted else { continue }
            items.append(
                CoachFeedbackFeedItem(
                    notifID: notifID,
                    videoID: targetID,
                    clip: clip,
                    deliveredAt: n.createdAt ?? .distantPast,
                    isRead: n.isRead,
                    coachName: n.senderName,
                    summary: n.displayBody
                )
            )
        }
        return items
    }
}
