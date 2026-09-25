//
//  JournalRoute.swift
//  PlayerPath
//
//  Value-based push targets for the Home (Journal) navigation stack. Journal
//  pushes MUST go through MainTabView's `homePath` so that re-tapping the Home
//  tab and the Live Now accessory's `openJournalRoot()` can actually pop them —
//  a closure-destination `NavigationLink { … }` never touches the path, which
//  left `homePath` permanently empty. Carries IDs, not @Models, so a stale path
//  entry can never hold a deleted model; JournalView resolves them against its
//  live @Query arrays.
//

import Foundation

enum JournalRoute: Hashable {
    case game(UUID)
    case practice(UUID)
}
