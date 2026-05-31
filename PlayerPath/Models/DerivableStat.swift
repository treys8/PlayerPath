//
//  DerivableStat.swift
//  PlayerPath
//
//  The complete allowlist of batting stats PlayerPath is permitted to SHOW in
//  any derived grid or surface. RBI and runs are deliberately ABSENT: the
//  visual overhaul removed them from the UI, and this list is the guard that
//  keeps them out. A stat surface should drive its rows from
//  `DerivableStat.allCases` (or gate on `isDisplayable`) so a future edit can't
//  silently reintroduce a non-derivable, removed stat.
//
//  "Derivable" = computable from at-bats and hit outcomes alone (the data a
//  clip tag carries). Runs and RBIs depend on baserunner/team context the app
//  doesn't model, which is exactly why they were cut.
//

import Foundation

enum DerivableStat: String, CaseIterable {
    case games      = "Games"
    case atBats     = "AB"
    case hits       = "H"
    case singles    = "1B"
    case doubles    = "2B"
    case triples    = "3B"
    case homeRuns   = "HR"
    case walks      = "BB"
    case strikeouts = "K"
    case average    = "AVG"
    case onBase     = "OBP"
    case slugging   = "SLG"
    case ops        = "OPS"

    /// Stats explicitly banned from every UI surface, in any phrasing.
    private static let banned: Set<String> = ["RBI", "RBIS", "R", "RUN", "RUNS"]

    /// True iff a stat key / abbreviation is on the allowlist. Case- and
    /// whitespace-insensitive. Banned keys (RBI / runs) always return false.
    static func isDisplayable(_ key: String) -> Bool {
        let normalized = key.trimmingCharacters(in: .whitespaces).uppercased()
        if banned.contains(normalized) { return false }
        return allCases.contains { $0.rawValue.uppercased() == normalized }
    }
}
