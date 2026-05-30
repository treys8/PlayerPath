//
//  VideoTagEditor+Golf.swift
//  PlayerPath
//
//  Golf-specific drill types and tag suggestions for VideoTagEditor.
//  Selected when the clip being tagged is a golf clip (club/hole present).
//  Mirrors the baseball DrillType / VideoTag taxonomy in VideoTagEditor.swift.
//  drillType is persisted as a String rawValue, so these live alongside the
//  baseball cases without any schema change.
//

import Foundation

enum GolfDrillType: String, CaseIterable {
    case drivingRange = "driving_range"
    case fullSwing = "full_swing"
    case shortGame = "short_game"
    case chipping = "chipping"
    case pitching = "pitching_golf"
    case bunker = "bunker"
    case putting = "putting"
    case coursePlay = "course_play"

    var displayName: String {
        switch self {
        case .drivingRange: return "Driving Range"
        case .fullSwing:    return "Full Swing"
        case .shortGame:    return "Short Game"
        case .chipping:     return "Chipping"
        case .pitching:     return "Pitching"
        case .bunker:       return "Bunker"
        case .putting:      return "Putting"
        case .coursePlay:   return "Course Play"
        }
    }
}

extension VideoTag {
    static let golfSuggestions: [String] = [
        "swing path", "tempo", "contact", "ball flight",
        "alignment", "setup", "follow through", "tee shot",
        "good rep", "needs work", "highlight", "slow-mo"
    ]
}
