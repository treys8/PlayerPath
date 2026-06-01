//
//  Pluralize.swift
//  PlayerPath
//
//  Tiny count-pluralization helper so rendered counts read "1 Game" / "3 Games"
//  instead of a hardcoded "1 Games". Centralized so call sites don't reinvent
//  the `count == 1 ? "" : "s"` ternary (or forget it).
//

import Foundation

extension Int {
    /// The count followed by its noun, pluralized by simple English rules:
    /// `1.pluralized("Game")` → "1 Game", `3.pluralized("Game")` → "3 Games".
    /// Pass an explicit `plural` for irregular nouns (e.g. "Match", "Matches").
    func pluralized(_ singular: String, _ plural: String? = nil) -> String {
        "\(self) \(self == 1 ? singular : (plural ?? singular + "s"))"
    }
}
