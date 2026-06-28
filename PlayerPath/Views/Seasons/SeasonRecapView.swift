//
//  SeasonRecapView.swift
//  PlayerPath
//
//  A "year in review" for one season: an at-a-glance count card, a sport-aware
//  stat band (batting line for baseball/softball, scoring roll-up for golf), the
//  season's top milestones, and a one-tap "Build Recap Reel".
//
//  Pure read-over of existing data — no schema, no new fields. Stats come from
//  `season.seasonStatistics` / `GolfExportData.seasonSummary`, milestones from
//  `MilestoneEngine`, and the reel reuses the same `GenerateReelView` +
//  `season_<id>` cache scope as the per-season reel in `SeasonDetailView`. The
//  recap itself is free; only the reel build is Plus-gated.
//

import SwiftUI
import SwiftData

struct SeasonRecapView: View {
    let season: Season
    let athlete: Athlete

    @Environment(\.ppAccent) private var ppAccent
    @EnvironmentObject private var authManager: ComprehensiveAuthManager

    @State private var showingReel = false
    @State private var showingReelPaywall = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                glanceCard
                sportStatCard
                milestonesCard
                reelCard
            }
            .padding()
        }
        .ppDetailBackground()
        .navigationTitle("Season Recap")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { AnalyticsService.shared.trackScreenView(screenName: "SeasonRecap", screenClass: "SeasonRecapView") }
        .fullScreenCover(isPresented: $showingReel) {
            GenerateReelView(
                clips: reelClips,
                scopeKey: "season_\(season.id.uuidString)",
                title: "\(season.displayName) Recap"
            )
        }
        .sheet(isPresented: $showingReelPaywall) {
            if let user = authManager.localUser {
                ImprovedPaywallView(user: user, requiredTier: .plus)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: (season.sport ?? .baseball).icon)
                .font(.largeTitle)
                .foregroundStyle(ppAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text(season.displayName)
                    .font(.ppTitle)
                    .foregroundStyle(Theme.textPrimary)
                if let range = dateRangeText {
                    Text(range)
                        .font(.ppSubheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - At a glance

    private var glanceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("At a Glance").smallCapsLabel(color: ppAccent)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                ForEach(glanceStats) { stat in
                    statTile(stat)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .ppCard()
    }

    private var glanceStats: [RecapStat] {
        [
            RecapStat(label: season.gameUnitNounPlural, value: "\(season.completedGames)", icon: season.gameUnitIcon),
            RecapStat(label: "Highlights", value: "\(season.highlights.count)", icon: "star.fill"),
            RecapStat(label: "Videos", value: "\(season.totalVideos)", icon: "video.fill"),
            RecapStat(label: "Practices", value: "\(season.practicesCount)", icon: "figure.run")
        ]
    }

    private func statTile(_ stat: RecapStat) -> some View {
        VStack(spacing: 6) {
            Image(systemName: stat.icon)
                .font(.title3)
                .foregroundStyle(ppAccent)
            Text(stat.value)
                .font(.ppTitle)
                .foregroundStyle(Theme.textPrimary)
            Text(stat.label).smallCapsLabel()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Sport stat band

    @ViewBuilder
    private var sportStatCard: some View {
        if (season.sport ?? .baseball) == .golf {
            golfStatCard
        } else {
            battingStatCard
        }
    }

    @ViewBuilder
    private var battingStatCard: some View {
        if let stats = season.seasonStatistics, stats.atBats > 0 {
            VStack(alignment: .leading, spacing: 14) {
                Text("Batting").smallCapsLabel(color: ppAccent)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    statTile(RecapStat(label: "Average", value: battingAvgDisplay(stats.battingAverage), icon: "chart.bar.fill"))
                    statTile(RecapStat(label: "Hits", value: "\(stats.hits)", icon: "figure.baseball"))
                    statTile(RecapStat(label: "Home Runs", value: "\(stats.homeRuns)", icon: "sparkles"))
                    statTile(RecapStat(label: "Walks", value: "\(stats.walks)", icon: "figure.walk"))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .ppCard()
        }
    }

    @ViewBuilder
    private var golfStatCard: some View {
        let summary = GolfExportData.seasonSummary(for: athlete, season: season)
        if summary.rounds > 0 {
            VStack(alignment: .leading, spacing: 14) {
                Text("Scoring").smallCapsLabel(color: ppAccent)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    statTile(RecapStat(label: "18-Hole Rounds", value: "\(summary.rounds)", icon: "figure.golf"))
                    if let best = summary.bestScore {
                        statTile(RecapStat(label: "Best Round", value: "\(best)", icon: "trophy.fill"))
                    }
                    if let avg = summary.avgScore {
                        statTile(RecapStat(label: "Avg Score", value: String(format: "%.1f", avg), icon: "chart.bar.fill"))
                    }
                    if let toPar = summary.avgToPar {
                        statTile(RecapStat(label: "Avg to Par", value: toParDisplay(toPar), icon: "flag.fill"))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .ppCard()
        }
    }

    // MARK: - Milestones

    @ViewBuilder
    private var milestonesCard: some View {
        let top = topMilestones
        if !top.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("Top Moments").smallCapsLabel(color: ppAccent)
                ForEach(top) { milestone in
                    VStack(alignment: .leading, spacing: 4) {
                        PPMilestoneMarker(label: milestone.markerLabel)
                        Text(milestone.title)
                            .font(.ppHeadline)
                            .foregroundStyle(Theme.textPrimary)
                        if let detail = milestone.detail {
                            Text(detail)
                                .font(.ppCaption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if milestone.id != top.last?.id {
                        Divider()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .ppCard()
        }
    }

    /// Most significant milestones first (rank, then recency), capped at three.
    private var topMilestones: [Milestone] {
        MilestoneEngine.milestones(for: season)
            .sorted { lhs, rhs in
                lhs.kind.sortRank == rhs.kind.sortRank
                    ? lhs.date > rhs.date
                    : lhs.kind.sortRank > rhs.kind.sortRank
            }
            .prefix(3)
            .map { $0 }
    }

    // MARK: - Reel

    private var reelCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recap Reel").smallCapsLabel(color: ppAccent)
            if reelEligible {
                Text("Stitch this season's \(season.highlights.count) starred clips into one shareable reel.")
                    .font(.ppSubheadline)
                    .foregroundStyle(Theme.textSecondary)
                Button {
                    generateReelTapped()
                } label: {
                    Label("Build Recap Reel", systemImage: "film.stack")
                        .font(.ppHeadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(ppAccent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            } else {
                Text("Star at least two clips from this season to build a recap reel.")
                    .font(.ppSubheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .ppCard()
    }

    /// Starred clips for this season in chronological (playback) order.
    private var reelClips: [VideoClip] {
        season.highlights.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }

    /// A reel needs at least two clips.
    private var reelEligible: Bool { season.highlights.count >= 2 }

    /// Plus-gated: open the generator, or route free users to the paywall.
    private func generateReelTapped() {
        Haptics.light()
        if SubscriptionGate.effectiveAthleteTier.hasAutoHighlights {
            showingReel = true
        } else {
            showingReelPaywall = true
        }
    }

    // MARK: - Formatting helpers

    private var dateRangeText: String? {
        guard let start = season.startDate else { return nil }
        let startStr = start.formatted(date: .abbreviated, time: .omitted)
        if let end = season.endDate {
            return "\(startStr) – \(end.formatted(date: .abbreviated, time: .omitted))"
        }
        return season.isActive ? "\(startStr) – In Progress" : startStr
    }

    /// Matches `SeasonDetailView`'s batting-average formatting.
    private func battingAvgDisplay(_ avg: Double) -> String {
        avg >= 1.0 ? "1.000" : String(format: ".%03d", Int(avg * 1000))
    }

    private func toParDisplay(_ diff: Double) -> String {
        if abs(diff) < 0.05 { return "E" }
        return diff > 0 ? "+\(String(format: "%.1f", diff))" : String(format: "%.1f", diff)
    }
}

/// One stat tile's content. `label` is its stable identity (each appears once).
private struct RecapStat: Identifiable {
    let label: String
    let value: String
    let icon: String
    var id: String { label }
}
