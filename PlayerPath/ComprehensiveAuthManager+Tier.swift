//
//  ComprehensiveAuthManager+Tier.swift
//  PlayerPath
//
//  Subscription tier sync: StoreKit ↔ Firestore, comped tier overrides.
//

import Combine
import FirebaseAuth
import SwiftData
import os

private let authLog = Logger(subsystem: "com.playerpath.app", category: "Auth")

extension ComprehensiveAuthManager {

    /// Sets up Combine subscribers to keep athlete and coach tiers in sync with StoreKitManager.
    func setupStoreKitSubscribers() {
        // Keep athlete tier in sync with StoreKitManager.
        // If Firestore granted a comped tier (hasAthleteTierOverride), only accept
        // StoreKit updates that are equal or higher — don't downgrade a comp.
        StoreKitManager.shared.$currentTier
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] tier in
                guard let self else { return }
                if self.hasAthleteTierOverride && tier < self.currentTier {
                    // StoreKit resolved lower than the Firestore comp — keep the comp
                    #if DEBUG
                    print("⏭️ StoreKit tier \(tier.rawValue) lower than comped tier \(self.currentTier.rawValue) — keeping comp")
                    #endif
                } else {
                    let hadOverride = self.hasAthleteTierOverride
                    self.currentTier = tier
                    // If StoreKit now meets or exceeds the comped tier, clear the override
                    if hadOverride { self.hasAthleteTierOverride = false }
                }
                // Don't sync until profile has loaded — otherwise a "free" StoreKit
                // tier overwrites a Firestore-comped "pro" before the override is applied.
                guard self.hasLoadedProfile else { return }
                self.syncSubscriptionTierToFirestore()
                // Keep SwiftData User model in sync so user.tier doesn't go stale
                // (e.g. subscription expires while app is backgrounded)
                self.syncTierToLocalUser(self.currentTier)
            }
            .store(in: &storeKitCancellables)

        // Keep coach tier in sync with StoreKitManager (Academy override happens in loadUserProfile)
        StoreKitManager.shared.$currentCoachTier
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] tier in
                guard let self else { return }
                self.currentCoachTier = tier
                guard self.hasLoadedProfile else { return }
                self.syncSubscriptionTierToFirestore()
            }
            .store(in: &storeKitCancellables)
    }

    /// Keeps the SwiftData User.subscriptionTier in sync with the live StoreKit tier.
    /// Without this, the SwiftData field only updates at purchase time in the paywall
    /// and becomes stale when a subscription expires or renews in the background.
    func syncTierToLocalUser(_ tier: SubscriptionTier) {
        guard let localUser, localUser.subscriptionTier != tier.rawValue else { return }
        localUser.subscriptionTier = tier.rawValue
        do {
            try modelContext?.save()
        } catch {
            authLog.error("Failed to sync subscription tier to SwiftData: \(error.localizedDescription)")
        }
        #if DEBUG
        print("🔄 Synced SwiftData User.subscriptionTier to \(tier.rawValue)")
        #endif
    }

    func syncSubscriptionTierToFirestore() {
        guard let userID = currentFirebaseUser?.uid else { return }
        let hasOverride = hasAthleteTierOverride
        Task {
            await retryAsync(maxAttempts: 3) {
                try await FirestoreManager.shared.syncSubscriptionTiersWithThrow(
                    userID: userID,
                    hasAthleteTierOverride: hasOverride
                )
            }
        }
    }

    /// Refreshes the subscription tier from Firestore to pick up changes
    /// made on other devices, via Cloud Function, or admin revocation.
    /// Handles both upgrades (apply comp) and downgrades (revoke comp).
    func refreshTierFromFirestore() async {
        guard let userID = currentFirebaseUser?.uid else { return }
        do {
            guard let profile = try await FirestoreManager.shared.fetchUserProfile(userID: userID) else { return }
            if let tierStr = profile.subscriptionTier,
               let firestoreTier = SubscriptionTier(rawValue: tierStr) {
                if firestoreTier > currentTier {
                    // Firestore has a higher tier (comp granted) — apply it
                    currentTier = firestoreTier
                    hasAthleteTierOverride = true
                } else if firestoreTier < currentTier && hasAthleteTierOverride {
                    // Firestore has a lower tier AND we had an override — comp was revoked.
                    // Fall back to whatever StoreKit resolves.
                    hasAthleteTierOverride = false
                    currentTier = StoreKitManager.shared.currentTier
                }
            }
            if let coachTierStr = profile.coachSubscriptionTier,
               let firestoreCoachTier = CoachSubscriptionTier(rawValue: coachTierStr) {
                if firestoreCoachTier > currentCoachTier {
                    currentCoachTier = firestoreCoachTier
                } else if firestoreCoachTier < currentCoachTier {
                    // Coach comp revoked — fall back to StoreKit
                    currentCoachTier = max(firestoreCoachTier, StoreKitManager.shared.currentCoachTier)
                }
            }
        } catch {
            authLog.warning("Failed to refresh tier from Firestore: \(error.localizedDescription)")
        }
    }
}
