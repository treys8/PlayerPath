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
        VStack(spacing: 0) {
            if let listenerError = service.listenerError {
                listenerErrorBanner(listenerError)
            }
            inboxContent
        }
        // Note: opening the inbox no longer marks everything read — doing so
        // wiped the unread state before the user could scan it. Rows mark
        // themselves read on tap (handleTap); "Mark All Read" is the explicit
        // bulk action.
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if service.unreadCount > 0, let userID = authManager.userID {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Mark All Read") {
                        Haptics.light()
                        Task { await service.markAllRead(forUserID: userID) }
                    }
                    .font(.bodyMedium)
                }
            }
        }
    }

    @ViewBuilder
    private var inboxContent: some View {
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

    /// Surfaces a real-time listener failure (which leaves the unread counts
    /// stale) with a manual retry that re-attaches the snapshot listener via
    /// the service's revive path.
    @ViewBuilder
    private func listenerErrorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.bodySmall)
                .foregroundColor(.secondary)
            Spacer(minLength: 8)
            Button("Retry") {
                Haptics.light()
                service.noteAppDidBecomeActive()
            }
            .font(.bodyMedium)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.1))
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

    private var iconColor: Color {
        ActivityNotificationRouter.iconColor(for: notification.type)
    }

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
                        .font(notification.isRead ? .bodyMedium : .headingSmall)
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
                    .font(.bodySmall)
                    .foregroundColor(.secondary)
                    .lineLimit(3)

                if let createdAt = notification.createdAt {
                    Text(createdAt, style: .relative)
                        .font(.labelSmall)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

}
