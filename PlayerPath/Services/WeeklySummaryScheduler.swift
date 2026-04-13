//
//  WeeklySummaryScheduler.swift
//  PlayerPath
//
//  Computes fresh weekly-summary stats from SwiftData and schedules the
//  "Your Week in Review" local notification. Shared by MainTabView
//  (foreground + event hooks) and NotificationSettingsView (toggle on).
//

import Foundation
import SwiftData

@MainActor
enum WeeklySummaryScheduler {

    /// Compute and schedule the weekly summary for a single athlete.
    /// Window is the 7 days ending at the next Sunday 6 PM fire time,
    /// so games played late in the week are counted correctly.
    static func schedule(for athlete: Athlete) async {
        guard UserDefaults.standard.object(forKey: "notif_weeklyStats") as? Bool ?? true else { return }

        let calendar = Calendar.current
        var fireComponents = DateComponents()
        fireComponents.weekday = 1 // Sunday
        fireComponents.hour = 18
        fireComponents.minute = 0
        guard let fireDate = calendar.nextDate(after: Date(), matching: fireComponents, matchingPolicy: .nextTime),
              let windowStart = calendar.date(byAdding: .day, value: -7, to: fireDate) else {
            return
        }

        let gameDates = (athlete.games ?? []).compactMap(\.date)
        let videoDates = (athlete.videoClips ?? []).compactMap(\.createdAt)

        let gamesThisWeek = gameDates.filter { $0 >= windowStart && $0 <= fireDate }.count
        let videosThisWeek = videoDates.filter { $0 >= windowStart && $0 <= fireDate }.count
        let avg = athlete.statistics?.battingAverage

        await PushNotificationService.shared.scheduleWeeklySummary(
            athleteId: athlete.id.uuidString,
            gamesThisWeek: gamesThisWeek,
            videosThisWeek: videosThisWeek,
            battingAverage: avg
        )
    }

    /// Schedule a weekly summary for every athlete on the user.
    /// Multi-athlete households need per-athlete summaries refreshed,
    /// not just the currently selected one.
    static func scheduleAll(for user: User) async {
        for athlete in user.athletes ?? [] {
            await schedule(for: athlete)
        }
    }
}
