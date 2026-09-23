//
//  AthleteScheduleContext.swift
//  PlayerPath
//
//  Answers two questions about an athlete's calendar that notification copy and
//  timing depend on: are they in season right now, and do they play a weekend
//  tournament schedule or a weekday school schedule?
//
//  Derived from behavior (when their recent games actually happened) rather than
//  asked at signup: one person is often both — school ball Feb–May, then travel
//  ball through the summer and fall — so the answer changes across the year and
//  a stored "level" would go stale. `Season.seasonType` is the fallback when
//  there isn't enough game history to tell.
//
//  All reads are synchronous SwiftData property reads, so callers can snapshot a
//  result before any await (the concurrent-delete rule).
//

import Foundation
import SwiftData

enum AthleteScheduleMode {
    /// Weekend tournaments — games cluster on Sat/Sun, often starting ~9 AM.
    case tournament
    /// School ball — games on weekday afternoons/evenings.
    case school
    /// Not enough signal. Callers use neutral timing.
    case unknown
}

@MainActor
enum AthleteScheduleContext {

    /// How many recent games to judge the pattern from.
    private static let recentGameSample = 6
    /// Fewer than this many played games and we don't guess from behavior.
    private static let minimumGamesForPattern = 3
    /// A game this recently means the athlete is active even with no active season.
    private static let recentPlayWindowDays = 30

    /// Whether the athlete is currently in season. True when an active season
    /// spans today, or (for users who don't keep season dates tidy) when they
    /// played within the last 30 days.
    static func isInSeason(for athlete: Athlete, now: Date = Date()) -> Bool {
        guard !athlete.isDeleted, athlete.modelContext != nil else { return false }

        if let season = athlete.activeSeason, !season.isDeleted {
            let startedAlready = (season.startDate ?? .distantPast) <= now
            // A nil endDate means open-ended, matching Season's own convention.
            let notEndedYet = season.endDate.map { $0 >= now } ?? true
            if startedAlready && notEndedYet { return true }
        }

        guard let cutoff = Calendar.current.date(byAdding: .day, value: -recentPlayWindowDays, to: now) else {
            return false
        }
        return (athlete.games ?? []).contains { game in
            guard let date = game.date else { return false }
            return date >= cutoff && date <= now
        }
    }

    /// True when ANY athlete on the account is in season. A household with a
    /// baseball player mid-season and a sibling between seasons is still an
    /// in-season household — the nudge is per device, not per profile.
    static func isAnyAthleteInSeason(for user: User, now: Date = Date()) -> Bool {
        guard !user.isDeleted, user.modelContext != nil else { return false }
        return (user.athletes ?? []).contains { isInSeason(for: $0, now: now) }
    }

    /// Sat 00:00 through Sun 23:59 of the weekend `now` sits in (or, on a
    /// weekday, the weekend just past). Anchored on the most recent Saturday.
    static func currentWeekendRange(now: Date = Date(), calendar: Calendar = .current) -> (start: Date, end: Date)? {
        let startOfToday = calendar.startOfDay(for: now)
        // weekday: 1 = Sunday … 7 = Saturday, so `% 7` maps Sat → 0, Sun → 1,
        // Mon → 2 … Fri → 6: exactly the days back to the most recent Saturday.
        let weekday = calendar.component(.weekday, from: startOfToday)
        let daysSinceSaturday = weekday % 7
        guard let saturday = calendar.date(byAdding: .day, value: -daysSinceSaturday, to: startOfToday),
              let monday = calendar.date(byAdding: .day, value: 2, to: saturday) else { return nil }
        return (saturday, monday)
    }

    /// Games played on the current weekend. Two or more is the tournament-weekend
    /// signal: travel ball runs pool play into bracket play, so a real tournament
    /// leaves several games behind, while a one-off Saturday game does not.
    static func weekendGameCount(for athlete: Athlete, now: Date = Date()) -> Int {
        guard !athlete.isDeleted, athlete.modelContext != nil else { return 0 }
        guard let range = currentWeekendRange(now: now) else { return 0 }
        var count = 0
        for game in athlete.games ?? [] {
            guard let date = game.date, date >= range.start, date < range.end, date <= now else { continue }
            count += 1
        }
        return count
    }

    /// True when this weekend already looks like a tournament.
    static func isTournamentWeekend(for athlete: Athlete, now: Date = Date()) -> Bool {
        weekendGameCount(for: athlete, now: now) >= 2
    }

    /// The athlete's current schedule pattern, from their last few played games,
    /// falling back to the active season's `seasonType`.
    static func mode(for athlete: Athlete, now: Date = Date()) -> AthleteScheduleMode {
        guard !athlete.isDeleted, athlete.modelContext != nil else { return .unknown }

        // Split into steps: the single chained expression tripped the type
        // checker's time limit.
        let games: [Game] = athlete.games ?? []
        var playedDates: [Date] = []
        for game in games {
            guard let date = game.date, date <= now else { continue }
            playedDates.append(date)
        }
        playedDates.sort(by: >)
        let played = Array(playedDates.prefix(recentGameSample))

        if played.count >= minimumGamesForPattern {
            let calendar = Calendar.current
            let weekendCount = played.filter { calendar.isDateInWeekend($0) }.count
            let weekendShare = Double(weekendCount) / Double(played.count)
            // Deliberately leaves a dead band in the middle: a genuinely mixed
            // schedule falls through to the season type rather than being forced
            // into a bucket it only half fits.
            if weekendShare >= 0.6 { return .tournament }
            if weekendShare <= 0.4 { return .school }
        }

        switch athlete.activeSeason?.seasonTypeValue {
        case .travel, .tournament: return .tournament
        case .school:              return .school
        default:                   return .unknown
        }
    }
}
