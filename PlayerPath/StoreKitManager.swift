//
//  StoreKitManager.swift
//  PlayerPath
//
//  Created by Assistant on 11/22/25.
//  StoreKit 2 manager for in-app purchases and subscriptions
//

import Foundation
import StoreKit
import SwiftUI
import Combine

/// Product identifiers - Must match your App Store Connect configuration
enum SubscriptionProduct: String, CaseIterable {
    case monthlyPremium = "com.playerpath.premium.monthly"
    case annualPremium = "com.playerpath.premium.annual"
    
    var displayName: String {
        switch self {
        case .monthlyPremium: return "Monthly Premium"
        case .annualPremium: return "Annual Premium"
        }
    }
    
    var description: String {
        switch self {
        case .monthlyPremium: return "Premium features billed monthly"
        case .annualPremium: return "Premium features billed annually - Save 50%"
        }
    }
}

/// Manages StoreKit 2 operations for in-app purchases
@MainActor
class StoreKitManager: ObservableObject {
    
    static let shared = StoreKitManager()
    
    // MARK: - Published Properties
    
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIDs: Set<String> = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: StoreError?
    
    // Subscription status
    @Published private(set) var subscriptionStatus: SubscriptionStatus = .notSubscribed
    @Published private(set) var expirationDate: Date?
    
    // MARK: - Private Properties
    
    private var updateListenerTask: Task<Void, Error>?
    private var productsLoaded = false
    
    // MARK: - Initialization
    
    private init() {
        // Start listening for transaction updates
        updateListenerTask = listenForTransactions()
        
        Task {
            await loadProducts()
            await updateSubscriptionStatus()
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
            let productIDs = SubscriptionProduct.allCases.map { $0.rawValue }
            let storeProducts = try await Product.products(for: productIDs)
            
            products = storeProducts.sorted { product1, product2 in
                // Sort by price (monthly first, then annual)
                product1.price < product2.price
            }
            
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
                // Verify the transaction
                let transaction = try checkVerified(verification)
                
                // Update subscription status
                await updateSubscriptionStatus()
                
                // Finish the transaction
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
            await updateSubscriptionStatus()
            print("✅ Purchases restored successfully")
            Haptics.success()
        } catch {
            print("❌ Failed to restore purchases: \(error)")
            self.error = .restoreFailed(error)
        }
        
        isLoading = false
    }
    
    // MARK: - Subscription Status
    
    /// Update current subscription status
    func updateSubscriptionStatus() async {
        var activeSubscription: Product.SubscriptionInfo.Status?
        var latestTransaction: StoreKit.Transaction?
        
        // Check all subscription groups
        for product in products {
            guard let subscription = product.subscription else { continue }
            
            // Get status for this subscription group
            guard let statuses = try? await subscription.status else { continue }
            
            for status in statuses {
                // Check if verified
                guard case .verified(let transaction) = status.transaction else { continue }
                
                // Check if active or in grace period
                if status.state == .subscribed || status.state == .inGracePeriod {
                    // Store this if it's the most recent
                    if let existing = latestTransaction {
                        if transaction.purchaseDate > existing.purchaseDate {
                            latestTransaction = transaction
                            activeSubscription = status
                        }
                    } else {
                        latestTransaction = transaction
                        activeSubscription = status
                    }
                    
                    purchasedProductIDs.insert(transaction.productID)
                }
            }
        }
        
        // Update published status
        if let status = activeSubscription, let transaction = latestTransaction {
            switch status.state {
            case .subscribed:
                subscriptionStatus = .active
            case .inGracePeriod:
                subscriptionStatus = .inGracePeriod
            case .inBillingRetryPeriod:
                subscriptionStatus = .inBillingRetry
            case .revoked:
                subscriptionStatus = .expired
            case .expired:
                subscriptionStatus = .expired
            default:
                subscriptionStatus = .notSubscribed
            }
            
            // Set expiration date from the transaction
            expirationDate = transaction.expirationDate
            
            print("✅ Subscription status: \(subscriptionStatus)")
            if let expDate = expirationDate {
                print("   Expires: \(expDate)")
            }
        } else {
            subscriptionStatus = .notSubscribed
            expirationDate = nil
            purchasedProductIDs.removeAll()
        }
    }
    
    // MARK: - Transaction Listening
    
    /// Listen for transaction updates
    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            // Iterate through any transactions that don't come from a direct call to purchase()
            for await result in StoreKit.Transaction.updates {
                do {
                    let transaction = try self.checkVerified(result)
                    
                    // Deliver products to the user
                    await self.updateSubscriptionStatus()
                    
                    // Always finish a transaction
                    await transaction.finish()
                    
                    print("✅ Transaction update processed: \(transaction.productID)")
                } catch {
                    print("❌ Transaction verification failed: \(error)")
                }
            }
        }
    }
    
    // MARK: - Verification
    
    /// Verify a transaction is valid
    nonisolated private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.transactionVerificationFailed
        case .verified(let safe):
            return safe
        }
    }
    
    // MARK: - Convenience Properties
    
    /// Whether user has an active subscription
    var isPremium: Bool {
        subscriptionStatus == .active || subscriptionStatus == .inGracePeriod
    }
    
    /// Get product by identifier
    func product(for identifier: SubscriptionProduct) -> Product? {
        products.first { $0.id == identifier.rawValue }
    }
    
    /// Get monthly subscription product
    var monthlyProduct: Product? {
        product(for: .monthlyPremium)
    }
    
    /// Get annual subscription product
    var annualProduct: Product? {
        product(for: .annualPremium)
    }
}

// MARK: - Supporting Types

enum SubscriptionStatus: String {
    case notSubscribed = "Not Subscribed"
    case active = "Active"
    case inGracePeriod = "Grace Period"
    case inBillingRetry = "Billing Retry"
    case expired = "Expired"
}

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
    /// Create a mock manager for previews
    static func mock(isPremium: Bool = false) -> StoreKitManager {
        let manager = StoreKitManager.shared
        if isPremium {
            manager.subscriptionStatus = .active
        }
        return manager
    }
}
#endif
