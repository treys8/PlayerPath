//
//  GameRow.swift
//  PlayerPath
//
//  Game row view for displaying individual games in a list.
//

import SwiftUI
import SwiftData

// MARK: - Game Row View
struct GameRow: View {
    let game: Game
    var isSeasonFiltered: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            // Accent bar
            RoundedRectangle(cornerRadius: 2)
                .fill(statusColor)
                .frame(width: 4)
                .padding(.vertical, 4)

            HStack(spacing: 8) {
                GameInfoView(game: game, showSeason: !game.isLive && !isSeasonFiltered)
                Spacer()
                RightStatusView(game: game)
            }
            .padding(.leading, 12)
            .padding(.trailing, 12)
            .padding(.vertical, 12)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: .cornerLarge, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Game against \(game.opponent)")
        .accessibilityValue(accessibilityStatus)
    }

    private var accessibilityStatus: String {
        switch game.displayStatus {
        case .live: return "Live"
        case .completed: return "Completed"
        case .scheduled: return "Scheduled"
        }
    }

    private var statusColor: Color {
        switch game.displayStatus {
        case .live: return .red
        case .completed: return .green
        case .scheduled: return .brandNavy
        }
    }

    private struct RightStatusView: View {
        let game: Game

        var body: some View {
            HStack(spacing: 10) {
                // Stats summary (if available)
                if let stats = game.gameStats, stats.atBats > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(stats.hits)-\(stats.atBats)")
                            .font(.ppStatSmall)
                            .monospacedDigit()
                            .foregroundColor(.primary)
                        HStack(spacing: 3) {
                            Text(StatisticsService.shared.formatBattingAverage(Double(stats.hits) / Double(stats.atBats)))
                                .font(.labelSmall)
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                            Text("AVG")
                                .font(.labelSmall)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(width: 70, alignment: .trailing)
                }

                if game.displayStatus == .live {
                    LiveBadge()
                }
            }
        }
    }

    private struct GameInfoView: View {
        let game: Game
        var showSeason: Bool = true

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                // Opponent name
                Text("vs \(game.opponent)")
                    .font(.headingMedium)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                // Date and season
                HStack(spacing: 8) {
                    if let date = game.date {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.caption2)
                            Text(date, format: .dateTime.month(.abbreviated).day().year())
                                .font(.bodySmall)
                                .lineLimit(1)
                        }
                        .foregroundColor(.secondary)
                    }

                    if showSeason, let season = game.season {
                        Text(season.displayName)
                            .font(.labelSmall)
                            .foregroundColor(.white)
                            .badgeSmall()
                            .background(
                                season.isActive ? Color.brandNavy : Color.gray,
                                in: Capsule()
                            )
                    }
                }
            }
        }
    }
}

// Pulsing live badge
struct LiveBadge: View {
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            // Glow
            Capsule()
                .fill(Color.red.opacity(0.3))
                .frame(width: 52, height: 26)
                .scaleEffect(isPulsing ? 1.3 : 1.0)
                .opacity(isPulsing ? 0 : 0.6)

            // Badge
            HStack(spacing: 4) {
                Circle()
                    .fill(.white)
                    .frame(width: 6, height: 6)

                Text("LIVE")
                    .font(.custom("Inter18pt-Bold", size: 11, relativeTo: .caption2))
            }
            .foregroundColor(.white)
            .badgeMedium()
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.red, .red.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .shadow(color: .red.opacity(0.4), radius: 4, x: 0, y: 2)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                isPulsing = true
            }
        }
    }
}
