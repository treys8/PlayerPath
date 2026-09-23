//
//  InactivityReminderService.swift
//  PlayerPath
//
//  Behavioral nudge #2: a one-shot "we miss you" local notification scheduled
//  N days out and rescheduled on every app open, so it only ever fires after a
//  genuine stretch away. Cancel-then-reschedule keeps exactly one pending
//  request — naturally capped, weekly cadence, fully local.
//

import Foundation
@preconcurrency import UserNotifications

@MainActor
final class InactivityReminderService {

    static let shared = InactivityReminderService()
    private init() {}

    private static let notifID = "inactivity-reminder"

    /// Days of inactivity before the nudge fires. Weekly cadence per the plan.
    static let inactivityDays = 7

    /// Cancel any pending nudge and (if enabled) schedule a fresh one `inactivityDays`
    /// out. Call on launch and on every foreground — each open pushes the fire
    /// date forward, so an active user never sees it.
    ///
    /// `isInSeason` picks the copy: "log a game" is wrong in December, when a
    /// travel athlete (Feb–Oct) or a high school one (Feb–May) has nothing to
    /// log. Callers compute it with `AthleteScheduleContext.isInSeason(for:)`
    /// BEFORE calling, so no `@Model` is read across this function's awaits.
    func reschedule(isInSeason: Bool = true) async {
        // Always clear the previous one first so a returning user resets the clock
        // (and a disabled toggle leaves nothing pending).
        PushNotificationService.shared.cancelNotifications(withIdentifiers: [Self.notifID])

        let enabled = UserDefaults.standard.object(forKey: NotificationPrefKeys.inactivityReminder) as? Bool ?? true
        guard enabled else { return }

        // 7 PM on the target day (NotificationTiming) rather than the clock time
        // of the last open, so it never lands mid-school-day or late at night.
        guard let fireDate = NotificationTiming.evening(daysFromNow: Self.inactivityDays) else { return }
        let interval = fireDate.timeIntervalSinceNow
        guard interval > 0 else { return }
        _ = await PushNotificationService.shared.scheduleLocalNotification(
            identifier: Self.notifID,
            title: isInSeason ? "We miss you!" : "Ready for next season?",
            body: isInSeason
                ? "It's been a while — log a game, record a clip, or check your stats to keep your progress going."
                : "Off-season is a good time to look back. Check last season's stats or turn your best moments into a highlight reel.",
            categoryIdentifier: nil,
            userInfo: ["type": "inactivity"],
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        )
    }

    /// Cancel the pending inactivity nudge. Used when the toggle is switched off.
    func cancel() {
        PushNotificationService.shared.cancelNotifications(withIdentifiers: [Self.notifID])
    }
}
