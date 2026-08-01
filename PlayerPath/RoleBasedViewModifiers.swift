//
//  RoleBasedViewModifiers.swift
//  PlayerPath
//
//  Created by Assistant on 12/2/25.
//  Subscription tier gating for views
//

import SwiftUI

// MARK: - Tier Gate Modifiers

extension View {
    /// Requires Plus tier or above
    func plusRequired() -> some View {
        modifier(TierGateModifier(requiredTier: .plus))
    }

    /// Requires Pro tier (the top player tier). Used by the recruiting profile.
    func proRequired() -> some View {
        modifier(TierGateModifier(requiredTier: .pro))
    }
}

// MARK: - Tier Gate Modifier

struct TierGateModifier: ViewModifier {
    @EnvironmentObject var authManager: ComprehensiveAuthManager
    let requiredTier: SubscriptionTier
    @State private var showingPaywall = false

    func body(content: Content) -> some View {
        // Take the higher of the auth manager's tier and `effectiveAthleteTier`
        // (max of the live StoreKit entitlement and the comp mirror). The two can
        // disagree during the launch window before the auth manager first publishes
        // a tier, and this modifier REPLACES the whole screen — so a paying user
        // could be shown "Plus Feature" on a screen they own, while the CTAs inside
        // features that gate on `effectiveAthleteTier` worked fine. Never under-gate
        // someone holding a live entitlement.
        if max(authManager.currentTier, SubscriptionGate.effectiveAthleteTier) >= requiredTier {
            content
        } else {
            LockedFeatureView(
                icon: "crown.fill",
                iconColor: .yellow,
                title: "\(requiredTier.displayName) Feature",
                subtitle: "Upgrade to \(requiredTier.displayName) to unlock this feature",
                buttonLabel: "View Plans"
            ) {
                showingPaywall = true
            }
            .sheet(isPresented: $showingPaywall) {
                if let user = authManager.localUser {
                    ImprovedPaywallView(user: user)
                }
            }
        }
    }
}

// MARK: - Locked Feature View

private struct LockedFeatureView: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let buttonLabel: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 56))
                .foregroundStyle(iconColor)
            Text(title)
                .font(.displayMedium)
            Text(subtitle)
                .font(.bodyMedium)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button(buttonLabel, action: action)
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}
