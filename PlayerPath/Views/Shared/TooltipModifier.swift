//
//  TooltipModifier.swift
//  PlayerPath
//

import SwiftUI

struct TooltipModifier: ViewModifier {
    let tipID: String
    let text: String
    let arrowEdge: Edge
    let arrowOffset: CGFloat
    let condition: Bool

    @ObservedObject private var onboardingManager = OnboardingManager.shared
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: overlayAlignment) {
                if isVisible {
                    TooltipBubble(
                        text,
                        arrowEdge: arrowEdge,
                        arrowOffset: arrowOffset
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isVisible = false
                        }
                        onboardingManager.dismissTip(tipID)
                    }
                    // Shift tooltip outside the target's bounds using alignment guides
                    .alignmentGuide(.top) { d in
                        arrowEdge == .bottom ? d.height + 4 : d[.top]
                    }
                    .alignmentGuide(.bottom) { d in
                        arrowEdge == .top ? -4 : d[.bottom]
                    }
                    .alignmentGuide(.leading) { d in
                        arrowEdge == .trailing ? d.width + 4 : d[.leading]
                    }
                    .alignmentGuide(.trailing) { d in
                        arrowEdge == .leading ? -4 : d[.trailing]
                    }
                    .transition(.scale(scale: 0.85, anchor: transitionAnchor).combined(with: .opacity))
                    .allowsHitTesting(true)
                }
            }
            .task(id: tipID) {
                guard condition, onboardingManager.shouldShowTip(tipID) else { return }
                try? await Task.sleep(for: .seconds(0.6))
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    isVisible = true
                }
            }
    }

    private var overlayAlignment: Alignment {
        switch arrowEdge {
        case .top: return .bottom
        case .bottom: return .top
        case .leading: return .trailing
        case .trailing: return .leading
        @unknown default: return .top
        }
    }

    private var transitionAnchor: UnitPoint {
        switch arrowEdge {
        case .top: return .top
        case .bottom: return .bottom
        case .leading: return .leading
        case .trailing: return .trailing
        @unknown default: return .center
        }
    }
}

extension View {
    func tooltip(
        _ tipID: String,
        text: String,
        arrowEdge: Edge = .top,
        arrowOffset: CGFloat = 0,
        showWhen condition: Bool = true
    ) -> some View {
        modifier(TooltipModifier(
            tipID: tipID,
            text: text,
            arrowEdge: arrowEdge,
            arrowOffset: arrowOffset,
            condition: condition
        ))
    }
}
