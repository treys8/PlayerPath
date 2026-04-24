//
//  ViewStyleExtensions.swift
//  PlayerPath
//
//  Extracted from MainAppView.swift
//

import SwiftUI
import SwiftData
import TipKit

extension View {
    /// Attach `.popoverTip` gated on the user's `showOnboardingTips` preference.
    /// `also` adds a caller-controlled gate (e.g. "only on the first cell").
    func onboardingTip<T: Tip>(_ tip: T, arrowEdge: Edge = .top, also: Bool = true) -> some View {
        modifier(OnboardingTipModifier(tip: tip, arrowEdge: arrowEdge, also: also))
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

private struct OnboardingTipModifier<T: Tip>: ViewModifier {
    let tip: T
    let arrowEdge: Edge
    let also: Bool
    @Query private var prefs: [UserPreferences]

    private var enabled: Bool {
        (prefs.first?.showOnboardingTips ?? true) && also
    }

    func body(content: Content) -> some View {
        if enabled {
            content.popoverTip(tip, arrowEdge: arrowEdge)
        } else {
            content
        }
    }
}
