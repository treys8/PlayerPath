//
//  DashboardVideoCard.swift
//  PlayerPath
//
//  Extracted from MainAppView.swift
//

import SwiftUI

struct DashboardVideoCard: View {
    let video: VideoClip

    @State private var isPressed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Video thumbnail with overlay gradient
            ZStack(alignment: .bottomLeading) {
                DashboardVideoThumbnail(video: video)
                    .accessibilityLabel("Video thumbnail")

                // Gradient overlay for better text contrast
                LinearGradient(
                    colors: [.clear, .black.opacity(0.6)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // Duration or play badge overlay
                HStack(spacing: 4) {
                    Image(systemName: "play.fill")
                        .font(.caption2)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial.opacity(0.8))
                .clipShape(Capsule())
                .padding(8)
            }

            Text(video.playResult?.type.displayName ?? video.fileName)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .foregroundColor(.primary)

            if let created = video.createdAt {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.caption2)
                    Text(created, format: .dateTime.month().day())
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            } else {
                Text("—")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 150)
        .padding(8)
        .appCard()
        .scaleEffect(isPressed ? 0.96 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .accessibilityElement(children: .combine)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .contextMenu {
            Button {
                Haptics.light()
                NotificationCenter.default.post(name: Notification.Name.presentFullscreenVideo, object: video)
            } label: {
                Label("Play", systemImage: "play.fill")
            }

            if FileManager.default.fileExists(atPath: video.filePath) {
                ShareLink(item: URL(fileURLWithPath: video.filePath)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            } else {
                Text("File unavailable")
                    .foregroundColor(.secondary)
            }
        }
    }
}
