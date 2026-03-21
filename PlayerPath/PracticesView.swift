//
//  PracticesView.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import SwiftUI
import SwiftData
import os

private let log = Logger(subsystem: "com.playerpath.app", category: "Practices")

// MARK: - PracticeType Color Extension (SwiftUI-only, kept out of Models.swift)

extension PracticeType {
    var color: Color {
        switch self {
        case .general:  return .brandNavy
        case .batting:  return .orange
        case .fielding: return .green
        case .bullpen:  return .red
        case .team:     return .purple
        }
    }
}

// MARK: - Convenience accessor on Practice

extension Practice {
    var type: PracticeType {
        get { PracticeType(rawValue: practiceType) ?? .general }
        set { practiceType = newValue.rawValue }
    }
}

struct PracticesView: View {
    let athlete: Athlete?
    @Environment(\.modelContext) private var modelContext
    @State private var searchText: String = ""
    @State private var selectedSeasonFilter: String? = nil
    @State private var navigateToPractice: Practice?

    enum SortOrder: String, CaseIterable, Identifiable {
        case newestFirst = "Newest First"
        case oldestFirst = "Oldest First"
        case mostVideos = "Most Videos"
        case mostNotes = "Most Notes"

        var id: String { rawValue }
    }

    @State private var sortOrder: SortOrder = .newestFirst

    // Cached arrays (updated via updatePracticesCache)
    @State private var cachedPractices: [Practice] = []
    @State private var cachedFilteredPractices: [Practice] = []
    @State private var cachedPracticesSummary: String = ""
    @State private var cachedAvailableSeasons: [Season] = []

    // Check if filters are active
    private var hasActiveFilters: Bool {
        selectedSeasonFilter != nil ||
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // Check if we have any practices at all (before filtering)
    private var hasAnyPractices: Bool {
        !(athlete?.practices?.isEmpty ?? true)
    }

    private func updatePracticesCache() {
        // Sort practices
        let items = athlete?.practices ?? []
        switch sortOrder {
        case .newestFirst:
            cachedPractices = items.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        case .oldestFirst:
            cachedPractices = items.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
        case .mostVideos:
            cachedPractices = items.sorted { ($0.videoClips?.count ?? 0) > ($1.videoClips?.count ?? 0) }
        case .mostNotes:
            cachedPractices = items.sorted { ($0.notes?.count ?? 0) > ($1.notes?.count ?? 0) }
        }

        // Filter practices
        var filtered: [Practice] = cachedPractices
        if let seasonFilter = selectedSeasonFilter {
            filtered = filtered.filter { practice in
                if seasonFilter == "no_season" {
                    return practice.season == nil
                } else {
                    return practice.season?.id.uuidString == seasonFilter
                }
            }
        }
        let trimmed: String = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let q: String = trimmed.lowercased()
            filtered = filtered.filter { practice in
                matchesSearch(practice, query: q)
            }
        }
        cachedFilteredPractices = filtered

        // Compute summary
        cachedPracticesSummary = computePracticesSummary(from: filtered)

        // Available seasons
        let seasons = (athlete?.practices ?? []).compactMap { $0.season }
        let uniqueSeasons = Array(Set(seasons))
        cachedAvailableSeasons = uniqueSeasons.sorted { ($0.startDate ?? Date.distantPast) > ($1.startDate ?? Date.distantPast) }
    }

    private var filterDescription: String {
        var parts: [String] = []

        if let seasonID = selectedSeasonFilter {
            if seasonID == "no_season" {
                parts.append("season: None")
            } else if let season = cachedAvailableSeasons.first(where: { $0.id.uuidString == seasonID }) {
                parts.append("season: \(season.displayName)")
            }
        }

        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("search: \"\(searchText)\"")
        }

        return parts.isEmpty ? "your filters" : parts.joined(separator: ", ")
    }

    private func clearAllFilters() {
        Haptics.light()
        withAnimation {
            selectedSeasonFilter = nil
            searchText = ""
        }
    }

    private func matchesSearch(_ practice: Practice, query q: String) -> Bool {
        let dateString: String = (practice.date ?? .distantPast)
            .formatted(date: .abbreviated, time: .omitted)
            .lowercased()

        let matchesDate: Bool = dateString.contains(q)
        let matchesSeason: Bool = practice.season?.displayName.lowercased().contains(q) ?? false
        let matchesNotes: Bool = (practice.notes ?? []).contains { note in
            note.content.lowercased().contains(q)
        }
        let matchesType: Bool = practice.type.displayName.lowercased().contains(q)

        return matchesDate || matchesSeason || matchesNotes || matchesType
    }

    @ViewBuilder
    private var practicesContent: some View {
        if cachedFilteredPractices.isEmpty {
            if hasActiveFilters && hasAnyPractices {
                FilteredEmptyStateView(
                    filterDescription: filterDescription,
                    onClearFilters: clearAllFilters
                )
            } else {
                EmptyPracticesView {
                    quickCreatePractice(type: .general)
                }
            }
        } else {
            practicesListContent
        }
    }

    @ViewBuilder
    private var practicesListContent: some View {
        VStack(spacing: 0) {
            if let athlete = athlete {
                let seasonRecommendation = SeasonManager.checkSeasonStatus(for: athlete)
                if seasonRecommendation.message != nil {
                    SeasonRecommendationBanner(athlete: athlete, recommendation: seasonRecommendation)
                        .padding()
                }
            }

            List {
                if !cachedFilteredPractices.isEmpty {
                    HStack {
                        Image(systemName: "chart.bar.fill")
                            .foregroundStyle(.green)
                            .font(.caption)

                        Text(cachedPracticesSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .minimumScaleFactor(0.8)

                        Spacer()
                    }
                }

                ForEach(cachedFilteredPractices, id: \.persistentModelID) { practice in
                    NavigationLink(destination: PracticeDetailView(practice: practice)) {
                        PracticeCard(practice: practice)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            deleteSinglePractice(practice)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .refreshable {
                await refreshPractices()
            }
        }
    }

    @ToolbarContentBuilder
    private var practicesToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    quickCreatePractice(type: .general)
                } label: {
                    Label("General Practice", systemImage: PracticeType.general.icon)
                }
                ForEach(PracticeType.allCases.filter { $0 != .general }) { type in
                    Button {
                        quickCreatePractice(type: type)
                    } label: {
                        Label(type.displayName, systemImage: type.icon)
                    }
                }
            } label: {
                Image(systemName: "plus")
            } primaryAction: {
                quickCreatePractice(type: .general)
            }
            .accessibilityLabel("Add Practice")
        }

        if !cachedPractices.isEmpty {
            ToolbarItem(placement: .topBarLeading) {
                SeasonFilterMenu(
                    selectedSeasonID: $selectedSeasonFilter,
                    availableSeasons: cachedAvailableSeasons,
                    showNoSeasonOption: (athlete?.practices ?? []).contains(where: { $0.season == nil })
                )
            }
        }

        if !cachedPractices.isEmpty {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort", selection: $sortOrder) {
                        ForEach(SortOrder.allCases) { order in
                            Label(order.rawValue, systemImage: getSortIcon(order)).tag(order)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down.circle")
                }
                .accessibilityLabel("Sort practices")
            }
        }
    }

    var body: some View {
        practicesContent
        .onAppear {
            AnalyticsService.shared.trackScreenView(screenName: "Practices", screenClass: "PracticesView")
            updatePracticesCache()
        }
        .onChange(of: searchText) { _, _ in updatePracticesCache() }
        .onChange(of: selectedSeasonFilter) { _, _ in updatePracticesCache() }
        .onChange(of: sortOrder) { _, _ in updatePracticesCache() }
        .onChange(of: athlete?.practices?.count) { _, _ in updatePracticesCache() }
        .navigationTitle("Practices")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic))
        .toolbar { practicesToolbar }
        .navigationDestination(item: $navigateToPractice) { practice in
            PracticeDetailView(practice: practice)
        }
    }

    // MARK: - Quick Create

    private func quickCreatePractice(type: PracticeType) {
        guard let athlete = athlete else { return }

        let practice = Practice(date: Date())
        practice.practiceType = type.rawValue
        practice.athlete = athlete
        practice.needsSync = true

        if athlete.practices == nil {
            athlete.practices = []
        }
        athlete.practices?.append(practice)
        modelContext.insert(practice)

        SeasonManager.linkPracticeToActiveSeason(practice, for: athlete, in: modelContext)

        do {
            try modelContext.save()

            AnalyticsService.shared.trackPracticeCreated(
                practiceID: practice.id.uuidString,
                seasonID: practice.season?.id.uuidString
            )

            Task {
                if let user = athlete.user {
                    do {
                        try await SyncCoordinator.shared.syncPractices(for: user)
                    } catch {
                        log.error("Failed to sync practice to Firestore: \(error.localizedDescription)")
                    }
                }
            }

            Haptics.success()
            navigateToPractice = practice
        } catch {
            Haptics.error()
            log.error("Failed to save practice: \(error.localizedDescription)")
        }
    }

    private func deleteSinglePractice(_ practice: Practice) {
        // Sync deletion to Firestore if practice was synced
        if let firestoreId = practice.firestoreId,
           let athlete = practice.athlete,
           let user = athlete.user {
            let userId = user.id.uuidString
            Task {
                await retryAsync {
                    try await FirestoreManager.shared.deletePractice(userId: userId, practiceId: firestoreId)
                }
            }
        }

        let practiceAthlete = practice.athlete

        withAnimation {
            practice.delete(in: modelContext)

            Task {
                do {
                    try modelContext.save()

                    // Recalculate athlete statistics to reflect the removed play results
                    if let athlete = practiceAthlete {
                        try StatisticsService.shared.recalculateAthleteStatistics(for: athlete, context: modelContext)
                    }

                    Haptics.success()
                    log.info("Successfully deleted practice")
                } catch {
                    Haptics.error()
                    log.error("Failed to delete practice: \(error.localizedDescription)")
                }
            }
        }
    }

    @MainActor
    private func refreshPractices() async {
        Haptics.light()
        updatePracticesCache()
    }

    private static let summaryDateFormatter = DateFormatter.mediumDate

    private func computePracticesSummary(from practices: [Practice]) -> String {
        let practiceCount = practices.count
        guard practiceCount > 0 else { return "" }

        let videoCount = practices.reduce(0) { $0 + ($1.videoClips?.count ?? 0) }
        let noteCount = practices.reduce(0) { $0 + ($1.notes?.count ?? 0) }

        let dates = practices.compactMap(\.date)
        guard let oldest = dates.min(), let newest = dates.max() else {
            return "\(practiceCount) practice\(practiceCount == 1 ? "" : "s") • \(videoCount) videos"
        }

        let dateRange = "\(Self.summaryDateFormatter.string(from: oldest)) - \(Self.summaryDateFormatter.string(from: newest))"

        return "\(practiceCount) practices • \(videoCount) videos • \(noteCount) notes • \(dateRange)"
    }

    private func getSortIcon(_ order: SortOrder) -> String {
        switch order {
        case .newestFirst:
            return "arrow.down"
        case .oldestFirst:
            return "arrow.up"
        case .mostVideos:
            return "video"
        case .mostNotes:
            return "note.text"
        }
    }
}

#Preview {
    PracticesView(athlete: nil)
}
