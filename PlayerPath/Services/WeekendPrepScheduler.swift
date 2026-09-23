//
//  WeekendPrepScheduler.swift
//  PlayerPath
//
//  Friday-evening prep nudge for tournament athletes: how much room is left to
//  record, and a reminder to charge. Filling up mid-tournament is the failure a
//  parent filming a whole weekend actually hits, and Saturday 8 AM in a parking
//  lot is too late to find out.
//
//  Deliberately keyed on the athlete's SCHEDULE MODE, not on games being on the
//  calendar: most people create the game at the field, so a version that only
//  fired for pre-scheduled games would almost never fire at all.
//
//  One notification per device (not per athlete) — the storage it reports is the
//  phone's, and a multi-athlete household would otherwise get the same message
//  several times over.
//

import Foundation
import SwiftData
@preconcurrency import UserNotifications

@MainActor
enum WeekendPrepScheduler {

    private static let notifID = "weekend-prep"

    /// Friday. `Calendar` weekdays run 1 = Sunday … 7 = Saturday.
    private static let friday = 6

    /// Re-arm the Friday nudge, or clear it when nobody on the account is in a
    /// tournament season right now. Called on foreground alongside the weekly
    /// summary, so it keeps pace with the season ending or a sport switch.
    static func schedule(for user: User) async {
        PushNotificationService.shared.cancelNotifications(withIdentifiers: [notifID])

        guard UserDefaults.standard.object(forKey: NotificationPrefKeys.weekendPrep) as? Bool ?? true else { return }
        guard !user.isDeleted, user.modelContext != nil else { return }

        // Synchronous model reads, all before the first await.
        let qualifies = (user.athletes ?? []).contains { athlete in
            AthleteScheduleContext.isInSeason(for: athlete)
                && AthleteScheduleContext.mode(for: athlete) == .tournament
        }
        guard qualifies else { return }

        guard let fireDate = NotificationTiming.nextEvening(onWeekday: friday) else { return }
        let interval = fireDate.timeIntervalSinceNow
        guard interval > 0 else { return }

        _ = await PushNotificationService.shared.scheduleLocalNotification(
            identifier: notifID,
            title: "Ready for the weekend?",
            body: bodyText(),
            categoryIdentifier: nil,
            userInfo: ["type": "weekend_prep"],
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        )
    }

    /// Cancel the pending nudge. Used when the toggle is switched off.
    static func cancel() {
        PushNotificationService.shared.cancelNotifications(withIdentifiers: [notifID])
    }

    // MARK: - Private

    /// Storage line + charge reminder. Falls back to the charge half alone when
    /// the volume can't be read — a nudge with no number still beats none.
    private static func bodyText() -> String {
        let charge = "Charge up tonight so you're ready to record."
        guard let info = StorageManager.getStorageInfo() else { return charge }

        let gb = String(format: "%.1f", info.availableGB)
        let minutes = info.estimatedMinutesOfVideo
        guard minutes > 0 else { return "\(gb) GB free. \(charge)" }

        let recordingTime: String
        if minutes >= 60 {
            let hours = minutes / 60
            let remainder = minutes % 60
            recordingTime = remainder == 0 ? "~\(hours)h" : "~\(hours)h \(remainder)m"
        } else {
            recordingTime = "~\(minutes)m"
        }
        return "\(gb) GB free (\(recordingTime) of recording). \(charge)"
    }
}
