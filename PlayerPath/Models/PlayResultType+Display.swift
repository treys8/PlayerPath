//
//  PlayResultType+Display.swift
//  PlayerPath
//

import Foundation

extension PlayResultType {
    var iconName: String {
        switch self {
        case .single: return "1.circle.fill"
        case .double: return "2.circle.fill"
        case .triple: return "3.circle.fill"
        case .homeRun: return "4.circle.fill"
        case .walk: return "figure.walk"
        case .strikeout: return "k.circle.fill"
        case .groundOut: return "arrow.down.circle.fill"
        case .flyOut: return "arrow.up.circle.fill"
        case .batterHitByPitch: return "figure.fall"
        case .ball: return "circle"
        case .strike: return "xmark.circle.fill"
        case .hitByPitch: return "figure.fall"
        case .wildPitch: return "arrow.up.right.and.arrow.down.left"
        case .pitchingStrikeout: return "k.circle.fill"
        case .pitchingWalk: return "figure.walk"
        case .pitchingSingleAllowed: return "1.circle.fill"
        case .pitchingDoubleAllowed: return "2.circle.fill"
        case .pitchingTripleAllowed: return "3.circle.fill"
        case .pitchingHomeRunAllowed: return "4.circle.fill"
        }
    }

    /// Short abbreviation used in badges and compact displays.
    var abbreviation: String {
        switch self {
        case .single: return "1B"
        case .double: return "2B"
        case .triple: return "3B"
        case .homeRun: return "HR"
        case .walk: return "BB"
        case .strikeout: return "K"
        case .groundOut: return "GO"
        case .flyOut: return "FO"
        case .batterHitByPitch: return "HBP"
        case .ball: return "B"
        case .strike: return "S"
        case .hitByPitch: return "HBP"
        case .wildPitch: return "WP"
        case .pitchingStrikeout: return "K"
        case .pitchingWalk: return "BB"
        case .pitchingSingleAllowed: return "1B"
        case .pitchingDoubleAllowed: return "2B"
        case .pitchingTripleAllowed: return "3B"
        case .pitchingHomeRunAllowed: return "HR"
        }
    }

    var accessibilityLabel: String { displayName }
}
