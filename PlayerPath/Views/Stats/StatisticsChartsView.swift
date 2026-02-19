//
//  StatisticsChartsView.swift
//  PlayerPath
//
//  Interactive charts for visualizing performance trends and statistics
//

import SwiftUI
import Charts

struct StatisticsChartsView: View {
    let athlete: Athlete

    @State private var selectedMetric: StatMetric = .battingAverage
    @State private var selectedTimeframe: Timeframe = .season
    @State private var selectedSeason: Season?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Metric Selector
                metricSelectorView

                // Timeframe Selector
                timeframeSelectorView

                // Season Filter (if applicable)
                if selectedTimeframe == .game {
                    seasonFilterView
                }

                // Main Chart
                mainChartView

                // Statistics Summary
                statisticsSummaryView

                // Additional Charts
                additionalChartsView
            }
            .padding()
        }
        .navigationTitle("Performance Charts")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Metric Selector

    private var metricSelectorView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Metric")
                .font(.headline)
                .foregroundColor(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(StatMetric.allCases) { metric in
                        MetricChip(
                            metric: metric,
                            isSelected: selectedMetric == metric
                        ) {
                            selectedMetric = metric
                        }
                    }
                }
            }
        }
    }

    // MARK: - Timeframe Selector

    private var timeframeSelectorView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("View By")
                .font(.headline)
                .foregroundColor(.secondary)

            Picker("Timeframe", selection: $selectedTimeframe) {
                ForEach(Timeframe.allCases) { timeframe in
                    Text(timeframe.displayName).tag(timeframe)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Season Filter

    private var seasonFilterView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Season")
                .font(.headline)
                .foregroundColor(.secondary)

            let seasons = athlete.seasons ?? []
            if !seasons.isEmpty {
                Picker("Season", selection: $selectedSeason) {
                    Text("All Seasons").tag(nil as Season?)
                    ForEach(seasons.sorted(by: { ($0.startDate ?? Date.distantPast) > ($1.startDate ?? Date.distantPast) })) { season in
                        Text(season.displayName).tag(season as Season?)
                    }
                }
                .pickerStyle(.menu)
            } else {
                Text("No seasons available")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
    }

    // MARK: - Main Chart

    private var mainChartView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(selectedMetric.displayName, systemImage: selectedMetric.icon)
                    .font(.headline)

                Spacer()

                if let current = currentValue {
                    Text(formatValue(current, for: selectedMetric))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                }
            }

            if chartData.isEmpty {
                emptyChartView
            } else {
                Chart {
                    ForEach(chartData) { dataPoint in
                        LineMark(
                            x: .value("Time", dataPoint.date),
                            y: .value(selectedMetric.displayName, dataPoint.value)
                        )
                        .foregroundStyle(selectedMetric.color)
                        .interpolationMethod(.catmullRom)

                        AreaMark(
                            x: .value("Time", dataPoint.date),
                            y: .value(selectedMetric.displayName, dataPoint.value)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                gradient: Gradient(colors: [selectedMetric.color.opacity(0.3), selectedMetric.color.opacity(0.05)]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Time", dataPoint.date),
                            y: .value(selectedMetric.displayName, dataPoint.value)
                        )
                        .foregroundStyle(selectedMetric.color)
                        .symbolSize(50)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let doubleValue = value.as(Double.self) {
                                Text(formatAxisValue(doubleValue, for: selectedMetric))
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated))
                    }
                }
                .frame(height: 250)
            }

            // Trend Indicator
            if let trend = calculateTrend() {
                trendIndicatorView(trend: trend)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }

    private var emptyChartView: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No data available")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Complete more games to see performance trends")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(height: 250)
        .frame(maxWidth: .infinity)
    }

    private func trendIndicatorView(trend: TrendDirection) -> some View {
        HStack {
            Image(systemName: trend.icon)
                .foregroundColor(trend.color)

            Text(trend.description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Statistics Summary

    private var statisticsSummaryView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Summary")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                if let stats = relevantStatistics {
                    SummaryCard(title: "High", value: formatValue(stats.max, for: selectedMetric), color: .green)
                    SummaryCard(title: "Low", value: formatValue(stats.min, for: selectedMetric), color: .orange)
                    SummaryCard(title: "Average", value: formatValue(stats.average, for: selectedMetric), color: .blue)
                    SummaryCard(title: "Games", value: "\(stats.gamesCount)", color: .purple)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }

    // MARK: - Additional Charts

    private var additionalChartsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Hit Distribution")
                .font(.headline)

            hitDistributionChart
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }

    private var hitDistributionChart: some View {
        Group {
            if let stats = athlete.statistics {
                Chart {
                    BarMark(
                        x: .value("Type", "1B"),
                        y: .value("Count", stats.singles)
                    )
                    .foregroundStyle(Color.green)

                    BarMark(
                        x: .value("Type", "2B"),
                        y: .value("Count", stats.doubles)
                    )
                    .foregroundStyle(Color.blue)

                    BarMark(
                        x: .value("Type", "3B"),
                        y: .value("Count", stats.triples)
                    )
                    .foregroundStyle(Color.orange)

                    BarMark(
                        x: .value("Type", "HR"),
                        y: .value("Count", stats.homeRuns)
                    )
                    .foregroundStyle(Color.red)
                }
                .frame(height: 200)
            } else {
                Text("No hit data available")
                    .foregroundColor(.secondary)
                    .frame(height: 200)
            }
        }
    }

    // MARK: - Data Processing

    private var chartData: [ChartDataPoint] {
        switch selectedTimeframe {
        case .season:
            return seasonChartData
        case .game:
            return gameChartData
        }
    }

    private var seasonChartData: [ChartDataPoint] {
        let seasons = athlete.seasons ?? []
        let sortedSeasons = seasons
            .filter { $0.seasonStatistics != nil || $0.isActive }
            .sorted { ($0.startDate ?? Date.distantPast) < ($1.startDate ?? Date.distantPast) }

        return sortedSeasons.compactMap { season in
            let value: Double
            if let stats = season.seasonStatistics {
                value = getValue(from: stats, for: selectedMetric)
            } else {
                // Active season with no archived snapshot — compute live from completed games
                guard let liveValue = liveSeasonValue(for: season, metric: selectedMetric) else { return nil }
                value = liveValue
            }
            let label = season.isActive ? "\(season.displayName) ↑" : season.displayName
            return ChartDataPoint(
                date: season.startDate ?? Date(),
                value: value,
                label: label
            )
        }
    }

    /// Computes a single metric value for an active season by aggregating its completed game stats.
    private func liveSeasonValue(for season: Season, metric: StatMetric) -> Double? {
        let completedGames = (season.games ?? []).filter { $0.isComplete && $0.gameStats != nil }
        guard !completedGames.isEmpty else { return nil }

        var atBats = 0, hits = 0, singles = 0, doubles = 0
        var triples = 0, homeRuns = 0, walks = 0, runs = 0, rbis = 0

        for game in completedGames {
            guard let gs = game.gameStats else { continue }
            atBats    += gs.atBats
            hits      += gs.hits
            singles   += gs.singles
            doubles   += gs.doubles
            triples   += gs.triples
            homeRuns  += gs.homeRuns
            walks     += gs.walks
            runs      += gs.runs
            rbis      += gs.rbis
        }

        switch metric {
        case .battingAverage:
            return atBats > 0 ? Double(hits) / Double(atBats) : 0
        case .onBasePercentage:
            let pa = atBats + walks
            return pa > 0 ? Double(hits + walks) / Double(pa) : 0
        case .sluggingPercentage:
            let bases = singles + (doubles * 2) + (triples * 3) + (homeRuns * 4)
            return atBats > 0 ? Double(bases) / Double(atBats) : 0
        case .ops:
            let pa = atBats + walks
            let obp = pa > 0 ? Double(hits + walks) / Double(pa) : 0.0
            let bases = singles + (doubles * 2) + (triples * 3) + (homeRuns * 4)
            let slg = atBats > 0 ? Double(bases) / Double(atBats) : 0.0
            return obp + slg
        case .hits:     return Double(hits)
        case .homeRuns: return Double(homeRuns)
        case .rbis:     return Double(rbis)
        case .runs:     return Double(runs)
        }
    }

    private var gameChartData: [ChartDataPoint] {
        var games = athlete.games ?? []

        // Filter by season if selected
        if let season = selectedSeason {
            games = games.filter { $0.season?.id == season.id }
        }

        let sortedGames = games
            .filter { $0.isComplete && $0.gameStats != nil }
            .sorted { ($0.date ?? Date.distantPast) < ($1.date ?? Date.distantPast) }

        return sortedGames.compactMap { game in
            guard let stats = game.gameStats else { return nil }
            let value = getValue(from: stats, for: selectedMetric)
            return ChartDataPoint(
                date: game.date ?? Date(),
                value: value,
                label: game.opponent
            )
        }
    }

    private var currentValue: Double? {
        chartData.last?.value
    }

    private var relevantStatistics: StatsSummary? {
        guard !chartData.isEmpty else { return nil }

        let values = chartData.map { $0.value }
        return StatsSummary(
            max: values.max() ?? 0,
            min: values.min() ?? 0,
            average: values.reduce(0, +) / Double(values.count),
            gamesCount: chartData.count
        )
    }

    private func getValue(from stats: AthleteStatistics, for metric: StatMetric) -> Double {
        switch metric {
        case .battingAverage: return stats.battingAverage
        case .onBasePercentage: return stats.onBasePercentage
        case .sluggingPercentage: return stats.sluggingPercentage
        case .ops: return stats.ops
        case .hits: return Double(stats.hits)
        case .homeRuns: return Double(stats.homeRuns)
        case .rbis: return Double(stats.rbis)
        case .runs: return Double(stats.runs)
        }
    }

    private func getValue(from stats: GameStatistics, for metric: StatMetric) -> Double {
        switch metric {
        case .battingAverage: return stats.battingAverage
        case .onBasePercentage: return stats.onBasePercentage
        case .sluggingPercentage: return stats.sluggingPercentage
        case .ops: return stats.ops
        case .hits: return Double(stats.hits)
        case .homeRuns: return Double(stats.homeRuns)
        case .rbis: return Double(stats.rbis)
        case .runs: return Double(stats.runs)
        }
    }

    private func calculateTrend() -> TrendDirection? {
        guard chartData.count >= 2 else { return nil }

        let recentData = chartData.suffix(min(5, chartData.count))
        let values = recentData.map { $0.value }

        guard values.count >= 2 else { return nil }

        let firstHalf = values.prefix(values.count / 2)
        let secondHalf = values.suffix(values.count - values.count / 2)

        let firstAvg = firstHalf.reduce(0, +) / Double(firstHalf.count)
        let secondAvg = secondHalf.reduce(0, +) / Double(secondHalf.count)

        let change = secondAvg - firstAvg
        guard firstAvg != 0.0 else { return .stable }
        let percentChange = (change / firstAvg) * 100

        if percentChange > 5 {
            return .improving
        } else if percentChange < -5 {
            return .declining
        } else {
            return .stable
        }
    }

    // MARK: - Formatting

    private func formatValue(_ value: Double, for metric: StatMetric) -> String {
        switch metric {
        case .battingAverage, .onBasePercentage, .sluggingPercentage:
            return value.formatted(.number.precision(.fractionLength(3)))
        case .ops:
            return value.formatted(.number.precision(.fractionLength(3)))
        case .hits, .homeRuns, .rbis, .runs:
            return String(Int(value))
        }
    }

    private func formatAxisValue(_ value: Double, for metric: StatMetric) -> String {
        switch metric {
        case .battingAverage, .onBasePercentage, .sluggingPercentage, .ops:
            return value.formatted(.number.precision(.fractionLength(2)))
        case .hits, .homeRuns, .rbis, .runs:
            return String(Int(value))
        }
    }
}

// MARK: - Supporting Types

enum StatMetric: String, CaseIterable, Identifiable {
    case battingAverage = "avg"
    case onBasePercentage = "obp"
    case sluggingPercentage = "slg"
    case ops = "ops"
    case hits = "hits"
    case homeRuns = "hr"
    case rbis = "rbi"
    case runs = "runs"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .battingAverage: return "Batting Average"
        case .onBasePercentage: return "On-Base %"
        case .sluggingPercentage: return "Slugging %"
        case .ops: return "OPS"
        case .hits: return "Hits"
        case .homeRuns: return "Home Runs"
        case .rbis: return "RBIs"
        case .runs: return "Runs"
        }
    }

    var shortName: String {
        switch self {
        case .battingAverage: return "AVG"
        case .onBasePercentage: return "OBP"
        case .sluggingPercentage: return "SLG"
        case .ops: return "OPS"
        case .hits: return "H"
        case .homeRuns: return "HR"
        case .rbis: return "RBI"
        case .runs: return "R"
        }
    }

    var icon: String {
        switch self {
        case .battingAverage: return "chart.bar.fill"
        case .onBasePercentage: return "target"
        case .sluggingPercentage: return "bolt.fill"
        case .ops: return "star.fill"
        case .hits: return "figure.baseball"
        case .homeRuns: return "baseball.fill"
        case .rbis: return "person.2.fill"
        case .runs: return "flag.fill"
        }
    }

    var color: Color {
        switch self {
        case .battingAverage: return .blue
        case .onBasePercentage: return .green
        case .sluggingPercentage: return .orange
        case .ops: return .purple
        case .hits: return .cyan
        case .homeRuns: return .red
        case .rbis: return .indigo
        case .runs: return .mint
        }
    }
}

enum Timeframe: String, CaseIterable, Identifiable {
    case season = "season"
    case game = "game"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .season: return "Season"
        case .game: return "Game"
        }
    }
}

struct ChartDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
    let label: String
}

struct StatsSummary {
    let max: Double
    let min: Double
    let average: Double
    let gamesCount: Int
}

enum TrendDirection {
    case improving
    case declining
    case stable

    var icon: String {
        switch self {
        case .improving: return "arrow.up.right"
        case .declining: return "arrow.down.right"
        case .stable: return "arrow.right"
        }
    }

    var color: Color {
        switch self {
        case .improving: return .green
        case .declining: return .red
        case .stable: return .blue
        }
    }

    var description: String {
        switch self {
        case .improving: return "Trending up"
        case .declining: return "Trending down"
        case .stable: return "Stable performance"
        }
    }
}

// MARK: - Supporting Views

struct MetricChip: View {
    let metric: StatMetric
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: metric.icon)
                    .font(.caption)
                Text(metric.shortName)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isSelected ? metric.color : Color(.systemGray6))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(20)
        }
    }
}

struct SummaryCard: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        StatisticsChartsView(athlete: Athlete(name: "Sample Player"))
    }
}
