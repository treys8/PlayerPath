//
//  DashboardGameCard.swift
//  PlayerPath
//
//  Extracted from MainAppView.swift
//

import SwiftUI

struct DashboardGameCard: View {
    let game: Game
    var onOpen: (() -> Void)? = nil
    var onToggleLive: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            // Game icon indicator
            Image(systemName: "baseball.fill")
                .font(.title3)
                .foregroundColor(game.isLive ? .red : .blue)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(game.isLive ? Color.red.opacity(0.1) : Color.blue.opacity(0.1))
                )

            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if game.isLive {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 6, height: 6)
                                .symbolEffect(.pulse, options: .repeating)
                            Text("LIVE")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.red)
                                .textCase(.uppercase)
                        }
                    }

                    Text("GAME")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                }

                // Opponent name
                Text("vs \(game.opponent.isEmpty ? "Unknown" : game.opponent)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                // Date information
                if let date = game.date {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(date, format: .dateTime.month(.abbreviated).day())
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Date TBD")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(game.isLive ? Color.red.opacity(0.05) : Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(game.isLive ? Color.red.opacity(0.3) : Color(.systemGray5), lineWidth: game.isLive ? 1.5 : 1)
        )
        .contextMenu {
            Button {
                Haptics.light()
                onOpen?()
            } label: {
                Label("Open", systemImage: "arrow.right.circle")
                    .accessibilityLabel("Open game")
            }
            Button {
                toggleHapticThen(onToggleLive)
            } label: {
                Label(game.isLive ? "End Live" : "Mark Live", systemImage: game.isLive ? "stop.circle" : "record.circle")
                    .accessibilityLabel("Toggle live status")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(game.isLive ? "Live game against \(game.opponent)" : "Game against \(game.opponent)")
    }

    private func toggleHapticThen(_ action: (() -> Void)?) { Haptics.light(); action?() }
}
