//
//  StatisticsView.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import SwiftUI
import SwiftData
import Charts
import TipKit

struct StatisticsView: View {
    let athlete: Athlete?
    let currentTier: SubscriptionTier

    enum ActiveSheet: Identifiable {
        case quickEntry(Game)
        case gameSelection
        var id: String {
            switch self {
            case .quickEntry(let game):
                return "quickEntry_\(game.id.uuidString)"
            case .gameSelection:
                return "gameSelection"
            }
        }
    }
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext
    private var activeSport: Season.SportType { athlete?.sportType ?? .baseball }
    @State private var activeSheet: ActiveSheet?
    @State private var selectedSeasonFilter: String? = nil // nil = All Seasons (Career)

    private var isGolf: Bool {
        // When a specific season is filtered, prefer its sport; otherwise the
        // tab-bar's active sport context wins.
        if let id = selectedSeasonFilter,
           let season = availableSeasons.first(where: { $0.id.uuidString == id }) {
            return season.sport == .golf
        }
        return activeSport == .golf
    }

    private var selectedSeason: Season? {
        guard let id = selectedSeasonFilter else { return nil }
        return availableSeasons.first { $0.id.uuidString == id }
    }

    /// Milestones for the current selection: the chosen season, or — in the
    /// career (All Seasons) view — every season of the active sport, flattened
    /// and most-recent first. Pure compute via MilestoneEngine.
    private var milestonesForSelection: [Milestone] {
        if let season = selectedSeason {
            return MilestoneEngine.milestones(for: season)
        }
        let seasons = (athlete?.seasons ?? []).filter { ($0.sport ?? .baseball) == activeSport }
        return seasons
            .flatMap { MilestoneEngine.milestones(for: $0) }
            .sorted { $0.date > $1.date }
    }

    /// Golf has no `AthleteStatistics`, so its charts/comparison buttons can't
    /// ride the `statistics != nil` toolbar block — they gate on real rounds.
    private var hasGolfRounds: Bool {
        guard isGolf, let athlete else { return false }
        if !GolfExportData.tournamentRounds(for: athlete, season: selectedSeason).isEmpty { return true }
        return !GolfExportData.practiceRounds(for: athlete, season: selectedSeason).isEmpty
    }

    // Get all available seasons (active + archived)
    private var availableSeasons: [Season] {
        var seasons: [Season] = []
        if let activeSeason = athlete?.activeSeason {
            seasons.append(activeSeason)
        }
        seasons.append(contentsOf: athlete?.archivedSeasons ?? [])
        return seasons.sorted { ($0.startDate ?? Date.distantPast) > ($1.startDate ?? Date.distantPast) }
    }

    // Get statistics based on selected filter
    var statistics: AthleteStatistics? {
        if let seasonID = selectedSeasonFilter {
            // Show specific season statistics
            if let season = availableSeasons.first(where: { $0.id.uuidString == seasonID }) {
                return season.seasonStatistics
            }
            return nil
        } else {
            // Show career statistics
            return athlete?.statistics
        }
    }

    var currentLiveGame: Game? {
        athlete?.games?.first(where: { $0.isLive })
    }

    var hasLiveGame: Bool { currentLiveGame != nil }

    @State private var showingExportOptions = false
    @State private var exportedFileURL: URL?
    @State private var showingShareSheet = false
    @State private var exportError: String?
    @State private var showingExportError = false
    @State private var showingSeasonComparison = false
    @State private var showingCharts = false

    var body: some View {
        contentView
            // Scope rule: on Stats the accent follows the Baseball/Golf selection
            // (`isGolf` prefers the filtered season's sport), overriding the
            // profile's sport for this subtree.
            .ppAccent(forGolf: isGolf)
            .navigationTitle("The Numbers.")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if let athlete = athlete {
                    ToolbarItem(placement: .principal) {
                        PPAthleteSwitcher(athlete: athlete)
                    }
                }
                if statistics != nil {
                    // View Charts button — baseball/softball-only (StatisticsChartsView
                    // is hard-coded to batting/pitching metrics).
                    if !isGolf {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                showingCharts = true
                            } label: {
                                Label("View Charts", systemImage: "chart.xyaxis.line")
                            }
                            .accessibilityLabel("View performance charts")
                        }
                    }

                    // Compare seasons button (Plus+) — also batting-only.
                    if currentTier >= .plus && !isGolf {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                showingSeasonComparison = true
                            } label: {
                                Label("Compare Seasons", systemImage: "chart.line.uptrend.xyaxis")
                            }
                            .accessibilityLabel("Compare seasons")
                        }
                    }

                    // Season filter
                    if !availableSeasons.isEmpty {
                        ToolbarItem(placement: .topBarTrailing) {
                            SeasonFilterMenu(
                                selectedSeasonID: $selectedSeasonFilter,
                                availableSeasons: availableSeasons,
                                showNoSeasonOption: false
                            )
                        }
                    }
                }

                // Golf charts + comparison. Golf has no AthleteStatistics, so
                // these can't live in the `statistics != nil` block above and
                // gate on real scored rounds instead. Charts are free (parity
                // with baseball's free charts); comparison stays Plus-gated.
                if isGolf && hasGolfRounds {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showingCharts = true
                        } label: {
                            Label("View Charts", systemImage: "chart.xyaxis.line")
                        }
                        .accessibilityLabel("View golf charts")
                    }

                    if currentTier >= .plus {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                showingSeasonComparison = true
                            } label: {
                                Label("Compare Seasons", systemImage: "chart.line.uptrend.xyaxis")
                            }
                            .accessibilityLabel("Compare golf seasons")
                        }
                    }
                }

                if let ath = athlete {
                    // Actions menu (always available)
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            // Manual-entry shortcuts contradict a user who has
                            // explicitly turned off stat tracking. Hide them
                            // here — export still works if they have old stats.
                            // Also hide for golf: scoring is per-tournament via
                            // EnterScoreSheet, not per-at-bat manual stats.
                            if ath.trackStatsEnabled && !isGolf {
                                if let game = currentLiveGame {
                                    Button {
                                        activeSheet = .quickEntry(game)
                                    } label: {
                                        Label("Record Live Game Stats", systemImage: "chart.bar.doc.horizontal.fill")
                                    }
                                }

                                Button {
                                    activeSheet = .gameSelection
                                } label: {
                                    Label("Add Past Game Statistics", systemImage: "plus.circle.fill")
                                }
                            }

                            if statistics != nil, currentTier >= .plus, !isGolf {
                                // Export is baseball-only — CSV/PDF generators
                                // pull from batting/pitching fields on AthleteStatistics.
                                Divider()

                                Button {
                                    exportCSV(athlete: ath)
                                } label: {
                                    Label("Export as CSV", systemImage: "doc.text")
                                }

                                Button {
                                    exportPDF(athlete: ath)
                                } label: {
                                    Label("Export as PDF", systemImage: "doc.richtext")
                                }
                            }

                            // Golf export — derives from GolfExportData (no
                            // AthleteStatistics), so it has its own gate + handlers.
                            if isGolf, currentTier >= .plus, hasGolfRounds(ath) {
                                Button {
                                    exportGolfCSV(athlete: ath)
                                } label: {
                                    Label("Export as CSV", systemImage: "doc.text")
                                }

                                Button {
                                    exportGolfPDF(athlete: ath)
                                } label: {
                                    Label("Export as PDF", systemImage: "doc.richtext")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("Statistics actions")
                    }
                }
            }
            .sheet(item: $activeSheet) { item in
                switch item {
                case .quickEntry(let game):
                    QuickStatisticsEntryView(game: game, athlete: athlete)
                        .presentationDetents(horizontalSizeClass == .regular ? [.medium, .large] : [.large])
                case .gameSelection:
                    GameSelectionForStatsView(athlete: athlete)
                        .presentationDetents(horizontalSizeClass == .regular ? [.medium, .large] : [.large])
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let url = exportedFileURL {
                    ShareSheet(items: [url])
                }
            }
            .sheet(isPresented: $showingSeasonComparison) {
                if let ath = athlete {
                    if isGolf {
                        GolfSeasonComparisonView(athlete: ath)
                    } else {
                        SeasonComparisonView(athlete: ath)
                    }
                }
            }
            .sheet(isPresented: $showingCharts) {
                if let ath = athlete {
                    NavigationStack {
                        Group {
                            if isGolf {
                                GolfChartsView(athlete: ath, initialSeason: selectedSeason)
                            } else {
                                StatisticsChartsView(
                                    athlete: ath,
                                    initialSeason: selectedSeasonFilter.flatMap { id in
                                        availableSeasons.first { $0.id.uuidString == id }
                                    }
                                )
                            }
                        }
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") {
                                    showingCharts = false
                                }
                            }
                        }
                    }
                }
            }
            .alert("Export Error", isPresented: $showingExportError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportError ?? "Failed to export statistics")
            }
    }

    /// True when the athlete has any scored golf round (tournament or practice),
    /// gating the golf export menu items.
    private func hasGolfRounds(_ ath: Athlete) -> Bool {
        (ath.games ?? []).contains { $0.season?.sport == .golf && $0.isGolfRoundScored }
            || (ath.practices ?? []).contains {
                $0.practiceType == PracticeType.practiceRound.rawValue && !($0.holeScores ?? []).isEmpty
            }
    }

    private func exportGolfCSV(athlete: Athlete) {
        guard currentTier >= .plus else { return }
        let season = selectedSeasonFilter.flatMap { id in availableSeasons.first { $0.id.uuidString == id } }
        Task {
            let result = StatisticsExportService.exportGolfToCSV(athlete: athlete, season: season)
            switch result {
            case .success(let url):
                exportedFileURL = url
                showingShareSheet = true
                Haptics.success()
            case .failure(let error):
                exportError = error.localizedDescription
                showingExportError = true
                Haptics.warning()
            }
        }
    }

    private func exportGolfPDF(athlete: Athlete) {
        guard currentTier >= .plus else { return }
        let season = selectedSeasonFilter.flatMap { id in availableSeasons.first { $0.id.uuidString == id } }
        Task {
            let result = StatisticsExportService.exportGolfToPDF(athlete: athlete, season: season)
            switch result {
            case .success(let url):
                exportedFileURL = url
                showingShareSheet = true
                Haptics.success()
            case .failure(let error):
                exportError = error.localizedDescription
                showingExportError = true
                Haptics.warning()
            }
        }
    }

    private func exportCSV(athlete: Athlete) {
        guard currentTier >= .plus else { return }
        guard let stats = statistics else { return }

        Task {
            let result = StatisticsExportService.exportToCSV(athlete: athlete, stats: stats)
            switch result {
            case .success(let url):
                exportedFileURL = url
                showingShareSheet = true
                Haptics.success()
            case .failure(let error):
                exportError = error.localizedDescription
                showingExportError = true
                Haptics.warning()
            }
        }
    }

    private func exportPDF(athlete: Athlete) {
        guard currentTier >= .plus else { return }
        guard let stats = statistics else { return }

        let selectedSeason = selectedSeasonFilter.flatMap { id in
            availableSeasons.first { $0.id.uuidString == id }
        } ?? athlete.activeSeason

        Task {
            let result = StatisticsExportService.exportToPDF(
                athlete: athlete,
                stats: stats,
                season: selectedSeason
            )
            switch result {
            case .success(let url):
                exportedFileURL = url
                showingShareSheet = true
                Haptics.success()
            case .failure(let error):
                exportError = error.localizedDescription
                showingExportError = true
                Haptics.warning()
            }
        }
    }
    
    @State private var showingEditAthlete = false

    @ViewBuilder
    private var contentView: some View {
        VStack(spacing: 0) {
            if let athlete, !athlete.trackStatsEnabled {
                statTrackingOffBanner(athlete: athlete)
            }
            mainContent
        }
        // Sheet attached at the parent so it survives the banner unmounting
        // when the user toggles tracking back on from inside the sheet.
        .sheet(isPresented: $showingEditAthlete) {
            if let athlete {
                NavigationStack { EditAthleteView(athlete: athlete) }
            }
        }
    }

    private func statTrackingOffBanner(athlete: Athlete) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundColor(.brandNavy)
            VStack(alignment: .leading, spacing: 2) {
                Text("Stat tracking is off for \(athlete.name)")
                    .font(.headingSmall)
                Text("New clips won't add to stats.")
                    .font(.bodySmall)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 8)
            Button("Turn On") {
                showingEditAthlete = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.brandNavy)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.brandNavy.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var mainContent: some View {
        if isGolf {
            ScrollView {
                LazyVStack(spacing: 20) {
                    GolfStatsSection(athlete: athlete, season: selectedSeason)

                    MilestonesListSection(milestones: milestonesForSelection)
                }
                .padding(horizontalSizeClass == .regular ? 32 : 18)
            }
            .background(Theme.surface)
        } else if let stats = statistics, stats.atBats > 0 || stats.hasPitchingData {
            ScrollView {
                LazyVStack(spacing: 20) {
                    // "The Numbers." hero — slash line + metric grid.
                    StatsHeroCard(
                        statistics: stats,
                        label: selectedSeasonFilter
                            .flatMap { id in availableSeasons.first(where: { $0.id.uuidString == id }) }?
                            .displayName ?? "Batting Line"
                    )

                    // Show different stats based on filter
                    if selectedSeasonFilter == nil {
                        // Career view - show comparison if active season exists
                        if let activeSeason = athlete?.activeSeason,
                           let seasonStats = activeSeason.seasonStatistics,
                           let careerStats = athlete?.statistics {
                            CareerSeasonComparisonSection(
                                careerStats: careerStats,
                                seasonStats: seasonStats,
                                seasonName: activeSeason.displayName
                            )
                        } else {
                            // Just show career stats
                            KeyStatsSection(statistics: stats)
                        }
                    } else {
                        // Specific season view - show season stats only
                        let seasonName = selectedSeasonFilter
                            .flatMap { id in availableSeasons.first(where: { $0.id.uuidString == id }) }?
                            .displayName
                        KeyStatsSection(statistics: stats, seasonLabel: seasonName)
                    }

                    // Batting Chart
                    BattingChartSection(statistics: stats)

                    // Detailed Statistics
                    DetailedStatsSection(statistics: stats)

                    // Play Results Breakdown
                    PlayResultsSection(statistics: stats)

                    // Pitching Statistics (only if athlete has pitching data)
                    if stats.hasPitchingData {
                        PitchingStatsSection(statistics: stats, athlete: athlete)
                    }

                    MilestonesListSection(milestones: milestonesForSelection)
                }
                .padding(horizontalSizeClass == .regular ? 32 : 18)
            }
            .background(Theme.surface)
        } else {
            EmptyStatisticsView(
                isQuickEntryEnabled: hasLiveGame,
                hasGames: !(athlete?.games ?? []).isEmpty,
                showQuickEntry: {
                    if let game = currentLiveGame { activeSheet = .quickEntry(game) }
                },
                showGameSelection: { activeSheet = .gameSelection }
            )
        }
    }

}

// MARK: - Notification

extension Notification.Name {
    static let switchToGamesTab = Notification.Name("switchToGamesTab")
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    let icon: String?
    @Environment(\.ppAccent) private var ppAccent

    init(title: String, icon: String? = nil) {
        self.title = title
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 8) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(ppAccent)
            }
            Text(title)
                .font(.ppTitle2)              // Fraunces serif
                .foregroundStyle(Theme.textPrimary)
        }
    }
}

// MARK: - Shared Styles

struct StatsPremiumButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension View {
    func statCardBackground() -> some View {
        self
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: .cornerLarge, style: .continuous)
                    .fill(Theme.card)
            )
    }
}

#Preview {
    let mockAthlete: Athlete = {
        let athlete = Athlete(name: "Sample Player")
        let stats = AthleteStatistics()
        stats.hits = 45
        stats.atBats = 130
        stats.walks = 20
        stats.doubles = 10
        stats.triples = 2
        stats.homeRuns = 5
        athlete.statistics = stats
        return athlete
    }()
    return NavigationStack { StatisticsView(athlete: mockAthlete, currentTier: .free) }
}
