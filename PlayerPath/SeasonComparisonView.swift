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
    @Environment(\.dismiss) private var dismiss

    // Selected seasons for comparison (max 4)
    @State private var selectedSeasons: Set<UUID> = []

    // Get all seasons (active + archived) sorted by date
    private var allSeasons: [Season] {
        var seasons: [Season] = []
        if let activeSeason = athlete.activeSeason {
            seasons.append(activeSeason)
        }
        seasons.append(contentsOf: athlete.archivedSeasons)
        // Dedup by ID in case activeSeason also appears in archivedSeasons
        let unique = Dictionary(grouping: seasons, by: \.id).compactMap { $0.value.first }
        return unique.sorted { ($0.startDate ?? Date.distantPast) > ($1.startDate ?? Date.distantPast) }
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
            VStack(spacing: 0) {
                if canCompare {
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

                            // Detailed Comparison Table
                            DetailedComparisonTable(seasons: seasonsToCompare)
                        }
                        .padding()
                    }
                } else {
                    // Season selection view
                    seasonSelectionView
                }
            }
            .navigationTitle("Season Comparison")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                if canCompare {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Change Seasons") {
                            // Clear selections to go back to selection view
                            selectedSeasons.removeAll()
                        }
                    }
                }
            }
        }
    }

    private var seasonSelectionView: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)

                Text("Compare Seasons")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Select 2-4 seasons to compare statistics and trends")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(.top, 40)

            // Season selection list
            if allSeasons.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("No Seasons Yet")
                        .font(.headline)
                    Text("Create at least two seasons with game data to start comparing.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
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
                    }
                }
                .listStyle(.insetGrouped)
            }

            // Compare button
            if selectedSeasons.count >= 2 {
                Button(action: {
                    // Button just keeps selections - view automatically shows comparison
                }) {
                    Text("Compare \(selectedSeasons.count) Seasons")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                }
                .padding()
            }

            Spacer()
        }
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

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(season.displayName)
                        .font(.headline)

                    if season.isActive {
                        Text("ACTIVE")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue)
                            .cornerRadius(4)
                    }
                }

                if let stats = season.seasonStatistics {
                    Text("\(stats.totalGames) games • \(stats.hits)/\(stats.atBats) • \(formatBattingAverage(stats.battingAverage))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No statistics yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
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
                .font(.headline)
                .fontWeight(.bold)

            if chartData.isEmpty {
                Text("No data available")
                    .font(.subheadline)
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
                    .foregroundStyle(Color.blue)
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Season", dataPoint.seasonName),
                        y: .value("Value", dataPoint.value)
                    )
                    .foregroundStyle(Color.blue)
                }
                .frame(height: 200)
                .chartYScale(domain: .automatic(includesZero: false))

                // Value cards
                HStack(spacing: 12) {
                    ForEach(chartData) { dataPoint in
                        VStack(spacing: 4) {
                            Text(dataPoint.seasonName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text(formatValue(dataPoint.value))
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundStyle(.blue)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.1))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Detailed Statistics")
                .font(.headline)
                .fontWeight(.bold)

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Header row
                    HStack(spacing: 0) {
                        Text("Stat")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .frame(width: 100, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 12)
                            .background(Color.gray.opacity(0.2))

                        ForEach(seasons) { season in
                            Text(season.displayName)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .frame(width: 100, alignment: .center)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 12)
                                .background(Color.blue.opacity(0.1))
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
                .font(.caption)
                .frame(width: 100, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)

            ForEach(seasons) { season in
                Text(String(describing: getValue(season)))
                    .font(.caption)
                    .frame(width: 100, alignment: .center)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
            }
        }
        .background(Color(.systemBackground))

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
