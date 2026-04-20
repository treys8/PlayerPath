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

    var body: some View {
        NavigationLink {
            NotificationInboxView()
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell")
                    .font(.body)
                    .frame(width: 28, height: 28)

                if service.unreadCount > 0 {
                    Text("\(min(service.unreadCount, 99))")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.red, in: Capsule())
                        .offset(x: 4, y: -2)
                }
            }
            .frame(width: 36, height: 32)
        }
        .accessibilityLabel("Activity")
        .accessibilityValue(service.unreadCount > 0 ? "\(service.unreadCount) unread" : "No unread notifications")
    }
}
