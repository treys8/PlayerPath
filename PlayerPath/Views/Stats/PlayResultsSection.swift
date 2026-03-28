//
//  PlayResultsSection.swift
//  PlayerPath
//
//  Created by Trey Schilling on 3/21/26.
//

import SwiftUI

struct PlayResultsSection: View {
    let statistics: AthleteStatistics

    @State private var isVisible = false

    private var playResults: [PlayResultData] {
        [
            PlayResultData(type: "Singles", count: statistics.singles, color: .green),
            PlayResultData(type: "Doubles", count: statistics.doubles, color: .blue),
            PlayResultData(type: "Triples", count: statistics.triples, color: .orange),
            PlayResultData(type: "Home Runs", count: statistics.homeRuns, color: .gold),
            PlayResultData(type: "Runs", count: statistics.runs, color: .purple),
            PlayResultData(type: "RBIs", count: statistics.rbis, color: .pink),
            PlayResultData(type: "Walks", count: statistics.walks, color: .cyan),
            PlayResultData(type: "Strikeouts", count: statistics.strikeouts, color: .red)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            SectionHeader(title: "Play Results", icon: "baseball")
                .opacity(isVisible ? 1 : 0)
                .offset(y: isVisible ? 0 : 10)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(playResults, id: \.type) { data in
                    PlayResultCard(data: data)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Play results summary")
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.4).delay(0.3)) {
                isVisible = true
            }
        }
    }
}

struct PlayResultData {
    let type: String
    let count: Int
    let color: Color
}

struct PlayResultCard: View {
    let data: PlayResultData

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 6) {
            Text("\(data.count)")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [data.color, data.color.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .scaleEffect(isAnimating ? 1.0 : 0.5)
                .opacity(isAnimating ? 1.0 : 0)

            Text(data.type)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .truncationMode(.tail)
                .minimumScaleFactor(0.8)
        }
        .frame(height: horizontalSizeClass == .regular ? 85 : 70)
        .frame(maxWidth: .infinity)
        .padding(horizontalSizeClass == .regular ? 12 : 8)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: .cornerLarge, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))

                // Subtle color tint at bottom
                RoundedRectangle(cornerRadius: .cornerLarge, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.clear, data.color.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        )
        .shadow(color: data.color.opacity(0.08), radius: 4, x: 0, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(data.type): \(data.count)")
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(Double.random(in: 0...0.2))) {
                isAnimating = true
            }
        }
    }
}
