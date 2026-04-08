//
//  EmptyStatsTip.swift
//  PlayerPath
//
//  Hint shown on the Stats tab empty state to teach users that statistics
//  are derived from tagged plays in games, not entered manually. Gated on
//  the user already having games — otherwise the games-add tip takes
//  priority and this one would be premature.
//

import SwiftUI
import TipKit

struct EmptyStatsTip: Tip {
    @Parameter static var hasGames: Bool = false

    var title: Text {
        Text("Stats come from plays")
    }

    var message: Text? {
        Text("Tag plays during your games and stats will calculate automatically")
    }

    var image: Image? {
        Image(systemName: "chart.bar.fill")
    }

    var rules: [Rule] {
        #Rule(Self.$hasGames) { $0 == true }
    }

    var options: [TipOption] {
        MaxDisplayCount(1)
    }
}
