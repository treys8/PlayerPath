//
//  GolfPreferences.swift
//  PlayerPath
//
//  Shared keys for golf-scoring user preferences (UserDefaults / @AppStorage).
//  Kept in one place so the scorecard, the single-hole sheet, and Settings all
//  read/write the same key without string drift.
//

import Foundation

enum GolfPrefs {
    /// When true, scoring surfaces reveal optional fairway / green / penalty
    /// inputs. Default false — casual scorers keep the score + putts fast path,
    /// which is the "optional for users" guarantee.
    static let trackDetailedStats = "golf.trackDetailedStats"

    /// Remembered default scoring mode for new golf holes. When true, tapping
    /// "Score Hole" opens the shot-by-shot card by default; when false it opens
    /// quick entry. Set by the in-sheet Quick / Shot-by-shot switch so a
    /// shot-tracker doesn't re-pick every round, and seeded into a round's
    /// `tracksShotByShot` at creation. Default false.
    static let preferredShotByShot = "golf.preferredShotByShot"
}
