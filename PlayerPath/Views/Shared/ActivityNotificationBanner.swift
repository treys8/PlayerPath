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
                    Image(systemName: iconName)
                        .font(.title3)
                        .foregroundColor(iconColor)
                        .frame(width: 36, height: 36)
                        .background(iconColor.opacity(0.15))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(notification.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Text(notification.body)
                            .font(.caption)
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
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: .cornerXLarge))
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
        .padding(.horizontal, 16)
        .task {
            // Auto-dismiss after 5 seconds; cancelled automatically on disappear
            do {
                try await Task.sleep(for: .seconds(5))
                onDismiss()
            } catch {
                // Task was cancelled (view disappeared) — don't dismiss
            }
        }
    }

    private var iconName: String {
        switch notification.type {
        case .newVideo:           return "video.fill"
        case .coachComment:       return "bubble.left.fill"
        case .invitationReceived: return "envelope.fill"
        case .invitationAccepted: return "checkmark.circle.fill"
        case .accessRevoked:      return "minus.circle.fill"
        case .accessLapsed:       return "exclamationmark.triangle.fill"
        }
    }

    private var iconColor: Color {
        switch notification.type {
        case .newVideo:           return .brandNavy
        case .coachComment:       return .green
        case .invitationReceived: return .indigo
        case .invitationAccepted: return .green
        case .accessRevoked:      return .orange
        case .accessLapsed:       return .yellow
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
