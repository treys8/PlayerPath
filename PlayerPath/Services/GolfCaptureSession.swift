//
//  GolfCaptureSession.swift
//  PlayerPath
//
//  Groups "orphan" golf clips — ones recorded with no game or practice context
//  (at the range, or on the course without starting a live round) — into a
//  single Practice for the day. Without this, every clip becomes its own journal
//  entry, so a 100-swing range session floods the feed with 100 cards; the
//  journal already collapses a practice's clips into one entry.
//
//  Called from ClipPersistenceService.saveClip. The session TYPE is chosen by
//  the caller from the current-hole stepper: a hole set means the golfer is on a
//  course → practice round (holes); nil means range work → range session.
//

import Foundation
import SwiftData

enum GolfCaptureSession {
    /// Today's golf session of `type` (`.rangeSession` or `.practiceRound`) for
    /// this athlete in `season`, creating one if none exists yet.
    ///
    /// The session is NOT marked live: recording a clip is not the same as
    /// deliberately starting a live session, so it must not claim the
    /// dashboard's single live-activity slot (see `LiveActivityGuard`).
    @MainActor
    static func todaysSession(
        type: PracticeType,
        for athlete: Athlete,
        season: Season?,
        in context: ModelContext
    ) -> Practice {
        let calendar = Calendar.current

        // Reuse an existing same-day session OF THIS TYPE so a morning's clips
        // don't fragment into many one-clip practices. Keyed by type too, so a
        // day with both range work and a casual round keeps two distinct
        // sessions. Match the season so a clip can't land in a different
        // season's session on a multi-season day. Broken into guards (not one
        // chained boolean) to keep the Swift type-checker fast.
        let isMatch: (Practice) -> Bool = { practice in
            guard practice.practiceType == type.rawValue else { return false }
            guard !practice.isDeletedRemotely else { return false }
            guard practice.season?.id == season?.id else { return false }
            guard let date = practice.date else { return false }
            return calendar.isDateInToday(date)
        }
        if let existing = (athlete.practices ?? []).first(where: isMatch) {
            return existing
        }

        let practice = Practice(date: Date())
        practice.practiceType = type.rawValue
        // Practice rounds carry a hole count (matches the stepper's cap) so
        // later scoring works; range sessions leave it nil.
        if type == .practiceRound {
            practice.holes = GolfCaptureContext.shared.holeCount
        }
        practice.needsSync = true
        context.insert(practice)
        // Set ONLY the to-one side — SwiftData maintains the inverse, so the
        // session still appears in `athlete.practices` (and the reuse check
        // above) without a manual append. Doing BOTH can double-insert it into
        // the to-many array.
        practice.athlete = athlete
        practice.season = season
        return practice
    }
}
