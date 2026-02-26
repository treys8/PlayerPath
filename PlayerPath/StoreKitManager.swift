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
    @Published private(set) var hasCoachingAddOn: Bool = false
    @Published private(set) var tierExpirationDate: Date?
    @Published private(set) var coachingExpirationDate: Date?

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
        guard !productsLoaded else { return }

        isLoading = true
        error = nil

        do {
            let productIDs = TierSubscriptionProduct.allCases.map { $0.rawValue }
            let storeProducts = try await Product.products(for: productIDs)
            products = storeProducts.sorted { $0.price < $1.price }
            productsLoaded = true
            print("✅ Loaded \(products.count) products from App Store")
            for product in products {
                print("  - \(product.displayName): \(product.displayPrice)")
            }
        } catch {
            print("❌ Failed to load products: \(error)")
            self.error = .productLoadFailed(error)
        }

        isLoading = false
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
                print("✅ Purchase successful: \(product.displayName)")
                Haptics.success()
                isLoading = false
                return .success

            case .userCancelled:
                print("ℹ️ User cancelled purchase")
                isLoading = false
                return .cancelled

            case .pending:
                print("⏳ Purchase pending approval")
                isLoading = false
                return .pending

            @unknown default:
                print("⚠️ Unknown purchase result")
                isLoading = false
                return .unknown
            }
        } catch {
            print("❌ Purchase failed: \(error)")
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
            print("✅ Purchases restored successfully")
            Haptics.success()
        } catch {
            print("❌ Failed to restore purchases: \(error)")
            self.error = .restoreFailed(error)
        }

        isLoading = false
    }

    // MARK: - Entitlement Resolution

    /// Re-evaluate all current entitlements and update tier + coaching add-on status.
    func updateEntitlements() async {
        var resolvedTier: SubscriptionTier = .free
        var resolvedCoaching = false
        var resolvedTierExpiration: Date?
        var resolvedCoachingExpiration: Date?
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
            } else if SubscriptionTier.coachingProductIDs.contains(id) {
                resolvedCoaching = true
                resolvedCoachingExpiration = transaction.expirationDate
            }
        }

        // Validate expiration dates
        if let exp = resolvedTierExpiration, exp <= Date() {
            resolvedTier = .free
            resolvedTierExpiration = nil
        }
        if let exp = resolvedCoachingExpiration, exp <= Date() {
            resolvedCoaching = false
            resolvedCoachingExpiration = nil
        }

        purchasedProductIDs = newPurchasedIDs
        currentTier = resolvedTier
        hasCoachingAddOn = resolvedCoaching
        tierExpirationDate = resolvedTierExpiration
        coachingExpirationDate = resolvedCoachingExpiration

        print("✅ Entitlements: tier=\(resolvedTier.displayName), coaching=\(resolvedCoaching)")
    }

    // MARK: - Transaction Listening

    private func listenForTransactions() -> Task<Void, Never> {
        return Task {
            for await result in Transaction.updates {
                do {
                    let transaction = try checkVerified(result)
                    await updateEntitlements()
                    await transaction.finish()
                    print("✅ Transaction update processed: \(transaction.productID)")
                } catch {
                    print("❌ Transaction verification failed: \(error)")
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

    /// True if user is on the Pro tier
    var isProTier: Bool { currentTier == .pro }

    /// True if coaching add-on is active AND user has at least Plus
    var hasFullCoachingAccess: Bool { hasCoachingAddOn && currentTier >= .plus }

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

    /// Coaching add-on products (monthly + annual)
    var coachingProducts: [Product] {
        products.filter { SubscriptionTier.coachingProductIDs.contains($0.id) }
    }

    /// Monthly Plus product
    var plusMonthlyProduct: Product? {
        products.first { $0.id == TierSubscriptionProduct.plusMonthly.rawValue }
    }

    /// Monthly Pro product
    var proMonthlyProduct: Product? {
        products.first { $0.id == TierSubscriptionProduct.proMonthly.rawValue }
    }

    /// Monthly coaching add-on product
    var coachingMonthlyProduct: Product? {
        products.first { $0.id == TierSubscriptionProduct.coachingMonthly.rawValue }
    }

    /// Get product by TierSubscriptionProduct case
    func product(for item: TierSubscriptionProduct) -> Product? {
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
        case .productLoadFailed(let error):
            return "Failed to load products: \(error.localizedDescription)"
        case .purchaseFailed(let error):
            return "Purchase failed: \(error.localizedDescription)"
        case .restoreFailed(let error):
            return "Failed to restore purchases: \(error.localizedDescription)"
        case .transactionVerificationFailed:
            return "Transaction verification failed"
        }
    }
}

// MARK: - Preview Helper

#if DEBUG
extension StoreKitManager {
    /// Mutates shared instance for SwiftUI previews — do not use in tests.
    static func previewMock(tier: SubscriptionTier = .free, coaching: Bool = false) -> StoreKitManager {
        let manager = StoreKitManager.shared
        manager.currentTier = tier
        manager.hasCoachingAddOn = coaching
        return manager
    }
}
#endif
