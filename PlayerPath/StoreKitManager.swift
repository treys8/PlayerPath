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

    // MARK: - Private Properties

    private var updateListenerTask: Task<Void, Never>?
    private var productsLoaded = false

    // MARK: - Initialization

    private init() {
        updateListenerTask = listenForTransactions()

        Task {
            await loadProducts()
            await updateEntitlements()
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
            if !products.isEmpty { productsLoaded = true }
            if storeProducts.isEmpty {
                storeLog.warning("App Store returned 0 products. Check App Store Connect configuration and Paid Apps agreement status.")
            }
        } catch {
            storeLog.error("Product load failed: \(error.localizedDescription)")
            self.error = .productLoadFailed(error)
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
    func updateEntitlements() async {
        var resolvedTier: SubscriptionTier = .free
        var resolvedTierExpiration: Date?
        var resolvedCoachTier: CoachSubscriptionTier = .free
        var newPurchasedIDs = Set<String>()

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard transaction.productType == .autoRenewable else { continue }
            guard transaction.revocationDate == nil else { continue }

            let id = transaction.productID
            newPurchasedIDs.insert(id)

            if SubscriptionTier.plusProductIDs.contains(id) {
                if resolvedTier < .plus {
                    resolvedTier = .plus
                    resolvedTierExpiration = transaction.expirationDate
                }
            } else if SubscriptionTier.proProductIDs.contains(id) {
                if resolvedTier < .pro {
                    resolvedTier = .pro
                    resolvedTierExpiration = transaction.expirationDate
                }
            } else if CoachSubscriptionTier.instructorProductIDs.contains(id) {
                if resolvedCoachTier < .instructor {
                    resolvedCoachTier = .instructor
                }
            } else if CoachSubscriptionTier.proInstructorProductIDs.contains(id) {
                if resolvedCoachTier < .proInstructor {
                    resolvedCoachTier = .proInstructor
                }
            }
        }

        // Check billing retry BEFORE applying expiration downgrade.
        // Uses status.state == .inBillingRetryPeriod — the correct StoreKit 2 API.
        var resolvedBillingRetry = false
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
                for status in statuses {
                    if status.state == .inBillingRetryPeriod {
                        resolvedBillingRetry = true
                    }
                }
            }
        }

        // Only downgrade on expiration if we can confirm Apple is NOT retrying payment.
        // If products aren't loaded or the status query failed, keep the current tier
        // to avoid incorrectly downgrading a user whose payment Apple is still retrying.
        if let exp = resolvedTierExpiration, exp <= Date() {
            if resolvedBillingRetry {
                // Apple is retrying — keep the tier
            } else if !billingRetryCheckSucceeded {
                // Can't confirm billing state — keep tier, log warning
            } else {
                // Confirmed: expired and not in billing retry
                resolvedTier = .free
                resolvedTierExpiration = nil
            }
        }

        purchasedProductIDs = newPurchasedIDs
        currentTier = resolvedTier
        tierExpirationDate = resolvedTierExpiration
        isInBillingRetryPeriod = resolvedBillingRetry
        currentCoachTier = resolvedCoachTier

    }

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
