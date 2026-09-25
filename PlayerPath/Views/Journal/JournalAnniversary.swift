//
//  JournalAnniversary.swift
//  PlayerPath
//
//  Pure date math for the Journal's "On This Day" card: how close a past date's
//  anniversary is to today. Foundation-only on purpose (no model types), so it
//  can be compiled and checked on its own.
//

import Foundation

struct JournalAnniversary: Equatable {
    let yearsAgo: Int
    /// Days between this year's anniversary of the date and today (0 = exact).
    let dayDistance: Int

    var isExactDay: Bool { dayDistance == 0 }

    /// "On This Day · 1 Year Ago" for an exact match, else "1 Year Ago This Week".
    var title: String {
        let years = yearsAgo == 1 ? "1 Year Ago" : "\(yearsAgo) Years Ago"
        return isExactDay ? "On This Day · \(years)" : "\(years) This Week"
    }

    /// An anniversary within ±3 days of today still counts ("this week"), so
    /// the card isn't limited to rare exact-day hits.
    static let windowDays = 3

    /// nil when `date` is today or later, is the `.distantPast` "undated"
    /// sentinel, or its nearest anniversary is outside the window. Both
    /// neighboring anniversaries are tried, so a date 2 days short of a full
    /// year still matches as "1 year ago this week". Feb 29 lands on Feb 28 in
    /// common years (`Calendar.date(byAdding:)` clamps).
    static func of(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> JournalAnniversary? {
        guard date != .distantPast else { return nil }
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        guard day < today else { return nil }
        let fullYears = calendar.dateComponents([.year], from: day, to: today).year ?? 0
        var best: JournalAnniversary?
        for years in [fullYears, fullYears + 1] where years >= 1 {
            guard let anniversary = calendar.date(byAdding: .year, value: years, to: day),
                  let signed = calendar.dateComponents([.day], from: today, to: anniversary).day
            else { continue }
            let distance = abs(signed)
            guard distance <= windowDays else { continue }
            if best.map({ distance < $0.dayDistance }) ?? true {
                best = JournalAnniversary(yearsAgo: years, dayDistance: distance)
            }
        }
        return best
    }

    /// Local-calendar day key ("2026-09-25") for "hide for today".
    static func dayKey(for now: Date = .now, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
