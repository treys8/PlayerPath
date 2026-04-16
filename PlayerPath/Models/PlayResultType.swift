//
//  PlayResultType.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import SwiftUI

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

    var isPitchingResult: Bool {
        rawValue >= 10
    }

    var isBattingResult: Bool {
        rawValue < 10
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
        }
    }

    /// Canonical display color for this play result.
    /// Used by video thumbnails, tagging overlays, and result editor cards.
    var color: Color {
        switch self {
        case .single, .double, .triple, .strike:
            return .green
        case .homeRun:
            return .gold
        case .walk, .pitchingWalk:
            return .cyan
        case .strikeout, .groundOut, .flyOut, .wildPitch, .pitchingStrikeout:
            return .red
        case .batterHitByPitch, .hitByPitch:
            return .purple
        case .ball:
            return .orange
        }
    }

    /// Returns only batting result types for filtering in UI
    static var battingCases: [PlayResultType] {
        allCases.filter { $0.isBattingResult }
    }

    /// Returns only pitching result types for filtering in UI
    static var pitchingCases: [PlayResultType] {
        allCases.filter { $0.isPitchingResult }
    }
}
