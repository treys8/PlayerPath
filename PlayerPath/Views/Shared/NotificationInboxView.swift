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
            // With nothing cached, the error gets the full-screen retry state
            // instead (inboxContent) — never a banner over "All caught up".
            if let listenerError = service.listenerError, !service.recentNotifications.isEmpty {
                listenerErrorBanner(listenerError)
            }
            inboxContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface)
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
        if service.recentNotifications.isEmpty, service.listenerError != nil {
            EmptyStateView(
                systemImage: "wifi.exclamationmark",
                title: "Couldn't load notifications",
                message: "Check your connection and try again.",
                actionTitle: "Try Again",
                buttonIcon: "arrow.clockwise",
                action: { service.noteAppDidBecomeActive() }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if service.recentNotifications.isEmpty {
            EmptyStateView(
                systemImage: "bell.slash",
                title: "All caught up",
                message: emptyMessage
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(service.recentNotifications) { notification in
                    Button {
                        handleTap(notification)
                    } label: {
                        NotificationInboxRow(notification: notification)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Theme.surface)
                    .listRowSeparatorTint(Theme.divider)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    /// Worded for what each role actually receives (see ActivityNotificationRouter).
    private var emptyMessage: String {
        if authManager.userRole == .coach {
            return "When athletes share clips or respond to your invites, you'll see it here."
        }
        return "When a coach leaves feedback or sends you an invite, you'll see it here."
    }

    /// Surfaces a real-time listener failure (which leaves the unread counts
    /// stale) with a manual retry that re-attaches the snapshot listener via
    /// the service's revive path.
    @ViewBuilder
    private func listenerErrorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.warning)
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
        .background(Theme.warning.opacity(0.1))
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
    @Environment(\.ppAccent) private var ppAccent
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
                            .fill(ppAccent)
                            .frame(width: 8, height: 8)
                    }
                }

                Text(notification.displayBody)
                    .font(.bodySmall)
                    .foregroundColor(.secondary)
                    .lineLimit(3)

                if let createdAt = notification.createdAt {
                    // Static "5 minutes ago" — `style: .relative` ticks every
                    // second like a timer. Clamp so slight server clock skew
                    // never reads "in 2 seconds".
                    Text(min(createdAt, Date()).formatted(.relative(presentation: .named)))
                        .font(.labelSmall)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

}
