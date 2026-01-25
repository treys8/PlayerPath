//
//  ViewStyleExtensions.swift
//  PlayerPath
//
//  Extracted from MainAppView.swift
//

import SwiftUI

extension View {
    /// Lightweight glass effect wrapper fallback when glassEffect is not available everywhere
    func appGlass(cornerRadius: CGFloat = 12, overlayOpacity: Double = 0.1) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(Color.white.opacity(overlayOpacity))
                            .blendMode(.overlay)
                    )
            )
    }
}

extension View {
    func appCard(cornerRadius: CGFloat = 16) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color(.systemGray5), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
    }

    func appCardMaterial(cornerRadius: CGFloat = 16) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color(.systemGray6), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
    }
}
