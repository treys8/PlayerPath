//
//  LayoutModeTip.swift
//  PlayerPath
//
//  Hint shown on the photos grid toolbar button to teach users they
//  can switch between card and dense grid layouts.
//

import SwiftUI
import TipKit

struct LayoutModeTip: Tip {
    var title: Text {
        Text("Switch grid layout")
    }

    var message: Text? {
        Text("Tap to toggle between roomy cards and a dense grid")
    }

    var image: Image? {
        Image(systemName: "square.grid.3x3.fill")
    }

    var options: [TipOption] {
        MaxDisplayCount(1)
    }
}
