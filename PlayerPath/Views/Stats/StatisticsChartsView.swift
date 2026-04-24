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
    var initialSeason: Season?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedMetric: StatMetric = .battingAverage
    @State private var selectedTimeframe: Timeframe = .game
    @State private var selectedSeason: Season?

    var body: some View {
        ScrollView {
            VStack(spacing: horizontalSizeClass == .regular ? 32 : 24) {
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
        .onAppear {
            if selectedSeason == nil {
                selectedSeason = initialSeason
            }
        }
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
                        if isGameLevelData {
                            LineMark(
                                x: .value("Game", dataPoint.index),
                                y: .value(selectedMetric.displayName, dataPoint.value)
                            )
                            .foregroundStyle(selectedMetric.color)
                            .interpolationMethod(.catmullRom)

                            AreaMark(
                                x: .value("Game", dataPoint.index),
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
                                x: .value("Game", dataPoint.index),
                                y: .value(selectedMetric.displayName, dataPoint.value)
                            )
                            .foregroundStyle(selectedMetric.color)
                            .symbolSize(50)
                        } else {
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
                        if isGameLevelData {
                            AxisValueLabel {
                                if let idx = value.as(Int.self) {
                                    Text("G\(idx)")
                                }
                            }
                        } else {
                            AxisValueLabel {
                                if let date = value.as(Date.self) {
                                    Text(date, format: .dateTime.month(.abbreviated).year(.twoDigits))
                                }
                            }
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(chartAccessibilityLabel)
                .frame(height: horizontalSizeClass == .regular ? 380 : 250)
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
        .frame(height: horizontalSizeClass == .regular ? 380 : 250)
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

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: horizontalSizeClass == .regular ? 4 : 2), spacing: 12) {
                if let stats = relevantStatistics {
                    SummaryCard(title: "High", value: formatValue(stats.max, for: selectedMetric), color: .green)
                    SummaryCard(title: "Low", value: formatValue(stats.min, for: selectedMetric), color: .orange)
                    SummaryCard(title: "Average", value: formatValue(stats.average, for: selectedMetric), color: .blue)
                    SummaryCard(title: "Games", value: "\(stats.gamesCount)", color: .purple)
                } else if let careerStats = athlete.statistics {
                    let careerValue = getValue(from: careerStats, for: selectedMetric)
                    SummaryCard(title: "Career \(selectedMetric.shortName)", value: formatValue(careerValue, for: selectedMetric), color: selectedMetric.color)
                    SummaryCard(title: "At-Bats", value: "\(careerStats.atBats)", color: .blue)
                    SummaryCard(title: "Hits", value: "\(careerStats.hits)", color: .green)
                    SummaryCard(title: "Games", value: "\(careerStats.totalGames)", color: .purple)
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

    /// Hit counts filtered to match the currently selected timeframe/season.
    private var filteredHits: (singles: Int, doubles: Int, triples: Int, homeRuns: Int) {
        var games = athlete.games ?? []

        // In game view, honour the season filter if one is selected
        if selectedTimeframe == .game, let season = selectedSeason {
            games = games.filter { $0.season?.id == season.id }
        }

        let completed = games.filter { $0.countsTowardStats && $0.gameStats != nil }

        guard !completed.isEmpty else {
            // Fall back to career totals when no game data matches
            return (
                athlete.statistics?.singles ?? 0,
                athlete.statistics?.doubles ?? 0,
                athlete.statistics?.triples ?? 0,
                athlete.statistics?.homeRuns ?? 0
            )
        }

        return (
            completed.compactMap { $0.gameStats?.singles }.reduce(0, +),
            completed.compactMap { $0.gameStats?.doubles }.reduce(0, +),
            completed.compactMap { $0.gameStats?.triples }.reduce(0, +),
            completed.compactMap { $0.gameStats?.homeRuns }.reduce(0, +)
        )
    }

    private var hitDistributionChart: some View {
        let hits = filteredHits
        let hasData = hits.singles + hits.doubles + hits.triples + hits.homeRuns > 0
        return Group {
            if hasData {
                Chart {
                    BarMark(x: .value("Type", "1B"), y: .value("Count", hits.singles))
                        .foregroundStyle(by: .value("Hit Type", "Single"))
                    BarMark(x: .value("Type", "2B"), y: .value("Count", hits.doubles))
                        .foregroundStyle(by: .value("Hit Type", "Double"))
                    BarMark(x: .value("Type", "3B"), y: .value("Count", hits.triples))
                        .foregroundStyle(by: .value("Hit Type", "Triple"))
                    BarMark(x: .value("Type", "HR"), y: .value("Count", hits.homeRuns))
                        .foregroundStyle(by: .value("Hit Type", "Home Run"))
                }
                .chartForegroundStyleScale([
                    "Single":   .green,
                    "Double":   .blue,
                    "Triple":   .orange,
                    "Home Run": .red
                ])
                .frame(height: horizontalSizeClass == .regular ? 300 : 200)
            } else {
                Text("No hit data available")
                    .foregroundColor(.secondary)
                    .frame(height: horizontalSizeClass == .regular ? 300 : 200)
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
        let sortedSeasons = (athlete.seasons ?? [])
            .filter { $0.seasonStatistics != nil || $0.isActive }
            .sorted { ($0.startDate ?? Date.distantPast) < ($1.startDate ?? Date.distantPast) }

        let seasonPoints = sortedSeasons.compactMap { season -> ChartDataPoint? in
            let value: Double
            if let stats = season.seasonStatistics {
                // Skip rate stats for seasons with no at-bats
                if selectedMetric.isRateStat && stats.atBats == 0 { return nil }
                value = getValue(from: stats, for: selectedMetric)
            } else {
                guard let liveValue = liveSeasonValue(for: season, metric: selectedMetric) else { return nil }
                value = liveValue
            }
            let label = season.isActive ? "\(season.displayName) ↑" : season.displayName
            return ChartDataPoint(date: season.startDate ?? Date(), value: value, label: label)
        }

        // If we have season-level data, use it.
        // If only one season exists, fall back to game-by-game cumulative view
        // so the chart has meaningful data points to show a trend.
        if seasonPoints.count >= 2 { return seasonPoints }

        // Fall back to game-by-game cumulative data (same as Game view)
        return buildGameChartData(from: athlete.games ?? [])
    }

    /// Computes a single metric value for an active season by aggregating its completed game stats.
    private func liveSeasonValue(for season: Season, metric: StatMetric) -> Double? {
        let completedGames = (season.games ?? []).filter { $0.countsTowardStats && $0.gameStats != nil }
        guard !completedGames.isEmpty else { return nil }

        let running = AthleteStatistics()
        for game in completedGames {
            if let gs = game.gameStats { running.addCounts(from: gs) }
        }

        return chartValue(from: running, for: metric)
    }

    /// Reads a rate or counting metric off an accumulator, preserving the
    /// "nil when no denominator" semantics the chart relies on (so empty series
    /// don't render a misleading .000 data point).
    private func chartValue(from stats: some PlayResultAccumulator, for metric: StatMetric) -> Double? {
        switch metric {
        case .battingAverage:
            return stats.atBats > 0 ? stats.battingAverage : nil
        case .onBasePercentage:
            let pa = stats.atBats + stats.walks + stats.hitByPitches
            return pa > 0 ? stats.onBasePercentage : nil
        case .sluggingPercentage:
            return stats.atBats > 0 ? stats.sluggingPercentage : nil
        case .ops:
            let pa = stats.atBats + stats.walks + stats.hitByPitches
            return (stats.atBats > 0 && pa > 0) ? stats.ops : nil
        case .hits:     return Double(stats.hits)
        case .homeRuns: return Double(stats.homeRuns)
        case .rbis:     return Double(stats.rbis)
        case .runs:     return Double(stats.runs)
        }
    }

    private var gameChartData: [ChartDataPoint] {
        var games = athlete.games ?? []

        // Filter by season if selected
        if let season = selectedSeason {
            games = games.filter { $0.season?.id == season.id }
        }

        return buildGameChartData(from: games)
    }

    /// Builds game-by-game chart data with ordinal indexes.
    /// Rate stats use running cumulative averages; counting stats use per-game values.
    private func buildGameChartData(from games: [Game]) -> [ChartDataPoint] {
        let sortedGames = games
            .filter { $0.countsTowardStats && $0.gameStats != nil }
            .sorted { ($0.date ?? Date.distantPast) < ($1.date ?? Date.distantPast) }

        if selectedMetric.isRateStat {
            let running = AthleteStatistics()
            var idx = 0

            return sortedGames.compactMap { game in
                guard let gs = game.gameStats else { return nil }
                running.addCounts(from: gs)

                guard let v = chartValue(from: running, for: selectedMetric) else { return nil }
                idx += 1
                return ChartDataPoint(date: game.date ?? Date(), value: v, label: game.opponent, index: idx)
            }
        }

        var idx = 0
        return sortedGames.compactMap { game in
            guard let stats = game.gameStats else { return nil }
            let value = getValue(from: stats, for: selectedMetric)
            idx += 1
            return ChartDataPoint(date: game.date ?? Date(), value: value, label: game.opponent, index: idx)
        }
    }

    private var currentValue: Double? {
        // Pull from the same statistics objects the Statistics page uses
        if let season = selectedSeason {
            if let stats = season.seasonStatistics {
                return getValue(from: stats, for: selectedMetric)
            }
            return liveSeasonValue(for: season, metric: selectedMetric)
        }
        // All Seasons = career statistics
        if let stats = athlete.statistics {
            return getValue(from: stats, for: selectedMetric)
        }
        return chartData.last?.value
    }

    /// True when chart data is game-by-game (needs ordinal X-axis, not dates)
    private var isGameLevelData: Bool {
        if selectedTimeframe == .game { return true }
        // Season view fell back to game data (single season)
        let seasonCount = (athlete.seasons ?? [])
            .filter { $0.seasonStatistics != nil || $0.isActive }
            .count
        return seasonCount < 2
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

    private func getValue(from stats: some PlayResultAccumulator, for metric: StatMetric) -> Double {
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

    // MARK: - Accessibility

    private var chartAccessibilityLabel: String {
        let metricName = selectedMetric.displayName
        let count = chartData.count
        guard count > 0 else { return "\(metricName) chart, no data" }

        let values = chartData.map { $0.value }
        guard let lastValue = values.last else { return "\(metricName) chart, no data" }
        let latest = formatValue(lastValue, for: selectedMetric)
        let trendText: String
        if let trend = calculateTrend() {
            switch trend {
            case .improving: trendText = ", trending up"
            case .declining: trendText = ", trending down"
            case .stable: trendText = ", stable"
            }
        } else {
            trendText = ""
        }

        return "\(metricName) chart, \(count) data points, latest value \(latest)\(trendText)"
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
        case .homeRuns: return .gold
        case .rbis: return .indigo
        case .runs: return .mint
        }
    }

    var isRateStat: Bool {
        switch self {
        case .battingAverage, .onBasePercentage, .sluggingPercentage, .ops: return true
        case .hits, .homeRuns, .rbis, .runs: return false
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
    let id: UUID
    let date: Date
    let value: Double
    let label: String
    let index: Int

    init(date: Date, value: Double, label: String, index: Int = 0) {
        self.id = UUID()
        self.date = date
        self.value = value
        self.label = label
        self.index = index
    }
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
