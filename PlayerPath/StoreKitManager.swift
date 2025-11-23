//
//  StoreKitManager.swift
//  PlayerPath
//
//  Created by Assistant on 11/22/25.
//  StoreKit 2 manager for in-app purchases and subscriptions
//

import Foundation
import StoreKit
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
    
    private var updateListenerTask: Task<Void, Never>?
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
            
            // Sort by price ascending (monthly will be cheaper than annual)
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
    
    /// Update current subscription status by checking all current entitlements
    func updateSubscriptionStatus() async {
        var latestTransaction: Transaction?
        purchasedProductIDs.removeAll()
        
        // Iterate through ALL current entitlements (not just loaded products)
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            
            // Only check auto-renewable subscriptions
            guard transaction.productType == .autoRenewable else { continue }
            
            // Track this product as purchased
            purchasedProductIDs.insert(transaction.productID)
            
            // Keep the most recent transaction
            if let existing = latestTransaction {
                if transaction.purchaseDate > existing.purchaseDate {
                    latestTransaction = transaction
                }
            } else {
                latestTransaction = transaction
            }
        }
        
        // Update published status based on latest transaction
        if let transaction = latestTransaction {
            expirationDate = transaction.expirationDate
            
            if let expDate = transaction.expirationDate {
                if expDate > Date() {
                    subscriptionStatus = .active
                    print("✅ Subscription active, expires: \(expDate)")
                } else {
                    subscriptionStatus = .expired
                    print("⚠️ Subscription expired on: \(expDate)")
                }
            } else {
                // No expiration date means it's a non-consumable or something else
                subscriptionStatus = .notSubscribed
            }
            
            // Check for revocation
            if transaction.revocationDate != nil {
                subscriptionStatus = .expired
                print("⚠️ Subscription was revoked")
            }
        } else {
            subscriptionStatus = .notSubscribed
            expirationDate = nil
            print("ℹ️ No active subscription found")
        }
    }
    
    // MARK: - Transaction Listening
    
    /// Listen for transaction updates
    private func listenForTransactions() -> Task<Void, Never> {
        return Task {
            // Iterate through any transactions that don't come from a direct call to purchase()
            for await result in Transaction.updates {
                do {
                    let transaction = try checkVerified(result)
                    
                    // Deliver products to the user
                    await updateSubscriptionStatus()
                    
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
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
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
        guard subscriptionStatus == .active else { return false }
        
        // Double-check expiration date for accuracy
        if let expDate = expirationDate {
            return expDate > Date()
        }
        
        return false
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
    /// Note: For production previews, use StoreKit testing configuration files instead
    static func previewMock(isPremium: Bool = false) -> StoreKitManager {
        let manager = StoreKitManager.shared
        // WARNING: This mutates the shared singleton, use only in isolated previews
        if isPremium {
            manager.subscriptionStatus = .active
            manager.expirationDate = Date().addingTimeInterval(30 * 24 * 60 * 60) // 30 days from now
        }
        return manager
    }
}
#endif
