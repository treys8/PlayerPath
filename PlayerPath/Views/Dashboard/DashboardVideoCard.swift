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
    @State private var isAnimating = false

    private var formattedDuration: String? {
        guard let duration = video.duration, duration > 0 else { return nil }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Video thumbnail with overlay gradient
            ZStack(alignment: .bottom) {
                DashboardVideoThumbnail(video: video)
                    .accessibilityLabel("Video thumbnail")

                // Gradient overlay for better text contrast
                LinearGradient(
                    colors: [.clear, .clear, .black.opacity(0.7)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // Bottom bar with play button and duration
                HStack {
                    // Play badge
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .opacity(0.9)
                    )

                    Spacer()

                    // Duration badge
                    if let duration = formattedDuration {
                        Text(duration)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.6))
                            )
                    }
                }
                .padding(8)
            }

            VStack(alignment: .leading, spacing: 4) {
                // Play result or filename
                Text(video.playResult?.type.displayName ?? "Video Clip")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .foregroundColor(.primary)

                // Date and highlight indicator
                HStack(spacing: 6) {
                    if let created = video.createdAt {
                        HStack(spacing: 3) {
                            Image(systemName: "calendar")
                                .font(.system(size: 9))
                            Text(created, format: .dateTime.month().day())
                                .font(.caption2)
                        }
                        .foregroundColor(.secondary)
                    }

                    if video.isHighlight {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 8))
                            Text("Highlight")
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundColor(.yellow)
                    }
                }
            }
        }
        .frame(width: 150)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
        .scaleEffect(isPressed ? 0.96 : 1.0)
        .opacity(isAnimating ? 1.0 : 0)
        .offset(x: isAnimating ? 0 : 20)
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
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(Double.random(in: 0...0.15))) {
                isAnimating = true
            }
        }
    }
}
