//
//  DrillCardTabView.swift
//  PlayerPath
//
//  Drill Card tab inside CoachVideoPlayerView — list of saved drill cards
//  with a "New Drill Card" entry point.
//

import SwiftUI

struct DrillCardTabView: View {
    let drillCards: [DrillCard]
    let canComment: Bool
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if canComment {
                Button(action: onAdd) {
                    Label("New Drill Card", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.brandNavy.opacity(0.1))
                        .foregroundColor(.brandNavy)
                }
            }

            Divider()

            if drillCards.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "clipboard")
                        .font(.system(size: 50))
                        .foregroundColor(.gray.opacity(0.5))
                    Text("No drill cards yet")
                        .font(.headline)
                    Text("Create a structured review with ratings for specific skills.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(drillCards) { card in
                            DrillCardSummaryView(card: card)
                        }
                    }
                    .padding()
                }
            }
        }
    }
}
