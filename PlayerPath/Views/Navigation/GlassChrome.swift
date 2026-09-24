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

    /// Gives a custom toolbar control (e.g. the principal athlete switcher) the
    /// same glass capsule iOS 26 draws behind standard toolbar items — without
    /// it, the control sits bare on whatever scrolls underneath and goes
    /// unreadable over a dark photo. No-op before iOS 26.
    @ViewBuilder
    func ppToolbarGlassPill() -> some View {
        if #available(iOS 26, *) {
            self
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .glassEffect(.regular, in: .capsule)
        } else {
            self
        }
    }

    /// The stronger iOS 26 scroll-edge treatment under the nav bar, for
    /// photo-led feeds where the default soft fade leaves the status bar and
    /// header unreadable over dark images. No-op before iOS 26.
    @ViewBuilder
    func ppHardTopScrollEdge() -> some View {
        if #available(iOS 26, *) {
            self.scrollEdgeEffectStyle(.hard, for: .top)
        } else {
            self
        }
    }

    /// Pins a bottom action bar. iOS 26: `safeAreaBar`, so content scrolls under
    /// the bar with the system scroll-edge effect. Before 26: stacked below the
    /// view on `Theme.surface` (the pre-26 layout, unchanged).
    @ViewBuilder
    func ppBottomBar<Bar: View>(isPresented: Bool, @ViewBuilder bar: () -> Bar) -> some View {
        if #available(iOS 26, *) {
            self.safeAreaBar(edge: .bottom) {
                if isPresented { bar() }
            }
        } else {
            VStack(spacing: 0) {
                self
                if isPresented { bar().background(Theme.surface) }
            }
        }
    }

    /// Pins an always-visible bottom action bar over a List/ScrollView. iOS 26:
    /// `safeAreaBar`, so content scrolls under the bar with the system
    /// scroll-edge effect and the bar draws no background of its own. Before 26:
    /// `safeAreaInset` on `fallbackBackground` — the layout these bars had
    /// before iOS 26 (content scrolls under the translucent ones).
    @ViewBuilder
    func ppBottomBar<Bar: View, Background: ShapeStyle>(
        fallbackBackground: Background,
        @ViewBuilder bar: () -> Bar
    ) -> some View {
        if #available(iOS 26, *) {
            self.safeAreaBar(edge: .bottom) { bar() }
        } else {
            self.safeAreaInset(edge: .bottom) { bar().background(fallbackBackground) }
        }
    }

    /// The primary button in a `ppBottomBar`. iOS 26: large `.glassProminent`
    /// tinted `tint` (the system draws the disabled state). Before 26: `fallback`
    /// re-applies the button style the bar has always used.
    @ViewBuilder
    func ppGlassBarButton<Fallback: View>(
        tint: Color,
        fallback: (Self) -> Fallback
    ) -> some View {
        if #available(iOS 26, *) {
            self
                .buttonStyle(.glassProminent)
                .tint(tint)
                .controlSize(.large)
        } else {
            fallback(self)
        }
    }

    /// The label half of `ppGlassBarButton`: before 26, `legacy` adds the fill,
    /// padding and foreground the label has always drawn itself. On iOS 26 the
    /// label stays bare so the glass button supplies them.
    @ViewBuilder
    func ppLegacyBarLabel<Legacy: View>(_ legacy: (Self) -> Legacy) -> some View {
        if #available(iOS 26, *) {
            self
        } else {
            legacy(self)
        }
    }

    /// A tall control panel pinned by `ppBottomBar(fallbackBackground:)` (the
    /// scorecard's hole editor). iOS 26: a regular-glass card inset from the
    /// screen edges, so the controls get their own surface while the content
    /// scrolls behind. No-op before 26 — the bar's fallback background covers it.
    @ViewBuilder
    func ppBarPanelGlass(cornerRadius: CGFloat = 24) -> some View {
        if #available(iOS 26, *) {
            self
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .padding(.horizontal, .spacingMedium)
                .padding(.bottom, .spacingSmall)
        } else {
            self
        }
    }

    /// A control panel floating over video or the camera: Liquid Glass tinted
    /// dark on iOS 26, with the dark scheme forced so the glass never flips light
    /// behind the panels' white glyphs over a bright frame. Before 26, `fallback`
    /// applies the panel's existing material so its look is unchanged.
    /// `interactive` adds the glass press response — pass it for buttons.
    @ViewBuilder
    func ppDarkGlassPanel<S: Shape, Fallback: View>(
        in shape: S,
        tint: Color? = nil,
        interactive: Bool = false,
        fallback: (Self) -> Fallback
    ) -> some View {
        if #available(iOS 26, *) {
            self
                .glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
                .environment(\.colorScheme, .dark)
        } else {
            fallback(self)
        }
    }

    /// A small control or badge floating over video or the camera — circle
    /// buttons, the Back capsule, the zoom readout. iOS 26: dark Liquid Glass
    /// (`interactive` for buttons). Before 26: the plain `.ultraThinMaterial`
    /// fill these controls always had.
    func ppOverlayGlass<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        ppDarkGlassPanel(in: shape, interactive: interactive) {
            $0.background(.ultraThinMaterial, in: shape)
        }
    }

    /// The large tag / trim / save panel floating over a paused clip. iOS 26:
    /// dark Liquid Glass with a light black tint so its white copy holds up over
    /// a bright frame (glass draws its own depth, so no shadow). Before 26: the
    /// hand-built material + gradient stack these panels have always used.
    func ppVideoOverlayPanel(cornerRadius: CGFloat = 28) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return ppDarkGlassPanel(in: shape, tint: .black.opacity(0.25)) {
            $0
                .background(
                    ZStack {
                        shape.fill(.ultraThinMaterial)
                        shape.fill(LinearGradient.glassDark)
                        VStack {
                            shape.fill(LinearGradient.glassShine)
                                .frame(height: 100)
                            Spacer()
                        }
                        .clipShape(shape)
                    }
                )
                .overlay(shape.strokeBorder(LinearGradient.glassBorder, lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 30, x: 0, y: 15)
        }
    }

    /// A light surface floating over content — toasts, top banners. iOS 26:
    /// regular Liquid Glass in the app's (light) scheme; glass draws its own
    /// depth, so no shadow. Before 26: `fallback` applies the material + shadow
    /// the surface has always used.
    @ViewBuilder
    func ppFloatingGlass<S: Shape, Fallback: View>(
        in shape: S,
        fallback: (Self) -> Fallback
    ) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            fallback(self)
        }
    }

    /// The top-of-screen notification card (activity, highlight reel, milestone).
    /// iOS 26: floating glass. Before 26: the regular-material card with its soft
    /// drop shadow.
    func ppBannerGlass() -> some View {
        let shape = RoundedRectangle(cornerRadius: .cornerXLarge)
        return ppFloatingGlass(in: shape) {
            $0
                .background(.regularMaterial, in: shape)
                .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
        }
    }

    /// A progress HUD centered over a dimmed screen. iOS 26: dark Liquid Glass,
    /// so the white copy and spinner stay legible over whatever sits behind the
    /// dimmer. Before 26: the `.ultraThinMaterial` card these HUDs always used.
    func ppHUDGlass(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        return ppDarkGlassPanel(in: shape) {
            $0.background(.ultraThinMaterial, in: shape)
        }
    }
}
