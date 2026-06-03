//
//  PPCard.swift
//  PlayerPath
//
//  Visual overhaul — the base card surface.
//  White card on the cream app background: hairline divider edge + a soft,
//  low shadow (calm, not floaty). Mirrors the contract of the legacy
//  `appCard()` (ViewStyleExtensions.swift) so it's a drop-in at call sites,
//  but uses the new Theme palette. Caller controls its own padding.
//

import SwiftUI

extension View {
    /// Wraps the view in the standard white card surface (Theme.card) with a
    /// hairline divider border and a soft shadow. Default radius 16 (cornerXLarge).
    func ppCard(cornerRadius: CGFloat = .cornerXLarge) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.divider, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 4)
    }
}
