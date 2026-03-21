//
//  CoachLimitPaywallSheet.swift
//  PlayerPath
//
//  Paywall shown when a coach tries to accept an invitation
//  but has reached their tier's athlete limit.
//

import SwiftUI

struct CoachLimitPaywallSheet: View {
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @ObservedObject private var storeManager = StoreKitManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isPurchasing = false

    private var connectedCount: Int { SubscriptionGate.connectedAthleteCount() }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                // Icon
                Image(systemName: "person.3.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)

                // Title
                Text("Athlete Limit Reached")
                    .font(.title2)
                    .fontWeight(.bold)

                // Status
                HStack(spacing: 4) {
                    Text("\(connectedCount)")
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                    Text("athletes connected")
                    Text("·")
                    Text("\(authManager.coachAthleteLimit) allowed")
                        .foregroundColor(.secondary)
                }
                .font(.subheadline)

                Text("Upgrade your coaching plan to connect with more athletes.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer()

                // Plan options
                VStack(spacing: 12) {
                    PlanOptionRow(
                        name: "Instructor",
                        limit: 10,
                        isCurrent: authManager.currentCoachTier == .instructor
                    )
                    PlanOptionRow(
                        name: "Pro Instructor",
                        limit: 30,
                        isCurrent: authManager.currentCoachTier == .proInstructor
                    )
                }
                .padding(.horizontal, 24)

                // Upgrade button
                Button {
                    // Open the existing coach paywall for purchase
                    dismiss()
                    // Post notification to show full paywall
                    NotificationCenter.default.post(name: .showSubscriptionPaywall, object: nil)
                } label: {
                    Text("View Plans")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 24)

                Button("Restore Purchases") {
                    Task { await storeManager.restorePurchases() }
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 16)
            }
            .navigationTitle("Upgrade Required")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Plan Option Row

private struct PlanOptionRow: View {
    let name: String
    let limit: Int
    let isCurrent: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("Up to \(limit) athletes")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if isCurrent {
                Text("Current")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.15))
                    .foregroundColor(.green)
                    .cornerRadius(6)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }
}
