//
//  Milestone.swift
//  PlayerPath
//
//  A computed "this mattered" moment in a season — first home run, a hot
//  streak, a personal-low golf round. PLAIN struct, intentionally NOT a
//  SwiftData @Model: milestones are derived on the fly by `MilestoneEngine`
//  from existing Games/PlayResults/HoleScores and are never persisted. No
//  Firestore field, no schema version — recomputed from source data each time.
//
//  Surfaced by the UI through `PPMilestoneMarker` (the accent star + overline)
//  and the auto-headline rule. Never derived from `runs`/`rbis`.
//

import Foundation

struct Milestone: Identifiable, Hashable {

    /// Drives the small-caps overline shown by `PPMilestoneMarker`.
    enum Kind: String {
        case seasonFirst   = "Season First"
        case personalBest  = "Personal Best"
        case streak        = "Hot Streak"
        case milestone     = "Milestone"

        /// Uppercased overline label ("SEASON FIRST").
        var markerLabel: String { rawValue.uppercased() }
    }

    /// Stable identity so the same milestone dedupes across recomputes.
    let id: String
    let kind: Kind
    /// One-line milestone sentence, e.g. "First home run of the season".
    let title: String
    /// Optional context line, e.g. "vs Tigers · May 12".
    let detail: String?
    /// When it happened — used for feed ordering and headline priority.
    let date: Date
    /// The Game this milestone is linked to, when one exists (for the clip /
    /// row star marker). Nil for season-spanning count milestones.
    let gameID: UUID?

    var markerLabel: String { kind.markerLabel }
}
