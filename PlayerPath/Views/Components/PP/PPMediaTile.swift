//
//  PPMediaTile.swift
//  PlayerPath
//
//  Visual overhaul — the media tile.
//  A colored rounded-rect surface for video/photo placeholders, with overlay
//  slots: outcome tag (top-left), highlight star (top-right), duration
//  (bottom-right), and an optional center play button. A `content` slot lets a
//  caller drop a real thumbnail on top of the tile color (which then shows
//  through only while the thumbnail loads / when absent).
//
//  Tile colors carry sport/variety only — never meaning (see Theme).
//

import SwiftUI

struct PPMediaTile<Content: View>: View {
    var aspectRatio: CGFloat?
    var cornerRadius: CGFloat
    var tileColor: Color
    var glyph: String?

    var outcome: PPOutcomeChip?
    var isStarred: Bool
    var duration: String?
    var showsPlayButton: Bool

    @Environment(\.ppAccent) private var ppAccent

    private let content: Content

    init(
        aspectRatio: CGFloat? = 16.0 / 9.0,
        cornerRadius: CGFloat = .cornerLarge,
        tileColor: Color = Theme.tileNavy,
        glyph: String? = nil,
        outcome: PPOutcomeChip? = nil,
        isStarred: Bool = false,
        duration: String? = nil,
        showsPlayButton: Bool = false,
        @ViewBuilder content: () -> Content = { EmptyView() }
    ) {
        self.aspectRatio = aspectRatio
        self.cornerRadius = cornerRadius
        self.tileColor = tileColor
        self.glyph = glyph
        self.outcome = outcome
        self.isStarred = isStarred
        self.duration = duration
        self.showsPlayButton = showsPlayButton
        self.content = content()
    }

    var body: some View {
        ZStack {
            tileColor

            if let glyph {
                Image(systemName: glyph)
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(.white.opacity(0.35))
            }

            content
        }
        .modifier(AspectRatioModifier(aspectRatio: aspectRatio))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(alignment: .center) { playButton }
        .overlay(alignment: .topLeading) { outcome.map { $0.padding(.spacingSmall) } }
        .overlay(alignment: .topTrailing) { star }
        .overlay(alignment: .bottomTrailing) { durationChip }
    }

    @ViewBuilder private var playButton: some View {
        if showsPlayButton {
            Image(systemName: "play.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .padding(14)
                .background(Circle().fill(.black.opacity(0.45)))
        }
    }

    @ViewBuilder private var star: some View {
        if isStarred {
            Image(systemName: "star.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ppAccent)
                .padding(6)
                .background(Circle().fill(.black.opacity(0.35)))
                .padding(.spacingSmall)
        }
    }

    @ViewBuilder private var durationChip: some View {
        if let duration {
            Text(duration)
                .font(.ppCaptionBold)
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(.black.opacity(0.55)))
                .padding(.spacingSmall)
        }
    }
}

/// Applies a fixed aspect ratio only when one is provided (square/16:9 tiles);
/// passing `nil` lets the tile size to its container.
private struct AspectRatioModifier: ViewModifier {
    let aspectRatio: CGFloat?
    func body(content: Content) -> some View {
        if let aspectRatio {
            content.aspectRatio(aspectRatio, contentMode: .fill)
        } else {
            content
        }
    }
}
