//
//  PlayResultType.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import SwiftUI

/// Whether a play result was good, neutral, or bad for the recording athlete.
/// The single source of truth for outcome sentiment — drives feed de-emphasis of
/// negatives and keeps `PlayResultType.color` honest about good/bad outcomes.
enum PlayValence {
    case positive
    case neutral
    case negative
}

enum PlayResultType: Int, CaseIterable, Codable {
    // Batting results
    case single = 0
    case double = 1
    case triple = 2
    case homeRun = 3
    case walk = 4
    case strikeout = 5
    case groundOut = 6
    case flyOut = 7
    case batterHitByPitch = 8

    // Pitching results
    case ball = 10
    case strike = 11
    case hitByPitch = 12
    case wildPitch = 13
    case pitchingStrikeout = 14
    case pitchingWalk = 15

    // Pitcher-perspective hits allowed — cosmetic clip labels only.
    // Do not accumulate into the athlete's batting counters.
    case pitchingSingleAllowed = 16
    case pitchingDoubleAllowed = 17
    case pitchingTripleAllowed = 18
    case pitchingHomeRunAllowed = 19

    var isPitchingResult: Bool {
        rawValue >= 10
    }

    var isBattingResult: Bool {
        rawValue < 10
    }

    /// True for pitcher-side hit-allowed labels that don't contribute to stats.
    var isHitAllowed: Bool {
        switch self {
        case .pitchingSingleAllowed, .pitchingDoubleAllowed, .pitchingTripleAllowed, .pitchingHomeRunAllowed:
            return true
        default:
            return false
        }
    }

    var isHit: Bool {
        switch self {
        case .single, .double, .triple, .homeRun:
            return true
        default:
            return false
        }
    }

    /// Determines if this result counts as an official at-bat
    /// Baseball rules: Walks, HBP, sac flies, and sac bunts do NOT count as at-bats
    var countsAsAtBat: Bool {
        switch self {
        case .walk, .hitByPitch, .batterHitByPitch:
            return false // Walks and HBP don't count as at-bats
        case .single, .double, .triple, .homeRun, .strikeout, .groundOut, .flyOut:
            return true // Hits and outs count as at-bats
        default:
            return false // Pitching results don't count as at-bats
        }
    }

    var isHighlight: Bool {
        switch self {
        case .single, .double, .triple, .homeRun:
            return true
        default:
            return false
        }
    }

    var bases: Int {
        switch self {
        case .single: return 1
        case .double: return 2
        case .triple: return 3
        case .homeRun: return 4
        default: return 0
        }
    }

    var displayName: String {
        switch self {
        case .single: return "Single"
        case .double: return "Double"
        case .triple: return "Triple"
        case .homeRun: return "Home Run"
        case .walk: return "Walk"
        case .strikeout: return "Strikeout"
        case .groundOut: return "Ground Out"
        case .flyOut: return "Fly Out"
        case .batterHitByPitch: return "Hit By Pitch"
        case .ball: return "Ball"
        case .strike: return "Strike"
        case .hitByPitch: return "Hit By Pitch"
        case .wildPitch: return "Wild Pitch"
        case .pitchingStrikeout: return "Strikeout"
        case .pitchingWalk: return "Walk"
        case .pitchingSingleAllowed: return "Single"
        case .pitchingDoubleAllowed: return "Double"
        case .pitchingTripleAllowed: return "Triple"
        case .pitchingHomeRunAllowed: return "Home Run"
        }
    }

    /// Canonical display color for this play result.
    /// Used by video thumbnails, tagging overlays, and result editor cards.
    ///
    /// Color reads from the **recording athlete's** perspective (see `valence`),
    /// NOT the abstract play type. That's why a pitcher's strikeout is green
    /// (good) while every hit/HR *allowed* is red (bad) — even though the same
    /// play is green/gold when a batter records it.
    var color: Color {
        switch self {
        // Positives that read green: batting hits, a pitcher's called strike,
        // and a pitcher's strikeout (a good outcome for the pitcher).
        case .single, .double, .triple, .strike, .pitchingStrikeout:
            return .green
        // The marquee positive — a batter's home run. (A HR *allowed* is a
        // pitcher negative and lives in the red group below, not here.)
        case .homeRun:
            return .gold
        // Batter reaching on a walk — positive, but not a hit.
        case .walk:
            return .cyan
        // Negatives → red. Batter: outs/strikeouts. Pitcher (POV): walk allowed,
        // wild pitch, and every hit/HR allowed.
        case .strikeout, .groundOut, .flyOut, .wildPitch, .pitchingWalk,
             .pitchingSingleAllowed, .pitchingDoubleAllowed, .pitchingTripleAllowed,
             .pitchingHomeRunAllowed:
            return .red
        // Hit-by-pitch (either side) — a special incident.
        case .batterHitByPitch, .hitByPitch:
            return .purple
        case .ball:
            return .orange
        }
    }

    /// Outcome sentiment from the recording athlete's point of view.
    ///
    /// Note: `groundOut`/`flyOut` are shared by the batter editor (out =
    /// negative) and the pitcher editor (induced out = positive for the
    /// pitcher). A clip stores no role flag to disambiguate, so these use the
    /// batter framing (`negative`), which also matches their red `color`.
    var valence: PlayValence {
        switch self {
        case .single, .double, .triple, .homeRun, .walk, .batterHitByPitch,
             .strike, .pitchingStrikeout:
            return .positive
        case .ball:
            return .neutral
        case .strikeout, .groundOut, .flyOut, .wildPitch, .hitByPitch, .pitchingWalk,
             .pitchingSingleAllowed, .pitchingDoubleAllowed, .pitchingTripleAllowed,
             .pitchingHomeRunAllowed:
            return .negative
        }
    }

    /// Returns only batting result types for filtering in UI
    static var battingCases: [PlayResultType] {
        allCases.filter { $0.isBattingResult }
    }

    /// Returns only pitching result types for filtering in UI.
    /// Excludes hit-allowed labels so the manual stats picker isn't cluttered with no-op entries.
    static var pitchingCases: [PlayResultType] {
        allCases.filter { $0.isPitchingResult && !$0.isHitAllowed }
    }
}
