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
    @Environment(\.ppAccent) private var ppAccent
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
    /// Quick-create aborted because the default season couldn't be saved —
    /// surfaced instead of silently filing a seasonless practice.
    @State private var showingSeasonSetupError = false
    /// Swipe-to-delete target, held until the confirmation resolves. Deleting a
    /// practice is a deep, irreversible cascade (clips, photos, hole scores,
    /// highlights), so it confirms like the games list does.
    @State private var practiceToDelete: Practice?
    @State private var showingDeletePracticeConfirmation = false

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
                    sportTitle: isMultiSport ? activeSport.displayName : nil,
                    sport: activeSport
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
                            practiceToDelete = practice
                            showingDeletePracticeConfirmation = true
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
                        .foregroundColor(ppAccent)
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
            ToolbarItem(placement: .topBarTrailing) {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface)
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
        .alert("Couldn't Create Practice", isPresented: $showingSeasonSetupError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Setting up a season failed. Please try again, or create a season from the Seasons screen.")
        }
        .confirmationDialog(
            "Delete Practice",
            isPresented: $showingDeletePracticeConfirmation,
            presenting: practiceToDelete
        ) { practice in
            // Golf type names already read as nouns ("Practice Round"), so
            // appending "Practice" would stutter.
            Button("Delete \(practice.type.displayName)", role: .destructive) {
                deleteSinglePractice(practice)
                practiceToDelete = nil
            }
            Button("Cancel", role: .cancel) { practiceToDelete = nil }
        } message: { practice in
            Text(practice.practiceType == PracticeType.practiceRound.rawValue
                 ? "This will permanently delete this round and all its videos, photos, notes, hole scores, and highlights."
                 : "This will permanently delete this practice and all its videos, photos, and notes.")
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

    /// One-tap create for baseball practice types. Golf must NOT route here:
    /// a golf practice created today on an active season is supposed to go live
    /// (single-live guard, hole count, course, stale-session reminder), and all
    /// of that lives in `AddPracticeView.performCreate`. Golf entry points —
    /// the "+" and the empty state — go through `NewPracticeTypePicker` into
    /// AddPracticeView for exactly that reason; sending a golf type here would
    /// silently file a historical log instead of starting a session.
    private func quickCreatePractice(type: PracticeType) {
        guard let athlete = athlete else { return }

        // Resolve the season before inserting anything so a failed
        // default-season save can't strand a seasonless practice (it would
        // half-vanish from season-filtered views).
        guard let season = SeasonManager.ensureActiveSeason(for: athlete, in: modelContext) else {
            Haptics.error()
            showingSeasonSetupError = true
            return
        }

        let practice = Practice(date: Date())
        practice.practiceType = type.rawValue
        practice.athlete = athlete
        practice.season = season
        practice.needsSync = true

        if athlete.practices == nil {
            athlete.practices = []
        }
        athlete.practices?.append(practice)
        modelContext.insert(practice)

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
        // PracticeService owns the whole cascade — local rows + files, the
        // Firestore tombstones (practice, holes, shots, reels), reminder
        // cancellation, and the stats recalc.
        Task {
            let deleted = await PracticeService(modelContext: modelContext).deleteDeep(practice)

            withAnimation {
                viewModel.update(practices: athlete?.practices ?? [])
            }

            if deleted {
                Haptics.success()
                log.info("Successfully deleted practice")
            } else {
                Haptics.error()
            }
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
