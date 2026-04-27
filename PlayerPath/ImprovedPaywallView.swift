//
//  ImprovedPaywallView.swift
//  PlayerPath
//
//  3-tier paywall (Free / Plus $5.99 / Pro $12.99)
//

import SwiftUI
import StoreKit
import SwiftData

struct ImprovedPaywallView: View {
    let user: User

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var storeManager = StoreKitManager.shared

    // Selection state
    @State private var selectedTier: SubscriptionTier = .plus
    @State private var isAnnual: Bool = false

    @State private var isPurchasing = false
    @State private var showingTerms = false
    @State private var showingPrivacyPolicy = false
    @State private var showingPendingAlert = false
    @State private var showingNoRestoreAlert = false
    @State private var hasAppeared = false
    @State private var pendingProductID: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    headerSection
                    billingToggle
                    tierComparisonTable
                    purchaseButton
                    restoreButton
                    termsSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
                .allowsHitTesting(!isPurchasing)
            }
            .navigationTitle("Choose Your Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .disabled(isPurchasing)
                }
            }
            .sheet(isPresented: $showingTerms) { TermsOfServiceView() }
            .sheet(isPresented: $showingPrivacyPolicy) { PrivacyPolicyView() }
            .alert("Purchase Failed", isPresented: Binding(
                get: { storeManager.error != nil },
                set: { if !$0 { storeManager.clearError() } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(storeManager.error?.localizedDescription ?? "An unknown error occurred.")
            }
            .alert("Purchase Pending", isPresented: $showingPendingAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your purchase is awaiting approval. Once approved, your subscription will activate automatically.")
            }
            .alert("No Purchase Found", isPresented: $showingNoRestoreAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("We couldn't find a previous subscription for this Apple ID. If you believe this is an error, contact Apple Support.")
            }
            .overlay {
                if isPurchasing { LoadingOverlay(message: "Processing purchase...") }
            }
            .task {
                AnalyticsService.shared.trackPaywallShown(source: "main_app")
                await storeManager.loadProducts()
                // Set after loadProducts so async entitlement resolution during
                // load doesn't immediately dismiss the paywall for existing subscribers
                hasAppeared = true
            }
            .onChange(of: storeManager.currentTier) { _, newTier in
                guard hasAppeared else { return }
                if newTier >= .plus {
                    onPurchaseSucceeded()
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "crown.fill")
                .font(.system(size: 52))
                .foregroundStyle(
                    LinearGradient.premiumAccent
                )
                .padding(.top, 8)

            Text("Unlock PlayerPath")
                .font(.displayMedium)

            Text("Share film with your coach. Track every at-bat.")
                .font(.bodyMedium)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Billing Toggle

    private var billingToggle: some View {
        HStack(spacing: 0) {
            billingPill(title: "Monthly", savingsPercent: nil, selected: !isAnnual) { isAnnual = false }
            billingPill(title: "Annual", savingsPercent: annualSavingsPercent, selected: isAnnual) { isAnnual = true }
        }
        .background(Color(.systemGray5))
        .cornerRadius(10)
    }

    private var annualSavingsPercent: Int? {
        guard let monthly = storeManager.product(for: .plusMonthly),
              let annual = storeManager.product(for: .plusAnnual) else {
            return nil
        }
        let yearlyAtMonthly = monthly.price * 12
        guard yearlyAtMonthly > 0 else { return nil }
        let savings = ((yearlyAtMonthly - annual.price) / yearlyAtMonthly * 100) as NSDecimalNumber
        let percent = savings.intValue
        return percent > 0 ? percent : nil
    }

    private func billingPill(title: String, savingsPercent: Int?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(selected ? .headingSmall : .bodyMedium)
                    .foregroundStyle(selected ? .white : .secondary)
                if let percent = savingsPercent {
                    Text("Save \(percent)%")
                        .font(.custom("Inter18pt-Bold", size: 11, relativeTo: .caption2))
                        .foregroundStyle(selected ? .white : .green)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(selected ? Color.brandNavy : Color.clear)
            .cornerRadius(9)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(savingsPercent.map { "\(title), save \($0) percent" } ?? title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .animation(.easeInOut(duration: 0.2), value: selected)
    }

    // MARK: - Tier Comparison Table

    private var tierComparisonTable: some View {
        VStack(spacing: 0) {
            // Column headers
            HStack(spacing: 0) {
                featureHeaderCell("")
                tierHeaderCell("Free", tier: .free)
                tierHeaderCell("Plus", tier: .plus)
                tierHeaderCell("Pro", tier: .pro)
            }

            Divider()

            // Price row
            tableRow(feature: "Price") {
                Text("Free")
                    .font(.bodySmall).foregroundStyle(.secondary)
            } plus: {
                priceLabel(
                    monthly: storeManager.product(for: .plusMonthly)?.displayPrice,
                    annual: storeManager.product(for: .plusAnnual)?.displayPrice,
                    forAnnual: isAnnual
                )
            } pro: {
                priceLabel(
                    monthly: storeManager.product(for: .proMonthly)?.displayPrice,
                    annual: storeManager.product(for: .proAnnual)?.displayPrice,
                    forAnnual: isAnnual
                )
            }

            tableRow(feature: "Athletes") {
                Text("\(SubscriptionTier.free.athleteLimit)").font(.ppStatSmall).monospacedDigit()
            } plus: {
                Text("\(SubscriptionTier.plus.athleteLimit)").font(.ppStatSmall).monospacedDigit()
            } pro: {
                Text("\(SubscriptionTier.pro.athleteLimit)").font(.ppStatSmall).monospacedDigit().foregroundColor(.brandNavy)
            }

            tableRow(feature: "Storage") {
                Text("\(SubscriptionTier.free.storageLimitGB) GB").font(.bodySmall).foregroundStyle(.secondary)
            } plus: {
                Text("\(SubscriptionTier.plus.storageLimitGB) GB").font(.labelMedium)
            } pro: {
                Text("\(SubscriptionTier.pro.storageLimitGB) GB").font(.labelMedium).foregroundColor(.brandNavy)
            }

            tableRow(feature: "Export Reports") {
                checkIcon(included: false)
            } plus: {
                checkIcon(included: true)
            } pro: {
                checkIcon(included: true)
            }

            tableRow(feature: "Auto Highlights") {
                checkIcon(included: false)
            } plus: {
                checkIcon(included: true)
            } pro: {
                checkIcon(included: true)
            }

            tableRow(feature: "Season Compare") {
                checkIcon(included: false)
            } plus: {
                checkIcon(included: true)
            } pro: {
                checkIcon(included: true)
            }

            tableRow(feature: "Coach Sharing") {
                checkIcon(included: false)
            } plus: {
                checkIcon(included: false)
            } pro: {
                checkIcon(included: true)
            }
        }
        .background(Color(.secondarySystemBackground))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(.separator), lineWidth: 0.5))
    }

    private func tierHeaderCell(_ title: String, tier: SubscriptionTier) -> some View {
        let isSelected = selectedTier == tier
        return Button {
            if tier != .free { withAnimation(.spring(response: 0.25)) { selectedTier = tier } }
        } label: {
            Text(title)
                .font(.headingMedium)
                .foregroundStyle(isSelected ? .white : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(isSelected ? Color.brandNavy : Color.clear)
                .cornerRadius(tier == .plus ? 0 : (tier == .pro ? 9 : 0), corners: tier == .pro ? [.topRight] : [])
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }

    private func featureHeaderCell(_ title: String) -> some View {
        Text(title)
            .frame(width: 110)
            .padding(.vertical, 12)
    }

    private func tableRow<Free: View, Plus: View, Pro: View>(
        feature: String,
        @ViewBuilder free: () -> Free,
        @ViewBuilder plus: () -> Plus,
        @ViewBuilder pro: () -> Pro
    ) -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 0) {
                Text(feature)
                    .font(.bodySmall)
                    .foregroundStyle(.primary)
                    .frame(width: 110, alignment: .leading)
                    .padding(.leading, 12)
                    .padding(.vertical, 11)

                Spacer(minLength: 0)

                cellFrame { free() }
                    .background(selectedTier == .free ? Color.brandNavy.opacity(0.06) : Color.clear)
                cellFrame { plus() }
                    .background(selectedTier == .plus ? Color.brandNavy.opacity(0.06) : Color.clear)
                cellFrame { pro() }
                    .background(selectedTier == .pro ? Color.brandNavy.opacity(0.06) : Color.clear)
            }
        }
    }

    private func checkIcon(included: Bool) -> some View {
        Image(systemName: included ? "checkmark" : "xmark")
            .font(.caption)
            .foregroundStyle(included ? .green : .secondary)
            .accessibilityLabel(included ? "Included" : "Not included")
    }

    private func cellFrame<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
    }

    private func priceLabel(monthly: String?, annual: String?, forAnnual: Bool) -> some View {
        VStack(spacing: 1) {
            if let price = forAnnual ? annual : monthly {
                Text(price)
                    .font(.custom("Inter18pt-SemiBold", size: 12, relativeTo: .caption))
                Text(forAnnual ? "per year" : "per month")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.mini)
            }
        }
    }

    // MARK: - CTA Button

    private var purchaseButton: some View {
        Group {
            if selectedTier == .free {
                Button { dismiss() } label: {
                    Text("Keep Free Plan")
                        .font(.headingMedium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color(.systemGray5))
                        .foregroundStyle(.secondary)
                        .cornerRadius(14)
                }
                .buttonStyle(.plain)
            } else if storeManager.products.isEmpty && storeManager.isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading plans...")
                        .font(.headingMedium)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color(.systemGray5))
                .cornerRadius(14)
            } else if storeManager.products.isEmpty {
                Button {
                    Task { await storeManager.loadProducts() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                        Text("Unable to load plans. Tap to retry.")
                            .font(.labelLarge)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(.systemGray5))
                    .foregroundStyle(.secondary)
                    .cornerRadius(14)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    Task { await purchaseSelected() }
                } label: {
                    HStack(spacing: 8) {
                        Text(ctaButtonTitle)
                            .font(.headingMedium)
                        if isPurchasing { ProgressView().tint(.white) }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(LinearGradient.primaryButton)
                    .foregroundStyle(.white)
                    .cornerRadius(14)
                    .shadow(color: Color.brandNavy.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .disabled(isPurchasing || storeManager.currentTier >= selectedTier)
                .buttonStyle(.plain)
            }
        }
    }

    private var ctaButtonTitle: String {
        if selectedTier != .free && storeManager.currentTier == selectedTier {
            return "Current Plan"
        }
        if selectedTier != .free && storeManager.currentTier > selectedTier {
            return "Included in \(storeManager.currentTier.displayName)"
        }
        switch selectedTier {
        case .free: return "Keep Free"
        case .plus: return "Get Plus"
        case .pro:  return "Get Pro"
        }
    }

    // MARK: - Restore / Terms

    private var restoreButton: some View {
        Button {
            Task {
                isPurchasing = true
                await storeManager.restorePurchases()
                isPurchasing = false
                if storeManager.currentTier == .free && storeManager.error == nil {
                    showingNoRestoreAlert = true
                }
            }
        } label: {
            Text("Restore Purchase")
                .font(.bodyMedium)
                .foregroundStyle(.secondary)
        }
        .disabled(isPurchasing)
    }

    private var termsSection: some View {
        VStack(spacing: 6) {
            if selectedTier != .free, let product = selectedProduct {
                Text("\(product.displayName) — \(product.displayPrice) / \(isAnnual ? "1 year" : "1 month")")
                    .font(.labelMedium)
                    .foregroundStyle(.primary)
            }
            Text("Subscription automatically renews unless cancelled at least 24 hours before the end of the current period. Payment will be charged to your Apple ID account at confirmation of purchase. Manage or cancel anytime in Settings > Subscriptions.")
                .font(.bodySmall)
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Button("Terms of Use (EULA)") { showingTerms = true }
                    .font(.bodySmall).foregroundColor(.brandNavy)
                Button("Privacy Policy") { showingPrivacyPolicy = true }
                    .font(.bodySmall).foregroundColor(.brandNavy)
            }
        }
        .multilineTextAlignment(.center)
    }

    private var selectedProduct: Product? {
        switch selectedTier {
        case .free: return nil
        case .plus:
            return isAnnual
                ? storeManager.product(for: .plusAnnual)
                : storeManager.product(for: .plusMonthly)
        case .pro:
            return isAnnual
                ? storeManager.product(for: .proAnnual)
                : storeManager.product(for: .proMonthly)
        }
    }

    // MARK: - Purchase Logic

    private func purchaseSelected() async {
        guard selectedTier != .free else { return }

        isPurchasing = true

        // Determine which tier product to purchase
        if storeManager.currentTier < selectedTier {
            let tierProduct: Product? = {
                if selectedTier == .plus {
                    return isAnnual
                        ? storeManager.product(for: .plusAnnual)
                        : storeManager.product(for: .plusMonthly)
                } else {
                    return isAnnual
                        ? storeManager.product(for: .proAnnual)
                        : storeManager.product(for: .proMonthly)
                }
            }()

            if let product = tierProduct {
                pendingProductID = product.id
                let result = await storeManager.purchase(product)
                switch result {
                case .failed:
                    isPurchasing = false
                    return
                case .cancelled:
                    isPurchasing = false
                    return
                case .pending:
                    isPurchasing = false
                    showingPendingAlert = true
                    return
                case .success:
                    break
                case .unknown:
                    break
                }
            } else {
                // Product not loaded — button should be disabled, but guard just in case
                isPurchasing = false
                return
            }
        }

        isPurchasing = false
    }

    private func onPurchaseSucceeded() {
        // Use the product ID captured at purchase time (not current UI state,
        // which the user may have toggled while the StoreKit sheet was up)
        let purchasedProduct: Product? = {
            if let id = pendingProductID {
                return storeManager.products.first(where: { $0.id == id })
            }
            // Fallback: infer from current tier + billing toggle
            switch storeManager.currentTier {
            case .plus:
                return isAnnual ? storeManager.product(for: .plusAnnual) : storeManager.product(for: .plusMonthly)
            case .pro:
                return isAnnual ? storeManager.product(for: .proAnnual) : storeManager.product(for: .proMonthly)
            default:
                return nil
            }
        }()

        if let product = purchasedProduct {
            AnalyticsService.shared.trackSubscriptionStarted(
                planType: product.id,
                price: product.displayPrice
            )
        }
        pendingProductID = nil
        // Subscription tier is managed by StoreKit verification + Firestore sync.
        // Do not write tier to local SwiftData — it's the server's source of truth.
        dismiss()
    }
}

// MARK: - RoundedCorner helper

private extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

private struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Preview

#Preview("Free User") {
    ImprovedPaywallView(user: User(username: "test", email: "test@example.com"))
        .environmentObject(ComprehensiveAuthManager())
}

#if DEBUG
#Preview("Plus User") {
    let _ = StoreKitManager.previewMock(tier: .plus)
    ImprovedPaywallView(user: User(username: "test", email: "test@example.com"))
        .environmentObject(ComprehensiveAuthManager())
}
#endif
