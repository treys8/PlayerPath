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
        case .general:        return .brandNavy
        case .batting:        return .orange
        case .fielding:       return .green
        case .bullpen:        return .red
        case .team:           return .purple
        case .practiceRound:  return .brandGold
        case .rangeSession:   return .green
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
    private var activeSport: Season.SportType { athlete?.sportType ?? .baseball }
    @State private var viewModel = PracticesViewModel()
    @State private var navigateToPractice: Practice?
    @State private var showingAddPractice = false
    /// Golf "+" → NewPracticeTypePicker sheet, then chains into AddPracticeView
    /// with `preselectedType` propagated. Baseball ignores both.
    @State private var showingNewPracticeTypePicker = false
    @State private var preselectedType: PracticeType?
    /// Set by `.setGolfPickerPending` (posted from the dashboard as it switches
    /// tabs). Consumed in `.onAppear` so the picker surfaces reliably even on a
    /// cold mount, replacing the old timing-based notification hand-off.
    @State private var pendingGolfPickerRequest = false

    /// True when this athlete has seasons in more than one sport. Drives
    /// sport-aware empty-state copy ("No Golf Practices Yet") so single-sport
    /// athletes keep the original wording.
    private var isMultiSport: Bool {
        Set((athlete?.seasons ?? []).map { $0.sport ?? .baseball }).count > 1
    }

    // Check if filters are active
    private var hasActiveFilters: Bool {
        viewModel.selectedSeasonFilter != nil ||
        !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // Check if we have any practices at all (before filtering)
    private var hasAnyPractices: Bool {
        !(athlete?.practices?.isEmpty ?? true)
    }

    /// Practices visible under the current sport context. Seasonless practices
    /// pass through under both sports so they aren't hidden mid-toggle.
    private var practicesForActiveSport: [Practice] {
        (athlete?.practices ?? []).filter { practice in
            guard let season = practice.season else { return true }
            return (season.sport ?? .baseball) == activeSport
        }
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
                EmptyPracticesView(
                    sportTitle: isMultiSport ? activeSport.displayName : nil
                ) {
                    if activeSport == .golf {
                        showingNewPracticeTypePicker = true
                    } else {
                        quickCreatePractice(type: .general)
                    }
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
                let seasonRecommendation = SeasonManager.checkSeasonStatus(for: athlete, sport: activeSport)
                if seasonRecommendation.message != nil {
                    SeasonRecommendationBanner(athlete: athlete, recommendation: seasonRecommendation)
                        .padding()
                }
            }

            List {
                if !viewModel.filteredPractices.isEmpty {
                    HStack {
                        Text(viewModel.practicesSummary)
                            .font(.bodySmall)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .minimumScaleFactor(0.8)

                        Spacer()
                    }
                    .listRowBackground(Theme.surface)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 5, leading: 18, bottom: 5, trailing: 18))
                }

                ForEach(viewModel.filteredPractices, id: \.persistentModelID) { practice in
                    // Button + navigationDestination(item:) (not NavigationLink) so
                    // the List doesn't add a system disclosure chevron outside the
                    // card — PracticeCard carries its own in-card chevron instead.
                    Button {
                        navigateToPractice = practice
                    } label: {
                        PracticeCard(practice: practice)
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button(role: .destructive) {
                            deleteSinglePractice(practice)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .listRowBackground(Theme.surface)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 5, leading: 18, bottom: 5, trailing: 18))

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
                        .foregroundColor(Theme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .listRowBackground(Theme.surface)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 5, leading: 18, bottom: 5, trailing: 18))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.surface)
            .refreshable {
                await refreshPractices()
            }
        }
    }

    @ToolbarContentBuilder
    private var practicesToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            // Golf athletes pick Range vs Practice Round in a sheet (per-hole
            // scoring and clip attribution depend on the type, so we don't
            // surface a single-tap "general" shortcut for golf). Baseball
            // athletes keep the inline Menu they're used to.
            if activeSport == .golf {
                Button {
                    showingNewPracticeTypePicker = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Practice")
            } else {
                Menu {
                    Button {
                        quickCreatePractice(type: .general)
                    } label: {
                        Label("General Practice", systemImage: PracticeType.general.icon)
                    }
                    ForEach(PracticeType.cases(for: activeSport).filter { $0 != .general }) { type in
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
        }

        if hasAnyPractices {
            ToolbarItem(placement: .topBarLeading) {
                SeasonFilterMenu(
                    selectedSeasonID: $viewModel.selectedSeasonFilter,
                    availableSeasons: viewModel.availableSeasons,
                    showNoSeasonOption: practicesForActiveSport.contains(where: { $0.season == nil })
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
            // Consume a picker request armed before this view mounted (cold
            // tab switch from the dashboard).
            if pendingGolfPickerRequest {
                pendingGolfPickerRequest = false
                if activeSport == .golf {
                    showingNewPracticeTypePicker = true
                }
            }
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
                AddPracticeView(athlete: athlete, initialType: preselectedType) { created in
                    navigateToPractice = created
                }
            }
        }
        // Picker → AddPracticeView is a two-sheet chain. Presenting the
        // second sheet inside the picker's onSelect closure (while the
        // first is still on-screen) loses the second sheet on iOS 17.
        // `onDismiss:` runs AFTER the picker fully tears down, so chaining
        // through it is reliable.
        .sheet(isPresented: $showingNewPracticeTypePicker, onDismiss: {
            if preselectedType != nil {
                showingAddPractice = true
            }
        }) {
            NewPracticeTypePicker { type in
                preselectedType = type
            }
        }
        .onChange(of: showingNewPracticeTypePicker) { _, presenting in
            // Reset preselectedType on each picker open so a stale value
            // from a previous Cancel'd AddPracticeView can't re-trigger the
            // creation sheet via onDismiss.
            if presenting {
                preselectedType = nil
                // The request (cold or warm path) has now been satisfied —
                // clear the pending flag so a later appear can't re-open it.
                pendingGolfPickerRequest = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .presentGolfPracticePicker)) { _ in
            guard activeSport == .golf else { return }
            showingNewPracticeTypePicker = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .setGolfPickerPending)) { _ in
            // Arm the request; `.onAppear` consumes it on a cold mount. The
            // warm path (view already mounted) is handled by the direct
            // `.presentGolfPracticePicker` receiver above, which clears this
            // flag via the onChange below when the picker opens.
            pendingGolfPickerRequest = true
        }
        .onChange(of: showingAddPractice) { _, isPresented in
            // Clear preselectedType after AddPracticeView dismisses so a
            // baseball "Schedule Practice…" tap doesn't inherit a stale
            // golf preselection.
            if !isPresented { preselectedType = nil }
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
