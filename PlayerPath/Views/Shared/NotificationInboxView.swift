//
//  NotificationInboxView.swift
//  PlayerPath
//
//  Browsable list of the current user's recent activity notifications.
//  Backed by ActivityNotificationService's 50-item real-time cache so the
//  view reflects reads/writes as they happen without its own listener.
//

import SwiftUI

struct NotificationInboxView: View {
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @ObservedObject private var service = ActivityNotificationService.shared

    var body: some View {
        Group {
            if service.recentNotifications.isEmpty {
                ContentUnavailableView(
                    "No notifications",
                    systemImage: "bell.slash",
                    description: Text("You're all caught up. New activity from coaches and athletes will appear here.")
                )
            } else {
                List {
                    ForEach(service.recentNotifications) { notification in
                        Button {
                            handleTap(notification)
                        } label: {
                            NotificationInboxRow(notification: notification)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if service.unreadCount > 0, let userID = authManager.userID {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Mark All Read") {
                        Haptics.light()
                        Task { await service.markAllRead(forUserID: userID) }
                    }
                    .font(.subheadline)
                }
            }
        }
    }

    private func handleTap(_ notification: ActivityNotification) {
        Haptics.light()
        if let notifID = notification.id, let userID = authManager.userID {
            Task { await service.markRead(notifID, forUserID: userID) }
        }
        let isCoach = authManager.userRole == .coach
        // Routing that targets a folder/invitation replaces the nav stack via
        // navigateToMore(...) / CoachNavigationCoordinator, which implicitly
        // pops this inbox. For no-route cases (e.g. athlete accessRevoked) the
        // row simply re-renders as read — no explicit dismiss needed.
        ActivityNotificationRouter.route(notification, isCoach: isCoach)
    }
}

// MARK: - Row

private struct NotificationInboxRow: View {
    let notification: ActivityNotification

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: ActivityNotificationRouter.iconName(for: notification.type))
                .font(.title3)
                .foregroundColor(iconColor)
                .frame(width: 36, height: 36)
                .background(iconColor.opacity(0.15))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(notification.displayTitle)
                        .font(.subheadline)
                        .fontWeight(notification.isRead ? .regular : .semibold)
                        .foregroundColor(.primary)
                        .lineLimit(2)

                    Spacer(minLength: 0)

                    if !notification.isRead {
                        Circle()
                            .fill(Color.brandNavy)
                            .frame(width: 8, height: 8)
                    }
                }

                Text(notification.displayBody)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)

                if let createdAt = notification.createdAt {
                    Text(createdAt, style: .relative)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private var iconColor: Color {
        switch notification.type {
        case .newVideo:           return .brandNavy
        case .coachComment:       return .green
        case .invitationReceived: return .indigo
        case .invitationAccepted: return .green
        case .accessRevoked:      return .orange
        case .accessLapsed:       return .yellow
        case .uploadFailed:       return .red
        }
    }
}
