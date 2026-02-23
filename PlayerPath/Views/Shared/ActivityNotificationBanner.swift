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

    @State private var isVisible = false

    var body: some View {
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

                Text(notification.body)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
        .padding(.horizontal, 16)
        .onAppear {
            // Auto-dismiss after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                onDismiss()
            }
        }
        .onTapGesture {
            Haptics.light()
            onDismiss()
        }
    }

    private var iconName: String {
        switch notification.type {
        case .newVideo:           return "video.fill"
        case .coachComment:       return "bubble.left.fill"
        case .invitationReceived: return "envelope.fill"
        case .invitationAccepted: return "checkmark.circle.fill"
        case .accessRevoked:      return "minus.circle.fill"
        }
    }

    private var iconColor: Color {
        switch notification.type {
        case .newVideo:           return .blue
        case .coachComment:       return .green
        case .invitationReceived: return .indigo
        case .invitationAccepted: return .green
        case .accessRevoked:      return .orange
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
            isRead: false,
            createdAt: Date()
        ),
        onDismiss: {}
    )
    .padding(.top, 60)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(Color(.systemBackground))
}
