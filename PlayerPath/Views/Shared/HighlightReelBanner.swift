//
//  HighlightReelBanner.swift
//  PlayerPath
//
//  Transient top banner shown after a game/practice ends, announcing the
//  auto-curated highlights ("PlayerPath found N highlights from today's …").
//  Sibling to ActivityNotificationBanner — same slide/auto-dismiss/tap
//  affordances — but driven by a local HighlightReelBannerService.Summary
//  rather than a Firestore-shaped ActivityNotification.
//

import SwiftUI

struct HighlightReelBanner: View {
    let summary: HighlightReelBannerService.Summary
    var onTap: () -> Void
    let onDismiss: () -> Void

    private var headline: String {
        "PlayerPath found \(summary.count) highlight\(summary.count == 1 ? "" : "s")"
    }
    private var subtitle: String {
        "From today's \(summary.eventKind.noun) · Tap to watch"
    }

    var body: some View {
        HStack(spacing: 12) {
            // Tappable content area (opens reel / paywall, then dismisses)
            Button {
                Haptics.light()
                onTap()
                onDismiss()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "film.stack")
                        .font(.title3)
                        .foregroundColor(.brandGold)
                        .frame(width: 36, height: 36)
                        .background(Color.brandGold.opacity(0.15))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(headline)
                            .font(.headingSmall)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Text(subtitle)
                            .font(.bodySmall)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                            .truncationMode(.tail)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            // Dismiss-only button (does NOT open the reel)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: .cornerXLarge))
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(headline). \(subtitle)")
        .accessibilityHint("Double-tap to watch, or activate the dismiss button to close")
        .accessibilityAddTraits(.isButton)
        .task {
            // Auto-dismiss after a timeout; extend under VoiceOver. Cancelled on disappear.
            let seconds: TimeInterval = UIAccessibility.isVoiceOverRunning ? 10 : 5
            do {
                try await Task.sleep(for: .seconds(seconds))
                onDismiss()
            } catch {
                // Cancelled (view disappeared) — don't dismiss.
            }
        }
    }
}

#Preview {
    HighlightReelBanner(
        summary: .init(
            id: UUID(),
            eventKind: .game,
            scopeKey: "game_preview",
            title: "vs Tigers · Jun 11",
            clipIDs: [UUID(), UUID(), UUID()],
            count: 3
        ),
        onTap: {},
        onDismiss: {}
    )
    .padding(.top, 60)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(Color(.systemBackground))
}
