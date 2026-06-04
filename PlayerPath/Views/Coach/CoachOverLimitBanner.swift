//
//  CoachOverLimitBanner.swift
//  PlayerPath
//
//  Banner shown when a coach has more connected athletes
//  than their current tier allows.
//

import SwiftUI

struct CoachOverLimitBanner: View {
    let connectedCount: Int
    let limit: Int

    private var overBy: Int { max(0, connectedCount - limit) }

    var body: some View {
        Button {
            // Funnel to the full coach paywall via the shared notification,
            // which CoachTabView observes and presents as CoachPaywallView —
            // the same path every other coach upgrade trigger uses.
            NotificationCenter.default.post(name: .showSubscriptionPaywall, object: nil)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(Theme.warning)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Over athlete limit")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    Text("\(connectedCount) connected (\(overBy) over your plan's limit of \(limit)). Upgrade to add more.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Theme.warning.opacity(0.1))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}
