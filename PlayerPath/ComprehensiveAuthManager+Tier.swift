//
//  ComprehensiveAuthManager+Tier.swift
//  PlayerPath
//
//  Subscription tier sync: StoreKit ↔ Firestore, comped tier detection.
//  Comped tier preservation is handled server-side in the syncSubscriptionTier
//  Cloud Function — the client no longer tracks an override flag.
//

import Combine
import FirebaseAuth
import SwiftData
import UIKit
import os

private let authLog = Logger(subsystem: "com.playerpath.app", category: "Auth")

extension ComprehensiveAuthManager {

    /// Sets up Combine subscribers to keep athlete and coach tiers in sync with StoreKitManager.
    func setupStoreKitSubscribers() {
        // Keep athlete tier in sync with StoreKitManager.
        // If StoreKit resolves higher, always accept. If StoreKit resolves lower
        // and the profile has loaded with a higher Firestore tier, don't downgrade
        // locally — the server preserves admin comps, and refreshTierFromFirestore()
        // will reconcile on the next foreground entry.
        StoreKitManager.shared.$currentTier
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] tier in
                guard let self else { return }
                if tier >= self.currentTier {
                    self.currentTier = tier
                } else if !self.hasLoadedProfile {
                    // Profile hasn't loaded yet — no Firestore comp to protect
                    self.currentTier = tier
                }
                // else: StoreKit resolved lower than a Firestore-loaded tier — don't
                // downgrade locally. The server sync will reconcile (it tracks tierSource
                // to distinguish comps from expired subscriptions).
                guard self.hasLoadedProfile, StoreKitManager.shared.hasResolvedEntitlements else { return }
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
                guard self.hasLoadedProfile, StoreKitManager.shared.hasResolvedEntitlements else { return }
                self.syncSubscriptionTierToFirestore()
            }
            .store(in: &storeKitCancellables)

        // When StoreKit finishes its initial entitlement resolution, sync to Firestore
        // if the profile has already loaded. This covers the case where the profile
        // loaded first and the tier subscribers were suppressed by removeDuplicates()
        // (e.g. StoreKit resolved to .free, same as the default).
        StoreKitManager.shared.$hasResolvedEntitlements
            .filter { $0 }
            .first()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.hasLoadedProfile else { return }
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
        Task {
            await retryAsync(maxAttempts: 3) {
                try await FirestoreManager.shared.syncSubscriptionTiersWithThrow(
                    userID: userID
                )
            }
        }
    }

    /// Awaitable version of tier sync — use before operations that depend on Firestore
    /// having the latest subscription tier (e.g. accepting coach invitations after upgrade).
    func syncSubscriptionTierToFirestoreAndWait() async {
        guard let userID = currentFirebaseUser?.uid else { return }
        await retryAsync(maxAttempts: 3) {
            try await FirestoreManager.shared.syncSubscriptionTiersWithThrow(
                userID: userID
            )
        }
    }

    /// Listens for app entering foreground and refreshes the tier from Firestore.
    /// This catches purchases made on other devices that this device's StoreKit
    /// may not have received (e.g. different Apple ID, or App Store propagation delay).
    func setupForegroundTierRefresh() {
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.hasLoadedProfile else { return }
                Task { await self.refreshTierFromFirestore() }
            }
            .store(in: &storeKitCancellables)
    }

    /// Refreshes the subscription tier from Firestore to pick up changes
    /// made on other devices, via Cloud Function, or admin revocation.
    func refreshTierFromFirestore() async {
        guard let userID = currentFirebaseUser?.uid else { return }
        do {
            guard let profile = try await FirestoreManager.shared.fetchUserProfile(userID: userID) else { return }
            if let tierStr = profile.subscriptionTier,
               let firestoreTier = SubscriptionTier(rawValue: tierStr) {
                if firestoreTier > currentTier {
                    // Firestore has a higher tier (comp granted or purchase on another device)
                    currentTier = firestoreTier
                } else if firestoreTier < currentTier {
                    // Firestore has a lower tier — fall back to whatever StoreKit resolves
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
