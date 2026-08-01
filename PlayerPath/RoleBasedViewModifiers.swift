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
        // `authManager.currentTier` is the ONLY source here on purpose. It already
        // floors at the live StoreKit entitlement (the StoreKit sink raises it) while
        // being reset on sign-out — whereas `StoreKitManager.currentTier` is the
        // device's Apple-ID entitlement and SURVIVES sign-out. Folding
        // `SubscriptionGate.effectiveAthleteTier` in here (as this briefly did) hands
        // a shared device's next account the previous owner's Plus screens.
        if authManager.currentTier >= requiredTier {
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
