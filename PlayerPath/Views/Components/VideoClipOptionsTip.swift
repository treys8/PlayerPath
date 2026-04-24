//
//  VideoClipOptionsTip.swift
//  PlayerPath
//
//  Hint shown on the first video card to teach users they can
//  long-press for options (share, highlight, upload, delete, etc.).
//

import SwiftUI
import TipKit

struct VideoClipOptionsTip: Tip {
    var title: Text {
        Text("Hold for more options")
    }

    var message: Text? {
        Text("Press and hold any video to share, highlight, upload, and more")
    }

    var image: Image? {
        Image(systemName: "hand.tap")
    }

    var options: [TipOption] {
        MaxDisplayCount(1)
    }
}
