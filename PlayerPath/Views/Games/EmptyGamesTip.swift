//
//  EmptyGamesTip.swift
//  PlayerPath
//
//  Hint shown on the Games tab empty state's "Add Game" button.
//  EmptyGamesView only renders when the athlete has zero games, so the
//  empty-state context is implicit — no display rule is required beyond
//  TipKit's built-in "show once" datastore.
//

import SwiftUI
import TipKit

struct EmptyGamesTip: Tip {
    var title: Text {
        Text("Create your first game")
    }

    var message: Text? {
        Text("Start tracking at-bats and plays")
    }

    var image: Image? {
        Image(systemName: "baseball.diamond.bases")
    }
}
