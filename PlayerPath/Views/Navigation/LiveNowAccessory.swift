//
//  LiveNowAccessory.swift
//  PlayerPath
//
//  iOS 26.1+ tab-bar bottom accessory for an in-progress game or golf practice —
//  the Music-style mini bar. Also used by CoachTabView for a live coach session.
//  Pure view: the tab root resolves the live item and passes strings, a date and
//  closures, so this never touches a @Model (no deleted-model traps while a game
//  ends underneath it).
//
//  Past the stale threshold the bar stops claiming "Live" and asks "Still
//  playing?" with an End action instead — a game left running for days would
//  otherwise sit on every tab looking broken.
//

import SwiftUI

@available(iOS 26.1, *)
struct LiveNowAccessory: View {
    let title: String
    let actionTitle: String
    let actionIcon: String
    /// When the activity counts as forgotten (live start + the stale-reminder
    /// threshold). Nil = never goes stale.
    let staleAt: Date?
    /// VoiceOver hint for tapping the bar, naming where it goes.
    let openHint: String
    let isEnding: Bool
    let onOpen: () -> Void
    let onAction: () -> Void
    let onEnd: () -> Void

    @Environment(\.ppAccent) private var ppAccent
    /// `.inline` = the tab bar has minimized and the accessory shares its row;
    /// there's only room for the icon then.
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        // Re-evaluated each minute so the bar flips to "Still playing?" on its
        // own, without waiting for something else to re-render the tab root.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let isStale = staleAt.map { context.date >= $0 } ?? false
            HStack(spacing: 12) {
                Button(action: onOpen) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(isStale ? Theme.warning : ppAccent)
                            .frame(width: 8, height: 8)
                        Text(isStale ? "Still playing?" : "Live")
                            .font(.ppCaptionBold)
                            .foregroundStyle(isStale ? Theme.warning : ppAccent)
                        Text(title)
                            .font(.ppHeadline)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isStale ? "Still playing? \(title)" : "Live: \(title)")
                .accessibilityHint(openHint)

                if isEnding {
                    ProgressView()
                } else if isStale {
                    actionButton(title: "End", icon: "stop.fill", action: onEnd)
                } else {
                    actionButton(title: actionTitle, icon: actionIcon, action: onAction)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func actionButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if placement == .inline {
                Image(systemName: icon)
            } else {
                Label(title, systemImage: icon)
                    .font(.ppCaptionBold)
            }
        }
        .tint(ppAccent)
        .accessibilityLabel(title)
    }
}

/// Applies the Live Now accessory on iOS 26.1+ (`isEnabled:` keeps the TabView's
/// identity stable as live state flips, so no tab loses its navigation stack);
/// no-op on earlier OSes, where the in-tab live card remains the entry point.
struct LiveNowAccessoryModifier<Accessory: View>: ViewModifier {
    let isEnabled: Bool
    @ViewBuilder let accessory: () -> Accessory

    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: isEnabled) { accessory() }
        } else {
            content
        }
    }
}
