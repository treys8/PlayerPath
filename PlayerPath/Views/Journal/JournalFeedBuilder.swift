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
    case practices
    case highlights

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:        return "All"
        case .games:      return "Games"
        case .golf:       return "Golf"
        case .practices:  return "Practices"
        case .highlights: return "Highlights"
        }
    }

    /// Whether a feed entry belongs under this filter. `.games` is baseball/
    /// softball games only (golf rounds live under `.golf`) so the two pills
    /// never overlap; `.practices` is any practice; `.highlights` cross-cuts.
    func matches(_ entry: JournalEntry) -> Bool {
        switch self {
        case .all:
            return true
        case .games:
            if case .game = entry { return !entry.isGolf }
            return false
        case .golf:
            return entry.isGolf
        case .practices:
            if case .practice = entry { return true }
            return false
        case .highlights:
            return entry.containsHighlight
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
        orphanPhotos: [Photo],
        filter: JournalFilter
    ) -> [JournalEntry] {
        var entries: [JournalEntry] = []
        entries.reserveCapacity(games.count + practices.count + orphanClips.count + orphanPhotos.count)
        entries.append(contentsOf: games.map(JournalEntry.game))
        entries.append(contentsOf: practices.map(JournalEntry.practice))
        entries.append(contentsOf: orphanClips.map(JournalEntry.clip))
        entries.append(contentsOf: orphanPhotos.map(JournalEntry.photo))

        return entries
            .filter { filter.matches($0) }
            .sorted { $0.date > $1.date }
    }

    /// Clips with no game/practice parent — the only clips that earn their own
    /// feed row (parented clips are counted inside their parent entry).
    static func orphans(from clips: [VideoClip]) -> [VideoClip] {
        clips.filter { $0.game == nil && $0.practice == nil }
    }

    /// Photos with no game/practice parent — the only photos that earn their own
    /// feed row (parented photos are counted inside their parent entry).
    static func orphans(from photos: [Photo]) -> [Photo] {
        photos.filter { $0.game == nil && $0.practice == nil }
    }
}
