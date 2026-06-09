import Foundation
import SwiftUI

@MainActor @Observable
final class VideoClipsViewModel {
    // MARK: - Filter State
    var searchText = ""
    var selectedSeasonFilter: String?
    var filter = VideoClipFilter()

    // MARK: - Loading & Pagination
    var isLoading = true
    var displayLimit = 50
    var hasMore: Bool { allFilteredVideos.count > displayLimit }

    // MARK: - Results
    private(set) var filteredVideos: [VideoClip] = []
    private(set) var filteredVideoIndex: [UUID: Int] = [:]
    private(set) var availableSeasons: [Season] = []
    private(set) var availableOpponents: [String] = []

    // MARK: - Private
    private var allVideos: [VideoClip] = []
    private var allFilteredVideos: [VideoClip] = []
    private static let searchDateFormatter = DateFormatter.mediumDate
    private static let searchShortFormatter = DateFormatter.compactDate

    // MARK: - Public API

    /// Call when source data changes (athlete.videoClips)
    func update(videos: [VideoClip]) {
        allVideos = videos
        updateAvailableSeasons()
        updateAvailableOpponents()
        refilter()
    }

    /// Call when any filter property changes
    func refilter() {
        var videos = allVideos

        // Season filter
        if let seasonFilter = selectedSeasonFilter {
            videos = videos.filter { video in
                if seasonFilter == "no_season" {
                    return video.season == nil
                } else {
                    return video.season?.id.uuidString == seasonFilter
                }
            }
        }

        // Combinable attribute filters (highlights / coach feedback / untagged /
        // play result / club / opponent) — all dimensions AND together.
        if filter.isActive {
            videos = videos.filter { filter.matches($0) }
        }

        // Search filter
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            videos = videos.filter { video in
                video.fileName.lowercased().contains(query) ||
                (video.displayTagName?.lowercased().contains(query) ?? false) ||
                (video.game?.opponent.lowercased().contains(query) ?? false) ||
                (video.game?.location?.lowercased().contains(query) ?? false) ||
                (video.game?.season?.displayName.lowercased().contains(query) ?? false) ||
                (video.practice?.season?.displayName.lowercased().contains(query) ?? false) ||
                (video.note?.lowercased().contains(query) ?? false) ||
                (video.createdAt.map { Self.searchDateFormatter.string(from: $0).lowercased() }?.contains(query) ?? false) ||
                (video.createdAt.map { Self.searchShortFormatter.string(from: $0).lowercased() }?.contains(query) ?? false)
            }
        }

        // Sort by creation date (newest first). Tie-break on UUID so the order
        // is deterministic when multiple clips share a `createdAt` — Photos
        // library imports often land on the same second-precision capture date
        // and `Array.sorted(by:)` is not stable.
        let sorted = videos.sorted { (lhs: VideoClip, rhs: VideoClip) in
            switch (lhs.createdAt, rhs.createdAt) {
            case let (l?, r?):
                if l != r { return l > r }
                return lhs.id.uuidString < rhs.id.uuidString
            case (nil, _?): return false
            case (_?, nil): return true
            case (nil, nil): return lhs.id.uuidString < rhs.id.uuidString
            }
        }
        allFilteredVideos = sorted
        displayLimit = 50
        filteredVideos = Array(sorted.prefix(displayLimit))

        // Build O(1) index map
        var indexMap: [UUID: Int] = [:]
        indexMap.reserveCapacity(filteredVideos.count)
        for (i, clip) in filteredVideos.enumerated() {
            indexMap[clip.id] = i
        }
        filteredVideoIndex = indexMap
        isLoading = false
    }

    func loadMore() {
        displayLimit += 50
        filteredVideos = Array(allFilteredVideos.prefix(displayLimit))

        // Rebuild index map
        var indexMap: [UUID: Int] = [:]
        indexMap.reserveCapacity(filteredVideos.count)
        for (i, clip) in filteredVideos.enumerated() {
            indexMap[clip.id] = i
        }
        filteredVideoIndex = indexMap
    }

    /// Call from `.onAppear` on each grid item. Loads the next page when the
    /// user scrolls within 10 items of the current display limit.
    func onItemAppear(_ video: VideoClip) {
        guard hasMore,
              let index = filteredVideoIndex[video.id],
              index >= displayLimit - 10 else { return }
        loadMore()
    }

    // MARK: - Private

    private func updateAvailableSeasons() {
        let seasons = allVideos.compactMap { $0.season }
        let uniqueSeasons = Array(Set(seasons))
        availableSeasons = uniqueSeasons.sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
    }

    /// Distinct opponents across the current clip set, for the Opponent filter
    /// menu. Prefers the live game relationship, falls back to the denormalized
    /// `gameOpponent` (matches `VideoClipFilter.opponentName`). Blank names dropped.
    private func updateAvailableOpponents() {
        let names = allVideos.compactMap { clip -> String? in
            let raw = (clip.game?.opponent ?? clip.gameOpponent)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (raw?.isEmpty == false) ? raw : nil
        }
        availableOpponents = Array(Set(names)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
