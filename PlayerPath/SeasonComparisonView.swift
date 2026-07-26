//
//  SeasonComparisonView.swift
//  PlayerPath
//
//  Created by Assistant on 12/21/25.
//  Year-over-year season comparison view
//

import SwiftUI
import SwiftData
import Charts

struct SeasonComparisonView: View {
    let athlete: Athlete
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.ppAccent) private var ppAccent

    // Selected seasons for comparison (max 4)
    @State private var selectedSeasons: Set<UUID> = []

    /// Set once the user taps Compare. Selection stays on screen until then, so
    /// picking a third or fourth season is possible — without this the view
    /// would swap to the charts the instant the second season was tapped.
    @State private var isComparing = false

    // Get all seasons (active + archived) sorted by date
    private var allSeasons: [Season] {
        var seasons: [Season] = []
        if let activeSeason = athlete.activeSeason {
            seasons.append(activeSeason)
        }
        seasons.append(contentsOf: athlete.archivedSeasons)
        // Dedup by ID in case activeSeason also appears in archivedSeasons
        let unique = Dictionary(grouping: seasons, by: \.id).compactMap { $0.value.first }
        return unique
            // Golf seasons compare on scoring, not batting — they belong to
            // GolfSeasonComparisonView. Mirrors that view's `== .golf` filter.
            .filter { $0.sport != .golf }
            .sorted { ($0.startDate ?? Date.distantPast) > ($1.startDate ?? Date.distantPast) }
    }

    // Get selected season objects
    private var seasonsToCompare: [Season] {
        allSeasons.filter { selectedSeasons.contains($0.id) }
            .sorted { ($0.startDate ?? Date.distantPast) > ($1.startDate ?? Date.distantPast) }
    }

    private var canCompare: Bool {
        selectedSeasons.count >= 2
    }

    var body: some View {
        NavigationStack {
            Group {
                if authManager.currentTier < .plus {
                    // Entitlement guard — prevents access via deep links or stale navigation
                    LockedFeaturePlaceholder(message: "Upgrade to Plus to compare seasons side-by-side")
                } else {
                    VStack(spacing: 0) {
                        if isComparing && canCompare {
                            // Comparison view
                            ScrollView {
                                VStack(spacing: 20) {
                                    // Batting Average Trend
                                    TrendChartSection(
                                        title: "Batting Average",
                                        seasons: seasonsToCompare,
                                        getValue: { $0.seasonStatistics?.battingAverage ?? 0.0 },
                                        formatValue: { formatBattingAverage($0) }
                                    )

                                    // On-Base Percentage Trend
                                    TrendChartSection(
                                        title: "On-Base Percentage",
                                        seasons: seasonsToCompare,
                                        getValue: { $0.seasonStatistics?.onBasePercentage ?? 0.0 },
                                        formatValue: { formatThreeDecimal($0) }
                                    )

                                    // Home Runs Trend
                                    TrendChartSection(
                                        title: "Home Runs",
                                        seasons: seasonsToCompare,
                                        getValue: { Double($0.seasonStatistics?.homeRuns ?? 0) },
                                        formatValue: { "\(Int($0))" }
                                    )

                                    // Pitching Trends (only if any selected season has pitching data)
                                    if seasonsToCompare.contains(where: { $0.seasonStatistics?.hasPitchingData == true }) {
                                        TrendChartSection(
                                            title: "Pitching Strikeouts",
                                            seasons: seasonsToCompare,
                                            getValue: { Double($0.seasonStatistics?.pitchingStrikeouts ?? 0) },
                                            formatValue: { "\(Int($0))" }
                                        )

                                        TrendChartSection(
                                            title: "Total Pitches",
                                            seasons: seasonsToCompare,
                                            getValue: { Double($0.seasonStatistics?.totalPitches ?? 0) },
                                            formatValue: { "\(Int($0))" }
                                        )
                                    }

                                    // Detailed Comparison Table
                                    DetailedComparisonTable(seasons: seasonsToCompare)
                                }
                                .padding()
                            }
                            .background(Theme.surface)
                        } else {
                            // Season selection view
                            seasonSelectionView
                        }
                    }
                    .onAppear { AnalyticsService.shared.trackScreenView(screenName: "Season Comparison", screenClass: "SeasonComparisonView") }
                }
            }
            .navigationTitle("Season Comparison")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                if authManager.currentTier >= .plus && isComparing {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Change Seasons") {
                            // Back to the picker with the current selection intact
                            isComparing = false
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var seasonSelectionView: some View {
        // Comparison needs two seasons — with fewer, the picker is a dead end,
        // so show what's missing instead of an un-actionable list.
        if allSeasons.count < 2 {
            notEnoughSeasonsView
        } else {
            List {
                Section {
                    ForEach(allSeasons) { season in
                        Button {
                            toggleSeasonSelection(season)
                        } label: {
                            SeasonSelectionRow(
                                season: season,
                                isSelected: selectedSeasons.contains(season.id)
                            )
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Theme.card)
                    }
                } header: {
                    Text("Select 2–4 Seasons")
                } footer: {
                    Text(selectionFooter)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.surface)
            .safeAreaInset(edge: .bottom) { compareBar }
        }
    }

    private var selectionFooter: String {
        switch selectedSeasons.count {
        case 0: return "Pick the seasons you want to see side-by-side."
        case 1: return "1 selected — pick one more to compare."
        case 4: return "4 selected — the maximum."
        default: return "\(selectedSeasons.count) selected."
        }
    }

    private var compareBar: some View {
        Button {
            Haptics.light()
            isComparing = true
        } label: {
            Text(canCompare ? "Compare \(selectedSeasons.count) Seasons" : "Compare")
                .font(.headingMedium)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: .cornerLarge, style: .continuous)
                        .fill(canCompare ? ppAccent : Theme.textTertiary)
                )
        }
        .disabled(!canCompare)
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Theme.surface)
    }

    private var notEnoughSeasonsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(allSeasons.isEmpty ? "No Seasons Yet" : "Only One Season")
                .font(.headingLarge)
            Text(allSeasons.isEmpty
                 ? "Create at least two seasons with game data to start comparing."
                 : "Comparison needs at least two seasons. Start a new season — this one stays in your history.")
                .font(.bodyMedium)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface)
    }

    private func toggleSeasonSelection(_ season: Season) {
        if selectedSeasons.contains(season.id) {
            selectedSeasons.remove(season.id)
            Haptics.light()
        } else {
            if selectedSeasons.count < 4 {
                selectedSeasons.insert(season.id)
                Haptics.light()
            } else {
                Haptics.warning()
            }
        }
    }
}

struct SeasonSelectionRow: View {
    let season: Season
    let isSelected: Bool

    @Environment(\.ppAccent) private var ppAccent

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(season.displayName)
                        .font(.headingMedium)

                    if season.isActive {
                        Text("ACTIVE")
                            .font(.custom("Inter18pt-Bold", size: 11, relativeTo: .caption2))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(ppAccent)
                            .cornerRadius(4)
                    }
                }

                if let stats = season.seasonStatistics {
                    Text("\(stats.totalGames) game\(stats.totalGames == 1 ? "" : "s") • \(stats.hits)/\(stats.atBats) • \(formatBattingAverage(stats.battingAverage))")
                        .font(.bodySmall)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No statistics yet")
                        .font(.bodySmall)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(ppAccent)
                    .font(.title3)
            } else {
                Image(systemName: "circle")
                    .foregroundStyle(.gray)
                    .font(.title3)
            }
        }
        .padding(.vertical, 4)
    }
}

struct TrendChartSection: View {
    let title: String
    let seasons: [Season]
    let getValue: (Season) -> Double
    let formatValue: (Double) -> String

    @Environment(\.ppAccent) private var ppAccent

    private var chartData: [SeasonDataPoint] {
        seasons.compactMap { season in
            guard season.seasonStatistics != nil else { return nil }
            return SeasonDataPoint(
                seasonName: season.displayName,
                value: getValue(season),
                date: season.startDate ?? Date()
            )
        }
        .sorted { $0.date < $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headingLarge)

            if chartData.isEmpty {
                Text("No data available")
                    .font(.bodyMedium)
                    .foregroundStyle(.secondary)
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
            } else {
                // Line chart
                Chart(chartData) { dataPoint in
                    LineMark(
                        x: .value("Season", dataPoint.seasonName),
                        y: .value("Value", dataPoint.value)
                    )
                    .foregroundStyle(ppAccent)
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Season", dataPoint.seasonName),
                        y: .value("Value", dataPoint.value)
                    )
                    .foregroundStyle(ppAccent)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(title) trend across \(chartData.count) seasons, from \(chartData.first?.seasonName ?? "") to \(chartData.last?.seasonName ?? "")")
                .frame(height: 200)
                .chartYScale(domain: .automatic(includesZero: false))

                // Value cards
                HStack(spacing: 12) {
                    ForEach(chartData) { dataPoint in
                        VStack(spacing: 4) {
                            Text(dataPoint.seasonName)
                                .font(.bodySmall)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text(formatValue(dataPoint.value))
                                .font(.ppStatMedium)
                                .monospacedDigit()
                                .foregroundStyle(ppAccent)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(ppAccent.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding()
        .statCardBackground()
    }
}

struct SeasonDataPoint: Identifiable {
    var id: String { seasonName }
    let seasonName: String
    let value: Double
    let date: Date
}

struct DetailedComparisonTable: View {
    let seasons: [Season]

    @Environment(\.ppAccent) private var ppAccent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Detailed Statistics")
                .font(.headingLarge)

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Header row
                    HStack(spacing: 0) {
                        Text("Stat")
                            .font(.custom("Inter18pt-SemiBold", size: 12, relativeTo: .caption))
                            .frame(width: 100, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 12)
                            .background(Color.gray.opacity(0.2))

                        ForEach(seasons) { season in
                            Text(season.displayName)
                                .font(.custom("Inter18pt-SemiBold", size: 12, relativeTo: .caption))
                                .frame(width: 100, alignment: .center)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 12)
                                .background(ppAccent.opacity(0.1))
                        }
                    }

                    Divider()

                    // Data rows
                    ComparisonRow(label: "Games", seasons: seasons) { $0.seasonStatistics?.totalGames ?? 0 }
                    ComparisonRow(label: "At-Bats", seasons: seasons) { $0.seasonStatistics?.atBats ?? 0 }
                    ComparisonRow(label: "Hits", seasons: seasons) { $0.seasonStatistics?.hits ?? 0 }
                    ComparisonRow(label: "Avg", seasons: seasons) { formatBattingAverage($0.seasonStatistics?.battingAverage ?? 0.0) }
                    ComparisonRow(label: "Singles", seasons: seasons) { $0.seasonStatistics?.singles ?? 0 }
                    ComparisonRow(label: "Doubles", seasons: seasons) { $0.seasonStatistics?.doubles ?? 0 }
                    ComparisonRow(label: "Triples", seasons: seasons) { $0.seasonStatistics?.triples ?? 0 }
                    ComparisonRow(label: "Home Runs", seasons: seasons) { $0.seasonStatistics?.homeRuns ?? 0 }
                    ComparisonRow(label: "Walks", seasons: seasons) { $0.seasonStatistics?.walks ?? 0 }
                    ComparisonRow(label: "Strikeouts", seasons: seasons) { $0.seasonStatistics?.strikeouts ?? 0 }
                    ComparisonRow(label: "OBP", seasons: seasons) { formatThreeDecimal($0.seasonStatistics?.onBasePercentage ?? 0.0) }
                    ComparisonRow(label: "SLG", seasons: seasons) { formatBattingAverage($0.seasonStatistics?.sluggingPercentage ?? 0.0) }

                    // Pitching rows (only if any selected season has pitching data)
                    if seasons.contains(where: { $0.seasonStatistics?.hasPitchingData == true }) {
                        HStack(spacing: 0) {
                            Text("Pitching")
                                .font(.custom("Inter18pt-SemiBold", size: 12, relativeTo: .caption))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 10)
                                .background(ppAccent.opacity(0.1))
                        }

                        Divider()

                        ComparisonRow(label: "Total Pitches", seasons: seasons) { $0.seasonStatistics?.totalPitches ?? 0 }
                        ComparisonRow(label: "Strikes", seasons: seasons) { $0.seasonStatistics?.strikes ?? 0 }
                        ComparisonRow(label: "Balls", seasons: seasons) { $0.seasonStatistics?.balls ?? 0 }
                        ComparisonRow(label: "P-Strikeouts", seasons: seasons) { $0.seasonStatistics?.pitchingStrikeouts ?? 0 }
                        ComparisonRow(label: "P-Walks", seasons: seasons) { $0.seasonStatistics?.pitchingWalks ?? 0 }
                        ComparisonRow(label: "Wild Pitches", seasons: seasons) { $0.seasonStatistics?.wildPitches ?? 0 }
                        ComparisonRow(label: "HBP", seasons: seasons) { $0.seasonStatistics?.hitByPitches ?? 0 }
                        ComparisonRow(label: "Avg FB Speed", seasons: seasons) {
                            let speed = $0.seasonStatistics?.averageFastballSpeed ?? 0.0
                            return speed > 0 ? String(format: "%.1f", speed) : "—"
                        }
                        ComparisonRow(label: "Avg OS Speed", seasons: seasons) {
                            let speed = $0.seasonStatistics?.averageOffspeedSpeed ?? 0.0
                            return speed > 0 ? String(format: "%.1f", speed) : "—"
                        }
                    }
                }
            }
        }
        .padding()
        .statCardBackground()
    }
}

struct ComparisonRow<Value>: View {
    let label: String
    let seasons: [Season]
    let getValue: (Season) -> Value

    var body: some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.bodySmall)
                .frame(width: 100, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)

            ForEach(seasons) { season in
                Text(String(describing: getValue(season)))
                    .font(.bodySmall)
                    .monospacedDigit()
                    .frame(width: 100, alignment: .center)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
            }
        }
        .background(Theme.surface)

        Divider()
    }
}

// Helper formatters

/// Formats a rate stat in baseball style: ".325" for values < 1.0, "1.400" for SLG/OPS >= 1.0
private func formatBattingAverage(_ value: Double) -> String {
    guard !value.isNaN, !value.isInfinite else { return ".000" }
    // SLG can exceed 1.0; show full decimal in that case
    if value >= 1.0 { return String(format: "%.3f", value) }
    let thousandths = Int((value * 1000).rounded())
    guard thousandths > 0 else { return ".000" }
    return String(format: ".%03d", thousandths)
}

/// Alias kept for call sites that use OBP/SLG — delegates to formatBattingAverage
private func formatThreeDecimal(_ value: Double) -> String {
    formatBattingAverage(value)
}

// `LockedFeaturePlaceholder` lives in ComparisonComponents.swift — shared with
// the golf comparison view.
