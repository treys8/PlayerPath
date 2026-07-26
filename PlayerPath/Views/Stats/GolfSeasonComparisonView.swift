//
//  GolfSeasonComparisonView.swift
//  PlayerPath
//
//  Plus golf season comparison — parity with baseball's SeasonComparisonView.
//  Compares 2-4 golf seasons on scoring metrics derived live from
//  GolfExportData.seasonSummary (18-hole tournament rounds only). Reuses the
//  shared MetricTrendChart / LockedFeaturePlaceholder / ComparisonRow shells.
//

import SwiftUI
import SwiftData
import Charts

struct GolfSeasonComparisonView: View {
    let athlete: Athlete
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedSeasons: Set<UUID> = []

    /// Set once the user taps Compare. Without it the view would swap to the
    /// charts the instant a second season was tapped, making the advertised
    /// 3- and 4-season comparisons unreachable.
    @State private var isComparing = false

    // MARK: - Season pools

    private var allSeasons: [Season] {
        var seasons: [Season] = []
        if let active = athlete.activeSeason { seasons.append(active) }
        seasons.append(contentsOf: athlete.archivedSeasons)
        let unique = Dictionary(grouping: seasons, by: \.id).compactMap { $0.value.first }
        return unique
            .filter { $0.sport == .golf }
            .sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
    }

    /// Selected seasons, oldest→newest so trends read left-to-right in time.
    private var seasonsToCompare: [Season] {
        allSeasons
            .filter { selectedSeasons.contains($0.id) }
            .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
    }

    private var canCompare: Bool { selectedSeasons.count >= 2 }

    /// One summary per compared season, in the same oldest→newest order.
    private var summaries: [(season: Season, summary: GolfSeasonSummary)] {
        seasonsToCompare.map { ($0, GolfExportData.seasonSummary(for: athlete, season: $0)) }
    }

    private var anyHasPutts: Bool { summaries.contains { $0.summary.avgPutts != nil } }
    private var anyHasBirdies: Bool { summaries.contains { $0.summary.birdiesPerRound != nil } }
    private var anyHasGir: Bool { summaries.contains { $0.summary.girPct != nil } }
    private var anyHasFir: Bool { summaries.contains { $0.summary.firPct != nil } }
    private var anyHasScramble: Bool { summaries.contains { $0.summary.scramblingPct != nil } }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if authManager.currentTier < .plus {
                    LockedFeaturePlaceholder(message: "Upgrade to Plus to compare golf seasons side-by-side")
                } else if isComparing && canCompare {
                    comparison
                        .onAppear { AnalyticsService.shared.trackScreenView(screenName: "Golf Season Comparison", screenClass: "GolfSeasonComparisonView") }
                } else {
                    seasonSelection
                }
            }
            .navigationTitle("Season Comparison")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if authManager.currentTier >= .plus && isComparing {
                    ToolbarItem(placement: .primaryAction) {
                        // Back to the picker with the current selection intact
                        Button("Change Seasons") { isComparing = false }
                    }
                }
            }
        }
    }

    // MARK: - Comparison

    private var comparison: some View {
        ScrollView {
            VStack(spacing: 20) {
                MetricTrendChart(
                    title: "Scoring Average",
                    points: points { $0.avgScore },
                    format: { formatScore($0) }
                )

                MetricTrendChart(
                    title: "Average To Par",
                    points: points { $0.avgToPar },
                    format: { formatToPar($0) }
                )

                if anyHasPutts {
                    MetricTrendChart(
                        title: "Putts per Round",
                        points: points { $0.avgPutts },
                        format: { formatScore($0) }
                    )
                }

                if anyHasBirdies {
                    MetricTrendChart(
                        title: "Birdies per Round",
                        points: points { $0.birdiesPerRound },
                        format: { formatScore($0) }
                    )
                }

                if anyHasGir {
                    MetricTrendChart(
                        title: "Greens in Regulation %",
                        points: points { $0.girPct },
                        format: { formatPct($0) }
                    )
                }

                if anyHasFir {
                    MetricTrendChart(
                        title: "Fairways Hit %",
                        points: points { $0.firPct },
                        format: { formatPct($0) }
                    )
                }

                detailTable
            }
            .padding()
        }
        .background(Theme.surface)
    }

    /// Builds trend points for a metric, skipping seasons with no qualifying
    /// rounds so a barren season doesn't plot as a misleading zero.
    private func points(_ value: (GolfSeasonSummary) -> Double?) -> [TrendPoint] {
        summaries.enumerated().compactMap { index, pair in
            guard let v = value(pair.summary) else { return nil }
            return TrendPoint(order: index, label: pair.season.displayName, value: v)
        }
    }

    private var detailTable: some View {
        let seasons = seasonsToCompare
        let byID = Dictionary(uniqueKeysWithValues: summaries.map { ($0.season.id, $0.summary) })

        func cell(_ pick: @escaping (GolfSeasonSummary) -> String) -> (Season) -> String {
            { season in byID[season.id].map(pick) ?? "—" }
        }

        return VStack(alignment: .leading, spacing: 12) {
            Text("Detailed Scoring")
                .font(.headingLarge)

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        Text("Stat")
                            .font(.custom("Inter18pt-SemiBold", size: 12, relativeTo: .caption))
                            .frame(width: 110, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 12)
                            .background(Color.gray.opacity(0.2))

                        ForEach(seasons) { season in
                            Text(season.displayName)
                                .font(.custom("Inter18pt-SemiBold", size: 12, relativeTo: .caption))
                                .frame(width: 100, alignment: .center)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 12)
                                .background(Color.brandNavy.opacity(0.1))
                        }
                    }

                    Divider()

                    GolfComparisonRow(label: "Rounds", seasons: seasons, width: 110,
                                      getValue: cell { "\($0.rounds)" })
                    GolfComparisonRow(label: "Best", seasons: seasons, width: 110,
                                      getValue: cell { $0.bestScore.map { "\($0)" } ?? "—" })
                    GolfComparisonRow(label: "Avg Score", seasons: seasons, width: 110,
                                      getValue: cell { $0.avgScore.map(formatScore) ?? "—" })
                    GolfComparisonRow(label: "Avg To Par", seasons: seasons, width: 110,
                                      getValue: cell { $0.avgToPar.map(formatToPar) ?? "—" })
                    GolfComparisonRow(label: "Putts/Round", seasons: seasons, width: 110,
                                      getValue: cell { $0.avgPutts.map(formatScore) ?? "—" })
                    GolfComparisonRow(label: "Birdies/Round", seasons: seasons, width: 110,
                                      getValue: cell { $0.birdiesPerRound.map(formatScore) ?? "—" })
                    if anyHasGir {
                        GolfComparisonRow(label: "GIR %", seasons: seasons, width: 110,
                                          getValue: cell { $0.girPct.map(formatPct) ?? "—" })
                    }
                    if anyHasFir {
                        GolfComparisonRow(label: "Fairways %", seasons: seasons, width: 110,
                                          getValue: cell { $0.firPct.map(formatPct) ?? "—" })
                    }
                    if anyHasScramble {
                        GolfComparisonRow(label: "Scrambling %", seasons: seasons, width: 110,
                                          getValue: cell { $0.scramblingPct.map(formatPct) ?? "—" })
                    }
                }
            }
        }
        .padding()
        .statCardBackground()
    }

    // MARK: - Season selection

    @ViewBuilder
    private var seasonSelection: some View {
        // Comparison needs two seasons — with fewer, the picker is a dead end.
        if allSeasons.count < 2 {
            notEnoughSeasons
        } else {
            List {
                Section {
                    ForEach(allSeasons) { season in
                        Button {
                            toggleSeason(season)
                        } label: {
                            GolfSeasonSelectionRow(
                                season: season,
                                summary: GolfExportData.seasonSummary(for: athlete, season: season),
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
        case 0: return "Pick the golf seasons you want to see side-by-side."
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
                        .fill(canCompare ? Theme.golfAccent : Theme.textTertiary)
                )
        }
        .disabled(!canCompare)
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Theme.surface)
    }

    private var notEnoughSeasons: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(allSeasons.isEmpty ? "No Golf Seasons Yet" : "Only One Golf Season")
                .font(.headingLarge)
            Text(allSeasons.isEmpty
                 ? "Create at least two golf seasons with scored rounds to start comparing."
                 : "Comparison needs at least two seasons. Start a new season — this one stays in your history.")
                .font(.bodyMedium)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface)
    }

    private func toggleSeason(_ season: Season) {
        if selectedSeasons.contains(season.id) {
            selectedSeasons.remove(season.id)
            Haptics.light()
        } else if selectedSeasons.count < 4 {
            selectedSeasons.insert(season.id)
            Haptics.light()
        } else {
            Haptics.warning()
        }
    }

    // MARK: - Formatting

    private func formatScore(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
    }

    private func formatToPar(_ value: Double) -> String {
        if abs(value) < 0.05 { return "E" }
        let rounded = (value * 10).rounded() / 10
        let body = rounded == rounded.rounded() ? "\(Int(rounded))" : String(format: "%.1f", rounded)
        return rounded > 0 ? "+\(body)" : body
    }

    private func formatPct(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }
}

// MARK: - Rows

/// Golf detail-table row. Mirrors baseball's `ComparisonRow` but takes a
/// pre-formatted string closure (golf values are derived, not stored on the
/// season) and a configurable label width for the longer golf stat names.
private struct GolfComparisonRow: View {
    let label: String
    let seasons: [Season]
    let width: CGFloat
    let getValue: (Season) -> String

    var body: some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.bodySmall)
                .frame(width: width, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)

            ForEach(seasons) { season in
                Text(getValue(season))
                    .font(.bodySmall)
                    .monospacedDigit()
                    .frame(width: 100, alignment: .center)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
            }
        }
        .background(Color(.systemBackground))

        Divider()
    }
}

private struct GolfSeasonSelectionRow: View {
    let season: Season
    let summary: GolfSeasonSummary
    let isSelected: Bool

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
                            .background(Color.brandNavy)
                            .cornerRadius(4)
                    }
                }

                if summary.rounds > 0 {
                    Text(subtitle)
                        .font(.bodySmall)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No scored 18-hole rounds yet")
                        .font(.bodySmall)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.brandNavy : Color.gray)
                .font(.title3)
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        var parts = ["\(summary.rounds) round\(summary.rounds == 1 ? "" : "s")"]
        if let best = summary.bestScore { parts.append("best \(best)") }
        if let avg = summary.avgScore {
            parts.append("avg \(avg == avg.rounded() ? "\(Int(avg))" : String(format: "%.1f", avg))")
        }
        return parts.joined(separator: " • ")
    }
}
