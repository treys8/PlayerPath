//
//  PhotoOptionsTip.swift
//  PlayerPath
//
//  Hint shown on the first photo tile to teach users they can
//  long-press for options (share, tag, caption, delete).
//

import SwiftUI
import TipKit

struct PhotoOptionsTip: Tip {
    var title: Text {
        Text("Hold for more options")
    }

    var message: Text? {
        Text("Press and hold any photo to share, tag, or delete")
    }

    var image: Image? {
        Image(systemName: "hand.tap")
    }

    var options: [TipOption] {
        MaxDisplayCount(1)
    }
}
