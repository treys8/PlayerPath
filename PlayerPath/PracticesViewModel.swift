import Foundation
import SwiftUI

@MainActor @Observable
final class PracticesViewModel {
    // MARK: - Filter State
    enum SortOrder: String, CaseIterable, Identifiable {
        case newestFirst = "Newest First"
        case oldestFirst = "Oldest First"
        case mostVideos = "Most Videos"
        case mostNotes = "Most Notes"
        var id: String { rawValue }
    }

    var searchText: String = ""
    var selectedSeasonFilter: String?
    var sortOrder: SortOrder = .newestFirst

    // MARK: - Loading & Pagination
    var isLoading = true
    var displayLimit = 50
    var hasMore: Bool { allFilteredPractices.count > displayLimit }

    // MARK: - Results
    private(set) var filteredPractices: [Practice] = []
    private(set) var practicesSummary: String = ""
    private(set) var availableSeasons: [Season] = []

    // MARK: - Private
    private var allPractices: [Practice] = []
    private var allFilteredPractices: [Practice] = []
    private static let summaryDateFormatter = DateFormatter.compactDate

    // MARK: - Public API

    /// Call when source data changes
    func update(practices: [Practice]) {
        allPractices = practices
        refilter()
    }

    /// Call when any filter property changes
    func refilter() {
        // Sort
        var sorted: [Practice]
        switch sortOrder {
        case .newestFirst:
            sorted = allPractices.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        case .oldestFirst:
            sorted = allPractices.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
        case .mostVideos:
            sorted = allPractices.sorted { ($0.videoClips?.count ?? 0) > ($1.videoClips?.count ?? 0) }
        case .mostNotes:
            sorted = allPractices.sorted { ($0.notes?.count ?? 0) > ($1.notes?.count ?? 0) }
        }

        // Season filter
        if let seasonFilter = selectedSeasonFilter {
            sorted = sorted.filter { practice in
                if seasonFilter == "no_season" {
                    return practice.season == nil
                } else {
                    return practice.season?.id.uuidString == seasonFilter
                }
            }
        }

        // Search filter
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let q = trimmed.lowercased()
            sorted = sorted.filter { matchesSearch($0, query: q) }
        }

        allFilteredPractices = sorted
        displayLimit = 50
        filteredPractices = Array(sorted.prefix(displayLimit))
        practicesSummary = computeSummary(from: sorted)
        updateAvailableSeasons()
        isLoading = false
    }

    func loadMore() {
        displayLimit += 50
        filteredPractices = Array(allFilteredPractices.prefix(displayLimit))
    }

    // MARK: - Private

    private func matchesSearch(_ practice: Practice, query q: String) -> Bool {
        let dateString = (practice.date ?? .distantPast)
            .formatted(date: .abbreviated, time: .omitted)
            .lowercased()
        let matchesDate = dateString.contains(q)
        let matchesSeason = practice.season?.displayName.lowercased().contains(q) ?? false
        let matchesNotes = (practice.notes ?? []).contains { $0.content.lowercased().contains(q) }
        let matchesType = practice.type.displayName.lowercased().contains(q)
        return matchesDate || matchesSeason || matchesNotes || matchesType
    }

    private func computeSummary(from practices: [Practice]) -> String {
        let count = practices.count
        guard count > 0 else { return "" }
        let videoCount = practices.reduce(0) { $0 + ($1.videoClips?.count ?? 0) }
        let noteCount = practices.reduce(0) { $0 + ($1.notes?.count ?? 0) }
        let dates = practices.compactMap(\.date)
        guard let oldest = dates.min(), let newest = dates.max() else {
            return "\(count) practice\(count == 1 ? "" : "s") \u{2022} \(videoCount) videos"
        }
        let dateRange = "\(Self.summaryDateFormatter.string(from: oldest)) - \(Self.summaryDateFormatter.string(from: newest))"
        return "\(count) practices \u{2022} \(videoCount) videos \u{2022} \(noteCount) notes \u{2022} \(dateRange)"
    }

    private func updateAvailableSeasons() {
        let seasons = allPractices.compactMap { $0.season }
        let uniqueSeasons = Array(Set(seasons))
        availableSeasons = uniqueSeasons.sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
    }
}
