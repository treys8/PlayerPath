//
//  GolfReelTip.swift
//  PlayerPath
//
//  Hint shown on the first golf highlight reel in the Highlights grid to
//  explain why a hole's clips collapse into one "reel" card. Golf highlights
//  group differently than baseball: a birdie-or-better hole bundles every
//  highlighted shot from that hole into a single reel, so a user who marked
//  several shots sees one card and would otherwise think clips went missing.
//  Gated at the call site to golf athletes and the first reel only.
//

import SwiftUI
import TipKit

struct GolfReelTip: Tip {
    var title: Text {
        Text("Your best holes become reels")
    }

    var message: Text? {
        Text("Birdie-or-better holes bundle every highlighted shot into one reel. Tap to watch them back to back.")
    }

    var image: Image? {
        Image(systemName: "flag.fill")
    }

    var options: [TipOption] {
        MaxDisplayCount(1)
    }
}
