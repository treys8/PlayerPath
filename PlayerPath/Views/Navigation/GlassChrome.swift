//
//  GlassChrome.swift
//  PlayerPath
//
//  iOS 26 Liquid Glass adoption helpers, gated so iOS 17/18 keep the pre-26
//  look. Everything version-dependent about system chrome lives here, so call
//  sites never carry their own #available checks.
//

import SwiftUI

/// SF Symbol names for toolbar buttons. iOS 26 draws a glass capsule around
/// every toolbar item, so a circled glyph renders as a circle inside a circle;
/// pre-26 toolbars have no capsule and still want the circle.
enum ToolbarSymbol {
    /// Overflow ("more actions") menu.
    static var more: String {
        if #available(iOS 26, *) { return "ellipsis" }
        return "ellipsis.circle"
    }

    /// Filter menu. The filled circle stays as the "a filter is on" signal on
    /// every OS — it reads as a badge, not as a doubled outline.
    static func filter(active: Bool) -> String {
        if active { return "line.3.horizontal.decrease.circle.fill" }
        if #available(iOS 26, *) { return "line.3.horizontal.decrease" }
        return "line.3.horizontal.decrease.circle"
    }
}

extension View {
    /// Shrinks the iOS 26 tab bar while scrolling down (as in Apple's own apps);
    /// no-op before iOS 26. Apply to the compact-width TabView only — the iPad
    /// sidebar-adaptable style has no bottom bar to minimize.
    @ViewBuilder
    func ppTabBarMinimizesOnScroll() -> some View {
        if #available(iOS 26, *) {
            self.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }
}
