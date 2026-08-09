//
//  RedeemOfferCodeRow.swift
//  PlayerPath
//
//  "Redeem Code" row — opens Apple's offer-code redemption sheet so a
//  subscription offer code (free months, discounted period) can be applied
//  without leaving the app.
//

import SwiftUI
import StoreKit

/// A Form/List row that presents the App Store offer-code redemption sheet.
///
/// Redemption happens entirely inside Apple's sheet. The resulting transaction
/// arrives on `Transaction.updates`, which `StoreKitManager` already listens
/// for — the explicit `updateEntitlements()` call here just avoids waiting on
/// that listener so the new tier appears immediately. Tier propagation to
/// Firestore is automatic from there (ComprehensiveAuthManager observes
/// `StoreKitManager.$currentTier` / `$currentCoachTier`).
///
/// The sheet is unavailable in the simulator and under Xcode's local StoreKit
/// testing configuration — it only works against the real App Store (sandbox
/// or production), so test it on a device.
struct RedeemOfferCodeRow: View {
    @Environment(\.ppAccent) private var ppAccent

    @State private var isPresentingRedeemSheet = false
    @State private var isRefreshing = false
    @State private var errorMessage = ""
    @State private var showingError = false

    var body: some View {
        Button {
            isPresentingRedeemSheet = true
        } label: {
            HStack {
                Label("Redeem Code", systemImage: "gift")
                Spacer()
                if isRefreshing {
                    ProgressView()
                }
            }
        }
        .foregroundColor(ppAccent)
        .disabled(isRefreshing)
        .offerCodeRedemption(isPresented: $isPresentingRedeemSheet) { result in
            switch result {
            case .success:
                // Success means the sheet presented and closed, NOT that a code
                // was entered — so refresh unconditionally and cheaply.
                refreshEntitlements()
            case .failure(let error):
                ErrorHandlerService.shared.reportError(
                    error,
                    context: "RedeemOfferCodeRow.offerCodeRedemption",
                    message: $errorMessage,
                    isPresented: $showingError,
                    userMessage: "Code redemption isn't available right now. You can also redeem in the App Store app: tap your photo, then Redeem Gift Card or Code."
                )
            }
        }
        .alert("Redeem Code", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private func refreshEntitlements() {
        isRefreshing = true
        Task {
            let store = StoreKitManager.shared
            let before = snapshot(store)
            await store.updateEntitlements()
            isRefreshing = false
            // The sheet reports success on plain cancellation too, so only
            // celebrate when an entitlement actually moved. A code that extends
            // an existing plan shifts the expiration without changing the tier.
            if snapshot(store) != before { Haptics.success() }
        }
    }

    private func snapshot(_ store: StoreKitManager) -> (SubscriptionTier, Date?, CoachSubscriptionTier, Date?) {
        (store.currentTier, store.tierExpirationDate,
         store.currentCoachTier, store.coachTierExpirationDate)
    }
}
