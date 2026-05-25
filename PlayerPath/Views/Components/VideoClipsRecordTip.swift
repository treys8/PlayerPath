//
//  VideoClipsRecordTip.swift
//  PlayerPath
//
//  Hint shown on the Videos tab empty state to teach users that game
//  recordings flow into this tab. Gated at the call site on the user
//  already having games so it doesn't fire alongside the games-add
//  onboarding tip.
//

import SwiftUI
import TipKit

struct VideoClipsRecordTip: Tip {
    var title: Text {
        Text("Record from a game")
    }

    var message: Text? {
        Text("Videos you record during games will show up here")
    }

    var image: Image? {
        Image(systemName: "video.fill")
    }

    var options: [TipOption] {
        MaxDisplayCount(1)
    }
}
