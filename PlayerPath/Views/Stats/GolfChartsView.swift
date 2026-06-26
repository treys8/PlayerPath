//
//  GolfChartsView.swift
//  PlayerPath
//
//  Free golf performance charts — parity with the (free) baseball charts.
//  Plots a scoring trend over rounds plus a scoring-mix breakdown, defaulting
//  to 18-hole tournament rounds so 9-hole and practice scores don't sit on the
//  same axis (the convention GolfStatsSection already follows). All values are
//  derived live via GolfExportData — no new stored stats.
//

import SwiftUI
import Charts

struct GolfChartsView: View {
    let athlete: Athlete
    /// When non-nil, only this season's rounds are charted. nil = all rounds.
    var initialSeason: Season? = nil

    enum Metric: String, CaseIterable, Identifiable {
        case score = "Score"
        case toPar = "To Par"
        case putts = "Putts"
        case gir = "GIR"
        case fir = "Fairways"
        /// Est. Strokes Gained per round vs the PGA Tour baseline. Plus-gated —
        /// see `availableMetrics`. Short label keeps the segmented picker legible.
        case strokesGained = "SG"
        var id: String { rawValue }

        /// Lower is better for strokes-based metrics; higher is better for the
        /// regulation percentages and Strokes Gained. Drives Best/Worst + axis.
        var lowerIsBetter: Bool {
            switch self {
            case .score, .toPar, .putts: return true
            case .gir, .fir, .strokesGained: return false
            }
        }
    }

    enum Scope: String, CaseIterable, Identifiable {
        case tournament = "Tournaments"
        case practice = "Practice"
        case all = "All"
        var id: String { rawValue }
    }

    @State private var metric: Metric = .score
    @State private var scope: Scope = .tournament
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    // MARK: - Round pool (newest-first rows from the shared export source)

    private var poolRows: [GolfRoundRow] {
        switch scope {
        case .tournament:
            return GolfExportData.tournamentRounds(for: athlete, season: initialSeason)
        case .practice:
            return GolfExportData.practiceRounds(for: athlete, season: initialSeason)
        case .all:
            let combined = GolfExportData.tournamentRounds(for: athlete, season: initialSeason)
                + GolfExportData.practiceRounds(for: athlete, season: initialSeason)
            return combined.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        }
    }

    /// 18-hole rounds only, oldest→newest, so the y-axis stays one scale.
    private var trendRows: [GolfRoundRow] {
        Array(poolRows.filter { $0.holes == 18 }.reversed())
    }

    // MARK: - Trend points

    private struct RoundPoint: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
    }

    private func metricValue(_ row: GolfRoundRow) -> Double? {
        switch metric {
        case .score: return row.score.map(Double.init)
        case .toPar: return row.toPar.map(Double.init)
        case .putts: return row.putts.map(Double.init)
        case .gir: return row.girPct
        case .fir: return row.firPct
        case .strokesGained: return row.strokesGained
        }
    }

    private var roundPoints: [RoundPoint] {
        trendRows.compactMap { row in
            guard let date = row.date, let value = metricValue(row) else { return nil }
            return RoundPoint(date: date, value: value)
        }
    }

    private var metricValues: [Double] { roundPoints.map { $0.value } }

    // MARK: - Holes in scope (for the distribution chart)

    private var scopedHoleScores: [HoleScore] {
        var holes: [HoleScore] = []
        if scope != .practice {
            holes += GolfExportData.scoredTournamentGames(for: athlete, season: initialSeason)
                .flatMap { $0.holeScores ?? [] }
        }
        if scope != .tournament {
            let pool = initialSeason?.practices ?? athlete.practices ?? []
            holes += pool
                .filter { $0.practiceType == PracticeType.practiceRound.rawValue }
                .flatMap { $0.holeScores ?? [] }
        }
        return holes
    }

    private var hasAnyData: Bool {
        !roundPoints.isEmpty || !scopedHoleScores.isEmpty
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                scopePicker

                if hasAnyData {
                    metricPicker
                    trendCard
                    if !metricValues.isEmpty {
                        summaryGrid
                    }
                    GolfScoreDistributionSection(holeScores: scopedHoleScores)
                } else {
                    emptyState
                }
            }
            .padding(horizontalSizeClass == .regular ? 32 : 16)
        }
        .navigationTitle("Golf Charts")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var scopePicker: some View {
        Picker("Rounds", selection: $scope) {
            ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    /// Strokes Gained is Plus-only; free users don't see it in the picker (the
    /// gated GolfStrokesGainedSection carries the upsell — that's the conversion
    /// point, not a broken locked chart).
    private var availableMetrics: [Metric] {
        SubscriptionGate.effectiveAthleteTier.hasStrokesGained
            ? Metric.allCases
            : Metric.allCases.filter { $0 != .strokesGained }
    }

    private var metricPicker: some View {
        Picker("Metric", selection: $metric) {
            ForEach(availableMetrics) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        // Belt-and-suspenders: if the tier dropped while viewing, fall back to
        // a metric that's still in scope so the segmented control isn't blank.
        .onAppear { if !availableMetrics.contains(metric) { metric = .score } }
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(metric.rawValue) by Round")
                .font(.headingLarge)

            if roundPoints.count < 2 {
                Text("Play another 18-hole round to see a trend.")
                    .font(.bodyMedium)
                    .foregroundStyle(.secondary)
                    .frame(height: 180)
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
            } else {
                Chart {
                    ForEach(roundPoints) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value(metric.rawValue, point.value)
                        )
                        .foregroundStyle(Color.brandNavy)
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Date", point.date),
                            y: .value(metric.rawValue, point.value)
                        )
                        .foregroundStyle(Color.brandNavy)
                    }
                    if metric == .toPar || metric == .strokesGained {
                        RuleMark(y: .value("Baseline", 0))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 200)
                .chartYScale(domain: .automatic(includesZero: metric == .toPar || metric == .strokesGained))
            }
        }
        .padding()
        .statCardBackground()
    }

    private var summaryGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            tile(label: "Rounds", value: "\(roundPoints.count)")
            // Lower is better for every metric (score, to-par, putts), so the
            // minimum is the best round and the maximum is the worst.
            if let best = (metric.lowerIsBetter ? metricValues.min() : metricValues.max()) {
                tile(label: "Best", value: format(best), color: .green)
            }
            if !metricValues.isEmpty {
                let avg = metricValues.reduce(0, +) / Double(metricValues.count)
                tile(label: "Average", value: format(avg))
            }
            if let worst = (metric.lowerIsBetter ? metricValues.max() : metricValues.min()) {
                tile(label: "Worst", value: format(worst), color: .secondary)
            }
        }
    }

    private func tile(label: String, value: String, color: Color = .primary) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.ppStatLarge)
                .monospacedDigit()
                .foregroundColor(color)
            Text(label)
                .font(.labelSmall)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .statCardBackground()
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.xyaxis.line")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("No rounds to chart yet")
                .font(.bodyMedium)
                .foregroundColor(.secondary)
            Text("Charts use completed 18-hole rounds. Score a full round to see your trends.")
                .font(.bodySmall)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    // MARK: - Formatting

    private func format(_ value: Double) -> String {
        switch metric {
        case .score, .putts:
            // Whole numbers stay clean; averages get one decimal.
            return value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
        case .gir, .fir:
            return "\(Int(value.rounded()))%"
        case .toPar:
            if abs(value) < 0.05 { return "E" }
            let rounded = (value * 10).rounded() / 10
            let body = rounded == rounded.rounded() ? "\(Int(rounded))" : String(format: "%.1f", rounded)
            return rounded > 0 ? "+\(body)" : body
        case .strokesGained:
            // Signed one-decimal; higher (more gained) is better.
            if abs(value) < 0.05 { return "E" }
            let rounded = (value * 10).rounded() / 10
            return rounded > 0 ? "+\(String(format: "%.1f", rounded))" : String(format: "%.1f", rounded)
        }
    }
}
