//
//  ActivityNotificationBanner.swift
//  PlayerPath
//
//  In-app notification banner that slides in from the top when the current user
//  receives a new activity notification while the app is in the foreground.
//

import SwiftUI

struct ActivityNotificationBanner: View {
    let notification: ActivityNotification
    let onDismiss: () -> Void
    var onTap: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            // Tappable content area (navigates + dismisses)
            Button {
                Haptics.light()
                onTap?()
                onDismiss()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: ActivityNotificationRouter.iconName(for: notification.type))
                        .font(.title3)
                        .foregroundColor(ActivityNotificationRouter.iconColor(for: notification.type))
                        .frame(width: 36, height: 36)
                        .background(ActivityNotificationRouter.iconColor(for: notification.type).opacity(0.15))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(notification.displayTitle)
                            .font(.headingSmall)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Text(notification.displayBody)
                            .font(.bodySmall)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                            .truncationMode(.tail)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            // Dismiss-only button (does NOT navigate)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Dismiss notification")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: .cornerXLarge))
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(notification.title). \(notification.body)")
        .accessibilityHint("Double-tap to open, or activate the dismiss button to close")
        .accessibilityAddTraits(.isButton)
        .task {
            // Auto-dismiss after a timeout; extend under VoiceOver so the user has time
            // to hear the announcement and interact. Cancelled automatically on disappear.
            let seconds: TimeInterval = UIAccessibility.isVoiceOverRunning ? 10 : 5
            do {
                try await Task.sleep(for: .seconds(seconds))
                onDismiss()
            } catch {
                // Task was cancelled (view disappeared) — don't dismiss
            }
        }
    }

}

#Preview {
    ActivityNotificationBanner(
        notification: ActivityNotification(
            id: "preview",
            type: .coachComment,
            title: "Coach Feedback on practice_2024-11-21.mov",
            body: "Coach Smith: Great swing! Focus on your follow-through next time.",
            senderName: "Coach Smith",
            senderID: "coach123",
            targetID: "video123",
            targetType: .video,
            folderID: "folder123",
            isRead: false,
            createdAt: Date()
        ),
        onDismiss: {}
    )
    .padding(.top, 60)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(Color(.systemBackground))
}
