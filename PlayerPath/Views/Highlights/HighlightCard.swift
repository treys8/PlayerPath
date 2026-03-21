//
//  HighlightCard.swift
//  PlayerPath
//
//  Empty highlights state and highlight card views for the Highlights tab.
//

import SwiftUI
import SwiftData

struct EmptyHighlightsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        EmptyStateView(
            systemImage: "star.fill",
            title: "No Highlights Yet",
            message: "Star your best plays!\nHits automatically become highlights",
            actionTitle: "Go to Videos",
            buttonIcon: "video.fill",
            action: {
                NotificationCenter.default.post(name: .switchToVideosTab, object: nil)
                dismiss()
            }
        )
    }
}

extension Notification.Name {
    static let switchToVideosTab = Notification.Name("switchToVideosTab")
}

struct HighlightCard: View {
    let clip: VideoClip
    let editMode: EditMode
    let onTap: () -> Void
    let hasCoachingAccess: Bool
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Button(action: {
            Haptics.light()
            onTap()
        }) {
            VStack(spacing: 0) {
                // Video thumbnail area — uses shared VideoThumbnailView for consistency with VideoClipsView
                ZStack {
                    VideoThumbnailView(
                        clip: clip,
                        size: .thumbnailLarge,
                        cornerRadius: 0,
                        showPlayButton: editMode == .inactive,
                        showPlayResult: true,
                        showHighlight: true,
                        showSeason: false,
                        showContext: false,
                        fillsContainer: true
                    )

                    // Gradient overlay for better contrast
                    VStack {
                        Spacer()
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.4)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 40)
                    }

                    // Duration badge (bottom-left)
                    VStack {
                        Spacer()
                        HStack {
                            if let duration = clip.duration, duration > 0 {
                                Text(formatDuration(duration))
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
                                    .padding(8)
                            }
                            Spacer()
                        }
                    }
                }
                .aspectRatio(16/9, contentMode: .fit)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 12))

                // Info section at bottom
                VStack(alignment: .leading, spacing: 6) {
                    if let playResult = clip.playResult {
                        Text(playResult.type.displayName)
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    if let game = clip.game {
                        HStack(spacing: 6) {
                            Text("vs \(game.opponent)")
                                .font(.caption)
                                .foregroundColor(.brandNavy)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer()
                            if let season = clip.season {
                                SeasonBadge(season: season, fontSize: 8)
                            }
                        }

                        Text((game.date ?? Date()), style: .date)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        HStack(spacing: 6) {
                            Text("Practice")
                                .font(.caption)
                                .foregroundColor(.green)
                            Spacer()
                            if let season = clip.season {
                                SeasonBadge(season: season, fontSize: 8)
                            }
                        }

                        Text((clip.createdAt ?? Date()), style: .date)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6))
            }
        }
        .buttonStyle(PressableCardButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(editMode == .active ? "Tap to select. Use bottom toolbar to delete." : "Tap to play the highlight.")
        .clipShape(RoundedRectangle(cornerRadius: .cornerLarge, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
        .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
        .scaleEffect(editMode == .active ? 0.96 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: editMode)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private var accessibilityLabel: String {
        var parts: [String] = []
        if let pr = clip.playResult { parts.append(pr.type.displayName) }
        if let game = clip.game { parts.append("vs \(game.opponent)") }
        else { parts.append("Practice") }
        let dateText = DateFormatter.shortDate.string(from: (clip.createdAt ?? Date()))
        parts.append(dateText)
        return parts.joined(separator: ", ")
    }
}
