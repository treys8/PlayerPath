//
//  ImprovedPaywallView.swift
//  PlayerPath
//
//  3-tier paywall (Free / Plus $3.99 / Pro $7.99) + Coaching Add-On ($7/mo)
//

import SwiftUI
import StoreKit
import SwiftData

struct ImprovedPaywallView: View {
    let user: User

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var storeManager = StoreKitManager.shared

    // Selection state
    @State private var selectedTier: SubscriptionTier = .plus
    @State private var isAnnual: Bool = false

    @State private var isPurchasing = false
    @State private var showingError = false
    @State private var showingTerms = false
    @State private var showingPrivacyPolicy = false
    @State private var hasAppeared = false

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
            }
            .navigationTitle("Choose Your Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showingTerms) { TermsOfServiceView() }
            .sheet(isPresented: $showingPrivacyPolicy) { PrivacyPolicyView() }
            .alert("Error", isPresented: $showingError, presenting: storeManager.error) { _ in
                Button("OK", role: .cancel) {}
            } message: { error in
                Text(error.localizedDescription)
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
                    LinearGradient(colors: [.yellow, .orange],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .padding(.top, 8)

            Text("Unlock PlayerPath")
                .font(.title2).fontWeight(.bold)

            Text("Advanced stats, more athletes, and Pro coach sharing")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Billing Toggle

    private var billingToggle: some View {
        HStack(spacing: 0) {
            billingPill(title: "Monthly", selected: !isAnnual) { isAnnual = false }
            billingPill(title: "Annual (Save ~30%)", selected: isAnnual) { isAnnual = true }
        }
        .background(Color(.systemGray5))
        .cornerRadius(10)
    }

    private func billingPill(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline).fontWeight(selected ? .semibold : .regular)
                .foregroundStyle(selected ? .white : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(selected ? Color.blue : Color.clear)
                .cornerRadius(9)
        }
        .buttonStyle(.plain)
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
                    .font(.caption).foregroundStyle(.secondary)
            } plus: {
                priceLabel(
                    monthly: storeManager.product(for: .plusMonthly)?.displayPrice ?? "—",
                    annual: storeManager.product(for: .plusAnnual)?.displayPrice ?? "—",
                    forAnnual: isAnnual
                )
            } pro: {
                priceLabel(
                    monthly: storeManager.product(for: .proMonthly)?.displayPrice ?? "—",
                    annual: storeManager.product(for: .proAnnual)?.displayPrice ?? "—",
                    forAnnual: isAnnual
                )
            }

            tableRow(feature: "Athletes") {
                Text("1").font(.caption)
            } plus: {
                Text("3").font(.caption)
            } pro: {
                Text("5").font(.caption).foregroundStyle(.blue)
            }

            tableRow(feature: "Storage") {
                Text("1 GB").font(.caption).foregroundStyle(.secondary)
            } plus: {
                Text("5 GB").font(.caption)
            } pro: {
                Text("15 GB").font(.caption).foregroundStyle(.blue)
            }

            tableRow(feature: "Advanced Stats") {
                Image(systemName: "xmark").font(.caption).foregroundStyle(.secondary)
            } plus: {
                Image(systemName: "checkmark").font(.caption).foregroundStyle(.green)
            } pro: {
                Image(systemName: "checkmark").font(.caption).foregroundStyle(.green)
            }

            tableRow(feature: "Export Reports") {
                Image(systemName: "xmark").font(.caption).foregroundStyle(.secondary)
            } plus: {
                Image(systemName: "checkmark").font(.caption).foregroundStyle(.green)
            } pro: {
                Image(systemName: "checkmark").font(.caption).foregroundStyle(.green)
            }

            tableRow(feature: "Auto Highlights") {
                Image(systemName: "xmark").font(.caption).foregroundStyle(.secondary)
            } plus: {
                Image(systemName: "checkmark").font(.caption).foregroundStyle(.green)
            } pro: {
                Image(systemName: "checkmark").font(.caption).foregroundStyle(.green)
            }

            tableRow(feature: "Season Compare") {
                Image(systemName: "xmark").font(.caption).foregroundStyle(.secondary)
            } plus: {
                Image(systemName: "checkmark").font(.caption).foregroundStyle(.green)
            } pro: {
                Image(systemName: "checkmark").font(.caption).foregroundStyle(.green)
            }

            tableRow(feature: "Coach Sharing") {
                Image(systemName: "xmark").font(.caption).foregroundStyle(.secondary)
            } plus: {
                Image(systemName: "xmark").font(.caption).foregroundStyle(.secondary)
            } pro: {
                Image(systemName: "checkmark").font(.caption).foregroundStyle(.green)
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
                .font(.subheadline).fontWeight(.semibold)
                .foregroundStyle(isSelected ? .white : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(isSelected ? Color.blue : Color.clear)
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
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .frame(width: 110, alignment: .leading)
                    .padding(.leading, 12)
                    .padding(.vertical, 11)

                Spacer(minLength: 0)

                cellFrame { free() }
                    .background(selectedTier == .free ? Color.blue.opacity(0.06) : Color.clear)
                cellFrame { plus() }
                    .background(selectedTier == .plus ? Color.blue.opacity(0.06) : Color.clear)
                cellFrame { pro() }
                    .background(selectedTier == .pro ? Color.blue.opacity(0.06) : Color.clear)
            }
        }
    }

    private func cellFrame<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
    }

    private func priceLabel(monthly: String, annual: String, forAnnual: Bool) -> some View {
        VStack(spacing: 1) {
            Text(forAnnual ? annual : monthly)
                .font(.caption).fontWeight(.semibold)
            if forAnnual {
                Text("billed yearly")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - CTA Button

    private var purchaseButton: some View {
        Button {
            Task { await purchaseSelected() }
        } label: {
            HStack(spacing: 8) {
                Text(ctaButtonTitle)
                    .font(.headline).fontWeight(.semibold)
                if isPurchasing { ProgressView().tint(.white) }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(LinearGradient(colors: [.blue, .blue.opacity(0.8)], startPoint: .leading, endPoint: .trailing))
            .foregroundStyle(.white)
            .cornerRadius(14)
            .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .disabled(selectedTier == .free || isPurchasing)
        .opacity(selectedTier == .free ? 0.6 : 1.0)
    }

    private var ctaButtonTitle: String {
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
                if storeManager.error != nil {
                    showingError = true
                }
            }
        } label: {
            Text("Restore Purchase")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .disabled(isPurchasing)
    }

    private var termsSection: some View {
        VStack(spacing: 6) {
            Text("Cancel anytime. Auto-renews until cancelled.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Button("Terms of Service") { showingTerms = true }
                    .font(.caption).foregroundStyle(.blue)
                Button("Privacy Policy") { showingPrivacyPolicy = true }
                    .font(.caption).foregroundStyle(.blue)
            }
        }
        .multilineTextAlignment(.center)
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
                let result = await storeManager.purchase(product)
                if case .failed = result { isPurchasing = false; showingError = true; return }
                if case .cancelled = result { isPurchasing = false; return }
            } else {
                // Product not loaded — inform the user rather than silently failing
                isPurchasing = false
                showingError = true
                return
            }
        }

        isPurchasing = false
    }

    private func onPurchaseSucceeded() {
        // Look up the product the user actually purchased, not an arbitrary first product
        let purchasedProduct: Product? = {
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
        user.subscriptionTier = storeManager.currentTier.rawValue
        try? modelContext.save()
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
