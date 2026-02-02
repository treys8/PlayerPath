//
//  ImprovedPaywallView.swift
//  PlayerPath
//
//  Created by Assistant on 11/22/25.
//  StoreKit 2 powered paywall for premium subscriptions
//

import SwiftUI
import StoreKit
import SwiftData

/// Modern paywall view with real StoreKit integration
struct ImprovedPaywallView: View {
    let user: User
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var storeManager = StoreKitManager.shared
    
    @State private var selectedProduct: Product?
    @State private var showingError = false
    @State private var isPurchasing = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Header
                    headerSection
                    
                    // Features
                    featuresSection
                    
                    // Subscription Options
                    if storeManager.products.isEmpty {
                        ProgressView("Loading subscription options...")
                            .padding()
                    } else {
                        subscriptionOptionsSection
                    }
                    
                    // Purchase Button
                    purchaseButton
                    
                    // Restore Button
                    restoreButton
                    
                    // Terms
                    termsSection
                }
                .padding()
            }
            .navigationTitle("Upgrade to Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showingError, presenting: storeManager.error) { _ in
                Button("OK", role: .cancel) {}
            } message: { error in
                Text(error.localizedDescription)
            }
            .overlay {
                if isPurchasing {
                    LoadingOverlay(message: "Processing purchase...")
                }
            }
            .task {
                // Track paywall shown analytics
                AnalyticsService.shared.trackPaywallShown(source: "main_app")

                // Load products if needed
                if storeManager.products.isEmpty {
                    await storeManager.loadProducts()
                }

                // Select monthly by default
                if selectedProduct == nil {
                    selectedProduct = storeManager.monthlyProduct ?? storeManager.products.first
                }
            }
            .onChange(of: storeManager.products) { _, products in
                // Auto-select first product when products load
                if selectedProduct == nil, !products.isEmpty {
                    selectedProduct = storeManager.monthlyProduct ?? products.first
                }
            }
            .onChange(of: storeManager.isPremium) { _, isPremium in
                if isPremium {
                    // Track subscription started analytics
                    if let product = selectedProduct {
                        AnalyticsService.shared.trackSubscriptionStarted(
                            planType: product.id,
                            price: product.displayPrice
                        )
                    }

                    // Update user model
                    user.isPremium = true
                    try? modelContext.save()

                    // Dismiss immediately - no delay needed
                    dismiss()
                }
            }
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "crown.fill")
                .font(.system(size: 60))
                .foregroundColor(.yellow)
                .shadow(color: .yellow.opacity(0.3), radius: 10)
            
            Text("Unlock Premium")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Take your baseball journey to the next level")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top)
    }
    
    // MARK: - Features
    
    private var featuresSection: some View {
        VStack(spacing: 16) {
            PremiumFeatureRow(
                icon: "person.3.fill",
                iconColor: .blue,
                title: "Unlimited Athletes",
                description: "Track as many players as you need"
            )
            
            PremiumFeatureRow(
                icon: "chart.line.uptrend.xyaxis",
                iconColor: .green,
                title: "Advanced Statistics",
                description: "Detailed analytics and performance trends"
            )
            
            PremiumFeatureRow(
                icon: "folder.badge.person.crop",
                iconColor: .purple,
                title: "Coach Sharing",
                description: "Share videos with your coaches securely"
            )
            
            PremiumFeatureRow(
                icon: "icloud.and.arrow.up",
                iconColor: .cyan,
                title: "Cloud Backup",
                description: "Never lose your data with automatic sync"
            )
            
            PremiumFeatureRow(
                icon: "video",
                iconColor: .red,
                title: "Unlimited Videos",
                description: "Record and store unlimited video clips"
            )
        }
    }
    
    // MARK: - Subscription Options
    
    private var subscriptionOptionsSection: some View {
        VStack(spacing: 12) {
            Text("Choose Your Plan")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            ForEach(storeManager.products, id: \.id) { product in
                SubscriptionOptionCard(
                    product: product,
                    isSelected: selectedProduct?.id == product.id,
                    onSelect: { selectedProduct = product }
                )
            }
        }
    }
    
    // MARK: - Purchase Button
    
    private var purchaseButton: some View {
        Button(action: {
            Task {
                await purchaseSelected()
            }
        }) {
            HStack {
                Text("Start 7-Day Free Trial")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                if isPurchasing {
                    ProgressView()
                        .tint(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                LinearGradient(
                    colors: [.blue, .blue.opacity(0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .foregroundColor(.white)
            .cornerRadius(12)
            .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .disabled(selectedProduct == nil || isPurchasing || storeManager.products.isEmpty)
    }
    
    // MARK: - Restore Button
    
    private var restoreButton: some View {
        Button(action: {
            Task {
                await restorePurchases()
            }
        }) {
            Text("Restore Purchase")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .disabled(isPurchasing)
    }
    
    // MARK: - Terms
    
    private var termsSection: some View {
        VStack(spacing: 8) {
            if let product = selectedProduct {
                Text("Then \(product.displayPrice) per \(product.subscription?.subscriptionPeriod.unit == .month ? "month" : "year")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text("Cancel anytime. Auto-renews until cancelled.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(spacing: 16) {
                Button("Terms of Service") {
                    // TODO: Open terms URL
                }
                .font(.caption)
                .foregroundColor(.blue)
                
                Button("Privacy Policy") {
                    // TODO: Open privacy URL
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
        }
        .multilineTextAlignment(.center)
    }
    
    // MARK: - Actions
    
    private func purchaseSelected() async {
        guard let product = selectedProduct else { return }

        isPurchasing = true

        let result = await storeManager.purchase(product)

        switch result {
        case .success:
            // Success is handled in onChange
            isPurchasing = false
        case .cancelled:
            // User cancelled, do nothing
            isPurchasing = false
        case .pending:
            // Show pending message
            isPurchasing = false
            showingError = true
        case .failed:
            isPurchasing = false
            showingError = true
        case .unknown:
            isPurchasing = false
            showingError = true
        }
    }
    
    private func restorePurchases() async {
        isPurchasing = true
        await storeManager.restorePurchases()
        isPurchasing = false
    }
}

// MARK: - Subscription Option Card

struct SubscriptionOptionCard: View {
    let product: Product
    let isSelected: Bool
    let onSelect: () -> Void
    
    private var isAnnual: Bool {
        product.subscription?.subscriptionPeriod.unit == .year
    }
    
    private var savingsText: String? {
        guard isAnnual else { return nil }
        return "Save 50%"
    }
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(product.displayName)
                            .font(.headline)
                        
                        if let savings = savingsText {
                            Text(savings)
                                .font(.caption)
                                .fontWeight(.bold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(4)
                        }
                    }
                    
                    Text(product.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(product.displayPrice)
                        .font(.title3)
                        .fontWeight(.bold)
                    
                    if isAnnual, let monthlyEquivalent = calculateMonthlyEquivalent() {
                        Text(monthlyEquivalent)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue.opacity(0.1) : Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func calculateMonthlyEquivalent() -> String? {
        let yearlyPrice = product.price
        let monthlyPrice = yearlyPrice / 12
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = product.priceFormatStyle.locale
        return formatter.string(from: NSDecimalNumber(decimal: monthlyPrice)).map { "\($0)/mo" }
    }
}

// MARK: - Premium Feature Row

struct PremiumFeatureRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(
                    LinearGradient(
                        colors: [iconColor, iconColor.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .cornerRadius(10)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.title3)
        }
    }
}

// MARK: - Preview

#Preview {
    ImprovedPaywallView(user: User(username: "test", email: "test@example.com"))
        .environmentObject(ComprehensiveAuthManager())
}
