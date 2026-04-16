//
//  ViewStyleExtensions.swift
//  PlayerPath
//
//  Extracted from MainAppView.swift
//

import SwiftUI
import TipKit

extension View {
    @ViewBuilder
    func popoverTipIfEnabled<T: Tip>(_ tip: T, arrowEdge: Edge = .top, enabled: Bool) -> some View {
        if enabled {
            popoverTip(tip, arrowEdge: arrowEdge)
        } else {
            self
        }
    }

    func appCard(cornerRadius: CGFloat = 16) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color(.separator).opacity(0.5), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
    }

}
