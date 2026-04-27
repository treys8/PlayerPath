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
    @State private var viewModel = PracticesViewModel()
    @State private var navigateToPractice: Practice?
    @State private var showingAddPractice = false

    // Check if filters are active
    private var hasActiveFilters: Bool {
        viewModel.selectedSeasonFilter != nil ||
        !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // Check if we have any practices at all (before filtering)
    private var hasAnyPractices: Bool {
        !(athlete?.practices?.isEmpty ?? true)
    }

    private var filterDescription: String {
        var parts: [String] = []

        if let seasonID = viewModel.selectedSeasonFilter {
            if seasonID == "no_season" {
                parts.append("season: None")
            } else if let season = viewModel.availableSeasons.first(where: { $0.id.uuidString == seasonID }) {
                parts.append("season: \(season.displayName)")
            }
        }

        if !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("search: \"\(viewModel.searchText)\"")
        }

        return parts.isEmpty ? "your filters" : parts.joined(separator: ", ")
    }

    private func clearAllFilters() {
        Haptics.light()
        withAnimation {
            viewModel.selectedSeasonFilter = nil
            viewModel.searchText = ""
        }
    }

    @ViewBuilder
    private var practicesContent: some View {
        if viewModel.isLoading {
            ListSkeletonView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.filteredPractices.isEmpty {
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
                if !viewModel.filteredPractices.isEmpty {
                    HStack {
                        Image(systemName: "chart.bar.fill")
                            .foregroundStyle(.green)
                            .font(.caption)

                        Text(viewModel.practicesSummary)
                            .font(.bodySmall)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .minimumScaleFactor(0.8)

                        Spacer()
                    }
                }

                ForEach(viewModel.filteredPractices, id: \.persistentModelID) { practice in
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

                if viewModel.hasMore {
                    Button {
                        Haptics.light()
                        viewModel.loadMore()
                    } label: {
                        HStack(spacing: 6) {
                            Text("Load More")
                            Image(systemName: "arrow.down.circle")
                        }
                        .font(.labelLarge)
                        .foregroundColor(.brandNavy)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
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
                Divider()
                Button {
                    showingAddPractice = true
                } label: {
                    Label("Schedule Practice…", systemImage: "calendar.badge.plus")
                }
            } label: {
                Image(systemName: "plus")
            } primaryAction: {
                quickCreatePractice(type: .general)
            }
            .accessibilityLabel("Add Practice")
        }

        if hasAnyPractices {
            ToolbarItem(placement: .topBarLeading) {
                SeasonFilterMenu(
                    selectedSeasonID: $viewModel.selectedSeasonFilter,
                    availableSeasons: viewModel.availableSeasons,
                    showNoSeasonOption: (athlete?.practices ?? []).contains(where: { $0.season == nil })
                )
            }
        }

        if hasAnyPractices {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort", selection: $viewModel.sortOrder) {
                        ForEach(PracticesViewModel.SortOrder.allCases) { order in
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
        .task {
            viewModel.update(practices: athlete?.practices ?? [])
        }
        .onAppear {
            AnalyticsService.shared.trackScreenView(screenName: "Practices", screenClass: "PracticesView")
        }
        .onChange(of: viewModel.searchText) { _, _ in viewModel.resetPagination(); viewModel.refilter() }
        .onChange(of: viewModel.selectedSeasonFilter) { _, _ in viewModel.resetPagination(); viewModel.refilter() }
        .onChange(of: viewModel.sortOrder) { _, _ in viewModel.refilter() }
        .onChange(of: athlete?.practices?.count) { _, _ in viewModel.update(practices: athlete?.practices ?? []) }
        .navigationTitle("Practices")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $viewModel.searchText, placement: .navigationBarDrawer(displayMode: .automatic))
        .toolbar { practicesToolbar }
        .navigationDestination(item: $navigateToPractice) { practice in
            PracticeDetailView(practice: practice)
        }
        .sheet(isPresented: $showingAddPractice) {
            if let athlete {
                AddPracticeView(athlete: athlete) { created in
                    navigateToPractice = created
                }
            }
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

        let saved = ErrorHandlerService.shared.saveContext(modelContext, caller: "PracticesView.quickCreatePractice")
        if saved {
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
        } else {
            Haptics.error()
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
        }

        let saved = ErrorHandlerService.shared.saveContext(modelContext, caller: "PracticesView.deleteSinglePractice")

        if saved, let athlete = practiceAthlete {
            do {
                try StatisticsService.shared.recalculateAthleteStatistics(for: athlete, context: modelContext)
            } catch {
                ErrorHandlerService.shared.handle(error, context: "PracticesView.recalculateAthleteStatistics", showAlert: false)
            }
        }

        viewModel.update(practices: athlete?.practices ?? [])

        if saved {
            Haptics.success()
            log.info("Successfully deleted practice")
        } else {
            Haptics.error()
        }
    }

    @MainActor
    private func refreshPractices() async {
        Haptics.light()
        if let user = athlete?.user {
            do {
                try await SyncCoordinator.shared.syncPractices(for: user)
            } catch {
                log.error("Pull-to-refresh sync failed: \(error.localizedDescription)")
            }
        }
        viewModel.update(practices: athlete?.practices ?? [])
    }

    private func getSortIcon(_ order: PracticesViewModel.SortOrder) -> String {
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
