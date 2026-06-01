//
//  HighlightReelCard.swift
//  PlayerPath
//
//  Card for a virtual golf highlight reel (v6.1 PR2). Mirrors VideoClipCard's
//  16:9 thumbnail + two-row chrome so the mixed Highlights grid stays visually
//  uniform. Thumbnail is drawn from the first clip in the reel; falls back to
//  a flag icon if no clip can be resolved (e.g. clips still uploading on first
//  cross-device sync).
//

import SwiftUI
import SwiftData

struct HighlightReelCard: View {
    let reel: HighlightReel
    let onPlay: () -> Void
    var isDimmed: Bool = false

    @Environment(\.modelContext) private var modelContext
    @State private var coverClip: VideoClip?

    var body: some View {
        Button(action: {
            guard !isDimmed else { return }
            Haptics.light()
            onPlay()
        }) {
            VStack(spacing: 0) {
                ZStack {
                    coverArt

                    // REEL pill — top trailing, mirrors the badge styling
                    // used elsewhere on cards.
                    VStack {
                        HStack {
                            Spacer()
                            Text("REEL")
                                .font(.custom("Inter18pt-Bold", size: 10, relativeTo: .caption2))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.brandNavy))
                                .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
                                .padding(8)
                        }
                        Spacer()
                    }

                    if isDimmed {
                        Color.black.opacity(0.35)
                    }
                }
                .aspectRatio(16/9, contentMode: .fit)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(reel.displayName)
                            .font(.bodySmall)
                            .foregroundColor(.brandNavy)
                            .lineLimit(1)
                        if !reel.courseOrOpponent.isEmpty {
                            Text("·")
                                .foregroundColor(.secondary)
                            Text(reel.courseOrOpponent)
                                .font(.bodySmall)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        Spacer(minLength: 4)
                    }
                    .frame(minHeight: 22)

                    HStack(spacing: 6) {
                        Text("Hole \(reel.holeNumber)")
                            .font(.labelSmall)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                        Text("·")
                            .foregroundColor(.secondary)
                        Text(reel.date, format: .dateTime.month(.abbreviated).day())
                            .font(.labelSmall)
                            .foregroundColor(.secondary)
                        Spacer(minLength: 4)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6))
            }
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: .cornerLarge, style: .continuous))
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardButtonStyle())
        .disabled(isDimmed)
        .task { resolveCoverClip() }
    }

    /// Thumbnail of the first resolvable clip in the reel. If none resolves,
    /// renders a brand-navy background with a flag icon — the same fallback
    /// used by HighlightReelCard's preview when clips are still uploading.
    @ViewBuilder
    private var coverArt: some View {
        if let clip = coverClip {
            VideoThumbnailView(
                clip: clip,
                size: .thumbnailLarge,
                cornerRadius: 0,
                showPlayResult: false,
                showHighlight: false,
                showSeason: false,
                showContext: false,
                showDuration: false,
                showOutcomeWithDuration: false,
                fillsContainer: true
            )
        } else {
            ZStack {
                LinearGradient(
                    colors: [Color.brandNavy, Color.brandNavy.opacity(0.7)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "flag.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
    }

    /// First-pass lookup against clipIDs. Stops at the first clip we can find
    /// locally — the thumbnail loader inside VideoThumbnailView already
    /// handles the local-vs-cloud fallback for thumbnail bytes.
    private func resolveCoverClip() {
        guard coverClip == nil else { return }
        let ids = reel.clipIDs
        guard !ids.isEmpty else { return }
        do {
            let descriptor = FetchDescriptor<VideoClip>(
                predicate: #Predicate<VideoClip> { clip in
                    ids.contains(clip.id.uuidString)
                }
            )
            let clips = try modelContext.fetch(descriptor)
            // Prefer the first in chronological reel order — find it in `ids`
            // and pick whichever clip in `clips` matches it first. Tolerate
            // duplicate ids (multi-device row duplication) rather than trapping.
            let clipsByID: [String: VideoClip] = Dictionary(
                clips.map { ($0.id.uuidString, $0) },
                uniquingKeysWith: { existing, _ in existing }
            )
            coverClip = ids.compactMap { clipsByID[$0] }.first
        } catch {
            // Silent fallback — the icon cover renders if we can't resolve.
            coverClip = nil
        }
    }
}
