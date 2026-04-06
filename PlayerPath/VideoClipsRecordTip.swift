//
//  VideoClipsRecordTip.swift
//  PlayerPath
//
//  Hint shown on the Videos tab empty state to teach users that game
//  recordings flow into this tab. Gated on the user already having games
//  so it doesn't fire alongside the games-add onboarding tip.
//

import SwiftUI
import TipKit

struct VideoClipsRecordTip: Tip {
    @Parameter static var hasGames: Bool = false

    var title: Text {
        Text("Record from a game")
    }

    var message: Text? {
        Text("Videos you record during games will show up here")
    }

    var image: Image? {
        Image(systemName: "video.fill")
    }

    var rules: [Rule] {
        #Rule(Self.$hasGames) { $0 == true }
    }
}
