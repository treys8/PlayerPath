//
//  StatisticsView.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import SwiftUI
import SwiftData
import Charts

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
    @State private var activeSheet: ActiveSheet?
    @State private var selectedSeasonFilter: String? = nil // nil = All Seasons (Career)

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
            .navigationTitle("Statistics")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if statistics != nil {
                    // View Charts button
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showingCharts = true
                        } label: {
                            Label("View Charts", systemImage: "chart.xyaxis.line")
                        }
                        .accessibilityLabel("View performance charts")
                    }

                    // Compare seasons button (Plus+)
                    if currentTier >= .plus {
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

                if let ath = athlete {
                    // Actions menu (always available)
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
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

                            if statistics != nil, currentTier >= .plus {
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
                case .gameSelection:
                    GameSelectionForStatsView(athlete: athlete)
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let url = exportedFileURL {
                    ShareSheet(items: [url])
                }
            }
            .sheet(isPresented: $showingSeasonComparison) {
                if let ath = athlete {
                    SeasonComparisonView(athlete: ath)
                }
            }
            .sheet(isPresented: $showingCharts) {
                if let ath = athlete {
                    NavigationStack {
                        StatisticsChartsView(athlete: ath)
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
    
    @ViewBuilder
    private var contentView: some View {
        if let stats = statistics {
            ScrollView {
                LazyVStack(spacing: 20) {
                    // Charts Prompt Card
                    ChartsPromptCard {
                        showingCharts = true
                    }

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
                        KeyStatsSection(statistics: stats)
                    }

                    // Batting Chart
                    BattingChartSection(statistics: stats)

                    // Detailed Statistics
                    DetailedStatsSection(statistics: stats)

                    // Play Results Breakdown
                    PlayResultsSection(statistics: stats)

                    // Pitching Statistics (only if athlete has pitching data)
                    if stats.hasPitchingData {
                        PitchingStatsSection(statistics: stats)
                    }
                }
                .padding()
            }
        } else {
            EmptyStatisticsView(
                isQuickEntryEnabled: hasLiveGame,
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

    init(title: String, icon: String? = nil) {
        self.title = title
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 8) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .blue.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            Text(title)
                .font(.headline)
                .fontWeight(.bold)
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
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
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
