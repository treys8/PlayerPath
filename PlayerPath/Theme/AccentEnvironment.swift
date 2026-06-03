//
//  AccentEnvironment.swift
//  PlayerPath
//
//  Sport-resolved accent, carried through the environment.
//
//  The brand accent is ONE accent that resolves by the active sport (terracotta
//  for baseball/softball, fairway green for golf — see Theme). Views read the
//  resolved color via `@Environment(\.ppAccent)` instead of the static
//  `Theme.accent`, so an athlete's sport re-tints the whole subtree.
//
//  Injected once at the tab roots from the active athlete's sport (and overridden
//  locally on the Stats screen by the Baseball/Golf selection). The default is
//  the terracotta base, so any surface that never injects — sport-neutral chrome,
//  mixed-sport views, auth/onboarding — stays on base. There is never more than
//  one accent visible at a time; the environment just decides which one.
//

import SwiftUI

private struct PPAccentKey: EnvironmentKey {
    static let defaultValue: Color = Theme.accent
}

private struct PPAccentLightKey: EnvironmentKey {
    static let defaultValue: Color = Theme.accentLight
}

extension EnvironmentValues {
    /// The active accent, resolved by the current athlete's sport. Defaults to
    /// the terracotta base when nothing upstream injects a sport.
    var ppAccent: Color {
        get { self[PPAccentKey.self] }
        set { self[PPAccentKey.self] = newValue }
    }

    /// The dark-surface variant of `ppAccent` (labels / telestration over video).
    var ppAccentLight: Color {
        get { self[PPAccentLightKey.self] }
        set { self[PPAccentLightKey.self] = newValue }
    }
}

extension View {
    /// Resolve the accent for `isGolf` and inject it (plus its dark-surface
    /// variant and a matching `.tint`) into this subtree's environment.
    func ppAccent(forGolf isGolf: Bool) -> some View {
        self
            .environment(\.ppAccent, Theme.accent(forGolf: isGolf))
            .environment(\.ppAccentLight, Theme.accentLight(forGolf: isGolf))
            .tint(Theme.accent(forGolf: isGolf))
    }

    /// Resolve the accent from an optional `Sport` and inject it into this
    /// subtree's environment. `nil` → terracotta base.
    func ppAccent(for sport: Sport?) -> some View {
        ppAccent(forGolf: sport == .golf)
    }
}
