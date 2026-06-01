//
//  HighlightCard.swift
//  PlayerPath
//
//  Empty highlights state and highlight card views for the Highlights tab.
//

import SwiftUI
import SwiftData

struct EmptyHighlightsView: View {
    /// Golf highlights work differently than baseball (manual star at record
    /// time + birdie reels, no auto-tagging), so the copy is sport-aware.
    var sport: Sport? = nil
    @Environment(\.dismiss) private var dismiss

    private var isGolf: Bool { sport == .golf }

    var body: some View {
        EmptyStateView(
            systemImage: "star.fill",
            title: "No Highlights Yet",
            message: isGolf
                ? "Tap Highlight while recording a shot to save it here.\nYour birdie-or-better holes also group into reels automatically."
                : "Star your best plays!\nHits automatically become highlights",
            actionTitle: "Go to Videos",
            buttonIcon: "video.fill",
            action: {
                NotificationCenter.default.post(name: .switchTab, object: MainTab.videos.rawValue)
                dismiss()
            }
        )
    }
}
