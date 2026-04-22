import Foundation
import SwiftUI

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
    var hasMore: Bool { allFilteredHighlights.count > displayLimit }
    var totalCount: Int { allFilteredHighlights.count }

    // MARK: - Results
    private(set) var highlights: [VideoClip] = []
    private(set) var highlightsIndex: [UUID: Int] = [:]
    private(set) var availableSeasons: [Season] = []
    private(set) var hasNoSeasonClips: Bool = false

    // MARK: - Private
    private var allVideoClips: [VideoClip] = []
    private var allFilteredHighlights: [VideoClip] = []
    private static let searchDateFormatter = DateFormatter.mediumDate
    private static let searchShortFormatter = DateFormatter.compactDate

    // MARK: - Public API

    /// Call when source data changes
    func update(videoClips: [VideoClip]) {
        allVideoClips = videoClips
        updateAvailableSeasons()
        refilter()
    }

    /// Call when any filter property changes
    func refilter() {
        recomputeHighlights()
    }

    // MARK: - Private

    private func recomputeHighlights() {
        var filtered = allVideoClips.filter { $0.isHighlight }

        // Season filter
        if let seasonFilter = selectedSeasonFilter {
            filtered = filtered.filter { clip in
                if seasonFilter == "no_season" {
                    return clip.season == nil
                } else {
                    return clip.season?.id.uuidString == seasonFilter
                }
            }
        }

        // Type filter
        filtered = filtered.filter { clip in
            switch filter {
            case .all: return true
            case .game: return clip.game != nil
            case .practice: return clip.practice != nil
            }
        }

        // Search filter
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            filtered = filtered.filter { clip in
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

        // Sort
        let sorted = filtered.sorted { lhs, rhs in
            let l = lhs.createdAt ?? .distantPast
            let r = rhs.createdAt ?? .distantPast
            return sortOrder == .newest ? (l > r) : (l < r)
        }
        allFilteredHighlights = sorted
        displayLimit = 50
        highlights = Array(sorted.prefix(displayLimit))
        rebuildHighlightsIndex()
        isLoading = false
    }

    func loadMore() {
        displayLimit += 50
        highlights = Array(allFilteredHighlights.prefix(displayLimit))
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

    /// Call from `.onAppear` on each grid item. Loads the next page when the
    /// user scrolls within 10 items of the current display limit.
    func onItemAppear(_ clip: VideoClip) {
        guard hasMore,
              let index = highlightsIndex[clip.id],
              index >= displayLimit - 10 else { return }
        loadMore()
    }

    private func updateAvailableSeasons() {
        let highlightClips = allVideoClips.filter { $0.isHighlight }
        let seasons = highlightClips.compactMap { $0.season }
        let uniqueSeasons = Array(Set(seasons))
        availableSeasons = uniqueSeasons.sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
        hasNoSeasonClips = highlightClips.contains(where: { $0.season == nil })
    }
}
