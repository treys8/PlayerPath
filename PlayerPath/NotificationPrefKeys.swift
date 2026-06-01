//
//  NotificationPrefKeys.swift
//  PlayerPath
//
//  Centralized UserDefaults keys for notification preference toggles.
//  Every default is `true` (or a numeric default), so a typo'd raw-string key
//  would silently re-enable a notification with no compiler error. Funneling all
//  call sites through these constants removes that whole class of bug.
//  (Coach review-reminder keys live separately in `ReviewReminderKeys`.)
//

import Foundation

enum NotificationPrefKeys {
    /// Weekly "Your Week in Review" summary (athlete). Default on.
    static let weeklyStats = "notif_weeklyStats"
    /// Stale-game "still playing?" reminder. Default on.
    static let staleGameReminders = "notif_staleGameReminders"
    /// Foreground banner for coach activity (comments, drill cards). Default on.
    static let coachActivity = "notif_coachActivity"
    /// Foreground banner for athlete activity (new videos). Default on.
    static let athleteActivity = "notif_athleteActivity"
    /// Pre-game "starts soon" reminder. Default on.
    static let gameReminders = "notif_gameReminders"
    /// Upload-complete notification. Default on.
    static let uploads = "notif_uploads"
    /// Minutes-before-game lead time for the game reminder. Default 30.
    static let gameReminderMinutes = "notif_gameReminderMinutes"
}
