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

// MARK: - View Modifier

extension View {
    func videoClipOptionsTip(isFirst: Bool) -> some View {
        modifier(VideoClipOptionsTipModifier(isFirst: isFirst))
    }
}

private struct VideoClipOptionsTipModifier: ViewModifier {
    let isFirst: Bool
    private let tip = VideoClipOptionsTip()

    func body(content: Content) -> some View {
        if isFirst {
            content.popoverTip(tip, arrowEdge: .top)
        } else {
            content
        }
    }
}
