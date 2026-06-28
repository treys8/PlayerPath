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

// `GolfDrillType` moved to Models/DrillType.swift (shared with athlete practice
// logging). Still referenced here by the same name.

extension VideoTag {
    static let golfSuggestions: [String] = [
        "swing path", "tempo", "contact", "ball flight",
        "alignment", "setup", "follow through", "tee shot",
        "good rep", "needs work", "highlight", "slow-mo"
    ]
}
