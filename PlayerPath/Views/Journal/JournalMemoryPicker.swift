//
//  JournalMemoryPicker.swift
//  PlayerPath
//
//  Chooses the one past Journal entry worth resurfacing today ("On This Day").
//

import Foundation

struct JournalMemory {
    let entry: JournalEntry
    let anniversary: JournalAnniversary
}

enum JournalMemoryPicker {
    /// The best entry whose anniversary is within the window, or nil.
    ///
    /// Candidates come from the built feed (already sport-scoped, with no live
    /// or scheduled rows). Coach-feedback cards are skipped: their date is when
    /// the feedback arrived, not a moment from the athlete's past. Ranking:
    /// exact day, then nearer day, then contains a highlight, then more media,
    /// then the most recent year. Ties keep feed order (newest first), which is
    /// deterministic. The media walk runs only for date-matched candidates, a
    /// handful at most.
    static func pick(from feed: [JournalEntry], now: Date = .now, calendar: Calendar = .current) -> JournalMemory? {
        var best: (memory: JournalMemory, rank: (Int, Int, Int, Int, Int))?
        for entry in feed {
            if case .coachFeedback = entry { continue }
            guard let anniversary = JournalAnniversary.of(entry.date, now: now, calendar: calendar) else { continue }
            let summary = entry.mediaSummary
            let rank = (
                anniversary.isExactDay ? 1 : 0,
                -anniversary.dayDistance,
                entry.containsHighlight ? 1 : 0,
                summary.clipCount + summary.photoCount,
                -anniversary.yearsAgo
            )
            if let current = best, !(current.rank < rank) { continue }
            best = (JournalMemory(entry: entry, anniversary: anniversary), rank)
        }
        return best?.memory
    }
}
