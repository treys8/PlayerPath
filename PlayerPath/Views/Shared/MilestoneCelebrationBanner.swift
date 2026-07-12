//
//  MilestoneCelebrationBanner.swift
//  PlayerPath
//
//  Transient top banner shown the moment a game/round completion earns a
//  personal best or season first ("PERSONAL BEST · Lowest round of the season").
//  Sibling to HighlightReelBanner — same slide/auto-dismiss affordances — but
//  the record stamp, so it speaks the milestone accent (fairway green for golf,
//  terracotta otherwise) rather than the reel surfaces' brand gold, visually
//  rhyming with the PPMilestoneMarker star the user will later find on that
//  game's Journal row. Tapping dismisses (the marker is the durable surface).
//

import SwiftUI

struct MilestoneCelebrationBanner: View {
    let stamp: MilestoneCelebrationService.Stamp
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var iconPop = false

    /// Resolved from the stamp's sport, not the environment — see Stamp.isGolf.
    private var accent: Color { Theme.accent(forGolf: stamp.isGolf) }

    private var accessibilityText: String {
        [stamp.kindLabel, stamp.title, stamp.detail].compactMap { $0 }.joined(separator: ". ")
    }

    var body: some View {
        HStack(spacing: 12) {
            // Whole card taps to dismiss — a pure celebration, no navigation.
            Button {
                Haptics.light()
                onDismiss()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "star.fill")
                        .font(.title3)
                        .foregroundColor(accent)
                        .symbolEffect(.bounce, value: iconPop)
                        .frame(width: 36, height: 36)
                        .background(accent.opacity(0.15))
                        .clipShape(Circle())
                        // One-shot entrance pop: the star overshoots (celebrate) then
                        // settles (selection). `iconPop` only flips true under
                        // !reduceMotion (see .onAppear), so Reduce Motion holds the
                        // badge at the resting first phase (1.0).
                        .phaseAnimator([1.0, 1.25, 0.92, 1.0], trigger: iconPop) { badge, scale in
                            badge.scaleEffect(scale)
                        } animation: { scale in
                            scale == 1.25 ? Animation.celebrate : Animation.selection
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(stamp.kindLabel)
                            .smallCapsLabel(color: accent)

                        Text(stamp.title)
                            .font(.headingSmall)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if let detail = stamp.detail {
                            Text(detail)
                                .font(.bodySmall)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

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
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Double-tap to dismiss")
        .accessibilityAddTraits(.isButton)
        .onAppear {
            // The banner is only created the moment a record is earned, so
            // appearing IS the celebratory beat: one success buzz + a single star
            // pop. Movement is dropped under Reduce Motion; the haptic stays.
            Haptics.success()
            if !reduceMotion { iconPop = true }
        }
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
    VStack(spacing: 16) {
        MilestoneCelebrationBanner(
            stamp: .init(
                id: "preview-golf",
                kindLabel: "PERSONAL BEST",
                title: "Lowest round of the season",
                detail: "Pebble Creek · Jul 11",
                isGolf: true
            ),
            onDismiss: {}
        )
        MilestoneCelebrationBanner(
            stamp: .init(
                id: "preview-baseball",
                kindLabel: "SEASON FIRST",
                title: "First home run of the season",
                detail: "vs Tigers · May 12",
                isGolf: false
            ),
            onDismiss: {}
        )
    }
    .padding(.top, 60)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(Color(.systemBackground))
}
