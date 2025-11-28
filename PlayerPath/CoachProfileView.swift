//
//  CoachProfileView.swift
//  PlayerPath
//
//  Created by Assistant on 11/21/25.
//  Profile and settings for coaches
//

import SwiftUI
import StoreKit

struct CoachProfileView: View {
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @ObservedObject private var sharedFolderManager = SharedFolderManager.shared
    @State private var showingSignOutAlert = false
    @State private var showingPaywall = false
    @State private var isSigningOut = false
    
    var body: some View {
        NavigationStack {
            List {
                // Profile Section
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.green)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(authManager.userDisplayName ?? "Coach")
                                .font(.title3)
                                .fontWeight(.semibold)
                            
                            Text(authManager.userEmail ?? "")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.caption)
                                Text("Coach Account")
                                    .font(.caption)
                            }
                            .foregroundColor(.green)
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                // Stats Section
                Section("Activity") {
                    HStack {
                        Label("Athletes", systemImage: "person.3.fill")
                        Spacer()
                        Text("\(uniqueAthleteCount)")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Label("Shared Folders", systemImage: "folder.fill")
                        Spacer()
                        Text("\(sharedFolderManager.coachFolders.count)")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Label("Total Videos", systemImage: "video.fill")
                        Spacer()
                        Text("\(totalVideoCount)")
                            .foregroundColor(.secondary)
                    }
                }
                
                // Account Section
                Section("Account") {
                    // Subscription Management
                    Button(action: {
                        Haptics.light()
                        showingPaywall = true
                    }) {
                        HStack {
                            Label("Subscription", systemImage: "crown")
                            Spacer()
                            Text("Manage")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(.primary)

                    Button(action: {
                        Haptics.warning()
                        showingSignOutAlert = true
                    }) {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                            .foregroundColor(.red)
                    }
                }
                
                // App Info
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersion)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Profile")
            .disabled(isSigningOut)
            .overlay {
                if isSigningOut {
                    LoadingOverlay(message: "Signing out...")
                }
            }
            .sheet(isPresented: $showingPaywall) {
                CoachPaywallView()
            }
            .alert("Sign Out", isPresented: $showingSignOutAlert) {
                Button("Sign Out", role: .destructive) {
                    Task {
                        isSigningOut = true
                        await authManager.signOut()
                        isSigningOut = false
                        Haptics.success()
                    }
                }
                Button("Cancel", role: .cancel) {
                    Haptics.light()
                }
            } message: {
                Text("Are you sure you want to sign out?")
            }
        }
    }

    // MARK: - Computed Properties

    private var uniqueAthleteCount: Int {
        Set(sharedFolderManager.coachFolders.map { $0.ownerAthleteID }).count
    }

    private var totalVideoCount: Int {
        sharedFolderManager.coachFolders.reduce(0) { $0 + ($1.videoCount ?? 0) }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
}

// MARK: - Coach Paywall View

struct CoachPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @Environment(\.openURL) private var openURL
    @ObservedObject private var storeManager = StoreKitManager.shared

    @State private var selectedProduct: Product?
    @State private var showingError = false
    @State private var isPurchasing = false
    @State private var dismissTask: Task<Void, Never>?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Header
                    VStack(spacing: 16) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.yellow)
                        
                        Text("Coach Premium")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("Access premium features to better support your athletes")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.top, 32)
                    
                    // Features
                    VStack(spacing: 20) {
                        CoachFeatureRow(
                            icon: "folder.badge.person.crop",
                            title: "Shared Video Folders",
                            description: "View and comment on athlete video folders"
                        )
                        
                        CoachFeatureRow(
                            icon: "chart.bar.fill",
                            title: "Athlete Analytics",
                            description: "Track performance across all your athletes"
                        )
                        
                        CoachFeatureRow(
                            icon: "person.3.fill",
                            title: "Unlimited Athletes",
                            description: "Work with as many athletes as you need"
                        )
                        
                        CoachFeatureRow(
                            icon: "bubble.left.fill",
                            title: "Video Comments",
                            description: "Provide feedback directly on videos"
                        )
                        
                        CoachFeatureRow(
                            icon: "icloud.fill",
                            title: "Cloud Sync",
                            description: "Access your data across all devices"
                        )
                    }
                    .padding(.horizontal)
                    
                    // Subscription Options
                    if storeManager.products.isEmpty {
                        ProgressView("Loading subscription options...")
                            .padding()
                    } else {
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
                        .padding(.horizontal)
                    }
                    
                    // Purchase Button
                    Button(action: {
                        Haptics.light()
                        Task {
                            await purchaseSelected()
                        }
                    }) {
                        HStack {
                            Text(purchaseButtonText)
                                .font(.headline)
                                .fontWeight(.semibold)

                            if isPurchasing {
                                ProgressView()
                                    .tint(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(selectedProduct == nil || isPurchasing)
                    .padding(.horizontal)
                    .accessibilityLabel(purchaseButtonText)
                    .accessibilityHint("Purchase the selected subscription plan")
                    
                    Button(action: {
                        Haptics.light()
                        Task {
                            await restorePurchases()
                        }
                    }) {
                        Text("Restore Purchase")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .disabled(isPurchasing)
                    .accessibilityLabel("Restore Purchase")
                    .accessibilityHint("Restore previously purchased subscriptions")

                    VStack(spacing: 8) {
                        if let product = selectedProduct, let subscription = product.subscription {
                            Text("Then \(product.displayPrice) per \(subscriptionPeriodText(subscription.subscriptionPeriod.unit))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Text("Cancel anytime • Auto-renews until cancelled")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Upgrade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        Haptics.light()
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showingError, presenting: storeManager.error) { _ in
                Button("OK", role: .cancel) {
                    Haptics.light()
                }
            } message: { error in
                Text(error.localizedDescription)
            }
            .overlay {
                if isPurchasing {
                    LoadingOverlay(message: "Processing purchase...")
                }
            }
            .task {
                // Load products if needed
                if storeManager.products.isEmpty {
                    await storeManager.loadProducts()
                }

                // Select monthly by default
                if selectedProduct == nil {
                    selectedProduct = storeManager.monthlyProduct
                }
            }
            .onChange(of: storeManager.isPremium) { _, isPremium in
                if isPremium {
                    Haptics.success()

                    // Dismiss after short delay with proper cancellation
                    dismissTask?.cancel()
                    dismissTask = Task {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        guard !Task.isCancelled else { return }

                        await MainActor.run {
                            dismiss()
                        }
                    }
                }
            }
            .onDisappear {
                // Cancel dismiss task on view disappear
                dismissTask?.cancel()
            }
        }
    }
    
    private func purchaseSelected() async {
        guard let product = selectedProduct else { return }

        isPurchasing = true

        let result = await storeManager.purchase(product)

        isPurchasing = false

        switch result {
        case .success:
            // Success is handled in onChange with haptic feedback
            break
        case .cancelled:
            // User cancelled, do nothing (no haptic)
            break
        case .pending:
            await MainActor.run {
                Haptics.light()
            }
            showingError = true
        case .failed, .unknown:
            await MainActor.run {
                Haptics.error()
            }
            showingError = true
        }
    }

    private func restorePurchases() async {
        isPurchasing = true
        await storeManager.restorePurchases()
        isPurchasing = false

        await MainActor.run {
            if storeManager.isPremium {
                Haptics.success()
            } else {
                Haptics.light()
            }
        }
    }

    // MARK: - Helper Methods

    private var purchaseButtonText: String {
        guard let product = selectedProduct,
              let subscription = product.subscription,
              let introOffer = subscription.introductoryOffer else {
            return "Subscribe Now"
        }

        // Check if it's a free trial
        if introOffer.price == 0 {
            let period = introOffer.period
            if period.unit == .day {
                return "Start \(period.value)-Day Free Trial"
            } else if period.unit == .week {
                return "Start \(period.value)-Week Free Trial"
            }
        }

        return "Subscribe Now"
    }

    private func subscriptionPeriodText(_ unit: Product.SubscriptionPeriod.Unit) -> String {
        switch unit {
        case .day: return "day"
        case .week: return "week"
        case .month: return "month"
        case .year: return "year"
        @unknown default: return "period"
        }
    }
}

struct CoachFeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundColor(.green)
                .frame(width: 44, height: 44)
                .background(Color.green.opacity(0.1))
                .cornerRadius(10)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityHint(description)
    }
}

// MARK: - Preview

#Preview {
    CoachProfileView()
        .environmentObject(ComprehensiveAuthManager())
}
