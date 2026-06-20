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

                    Text("After this period, you'll be asked to select which athletes to keep.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                }

                Spacer()

                Text("Upgrade")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.warning)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.white, in: Capsule())
            }
            .padding()
            .background(
                LinearGradient(
                    colors: [Theme.warning, .red.opacity(0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(daysRemaining) day\(daysRemaining == 1 ? "" : "s") to choose athletes. You have \(connectedCount) athletes but your plan allows \(limit). Tap to upgrade.")
        .sheet(isPresented: $showingPaywall) {
            CoachPaywallView()
        }
    }
}

/// Shown on all coach tabs once the grace period expires and the coach is still
/// over their athlete limit (server-set `downgradeUnresolved`). Feedback delivery
/// is blocked server-side until they resolve, but viewing stays available — so
/// this is a persistent banner, not the old hard full-screen blocker. "Choose"
/// opens the (now dismissable) selection sheet; "Upgrade" opens the paywall.
struct CoachDowngradeResolveBanner: View {
    let connectedCount: Int
    let limit: Int
    let onChooseAthletes: () -> Void
    @State private var showingPaywall = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.title3)
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text("Choose athletes to send feedback")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)

                Text("You have \(connectedCount) athletes but your plan allows \(limit). You can still watch videos — choose which to keep (or upgrade) to send feedback again.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }

            Spacer()

            VStack(spacing: 6) {
                Button(action: onChooseAthletes) {
                    Text("Choose")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.warning)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.white, in: Capsule())
                }
                Button { showingPaywall = true } label: {
                    Text("Upgrade")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .underline()
                }
            }
        }
        .padding()
        .background(
            LinearGradient(
                colors: [Theme.warning, .red.opacity(0.85)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Over your athlete limit: \(connectedCount) connected, plan allows \(limit). You can still watch videos but can't send new feedback. Choose athletes to keep or upgrade.")
        .sheet(isPresented: $showingPaywall) {
            CoachPaywallView()
        }
    }
}
