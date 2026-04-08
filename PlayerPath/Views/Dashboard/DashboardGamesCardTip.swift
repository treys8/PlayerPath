//
//  DashboardGamesCardTip.swift
//  PlayerPath
//
//  Hint shown on the Dashboard "Games" feature card to athletes who have
//  not yet created a game. Gated on gamesCount == 0.
//

import SwiftUI
import TipKit

struct DashboardGamesCardTip: Tip {
    /// Updated from `DashboardView` whenever the current athlete's game count changes.
    /// The rule below gates display on this value being zero.
    @Parameter static var gamesCount: Int = 0

    var title: Text {
        Text("Start here")
    }

    var message: Text? {
        Text("Create a game for your next matchup")
    }

    var image: Image? {
        Image(systemName: "baseball.diamond.bases")
    }

    var rules: [Rule] {
        #Rule(Self.$gamesCount) { $0 == 0 }
    }

    var options: [TipOption] {
        MaxDisplayCount(1)
    }
}
