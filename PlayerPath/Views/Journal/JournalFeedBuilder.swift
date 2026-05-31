//
//  JournalFeedBuilder.swift
//  PlayerPath
//
//  Visual overhaul — pure merge/sort for the Journal feed.
//  Consumes already-fetched arrays (no querying here) and returns a single
//  reverse-chron list of entries. Kept separate from the view so the feed
//  logic is testable and the view stays declarative.
//

import Foundation

enum JournalFilter: String, CaseIterable, Identifiable {
    case all
    case games
    case golf
    case highlights

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:        return "All"
        case .games:      return "Games"
        case .golf:       return "Golf"
        case .highlights: return "Highlights"
        }
    }
}

enum JournalFeedBuilder {

    /// Merge games, practices, and orphaned clips into one reverse-chron feed.
    /// - `orphanClips` should already exclude clips attached to a game/practice
    ///   (those surface via their parent entry) — see `orphans(from:)`.
    static func build(
        games: [Game],
        practices: [Practice],
        orphanClips: [VideoClip],
        filter: JournalFilter
    ) -> [JournalEntry] {
        var entries: [JournalEntry] = []
        entries.reserveCapacity(games.count + practices.count + orphanClips.count)
        entries.append(contentsOf: games.map(JournalEntry.game))
        entries.append(contentsOf: practices.map(JournalEntry.practice))
        entries.append(contentsOf: orphanClips.map(JournalEntry.clip))

        return entries
            .filter { matches($0, filter) }
            .sorted { $0.date > $1.date }
    }

    /// Clips with no game/practice parent — the only clips that earn their own
    /// feed row (parented clips are counted inside their parent entry).
    static func orphans(from clips: [VideoClip]) -> [VideoClip] {
        clips.filter { $0.game == nil && $0.practice == nil }
    }

    private static func matches(_ entry: JournalEntry, _ filter: JournalFilter) -> Bool {
        switch filter {
        case .all:
            return true
        case .games:
            if case .game = entry { return true }
            return false
        case .golf:
            return entry.isGolf
        case .highlights:
            return entry.containsHighlight
        }
    }
}
