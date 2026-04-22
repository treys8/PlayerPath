//
//  NotificationBellToolbarButton.swift
//  PlayerPath
//
//  Toolbar entry point for the activity notification inbox. Used on both
//  the athlete Home dashboard and the coach Dashboard so users can reach
//  the inbox in one tap from the tab they're already on.
//

import SwiftUI

struct NotificationBellToolbarButton: View {
    @ObservedObject private var service = ActivityNotificationService.shared

    private var hasUnread: Bool { service.unreadCount > 0 }

    /// "99+" past 99 — communicates truncation instead of claiming "99".
    private var badgeText: String {
        service.unreadCount > 99 ? "99+" : "\(service.unreadCount)"
    }

    var body: some View {
        NavigationLink {
            NotificationInboxView()
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell")
                    .font(.body)
                    .symbolVariant(hasUnread ? .fill : .none)
                    .symbolEffect(.bounce, value: hasUnread)

                if hasUnread {
                    Text(badgeText)
                        .font(.system(size: 10, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.red, in: Capsule())
                        .offset(x: 8, y: -6)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 40, height: 32)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: service.unreadCount)
        }
        .simultaneousGesture(TapGesture().onEnded { Haptics.light() })
        .accessibilityLabel("Activity")
        .accessibilityValue(hasUnread ? "\(service.unreadCount) unread" : "No unread notifications")
    }
}
