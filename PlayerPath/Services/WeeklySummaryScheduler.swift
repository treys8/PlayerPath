//
//  WeeklySummaryScheduler.swift
//  PlayerPath
//
//  Computes fresh weekly-summary stats from SwiftData and schedules the
//  "Your Week in Review" local notification. Shared by MainTabView
//  (foreground + event hooks) and NotificationSettingsView (toggle on).
//
//  Sport-aware: a golf athlete gets rounds + best score, not games + batting
//  average. The copy is built HERE rather than in PushNotificationService,
//  matching ClipTaggingReminderService / InactivityReminderService — the domain
//  service owns the wording because it is the only layer that knows the sport.
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
        let isGolf: Bool
        /// Games in the window. For golf these ARE rounds — a golf `Game` is a
        /// round — so the same count carries both sports.
        let eventsThisWeek: Int
        /// GOLF ONLY: practices in the window (practice rounds + range
        /// sessions). Golf practice is real scored work, so a golfer who only
        /// practised must not be told "no rounds logged this week". Stays 0 for
        /// baseball/softball, where a practice isn't a game.
        let golfPracticeSessions: Int
        let videosThisWeek: Int
        /// BASEBALL/SOFTBALL ONLY: pre-formatted at snapshot time so this struct
        /// stays a pure value — nothing here reaches back into a service or a
        /// `@Model` after the snapshot.
        let battingAverageText: String?
        /// GOLF ONLY: best fully-scored round in the window, with its to-par
        /// when the round carries par data.
        let bestGolfScore: Int?
        let bestGolfToPar: Int?

        /// Notification body. Pure string building over the snapshot, so it is
        /// safe to read after an await.
        var body: String { isGolf ? golfBody : ballBody }

        private var golfBody: String {
            if eventsThisWeek > 0 {
                let rounds = "\(eventsThisWeek) round\(eventsThisWeek == 1 ? "" : "s")"
                guard let score = bestGolfScore else {
                    return "You logged \(rounds) this week. Open the app to see your stats!"
                }
                let best = bestGolfToPar.map { "\(score) (\(Self.toParText($0)))" } ?? "\(score)"
                return "You logged \(rounds) this week. Best: \(best). Keep it up!"
            }
            if golfPracticeSessions > 0 {
                let sessions = "\(golfPracticeSessions) practice session\(golfPracticeSessions == 1 ? "" : "s")"
                return "You logged \(sessions) this week. Keep the work going!"
            }
            if videosThisWeek > 0 { return Self.videoText(videosThisWeek) }
            return "No rounds logged this week. Record your next round to keep your stats up to date!"
        }

        private var ballBody: String {
            if eventsThisWeek > 0 {
                let games = "\(eventsThisWeek) game\(eventsThisWeek == 1 ? "" : "s")"
                if let avg = battingAverageText {
                    return "You logged \(games) this week. Batting \(avg). Keep it up!"
                }
                return "You logged \(games) this week. Open the app to see your stats!"
            }
            if videosThisWeek > 0 { return Self.videoText(videosThisWeek) }
            return "No games logged this week. Record your next game to keep your stats up to date!"
        }

        private static func videoText(_ count: Int) -> String {
            "You recorded \(count) video\(count == 1 ? "" : "s") this week. Review your clips and track your progress!"
        }

        /// "E" / "+3" / "-2" — same convention as `GolfRoundRow.toParString`.
        private static func toParText(_ toPar: Int) -> String {
            if toPar == 0 { return "E" }
            return toPar > 0 ? "+\(toPar)" : "\(toPar)"
        }
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

        func inWindow(_ date: Date?) -> Bool {
            guard let date else { return false }
            return date >= windowStart && date <= fireDate
        }

        // Sport comes from the athlete row, not `activeSeason` — a profile is
        // pinned to one sport (a two-sport person is two linked rows), and the
        // pinned value is right even between seasons.
        let isGolf = athlete.sportType == .golf

        let games = athlete.games ?? []
        let eventsThisWeek = games.filter { inWindow($0.date) }.count
        let videosThisWeek = (athlete.videoClips ?? []).compactMap(\.createdAt)
            .filter { $0 >= windowStart && $0 <= fireDate }.count

        var battingAverageText: String?
        if !isGolf, let avg = athlete.statistics?.battingAverage, avg > 0 {
            battingAverageText = StatisticsService.shared.formatBattingAverage(avg)
        }

        // Golf extras, computed inside this synchronous snapshot so the async
        // scheduling step below never touches a `@Model`.
        var golfPracticeSessions = 0
        var bestGolfScore: Int?
        var bestGolfToPar: Int?
        if isGolf {
            // Every practice on a golf profile is golf work (practice round or
            // range session), so no type filter is needed here.
            golfPracticeSessions = (athlete.practices ?? []).filter { inWindow($0.date) }.count

            // `isGolfRoundScored` keeps a partial round (3 of 18 holes, then
            // ended) out of the headline, and `effectivePar` is deliberately
            // paired with `effectiveTotalScore` so to-par covers the same holes.
            let scoredRounds: [(score: Int, toPar: Int?)] = games
                .filter { inWindow($0.date) && !$0.isLive && $0.isGolfRoundScored }
                .compactMap { game -> (score: Int, toPar: Int?)? in
                    guard let score = game.effectiveTotalScore else { return nil }
                    return (score, game.effectivePar.map { score - $0 })
                }
            if let best = scoredRounds.min(by: { $0.score < $1.score }) {
                bestGolfScore = best.score
                bestGolfToPar = best.toPar
            }
        }

        return Summary(
            athleteId: athlete.id.uuidString,
            isGolf: isGolf,
            eventsThisWeek: eventsThisWeek,
            golfPracticeSessions: golfPracticeSessions,
            videosThisWeek: videosThisWeek,
            battingAverageText: battingAverageText,
            bestGolfScore: bestGolfScore,
            bestGolfToPar: bestGolfToPar
        )
    }

    private static func send(_ summary: Summary) async {
        await PushNotificationService.shared.scheduleWeeklySummary(
            athleteId: summary.athleteId,
            body: summary.body
        )
    }
}
