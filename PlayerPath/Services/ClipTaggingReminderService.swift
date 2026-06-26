//
//  ClipTaggingReminderService.swift
//  PlayerPath
//
//  Behavioral nudge #1: after a game/round ends with untagged clips, schedule a
//  one-shot local notification for the next morning reminding the athlete to tag
//  them so stats + highlights stay accurate. Mirrors `GameAlertService`'s
//  conditional-scheduling template — fully local (no Firestore, no badge feed).
//
//  Dedup: per-event identifier `clip-tagging-<eventID>`. Coalesce: at most one
//  clip-tag nudge per target morning, app-wide, via a "last target day" stamp —
//  so a multi-game day produces one nudge, not three.
//

import Foundation
@preconcurrency import UserNotifications

@MainActor
final class ClipTaggingReminderService {

    static let shared = ClipTaggingReminderService()
    private init() {}

    /// Shared identifier prefix so the settings toggle can cancel every pending
    /// clip-tag nudge by scanning for this prefix.
    static let idPrefix = "clip-tagging-"

    /// Hour of the morning the nudge fires (24h). Lives here as the single tunable
    /// — a reviewer can drop it to a near-future minute to verify delivery.
    private static let fireHour = 9

    /// UserDefaults stamp of the last morning we already queued a clip-tag nudge
    /// for. Drives the one-app-wide-nudge-per-day coalesce.
    private static let lastTargetDayKey = "notif_clipTagNudgeLastTargetDay"

    /// Schedule the nudge if the just-ended event left untagged clips. The caller
    /// MUST snapshot model values to plain values BEFORE calling — nothing here
    /// touches a `@Model` (a concurrent delete during the await would otherwise
    /// trap).
    /// - Parameters:
    ///   - eventID: the Game or Practice id, for the dedup identifier.
    ///   - untaggedCount: number of untagged, athlete-owned clips on the event.
    ///   - eventNoun: "game" or "round", for the body copy.
    func scheduleIfNeeded(eventID: UUID, untaggedCount: Int, eventNoun: String) async {
        guard untaggedCount > 0 else { return }

        // Opt-out toggle: a missing key means the user hasn't opted out → on.
        let enabled = UserDefaults.standard.object(forKey: NotificationPrefKeys.clipTaggingReminder) as? Bool ?? true
        guard enabled else { return }

        guard let fireDate = Self.nextMorning() else { return }
        let targetDay = Self.dayStamp(fireDate)

        // Coalesce: if we already queued a clip-tag nudge for this morning, stop.
        if UserDefaults.standard.string(forKey: Self.lastTargetDayKey) == targetDay { return }
        // Reserve the day SYNCHRONOUSLY before the await below so a second
        // near-simultaneous end() (e.g. a doubleheader: end round 1, immediately
        // end round 2) sees the reservation and coalesces instead of racing past
        // the check. Rolled back if the schedule ultimately fails.
        UserDefaults.standard.set(targetDay, forKey: Self.lastTargetDayKey)

        let center = UNUserNotificationCenter.current()
        let notifID = Self.idPrefix + eventID.uuidString

        // Per-event dedup — never double-schedule for the same game/round.
        let pending = await center.pendingNotificationRequests()
        guard !pending.contains(where: { $0.identifier == notifID }) else { return }

        let interval = fireDate.timeIntervalSinceNow
        guard interval > 0 else { return }

        // Count-agnostic copy: a local notification can't re-check the untagged
        // count at fire time, so naming an exact N risks being wrong if the
        // athlete tags clips before it fires.
        let body = "Some clips from your latest \(eventNoun) still need tags. Add tags so your stats and highlights stay accurate."

        let scheduled = await PushNotificationService.shared.scheduleLocalNotification(
            identifier: notifID,
            title: "Tag your clips 🎬",
            body: body,
            categoryIdentifier: "TAG_CLIPS",
            userInfo: ["type": "clip_tagging"],
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        )

        // Roll back the day reservation if nothing landed (e.g. notifications
        // unauthorized) so a later authorized event can still schedule one.
        if !scheduled {
            UserDefaults.standard.removeObject(forKey: Self.lastTargetDayKey)
        }
    }

    /// Cancel every pending clip-tag nudge. Used when the toggle is switched off.
    /// Also clears the coalesce stamp so re-enabling the same day can reschedule.
    func cancelAll() async {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { $0.hasPrefix(Self.idPrefix) }
        if !ids.isEmpty {
            PushNotificationService.shared.cancelNotifications(withIdentifiers: ids)
        }
        UserDefaults.standard.removeObject(forKey: Self.lastTargetDayKey)
    }

    /// After a clip is (re)tagged, cancel the per-event nudge once its parent
    /// game/practice has no untagged, athlete-owned clips left. Stays SYNCHRONOUS
    /// (model reads only, no await) so callers pass a live `@Model` with no
    /// concurrent-delete trap; the coalesce-stamp reconcile is fired separately.
    func cancelIfEventFullyTagged(for clip: VideoClip) {
        func remaining(_ clips: [VideoClip]?) -> Int {
            (clips ?? []).filter { !$0.isTagged && !$0.isDeletedRemotely && $0.sourceCoachVideoID == nil }.count
        }
        let eventID: UUID?
        if let game = clip.game, remaining(game.videoClips) == 0 {
            eventID = game.id
        } else if let practice = clip.practice, remaining(practice.videoClips) == 0 {
            eventID = practice.id
        } else {
            eventID = nil
        }
        guard let eventID else { return }
        cancelNudge(eventID: eventID)
    }

    /// Remove a single event's pending clip-tag nudge — for tag-save (fully
    /// tagged) and deletion paths. Synchronous; fires an async stamp reconcile so
    /// a later same-day event can re-arm if this freed the day's only nudge.
    func cancelNudge(eventID: UUID) {
        PushNotificationService.shared.cancelNotifications(withIdentifiers: [Self.idPrefix + eventID.uuidString])
        Task { await reconcileCoalesceStamp() }
    }

    /// Clear the one-nudge-per-day coalesce stamp when no clip-tag nudge remains
    /// pending. Without this, cancelling the day's reserved nudge would leave the
    /// stamp set and wedge every later same-day event into coalescing with
    /// nothing scheduled. Touches only UserDefaults + pending requests — no model.
    private func reconcileCoalesceStamp() async {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        if !pending.contains(where: { $0.identifier.hasPrefix(Self.idPrefix) }) {
            UserDefaults.standard.removeObject(forKey: Self.lastTargetDayKey)
        }
    }

    // MARK: - Helpers

    /// The next occurrence of `fireHour:00` strictly after now (today if it's
    /// still before the hour, otherwise tomorrow).
    private static func nextMorning() -> Date? {
        var comps = DateComponents()
        comps.hour = fireHour
        comps.minute = 0
        return Calendar.current.nextDate(after: Date(), matching: comps, matchingPolicy: .nextTime)
    }

    /// A calendar-day key ("2026-6-25") used to coalesce nudges by target morning.
    private static func dayStamp(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
}
