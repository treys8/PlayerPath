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
    private(set) var groupedHighlights: [GameHighlightGroup] = []
    private(set) var availableSeasons: [Season] = []

    // MARK: - Private
    private var allVideoClips: [VideoClip] = []
    private var allFilteredHighlights: [VideoClip] = []
    private var lastGroupInputHash: Int = 0

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

    /// Call when expandedGroups changes (UI state affects grouping)
    func recomputeGroups(expandedGroups: Set<UUID>) {
        recomputeGroupedHighlights(expandedGroups: expandedGroups)
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
            case .practice: return clip.game == nil
            }
        }

        // Search filter
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let q = searchText.lowercased()
            filtered = filtered.filter { clip in
                let opponent = clip.game?.opponent.lowercased() ?? ""
                let result = clip.playResult?.type.displayName.lowercased() ?? ""
                let fileName = clip.fileName.lowercased()
                return opponent.contains(q) || result.contains(q) || fileName.contains(q)
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
        isLoading = false
    }

    func loadMore() {
        displayLimit += 50
        highlights = Array(allFilteredHighlights.prefix(displayLimit))
    }

    /// Call from `.onAppear` on each grid item. Loads the next page when the
    /// user scrolls within 10 items of the current display limit.
    func onItemAppear(_ clip: VideoClip) {
        guard hasMore,
              let index = highlights.firstIndex(where: { $0.id == clip.id }),
              index >= displayLimit - 10 else { return }
        loadMore()
    }

    private func recomputeGroupedHighlights(expandedGroups: Set<UUID>) {
        let clips = highlights

        // Memoization guard
        var hasher = Hasher()
        hasher.combine(clips.count)
        hasher.combine(sortOrder)
        hasher.combine(expandedGroups)
        for clip in clips.prefix(20) { hasher.combine(clip.id) }
        let inputHash = hasher.finalize()
        guard inputHash != lastGroupInputHash else { return }
        lastGroupInputHash = inputHash

        // Group by game
        var gameClips: [UUID: [VideoClip]] = [:]
        var practiceClips: [VideoClip] = []

        for clip in clips {
            if let game = clip.game {
                gameClips[game.id, default: []].append(clip)
            } else {
                practiceClips.append(clip)
            }
        }

        // Build groups
        var groups: [GameHighlightGroup] = gameClips.map { gameID, clips in
            let sortedClips = clips.sorted { lhs, rhs in
                let l = lhs.createdAt ?? .distantPast
                let r = rhs.createdAt ?? .distantPast
                return l < r
            }
            return GameHighlightGroup(
                id: gameID,
                game: clips.first?.game,
                clips: sortedClips,
                isExpanded: expandedGroups.contains(gameID)
            )
        }

        for clip in practiceClips {
            groups.append(GameHighlightGroup(
                id: clip.id,
                game: nil,
                clips: [clip],
                isExpanded: true
            ))
        }

        // Sort groups
        groups.sort { lhs, rhs in
            let lDate = lhs.game?.date ?? lhs.clips.first?.createdAt ?? .distantPast
            let rDate = rhs.game?.date ?? rhs.clips.first?.createdAt ?? .distantPast
            return sortOrder == .newest ? (lDate > rDate) : (lDate < rDate)
        }

        // Auto-expand single-clip groups
        groups = groups.map { group in
            var g = group
            if g.clips.count == 1 { g.isExpanded = true }
            return g
        }

        groupedHighlights = groups
    }

    private func updateAvailableSeasons() {
        let highlightClips = allVideoClips.filter { $0.isHighlight }
        let seasons = highlightClips.compactMap { $0.season }
        let uniqueSeasons = Array(Set(seasons))
        availableSeasons = uniqueSeasons.sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
    }
}
