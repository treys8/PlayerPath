//
//  EmptyStatsTip.swift
//  PlayerPath
//
//  Hint shown on the Stats tab empty state to teach users that statistics
//  are derived from tagged plays in games, not entered manually. Gated at
//  the call site on the user already having games — otherwise the games-add
//  tip takes priority and this one would be premature.
//

import SwiftUI
import TipKit

struct EmptyStatsTip: Tip {
    var title: Text {
        Text("Stats come from plays")
    }

    var message: Text? {
        Text("Tag plays during your games and stats will calculate automatically")
    }

    var image: Image? {
        Image(systemName: "chart.bar.fill")
    }

    var options: [TipOption] {
        MaxDisplayCount(1)
    }
}
