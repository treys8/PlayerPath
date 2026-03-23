//
//  CoachDowngradeGraceBanner.swift
//  PlayerPath
//
//  Banner shown on all coach tabs during the 7-day grace period
//  after a downgrade leaves the coach over their athlete limit.
//

import SwiftUI

struct CoachDowngradeGraceBanner: View {
    let daysRemaining: Int
    let connectedCount: Int
    let limit: Int
    @State private var showingPaywall = false

    var body: some View {
        Button {
            showingPaywall = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.title3)
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(daysRemaining) day\(daysRemaining == 1 ? "" : "s") to choose athletes")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)

                    Text("You have \(connectedCount) athletes but your plan allows \(limit). Upgrade or select which to keep.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                }

                Spacer()

                Text("Upgrade")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.white, in: Capsule())
            }
            .padding()
            .background(
                LinearGradient(
                    colors: [.orange, .red.opacity(0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .sheet(isPresented: $showingPaywall) {
            CoachPaywallView()
        }
    }
}
