//
//  SmallCapsLabel.swift
//  PlayerPath
//
//  Visual overhaul — the editorial "overline" voice.
//  Small-caps, letter-spaced, muted labels: `RHETT · 2026 SPRING`, `GAME`,
//  `MILESTONES`. Reuses the registered Inter font (`.ppCaption`) plus `.tracking`,
//  the same letter-spacing convention already used across the app.
//

import SwiftUI

private struct SmallCapsLabelModifier: ViewModifier {
    var color: Color

    func body(content: Content) -> some View {
        content
            .font(.ppCaption)            // Inter 12pt (Font+PlayerPath)
            .textCase(.uppercase)
            .tracking(1.1)               // ~0.1em letter-spacing
            .foregroundStyle(color)
    }
}

extension View {
    /// Applies the small-caps overline style.
    /// Pass a lighter `color` when sitting over a dark media surface
    /// (e.g. `Theme.accentLight` or `.white.opacity(0.8)`).
    func smallCapsLabel(color: Color = Theme.textSecondary) -> some View {
        modifier(SmallCapsLabelModifier(color: color))
    }
}
