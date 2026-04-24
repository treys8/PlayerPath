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

    var body: some View {
        HStack(spacing: 0) {
            // Accent bar
            RoundedRectangle(cornerRadius: 2)
                .fill(statusColor)
                .frame(width: 4)
                .padding(.vertical, 4)

            HStack(spacing: 12) {
                GameInfoView(game: game, showSeason: !game.isLive)
                Spacer()
                RightStatusView(game: game)
            }
            .padding(.leading, 12)
            .padding(.trailing, 16)
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
            HStack(spacing: 12) {
                // Stats summary (if available)
                if let stats = game.gameStats, stats.atBats > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(stats.hits)-\(stats.atBats)")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        Text(String(format: ".%03d", Int(Double(stats.hits) / Double(stats.atBats) * 1000)))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                // Status badge
                Group {
                    switch game.displayStatus {
                    case .live:
                        LiveBadge()
                    case .completed:
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.green, .green.opacity(0.7)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    case .scheduled:
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
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
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                // Date and season
                HStack(spacing: 8) {
                    if let date = game.date {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.caption2)
                            Text(date, format: .dateTime.month(.abbreviated).day().year())
                                .font(.caption)
                                .lineLimit(1)
                        }
                        .foregroundColor(.secondary)
                    }

                    if showSeason, let season = game.season {
                        Text(season.displayName)
                            .font(.caption2)
                            .fontWeight(.medium)
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
                    .font(.caption2)
                    .fontWeight(.bold)
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
