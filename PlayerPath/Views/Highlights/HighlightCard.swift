//
//  HighlightCard.swift
//  PlayerPath
//
//  Empty highlights state and highlight card views for the Highlights tab.
//

import SwiftUI
import SwiftData

struct EmptyHighlightsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        EmptyStateView(
            systemImage: "star.fill",
            title: "No Highlights Yet",
            message: "Star your best plays!\nHits automatically become highlights",
            actionTitle: "Go to Videos",
            buttonIcon: "video.fill",
            action: {
                NotificationCenter.default.post(name: .switchTab, object: MainTab.videos.rawValue)
                dismiss()
            }
        )
    }
}
