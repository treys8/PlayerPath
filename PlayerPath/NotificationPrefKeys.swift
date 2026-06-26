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

    // MARK: - Behavioral re-engagement nudges (all local, opt-out, default on)

    /// "Tag your clips" nudge the morning after a game/round that left untagged
    /// clips behind. Default on.
    static let clipTaggingReminder = "notif_clipTaggingReminder"
    /// "We miss you" inactivity nudge, rescheduled on every app open so it only
    /// fires after a stretch away. Default on.
    static let inactivityReminder = "notif_inactivityReminder"
    /// New personal-best / milestone celebration nudge fired after a game ends.
    /// Default on. (`notif_weeklyStats` above is the weekly-recap nudge.)
    static let milestoneReminder = "notif_milestoneReminder"
}
