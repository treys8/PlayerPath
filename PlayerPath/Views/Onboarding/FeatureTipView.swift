//
//  FeatureTipView.swift
//  PlayerPath
//
//  Contextual tips that appear to guide users through features
//

import SwiftUI

struct FeatureTipView: View {
    let tip: FeatureTip
    let onDismiss: () -> Void
    let onAction: (() -> Void)?

    @State private var isVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: tip.icon)
                    .font(.title2)
                    .foregroundStyle(tip.color)

                VStack(alignment: .leading, spacing: 4) {
                    Text(tip.title)
                        .font(.headline)
                        .fontWeight(.semibold)

                    Text(tip.message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    withAnimation {
                        isVisible = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        onDismiss()
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .accessibleButton(label: "Dismiss tip")
            }

            if let action = onAction, let actionTitle = tip.actionTitle {
                Button {
                    action()
                    onDismiss()
                } label: {
                    Text(actionTitle)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(tip.color)
                        .foregroundStyle(.white)
                        .cornerRadius(8)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
        )
        .padding(.horizontal)
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : -20)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                isVisible = true
            }
        }
    }
}

struct FeatureTip: Identifiable {
    let id: String
    let title: String
    let message: String
    let icon: String
    let color: Color
    let actionTitle: String?
    let targetView: String?

    init(
        id: String,
        title: String,
        message: String,
        icon: String = "lightbulb.fill",
        color: Color = .blue,
        actionTitle: String? = nil,
        targetView: String? = nil
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.icon = icon
        self.color = color
        self.actionTitle = actionTitle
        self.targetView = targetView
    }

    // MARK: - Predefined Tips

    static let recordFirstVideo = FeatureTip(
        id: "record_first_video",
        title: "Record Your First Video",
        message: "Tap the Videos tab and press the record button to capture your swing",
        icon: "video.badge.plus",
        color: .blue,
        actionTitle: "Go to Videos"
    )

    static let createFirstGame = FeatureTip(
        id: "create_first_game",
        title: "Log Your First Game",
        message: "Track game performance and link videos to specific games",
        icon: "baseball.fill",
        color: .green,
        actionTitle: "Add Game"
    )

    static let viewStats = FeatureTip(
        id: "view_stats",
        title: "Check Your Statistics",
        message: "All your stats are calculated automatically from your videos",
        icon: "chart.bar.fill",
        color: .purple,
        actionTitle: "View Stats"
    )

    static let useSearch = FeatureTip(
        id: "use_search",
        title: "Search Your Videos",
        message: "Quickly find specific plays using the search feature",
        icon: "magnifyingglass",
        color: .orange,
        actionTitle: "Try Search"
    )

    static let exportData = FeatureTip(
        id: "export_data",
        title: "Export Your Stats",
        message: "Generate PDF or CSV reports to share with coaches",
        icon: "square.and.arrow.up.fill",
        color: .indigo,
        actionTitle: "Learn More"
    )

    static let quickActions = FeatureTip(
        id: "quick_actions",
        title: "Use Quick Actions",
        message: "Long press the app icon for shortcuts to common tasks",
        icon: "hand.tap.fill",
        color: .pink
    )

    static let slowMotion = FeatureTip(
        id: "slow_motion",
        title: "Slow Motion Playback",
        message: "Use playback controls to analyze your swing frame by frame",
        icon: "gauge.with.dots.needle.33percent",
        color: .cyan
    )

    static let highlightReel = FeatureTip(
        id: "highlight_reel",
        title: "Create Highlights",
        message: "Mark your best plays to create an automatic highlight reel",
        icon: "star.fill",
        color: .yellow
    )
}

// MARK: - Feature Tip Modifier

struct FeatureTipModifier: ViewModifier {
    let tip: FeatureTip
    let isShowing: Bool
    let onDismiss: () -> Void
    let onAction: (() -> Void)?

    func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content

            if isShowing {
                FeatureTipView(
                    tip: tip,
                    onDismiss: onDismiss,
                    onAction: onAction
                )
                .padding(.top, 60)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(100)
            }
        }
    }
}

extension View {
    func featureTip(
        _ tip: FeatureTip,
        isShowing: Bool,
        onDismiss: @escaping () -> Void,
        onAction: (() -> Void)? = nil
    ) -> some View {
        modifier(FeatureTipModifier(
            tip: tip,
            isShowing: isShowing,
            onDismiss: onDismiss,
            onAction: onAction
        ))
    }
}

#Preview {
    VStack {
        Spacer()
    }
    .featureTip(
        .recordFirstVideo,
        isShowing: true,
        onDismiss: {},
        onAction: {}
    )
}
