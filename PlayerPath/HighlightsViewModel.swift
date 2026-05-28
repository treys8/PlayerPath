import Foundation
import SwiftUI

/// A single item in the Highlights grid — either a starred VideoClip
/// (athlete- or auto-tagged) or a virtual HighlightReel (v6.1 PR2).
/// Wrapping the two heterogeneous types lets the grid render both in a single
/// sorted feed without duplicating layout code per source.
enum HighlightFeedItem: Identifiable {
    case clip(VideoClip)
    case reel(HighlightReel)

    var id: String {
        switch self {
        case .clip(let c): return "clip-\(c.id.uuidString)"
        case .reel(let r): return "reel-\(r.id.uuidString)"
        }
    }

    var sortDate: Date {
        switch self {
        case .clip(let c): return c.createdAt ?? .distantPast
        case .reel(let r): return r.date
        }
    }
}

extension HighlightFeedItem: Equatable {
    static func == (lhs: HighlightFeedItem, rhs: HighlightFeedItem) -> Bool {
        lhs.id == rhs.id
    }
}

extension HighlightFeedItem: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

@MainActor @Observable
final class HighlightsViewModel {
    // MARK: - Filter State
    enum Filter: String, CaseIterable, Identifiable {
        case all, game, practice
        var id: String { rawValue }
    }
    enum SortOrder: String, CaseIterable, Identifiable {
        case newest, oldest
        var id: String { rawValue }
    }

    var searchText: String = ""
    var filter: Filter = .all
    var sortOrder: SortOrder = .newest
    var selectedSeasonFilter: String?

    // MARK: - Loading & Pagination
    var isLoading = true
    var displayLimit = 50
    var hasMore: Bool { allFilteredFeed.count > displayLimit }
    var totalCount: Int { allFilteredFeed.count }

    // MARK: - Results
    private(set) var highlights: [VideoClip] = []
    private(set) var highlightsIndex: [UUID: Int] = [:]
    private(set) var availableSeasons: [Season] = []
    private(set) var hasNoSeasonClips: Bool = false

    /// Heterogeneous, filtered, paginated feed driving the grid in
    /// HighlightsView. Order matches `highlights` (single-clip entries appear
    /// at the same positions) but also interleaves HighlightReel items.
    private(set) var feed: [HighlightFeedItem] = []
    private(set) var feedIndex: [String: Int] = [:]

    /// Today-dated highlight clips for the "Today's Reel" hero card. Always
    /// computed from the unfiltered source list so user-applied filters
    /// (season/type/search) don't hide the card.
    private(set) var todaysHighlightClips: [VideoClip] = []

    // MARK: - Private
    private var allVideoClips: [VideoClip] = []
    private var allReels: [HighlightReel] = []
    private var allFilteredFeed: [HighlightFeedItem] = []
    private static let searchDateFormatter = DateFormatter.mediumDate
    private static let searchShortFormatter = DateFormatter.compactDate

    // MARK: - Public API

    /// Call when source data changes.
    func update(videoClips: [VideoClip], reels: [HighlightReel] = []) {
        allVideoClips = videoClips
        allReels = reels
        updateAvailableSeasons()
        refilter()
    }

    /// Call when any filter property changes
    func refilter() {
        recomputeFeed()
    }

    // MARK: - Private

    private func recomputeFeed() {
        // 1. Clip side — same logic as before, but no longer the only source.
        var filteredClips: [VideoClip] = allVideoClips.filter { $0.isHighlight }

        if let seasonFilter = selectedSeasonFilter {
            filteredClips = filteredClips.filter { clip in
                if seasonFilter == "no_season" {
                    return clip.season == nil
                } else {
                    return clip.season?.id.uuidString == seasonFilter
                }
            }
        }

        filteredClips = filteredClips.filter { clip in
            switch filter {
            case .all: return true
            case .game: return clip.game != nil
            case .practice: return clip.practice != nil
            }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            filteredClips = filteredClips.filter { clip in
                clip.fileName.lowercased().contains(query) ||
                (clip.playResult?.type.displayName.lowercased().contains(query) ?? false) ||
                (clip.game?.opponent.lowercased().contains(query) ?? false) ||
                (clip.game?.location?.lowercased().contains(query) ?? false) ||
                (clip.game?.season?.displayName.lowercased().contains(query) ?? false) ||
                (clip.practice?.season?.displayName.lowercased().contains(query) ?? false) ||
                (clip.note?.lowercased().contains(query) ?? false) ||
                (clip.createdAt.map { Self.searchDateFormatter.string(from: $0).lowercased() }?.contains(query) ?? false) ||
                (clip.createdAt.map { Self.searchShortFormatter.string(from: $0).lowercased() }?.contains(query) ?? false)
            }
        }

        // 2. Reel side — apply the same UX filters where they apply.
        // - Season: resolve via the parent game (if locatable in allVideoClips).
        // - Type: reels are game-origin in PR2, so .game and .all pass; .practice excludes.
        // - Search: match on displayName / course / hole label.
        let gamesByID: [UUID: Game] = Dictionary(
            uniqueKeysWithValues: allVideoClips.compactMap { clip -> (UUID, Game)? in
                guard let game = clip.game else { return nil }
                return (game.id, game)
            }
        )

        var filteredReels: [HighlightReel] = allReels.filter { !$0.isDeletedRemotely }

        if let seasonFilter = selectedSeasonFilter {
            filteredReels = filteredReels.filter { reel in
                guard let gameID = reel.gameID else { return seasonFilter == "no_season" }
                let parentSeason = gamesByID[gameID]?.season
                if seasonFilter == "no_season" {
                    return parentSeason == nil
                }
                return parentSeason?.id.uuidString == seasonFilter
            }
        }

        filteredReels = filteredReels.filter { _ in
            switch filter {
            case .all, .game: return true
            case .practice: return false
            }
        }

        if !query.isEmpty {
            filteredReels = filteredReels.filter { reel in
                reel.displayName.lowercased().contains(query) ||
                reel.courseOrOpponent.lowercased().contains(query) ||
                "hole \(reel.holeNumber)".contains(query)
            }
        }

        // 3. Merge + sort.
        var merged: [HighlightFeedItem] = filteredClips.map { .clip($0) }
        merged.append(contentsOf: filteredReels.map { .reel($0) })

        let sorted = merged.sorted { lhs, rhs in
            sortOrder == .newest ? (lhs.sortDate > rhs.sortDate) : (lhs.sortDate < rhs.sortDate)
        }

        allFilteredFeed = sorted
        displayLimit = 50
        feed = Array(sorted.prefix(displayLimit))
        rebuildFeedIndex()

        // Keep the legacy `highlights` array in sync — bulk operations and
        // selection still target clips only, so the rest of HighlightsView
        // can continue reading clip-only state from here.
        let clipsOnly: [VideoClip] = sorted.compactMap {
            if case .clip(let c) = $0 { return c } else { return nil }
        }
        highlights = clipsOnly
        rebuildHighlightsIndex()

        recomputeTodaysHighlights()
        isLoading = false
    }

    private func recomputeTodaysHighlights() {
        todaysHighlightClips = allVideoClips
            .filter { $0.isHighlight }
            .filter { $0.game?.date?.isToday == true }
            .sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }

    func loadMore() {
        displayLimit += 50
        feed = Array(allFilteredFeed.prefix(displayLimit))
        rebuildFeedIndex()

        let clipsOnly: [VideoClip] = allFilteredFeed.prefix(displayLimit).compactMap {
            if case .clip(let c) = $0 { return c } else { return nil }
        }
        highlights = clipsOnly
        rebuildHighlightsIndex()
    }

    private func rebuildHighlightsIndex() {
        var indexMap: [UUID: Int] = [:]
        indexMap.reserveCapacity(highlights.count)
        for (i, clip) in highlights.enumerated() {
            indexMap[clip.id] = i
        }
        highlightsIndex = indexMap
    }

    private func rebuildFeedIndex() {
        var indexMap: [String: Int] = [:]
        indexMap.reserveCapacity(feed.count)
        for (i, item) in feed.enumerated() {
            indexMap[item.id] = i
        }
        feedIndex = indexMap
    }

    /// Call from `.onAppear` on each grid item. Loads the next page when the
    /// user scrolls within 10 items of the current display limit.
    func onItemAppear(_ item: HighlightFeedItem) {
        guard hasMore,
              let index = feedIndex[item.id],
              index >= displayLimit - 10 else { return }
        loadMore()
    }

    /// Back-compat overload — older call sites still pass a VideoClip directly.
    func onItemAppear(_ clip: VideoClip) {
        onItemAppear(.clip(clip))
    }

    private func updateAvailableSeasons() {
        let highlightClips = allVideoClips.filter { $0.isHighlight }
        let seasons = highlightClips.compactMap { $0.season }
        let uniqueSeasons = Array(Set(seasons))
        availableSeasons = uniqueSeasons.sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
        hasNoSeasonClips = highlightClips.contains(where: { $0.season == nil })
    }
}
