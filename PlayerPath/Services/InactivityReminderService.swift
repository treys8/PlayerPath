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
    func reschedule() async {
        // Always clear the previous one first so a returning user resets the clock
        // (and a disabled toggle leaves nothing pending).
        PushNotificationService.shared.cancelNotifications(withIdentifiers: [Self.notifID])

        let enabled = UserDefaults.standard.object(forKey: NotificationPrefKeys.inactivityReminder) as? Bool ?? true
        guard enabled else { return }

        let interval = TimeInterval(Self.inactivityDays * 24 * 3600)
        _ = await PushNotificationService.shared.scheduleLocalNotification(
            identifier: Self.notifID,
            title: "We miss you!",
            body: "It's been a while — log a game, record a clip, or check your stats to keep your progress going.",
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
