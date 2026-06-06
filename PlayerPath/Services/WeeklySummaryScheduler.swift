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

    /// Plain-value snapshot of one athlete's week, read synchronously off the
    /// SwiftData models so the async scheduling step never touches a model
    /// that may have been deleted in the meantime.
    private struct Summary {
        let athleteId: String
        let gamesThisWeek: Int
        let videosThisWeek: Int
        let battingAverage: Double?
    }

    /// Compute and schedule the weekly summary for a single athlete.
    static func schedule(for athlete: Athlete) async {
        guard weeklyStatsEnabled else { return }
        guard let summary = makeSummary(for: athlete) else { return }
        await send(summary)
    }

    /// Schedule a weekly summary for every athlete on the user.
    /// Multi-athlete households need per-athlete summaries refreshed,
    /// not just the currently selected one.
    static func scheduleAll(for user: User) async {
        guard weeklyStatsEnabled else { return }
        // Snapshot every athlete synchronously *before* any `await`. All the
        // SwiftData reads below run as one uninterrupted main-actor job, so a
        // concurrent delete (Firestore sync, athlete removal) can't invalidate
        // a model between iterations. The previous version awaited the push
        // schedule *between* athletes, and a delete during that suspension left
        // a stale, still-referenced athlete whose `statistics` relationship
        // faulted into a SwiftData assertion → EXC_BREAKPOINT (build 177).
        guard !user.isDeleted, user.modelContext != nil else { return }
        let summaries = (user.athletes ?? []).compactMap { makeSummary(for: $0) }
        // Now do the async scheduling over plain values only — no model access.
        for summary in summaries {
            await send(summary)
        }
    }

    // MARK: - Private

    private static var weeklyStatsEnabled: Bool {
        UserDefaults.standard.object(forKey: NotificationPrefKeys.weeklyStats) as? Bool ?? true
    }

    /// Read every SwiftData-backed value for one athlete into a plain snapshot.
    /// Returns nil if the athlete is no longer a live, attached model — touching
    /// a deleted/detached model's relationships would trap inside SwiftData.
    ///
    /// Window is the 7 days ending at the next Sunday 6 PM fire time, so games
    /// played late in the week are counted correctly.
    private static func makeSummary(for athlete: Athlete) -> Summary? {
        guard !athlete.isDeleted, athlete.modelContext != nil else { return nil }

        let calendar = Calendar.current
        var fireComponents = DateComponents()
        fireComponents.weekday = 1 // Sunday
        fireComponents.hour = 18
        fireComponents.minute = 0
        guard let fireDate = calendar.nextDate(after: Date(), matching: fireComponents, matchingPolicy: .nextTime),
              let windowStart = calendar.date(byAdding: .day, value: -7, to: fireDate) else {
            return nil
        }

        let gameDates = (athlete.games ?? []).compactMap(\.date)
        let videoDates = (athlete.videoClips ?? []).compactMap(\.createdAt)

        let gamesThisWeek = gameDates.filter { $0 >= windowStart && $0 <= fireDate }.count
        let videosThisWeek = videoDates.filter { $0 >= windowStart && $0 <= fireDate }.count

        return Summary(
            athleteId: athlete.id.uuidString,
            gamesThisWeek: gamesThisWeek,
            videosThisWeek: videosThisWeek,
            battingAverage: athlete.statistics?.battingAverage
        )
    }

    private static func send(_ summary: Summary) async {
        await PushNotificationService.shared.scheduleWeeklySummary(
            athleteId: summary.athleteId,
            gamesThisWeek: summary.gamesThisWeek,
            videosThisWeek: summary.videosThisWeek,
            battingAverage: summary.battingAverage
        )
    }
}
