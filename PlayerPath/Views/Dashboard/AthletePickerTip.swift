//
//  AthletePickerTip.swift
//  PlayerPath
//
//  Teaches new users that the dashboard nav bar hosts their athlete
//  profile switcher. Shown once, no gating rules.
//

import SwiftUI
import TipKit

struct AthletePickerTip: Tip {
    var title: Text {
        Text("Switch athletes")
    }

    var message: Text? {
        Text("All your athlete profiles live here")
    }

    var image: Image? {
        Image(systemName: "person.2.fill")
    }

    var options: [TipOption] {
        MaxDisplayCount(1)
    }
}
