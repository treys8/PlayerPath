//
//  VideoClip+DisplayTag.swift
//  PlayerPath
//
//  Sport-agnostic tag helpers so render sites (rows, thumbnails, search,
//  player overlay) don't have to branch on `playResult` vs `club`. A clip
//  has either a `playResult` (baseball/softball) or a `club` (golf), never
//  both — these helpers collapse both into a single accessor.
//

import SwiftUI

extension VideoClip {
    /// Display name of whichever tag this clip carries: club name for golf,
    /// play-result name for baseball/softball, nil if untagged.
    var displayTagName: String? {
        if let club { return club.displayName }
        if let playResult { return playResult.type.displayName }
        return nil
    }

    /// Display color for the tag: club category color for golf, play-result
    /// color for baseball/softball, neutral gray when untagged.
    var displayTagColor: Color {
        if let club { return club.category.color }
        if let playResult { return playResult.type.color }
        return .gray
    }

    /// True when the clip carries either a play result or a club. Used by
    /// the untagged badge / filter so golf clips with a club selected are
    /// treated as tagged.
    var isTagged: Bool {
        playResult != nil || club != nil
    }
}
