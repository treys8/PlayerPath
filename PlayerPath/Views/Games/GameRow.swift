//
//  GameRow.swift
//  PlayerPath
//
//  Game row view for displaying individual games in a list.
//  Visual overhaul: cream-on-white scorebook row — date tile + opponent/course
//  + stat line + score + chevron. Swipe actions and sections are owned by
//  GamesView; this is the row surface only.
//

import SwiftUI
import SwiftData

// MARK: - Game Row View
struct GameRow: View {
    let game: Game
    var isSeasonFiltered: Bool = false

    private var isGolf: Bool { game.season?.sport == .golf }
    private var tileColor: Color { isGolf ? Theme.tileForest : Theme.tileNavy }
    private var showSeason: Bool { !game.isLive && !isSeasonFiltered }

    var body: some View {
        HStack(spacing: .spacingMedium) {
            PPDateTile(date: game.date ?? game.createdAt ?? Date(), tileColor: tileColor)

            GameInfoView(game: game, showSeason: showSeason)

            Spacer(minLength: .spacingSmall)

            if game.displayStatus == .live {
                LiveBadge()
            } else {
                RightStatusView(game: game)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.spacingMedium)
        .ppCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isGolf ? "Round at \(game.opponent)" : "Game against \(game.opponent)")
        .accessibilityValue(accessibilityStatus)
    }

    private var accessibilityStatus: String {
        switch game.displayStatus {
        case .live: return "Live"
        case .completed: return "Completed"
        case .scheduled: return "Scheduled"
        }
    }

    private struct RightStatusView: View {
        let game: Game

        private var isGolf: Bool { game.season?.sport == .golf }

        var body: some View {
            if isGolf, let score = game.effectiveTotalScore {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(score)")
                        .font(.ppStatSmall)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                    if let par = game.effectivePar {
                        let diff = score - par
                        Text(diff == 0 ? "E" : (diff > 0 ? "+\(diff)" : "\(diff)"))
                            .font(.labelSmall)
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        Text("SCORE").smallCapsLabel(color: Theme.textTertiary)
                    }
                }
            } else if !isGolf, let stats = game.gameStats, stats.atBats > 0 {
                // Baseball/softball batting summary — hits-for-AB + AVG.
                // Never RBI or runs (no game context tracked).
                VStack(alignment: .trailing, spacing: 2) {
                    // "1-for-2" — reads as a batting line, not a 1–2 game score
                    // (the app tracks no team score).
                    Text("\(stats.hits)-for-\(stats.atBats)")
                        .font(.ppStatSmall)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                    Text(StatisticsService.shared.formatBattingAverage(Double(stats.hits) / Double(stats.atBats)))
                        .font(.labelSmall)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private struct GameInfoView: View {
        let game: Game
        var showSeason: Bool = true

        private var isGolf: Bool { game.season?.sport == .golf }

        var body: some View {
            VStack(alignment: .leading, spacing: 5) {
                Text(game.opponentLabel)
                    .font(.ppHeadline)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if isGolf {
                        PPOutcomeChip(label: "GOLF", style: .green)
                    }
                    if let count = game.videoClips?.count, count > 0 {
                        Text("\(count) clip\(count == 1 ? "" : "s")")
                            .smallCapsLabel(color: Theme.textTertiary)
                    }
                    if showSeason, let season = game.season {
                        Text(season.displayName)
                            .font(.labelSmall)
                            .foregroundStyle(season.isActive ? Theme.surface : Theme.textSecondary)
                            .badgeSmall()
                            .background(
                                season.isActive ? Theme.accent : Theme.divider,
                                in: Capsule()
                            )
                    }
                }
            }
        }
    }
}

// Pulsing live badge — terracotta accent (live = significance, the one accent).
struct LiveBadge: View {
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(.white)
                .frame(width: 6, height: 6)
            Text("LIVE")
                .font(.ppCaptionBold)
        }
        .foregroundStyle(.white)
        .badgeMedium()
        .background(Capsule().fill(Theme.accent))
        .opacity(isPulsing ? 0.7 : 1.0)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}
