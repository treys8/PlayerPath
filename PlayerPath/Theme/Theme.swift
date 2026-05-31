//
//  Theme.swift
//  PlayerPath
//
//  Visual overhaul — "calm keepsake" palette.
//  Light-only by design (the app is locked to light appearance; the cream
//  surface IS the brand). Values come straight from the design token table.
//  Colors are built with the existing `Color(hex:)` initializer (DesignTokens.swift)
//  to match the codebase's code-declared color convention — no asset catalog split.
//
//  Rule: ONE accent only. `accent` means significance/action. The tile colors
//  carry sport/variety only — never meaning. Resist adding more accents.
//

import SwiftUI

enum Theme {

    // MARK: - Surfaces
    /// App background (cream).
    static let surface = Color(hex: "F4EFE6")
    /// Cards, tiles-on-cream, tab bar.
    static let card = Color(hex: "FFFFFF")

    // MARK: - Text
    /// Headlines, primary text.
    static let textPrimary = Color(hex: "1F1B16")
    /// Sublines, muted labels.
    static let textSecondary = Color(hex: "8A7F6F")
    /// Hints, inactive tab labels.
    static let textTertiary = Color(hex: "A89D8B")

    // MARK: - Lines
    /// Hairline separators.
    static let divider = Color(hex: "E3DACB")
    /// Unselected filter-pill border.
    static let pillBorder = Color(hex: "D8CFBE")

    // MARK: - Accent (the one accent)
    /// "Pay attention here" — milestones, active states, primary actions.
    static let accent = Color(hex: "C8693E")
    /// Accent on dark surfaces (labels / telestration over video).
    static let accentLight = Color(hex: "F0997B")

    // MARK: - Media tiles (sport / variety only — not meaning)
    static let tileNavy = Color(hex: "2D3D52")
    /// Video player surface.
    static let tileNavyDark = Color(hex: "20303F")
    static let tileForest = Color(hex: "3B5044")
    static let tileOlive = Color(hex: "5C5234")
    static let tilePlum = Color(hex: "4A3A48")

    // MARK: - Chips
    /// Golf/result chips, "Seen" receipt.
    static let chipGreenBg = Color(hex: "DCE7DD")
    static let chipGreenText = Color(hex: "3B5044")
    /// Quick-cue chips.
    static let cueBg = Color(hex: "EDE4D2")
    static let cueText = Color(hex: "5C5234")

    // MARK: - Media tile rotation
    /// Variety palette for media placeholders. No meaning — just rotation.
    static let mediaTiles: [Color] = [tileNavy, tileForest, tileOlive, tilePlum]

    /// Deterministic media-tile color for a given index (stable per item).
    static func tile(for index: Int) -> Color {
        mediaTiles[abs(index) % mediaTiles.count]
    }

    /// Stable media-tile color for a string key (e.g. a feed entry id). Uses a
    /// fixed FNV-1a hash rather than `String.hashValue`, whose seed is
    /// randomized per process launch — so a given entry keeps the same tile
    /// color across app restarts instead of flickering between palette colors.
    static func tile(forKey key: String) -> Color {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in key.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100000001b3
        }
        return mediaTiles[Int(hash % UInt64(mediaTiles.count))]
    }
}
