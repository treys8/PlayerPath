//
//  StoreKitManager.swift
//  PlayerPath
//
//  StoreKit 2 manager — 3-tier subscription system
//  (Free / Plus / Pro) + Coaching Add-On
//

import Foundation
import StoreKit
import Combine
import os

private let storeLog = Logger(subsystem: "com.playerpath.app", category: "StoreKit")

/// Manages StoreKit 2 operations for in-app purchases
@MainActor
class StoreKitManager: ObservableObject {

    static let shared = StoreKitManager()

    // MARK: - Published Properties

    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIDs: Set<String> = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: StoreError?

    // Tier entitlements
    @Published private(set) var currentTier: SubscriptionTier = .free
    @Published private(set) var tierExpirationDate: Date?
    @Published private(set) var isInBillingRetryPeriod: Bool = false

    // Coach tier entitlements
    @Published private(set) var currentCoachTier: CoachSubscriptionTier = .free
    @Published private(set) var coachTierExpirationDate: Date?

    /// Subscription is past its expiration date but Apple is still honoring it
    /// during the publisher-grace window (only applies if the subscription
    /// group is configured for grace periods in App Store Connect).
    @Published private(set) var isInGracePeriod: Bool = false

    /// When non-nil, the user has a subscription in a recoverable lapse state
    /// (grace period or billing retry). UserMainFlow observes this to present
    /// the win-back sheet on app open. Cleared once the user dismisses the
    /// sheet for this cycle or the subscription resumes.
    @Published private(set) var winBackOpportunity: WinBackOpportunity?

    // MARK: - Private Properties

    private var updateListenerTask: Task<Void, Never>?
    private var productsLoaded = false
    /// Tracks when products first failed to load, enabling a grace period
    /// before forcing a tier downgrade (prevents indefinite retention of expired tiers).
    private var productsUnavailableSince: Date?

    /// True once the first `updateEntitlements()` call completes.
    /// Until this is set, other components should not sync tiers to Firestore
    /// because the resolved tier may be stale (e.g. second device with no
    /// transactions synced yet).
    @Published private(set) var hasResolvedEntitlements = false

    // MARK: - Initialization

    private init() {
        updateListenerTask = listenForTransactions()

        Task {
            await loadProducts()
            await updateEntitlements()
            hasResolvedEntitlements = true
        }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    // MARK: - Product Loading

    /// Load products from App Store
    func loadProducts() async {
        // Allow retry if a previous load succeeded but returned no products
        guard !productsLoaded || products.isEmpty else { return }

        isLoading = true
        error = nil

        do {
            let productIDs = TierSubscriptionProduct.allCases.map { $0.rawValue }
            + CoachSubscriptionProduct.allCases.map { $0.rawValue }
            storeLog.info("Requesting \(productIDs.count) products: \(productIDs.joined(separator: ", "))")
            let storeProducts = try await Product.products(for: productIDs)
            storeLog.info("Loaded \(storeProducts.count) products: \(storeProducts.map(\.id).joined(separator: ", "))")
            products = storeProducts.sorted { $0.price < $1.price }
            // Only mark as loaded once we have actual products
            if !products.isEmpty {
                productsLoaded = true
                productsUnavailableSince = nil
            }
            if storeProducts.isEmpty {
                storeLog.warning("App Store returned 0 products. Check App Store Connect configuration and Paid Apps agreement status.")
                if productsUnavailableSince == nil { productsUnavailableSince = Date() }
            }
        } catch {
            storeLog.error("Product load failed: \(error.localizedDescription)")
            self.error = .productLoadFailed(error)
            if productsUnavailableSince == nil { productsUnavailableSince = Date() }
        }

        isLoading = false
    }

    func clearError() {
        error = nil
    }

    // MARK: - Purchase Management

    /// Purchase a subscription product
    func purchase(_ product: Product) async -> PurchaseResult {
        isLoading = true
        error = nil

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await updateEntitlements()
                await transaction.finish()
                Haptics.success()
                isLoading = false
                return .success

            case .userCancelled:
                isLoading = false
                return .cancelled

            case .pending:
                isLoading = false
                return .pending

            @unknown default:
                isLoading = false
                return .unknown
            }
        } catch {
            self.error = .purchaseFailed(error)
            isLoading = false
            return .failed(error)
        }
    }

    /// Restore previous purchases
    func restorePurchases() async {
        isLoading = true
        error = nil

        do {
            try await AppStore.sync()
            await updateEntitlements()
            Haptics.success()
        } catch {
            self.error = .restoreFailed(error)
        }

        isLoading = false
    }

    // MARK: - Entitlement Resolution

    /// Re-evaluate all current entitlements and update tier.
    /// For each tier, the LATEST expirationDate across all matching verified
    /// transactions wins — the prior implementation picked the first match per
    /// tier, so a coach who upgraded mid-cycle could see the older transaction's
    /// expiration date even though a newer one was active.
    func updateEntitlements() async {
        var resolvedTier: SubscriptionTier = .free
        var resolvedTierExpiration: Date?
        var resolvedCoachTier: CoachSubscriptionTier = .free
        var resolvedCoachTierExpiration: Date?
        var newPurchasedIDs = Set<String>()

        // Per-tier latest expiration, accumulated across all matching transactions.
        var latestPlus: Date?
        var latestPro: Date?
        var latestInstructor: Date?
        var latestProInstructor: Date?

        func keepNewer(_ existing: inout Date?, _ candidate: Date?) {
            guard let candidate else { return }
            if let existing0 = existing {
                if candidate > existing0 { existing = candidate }
            } else {
                existing = candidate
            }
        }

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard transaction.productType == .autoRenewable else { continue }
            guard transaction.revocationDate == nil else { continue }

            let id = transaction.productID
            newPurchasedIDs.insert(id)

            if SubscriptionTier.plusProductIDs.contains(id) {
                if resolvedTier < .plus { resolvedTier = .plus }
                keepNewer(&latestPlus, transaction.expirationDate)
            } else if SubscriptionTier.proProductIDs.contains(id) {
                if resolvedTier < .pro { resolvedTier = .pro }
                keepNewer(&latestPro, transaction.expirationDate)
            } else if CoachSubscriptionTier.instructorProductIDs.contains(id) {
                if resolvedCoachTier < .instructor { resolvedCoachTier = .instructor }
                keepNewer(&latestInstructor, transaction.expirationDate)
            } else if CoachSubscriptionTier.proInstructorProductIDs.contains(id) {
                if resolvedCoachTier < .proInstructor { resolvedCoachTier = .proInstructor }
                keepNewer(&latestProInstructor, transaction.expirationDate)
            }
        }

        // Pick the expiration that matches the resolved tier.
        switch resolvedTier {
        case .pro: resolvedTierExpiration = latestPro
        case .plus: resolvedTierExpiration = latestPlus
        case .free: resolvedTierExpiration = nil
        }
        switch resolvedCoachTier {
        case .proInstructor: resolvedCoachTierExpiration = latestProInstructor
        case .instructor: resolvedCoachTierExpiration = latestInstructor
        case .free, .academy: resolvedCoachTierExpiration = nil
        }

        // Check billing retry BEFORE applying expiration downgrade.
        // Uses status.state == .inBillingRetryPeriod — the correct StoreKit 2 API.
        var resolvedBillingRetry = false
        var resolvedGracePeriod = false
        var lapsingProductID: String?
        var billingRetryCheckSucceeded = false

        if !products.isEmpty {
            billingRetryCheckSucceeded = true
            for product in products {
                guard let subscription = product.subscription else { continue }
                let statuses: [Product.SubscriptionInfo.Status]
                do {
                    statuses = try await subscription.status
                } catch {
                    // If any status query fails (e.g. offline), mark the check as unreliable
                    ErrorHandlerService.shared.handle(error, context: "StoreKitManager.subscriptionStatus", showAlert: false)
                    billingRetryCheckSucceeded = false
                    continue
                }
                // status.status is per-subscription-group, not per-product, so
                // the lapsing product ID must come from status.transaction —
                // the iterated `product` is just the loop variable. Without
                // this, a user on plus.annual whose subscription is in grace
                // surfaces as plus.monthly (whichever product iterates first
                // in the same group).
                for status in statuses {
                    let isLapsing = status.state == .inBillingRetryPeriod || status.state == .inGracePeriod
                    if status.state == .inBillingRetryPeriod { resolvedBillingRetry = true }
                    if status.state == .inGracePeriod { resolvedGracePeriod = true }
                    if isLapsing, lapsingProductID == nil,
                       case .verified(let txn) = status.transaction {
                        lapsingProductID = txn.productID
                    }
                }
            }
        }

        // Only downgrade on expiration if we can confirm Apple is NOT retrying payment.
        // If products aren't loaded or the status query failed, keep the current tier
        // to avoid incorrectly downgrading a user whose payment Apple is still retrying.
        // Grace period: if products have been unavailable for > 1 hour, force downgrade
        // to prevent indefinite retention of expired tiers.
        let graceExpired = productsUnavailableSince.map { Date().timeIntervalSince($0) > 3600 } ?? false

        if let exp = resolvedTierExpiration, exp <= Date() {
            if resolvedBillingRetry {
                // Apple is retrying — keep the tier
            } else if !billingRetryCheckSucceeded && !graceExpired {
                // Can't confirm billing state — keep tier temporarily
                storeLog.warning("Billing retry check failed, keeping tier during grace period")
            } else {
                // Confirmed expired, or grace period exceeded
                resolvedTier = .free
                resolvedTierExpiration = nil
            }
        }

        // Apply same expiration logic to coach tier
        if let exp = resolvedCoachTierExpiration, exp <= Date() {
            if resolvedBillingRetry {
                // Apple is retrying — keep coach tier
            } else if !billingRetryCheckSucceeded && !graceExpired {
                // Can't confirm billing state — keep coach tier temporarily
                storeLog.warning("Billing retry check failed, keeping coach tier during grace period")
            } else {
                resolvedCoachTier = .free
                resolvedCoachTierExpiration = nil
            }
        }

        purchasedProductIDs = newPurchasedIDs
        currentTier = resolvedTier
        tierExpirationDate = resolvedTierExpiration
        isInBillingRetryPeriod = resolvedBillingRetry
        isInGracePeriod = resolvedGracePeriod
        currentCoachTier = resolvedCoachTier
        coachTierExpirationDate = resolvedCoachTierExpiration

        updateWinBackOpportunity(
            productID: lapsingProductID,
            inGracePeriod: resolvedGracePeriod,
            inBillingRetry: resolvedBillingRetry
        )
    }

    /// Compute the current `winBackOpportunity`, suppressing it if the user
    /// has already dismissed the sheet for this product since the last
    /// "subscription-active" observation. The dismiss marker lives in
    /// UserDefaults keyed by productID so it survives relaunch but is reset
    /// when the user resumes a healthy subscription.
    private func updateWinBackOpportunity(productID: String?, inGracePeriod: Bool, inBillingRetry: Bool) {
        guard let productID, inGracePeriod || inBillingRetry else {
            // Healthy state — reset the dismiss flag so a future lapse triggers
            // a fresh prompt.
            if winBackOpportunity != nil {
                winBackOpportunity = nil
            }
            UserDefaults.standard.removeObject(forKey: Self.winBackDismissKey)
            return
        }

        let dismissedProductID = UserDefaults.standard.string(forKey: Self.winBackDismissKey)
        if dismissedProductID == productID {
            winBackOpportunity = nil
            return
        }

        let reason: WinBackOpportunity.Reason = inGracePeriod ? .gracePeriod : .billingRetry
        let isCoachProduct = CoachSubscriptionProduct.allCases.contains { $0.rawValue == productID }
        let tierName: String = {
            if isCoachProduct {
                return currentCoachTier == .proInstructor ? "pro_instructor" : "instructor"
            }
            return currentTier == .pro ? "pro" : "plus"
        }()

        winBackOpportunity = WinBackOpportunity(
            productID: productID,
            tierName: tierName,
            reason: reason
        )
    }

    /// Suppresses the win-back sheet for the supplied product until the user
    /// either renews or transitions to a different SKU.
    func dismissWinBackOpportunity() {
        guard let opportunity = winBackOpportunity else { return }
        UserDefaults.standard.set(opportunity.productID, forKey: Self.winBackDismissKey)
        winBackOpportunity = nil
    }

    private static let winBackDismissKey = "winBack_dismissedProductID"

    // MARK: - Transaction Listening

    private func listenForTransactions() -> Task<Void, Never> {
        return Task {
            for await result in Transaction.updates {
                do {
                    let transaction = try checkVerified(result)
                    await updateEntitlements()
                    await transaction.finish()
                } catch {
                    // Still refresh entitlements so any other valid transactions are picked up
                    await updateEntitlements()
                }
            }
        }
    }

    // MARK: - Verification

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.transactionVerificationFailed
        case .verified(let safe):
            return safe
        }
    }

    // MARK: - Convenience Helpers

    /// True if user has Plus or Pro tier
    var isPlusOrAbove: Bool { currentTier >= .plus }

    /// Bridge for call sites still checking `.isPremium`
    var isPremium: Bool { currentTier >= .plus }

    /// Plus tier products (monthly + annual)
    var plusProducts: [Product] {
        products.filter { SubscriptionTier.plusProductIDs.contains($0.id) }
    }

    /// Pro tier products (monthly + annual)
    var proProducts: [Product] {
        products.filter { SubscriptionTier.proProductIDs.contains($0.id) }
    }

    /// Get product by TierSubscriptionProduct case
    func product(for item: TierSubscriptionProduct) -> Product? {
        products.first { $0.id == item.rawValue }
    }

    // MARK: - Coach Product Helpers

    /// All coach subscription products (Instructor + Pro Instructor, monthly + annual)
    var coachProducts: [Product] {
        let allCoachIDs = CoachSubscriptionProduct.allCases.map { $0.rawValue }
        return products.filter { allCoachIDs.contains($0.id) }
    }

    /// Get product by CoachSubscriptionProduct case
    func coachProduct(for item: CoachSubscriptionProduct) -> Product? {
        products.first { $0.id == item.rawValue }
    }
}

// MARK: - Supporting Types (unchanged)

enum PurchaseResult {
    case success
    case cancelled
    case pending
    case failed(Error)
    case unknown
}

/// Captures a recoverable subscription lapse so the UI can prompt for a
/// cancellation reason and offer recovery paths.
struct WinBackOpportunity: Equatable, Identifiable {
    enum Reason: String {
        case gracePeriod = "grace_period"
        case billingRetry = "billing_retry"
    }
    let productID: String
    let tierName: String
    let reason: Reason

    var id: String { productID }
}

enum StoreError: LocalizedError {
    case productLoadFailed(Error)
    case purchaseFailed(Error)
    case restoreFailed(Error)
    case transactionVerificationFailed

    var errorDescription: String? {
        switch self {
        case .productLoadFailed:
            return "Unable to load subscription plans. Please check your connection and try again."
        case .purchaseFailed:
            return "Purchase could not be completed. You have not been charged. Please try again."
        case .restoreFailed:
            return "Unable to restore purchases. Please check your connection and try again."
        case .transactionVerificationFailed:
            return "Purchase verification failed. If you were charged, your subscription will activate automatically."
        }
    }
}

// MARK: - Preview Helper

#if DEBUG
extension StoreKitManager {
    /// Mutates shared instance for SwiftUI previews — do not use in tests.
    static func previewMock(tier: SubscriptionTier = .free) -> StoreKitManager {
        let manager = StoreKitManager.shared
        manager.currentTier = tier
        return manager
    }
}
#endif
