//
//  NotificationTiming.swift
//  PlayerPath
//
//  Delivery-time rules for local re-engagement nudges. The audience is youth
//  travel ball (weekend tournaments from ~9 AM) and high school athletes
//  (weekday games, in class all morning), so nudges land in the evening:
//  7 PM is never school hours or a morning first pitch, and nothing is sent
//  after 9 PM. Pure date math — no notification or model access.
//

import Foundation

enum NotificationTiming {

    /// Earliest evening delivery hour (24h): 7 PM.
    static let eveningHour = 19
    /// Latest delivery hour (24h): 9 PM. A slot past this rolls to tomorrow.
    static let latestHour = 21

    /// Slot for a post-event nudge: `max(today 7 PM, now + minimumDelay)`. If
    /// that lands after 9 PM, the nudge moves to 7 PM tomorrow. A Saturday
    /// tournament game ending at 11 AM → 7 PM Saturday; a weekday game ending
    /// at 6 PM → 8 PM; a night game ending at 9:30 PM → 7 PM tomorrow.
    static func eveningFireDate(
        after now: Date = Date(),
        minimumDelay: TimeInterval = 2 * 3600,
        calendar: Calendar = .current
    ) -> Date? {
        guard let todayEvening = calendar.date(bySettingHour: eveningHour, minute: 0, second: 0, of: now),
              let todayLatest = calendar.date(bySettingHour: latestHour, minute: 0, second: 0, of: now) else {
            return nil
        }
        let candidate = max(todayEvening, now.addingTimeInterval(minimumDelay))
        if candidate <= todayLatest { return candidate }
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else { return nil }
        return calendar.date(bySettingHour: eveningHour, minute: 0, second: 0, of: tomorrow)
    }

    /// 7 PM local on the day `days` from now.
    static func evening(
        daysFromNow days: Int,
        from now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        guard let day = calendar.date(byAdding: .day, value: days, to: now) else { return nil }
        return calendar.date(bySettingHour: eveningHour, minute: 0, second: 0, of: day)
    }
}
