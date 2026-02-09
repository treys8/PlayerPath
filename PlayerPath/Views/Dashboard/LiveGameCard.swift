//
//  LiveGameCard.swift
//  PlayerPath
//
//  Extracted from MainAppView.swift
//

import SwiftUI

struct LiveGameCard: View {
    let game: Game
    var onEnd: (() -> Void)?

    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 14) {
            // Enhanced pulsing indicator with glow
            ZStack {
                // Outer glow ring
                Circle()
                    .fill(Color.red.opacity(isPulsing ? 0.15 : 0.25))
                    .frame(width: 50, height: 50)
                    .blur(radius: 4)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)

                Circle()
                    .fill(Color.red.opacity(0.2))
                    .frame(width: 44, height: 44)

                Circle()
                    .fill(Color.red.opacity(isPulsing ? 0.1 : 0.35))
                    .frame(width: 36, height: 36)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)

                Image(systemName: "baseball.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.red)
                    .symbolRenderingMode(.hierarchical)
            }
            .onAppear { isPulsing = true }

            // Game info
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    // Animated LIVE badge
                    HStack(spacing: 3) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 6, height: 6)
                            .opacity(isPulsing ? 0.5 : 1.0)

                        Text("LIVE")
                            .font(.caption2)
                            .fontWeight(.black)
                            .foregroundColor(.red)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color.red.opacity(0.12))
                    )

                    Text("GAME")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }

                Text("vs \(game.opponent.isEmpty ? "Unknown" : game.opponent)")
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                // Show stats if available
                if let stats = game.gameStats, stats.atBats > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "chart.bar.fill")
                            .font(.caption2)
                        Text("\(stats.hits)-\(stats.atBats)")
                            .font(.caption)
                            .monospacedDigit()
                    }
                    .foregroundColor(.secondary)
                } else if let date = game.date {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .font(.caption2)
                        Text(date, format: .dateTime.hour().minute())
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
            }

            Spacer()

            VStack(spacing: 8) {
                // End button with gradient
                Button {
                    Haptics.medium()
                    onEnd?()
                } label: {
                    Text("End")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            LinearGradient(
                                colors: [.red, .red.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(Capsule())
                        .shadow(color: .red.opacity(0.3), radius: 4, x: 0, y: 2)
                }
                .buttonStyle(.borderless)

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [Color.red.opacity(0.1), Color.red.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.red.opacity(0.4), lineWidth: 2)
        )
        .shadow(color: .red.opacity(0.15), radius: 8, x: 0, y: 4)
    }
}
