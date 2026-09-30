//
//  CoachPaywallView.swift
//  PlayerPath
//
//  4-column coach paywall: Free / Instructor / Pro Instructor / Academy
//

import SwiftUI
import StoreKit

struct CoachPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.ppAccent) private var ppAccent
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @ObservedObject private var storeManager = StoreKitManager.shared

    @State private var selectedTier: CoachSubscriptionTier = .instructor
    @State private var isAnnual: Bool = true
    @State private var isPurchasing = false
    @State private var showingTerms = false
    @State private var showingPrivacyPolicy = false
    @State private var showingPendingAlert = false
    @State private var showingEmailCopied = false
    @State private var purchaseSucceeded = false

    private let analyticsSource = "coach_paywall"

    private var selectedTierName: String {
        switch selectedTier {
        case .free:          return "coach_free"
        case .instructor:    return "instructor"
        case .proInstructor: return "pro_instructor"
        case .academy:       return "academy"
        }
    }

    /// Comp-aware current coach tier: the higher of the live StoreKit entitlement and
    /// the auth manager's tier (which carries Firestore-granted Academy comps). Used to
    /// prevent re-buying the current plan or silently initiating a downgrade.
    private var effectiveCoachTier: CoachSubscriptionTier {
        max(storeManager.currentCoachTier, authManager.currentCoachTier)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
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
            .background(Theme.surface)
            .navigationTitle("Coach Plans")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .disabled(isPurchasing)
                }
            }
            .sheet(isPresented: $showingTerms) { LegalSheet { TermsOfServiceView() } }
            .sheet(isPresented: $showingPrivacyPolicy) { LegalSheet { PrivacyPolicyView() } }
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
            .toast(isPresenting: $showingEmailCopied, message: "Email Copied")
            .overlay {
                if isPurchasing { LoadingOverlay(message: "Processing purchase...") }
            }
            .task {
                AnalyticsService.shared.trackPaywallShown(source: analyticsSource)
                await storeManager.loadProducts()
            }
            .onDisappear {
                if !purchaseSucceeded {
                    AnalyticsService.shared.trackPaywallDismissed(
                        source: analyticsSource,
                        selectedTier: selectedTierName,
                        isAnnual: isAnnual
                    )
                }
            }
            .onChange(of: storeManager.currentCoachTier) { _, newTier in
                if newTier >= .instructor {
                    purchaseSucceeded = true
                    dismiss()
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 44))
                .foregroundStyle(ppAccent)
                .padding(.top, 8)
                .accessibilityHidden(true)

            Text("Coach more athletes")
                .font(.ppTitle2)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)

            Text("More athlete seats, same simple model — your athletes never pay.")
                .font(.ppSubheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)

            if effectiveCoachTier != .free {
                Text("Current plan: \(effectiveCoachTier.displayName)")
                    .font(.ppCaptionBold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(effectiveCoachTier.color.opacity(0.15), in: Capsule())
                    .foregroundStyle(effectiveCoachTier.color)
            }
        }
    }

    // MARK: - Billing Toggle

    private var billingToggle: some View {
        HStack(spacing: 0) {
            billingPill(title: "Monthly", selected: !isAnnual) { isAnnual = false }
            billingPill(title: coachAnnualSavingsLabel, selected: isAnnual) { isAnnual = true }
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.pillBorder, lineWidth: 0.5))
    }

    private func billingPill(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.ppSubheadline)
                .foregroundStyle(selected ? Color.white : Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(selected ? ppAccent : Color.clear, in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .animation(.easeInOut(duration: 0.2), value: selected)
    }

    private var coachAnnualSavingsLabel: String {
        guard let monthly = storeManager.coachProduct(for: .instructorMonthly),
              let annual = storeManager.coachProduct(for: .instructorAnnual),
              let percent = StoreKitManager.annualSavingsPercent(monthly: monthly, annual: annual) else {
            return "Annual"
        }
        return "Annual (Save \(percent)%)"
    }

    // MARK: - Tier Comparison Table

    private let featureColumnWidth: CGFloat = 90
    private let columnTiers: [CoachSubscriptionTier] = [.free, .instructor, .proInstructor, .academy]

    private var tierComparisonTable: some View {
        VStack(spacing: 0) {
            tierHeaderRow

            coachTableRow(feature: "Price") { priceCell(for: $0) }
            coachTableRow(feature: "Athletes") { tier in
                Text(athleteLimitLabel(for: tier))
                    .font(.ppCaption)
                    .foregroundStyle(Theme.textPrimary)
            }
            coachTableRow(feature: "Per athlete") { perAthleteCell(for: $0) }
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.divider, lineWidth: 0.5))
        .overlay { selectedColumnOutline }
    }

    /// One continuous outline around the selected tier's column, so the selection
    /// reads as a column rather than a stack of separately tinted cells.
    private var selectedColumnOutline: some View {
        GeometryReader { geo in
            let columnWidth = (geo.size.width - featureColumnWidth) / CGFloat(columnTiers.count)
            let index = CGFloat(columnTiers.firstIndex(of: selectedTier) ?? 1)
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(ppAccent, lineWidth: 1.5)
                .frame(width: columnWidth, height: geo.size.height)
                .offset(x: featureColumnWidth + columnWidth * index)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var tierHeaderRow: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: featureColumnWidth, height: 1)
                .accessibilityHidden(true)
            ForEach(columnTiers, id: \.self) { tierHeaderCell($0) }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Free is the reference column, not a purchasable choice, so it renders as a
    /// plain label. Every header carries its column's VoiceOver summary because
    /// the data cells themselves are hidden from accessibility.
    @ViewBuilder
    private func tierHeaderCell(_ tier: CoachSubscriptionTier) -> some View {
        let isSelected = selectedTier == tier
        let label = Text(tier == .proInstructor ? "Pro\nInstructor" : tier.displayName)
            .font(.ppCaptionBold)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .foregroundStyle(isSelected ? Color.white : Theme.textPrimary)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if isSelected {
                    UnevenRoundedRectangle(topLeadingRadius: 10, topTrailingRadius: 10).fill(ppAccent)
                }
            }

        if tier == .free {
            label
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Free plan")
                .accessibilityValue(accessibilitySummary(for: tier))
        } else {
            Button {
                withAnimation(.spring(response: 0.25)) { selectedTier = tier }
            } label: {
                label
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(tier.displayName) plan")
            .accessibilityValue(accessibilitySummary(for: tier))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
    }

    private func coachTableRow<Cell: View>(
        feature: String,
        @ViewBuilder cell: @escaping (CoachSubscriptionTier) -> Cell
    ) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.divider).frame(height: 0.5)
            HStack(spacing: 0) {
                Text(feature)
                    .font(.ppCaption)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.leading, 12)
                    .frame(width: featureColumnWidth, alignment: .leading)
                    .padding(.vertical, 11)

                ForEach(columnTiers, id: \.self) { tier in
                    cell(tier)
                        .padding(.vertical, 11)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(selectedTier == tier ? ppAccent.opacity(0.08) : Color.clear)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func priceCell(for tier: CoachSubscriptionTier) -> some View {
        switch tier {
        case .free:
            Text(zeroPriceLabel)
                .font(.ppCaptionBold)
                .foregroundStyle(Theme.textSecondary)
        case .academy:
            Text("Contact\nUs")
                .font(.ppCaptionBold)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
        case .instructor, .proInstructor:
            if let product = product(for: tier, annual: isAnnual),
               let monthly = effectiveMonthly(for: tier) {
                VStack(spacing: 1) {
                    Text(product.displayPrice)
                        .font(.ppCaptionBold)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(isAnnual ? "\(monthly.amount.formatted(monthly.format))/mo" : "per month")
                        .font(secondaryLineFont)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            } else {
                ProgressView().controlSize(.mini)
            }
        }
    }

    @ViewBuilder
    private func perAthleteCell(for tier: CoachSubscriptionTier) -> some View {
        switch tier {
        case .free:
            Text(zeroPriceLabel)
                .font(.ppCaption)
                .foregroundStyle(Theme.textSecondary)
        case .academy:
            Text("Custom")
                .font(.ppCaption)
                .foregroundStyle(Theme.textPrimary)
        case .instructor, .proInstructor:
            if let perAthlete = perAthleteMonthlyLabel(for: tier) {
                Text("\(perAthlete)/mo")
                    .font(.ppCaption)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                ProgressView().controlSize(.mini)
            }
        }
    }

    /// Scales with Dynamic Type (unlike a fixed-size system font).
    private var secondaryLineFont: Font {
        .custom("Inter18pt-Regular", size: 10, relativeTo: .caption2)
    }

    private func athleteLimitLabel(for tier: CoachSubscriptionTier) -> String {
        tier.athleteLimit == .max ? "∞" : "\(tier.athleteLimit)"
    }

    /// "$0" in the store's currency once any coach product has loaded.
    private var zeroPriceLabel: String {
        guard let format = storeManager.coachProducts.first?.priceFormatStyle else { return "$0" }
        return Decimal(0).formatted(format.precision(.fractionLength(0)))
    }

    private func product(for tier: CoachSubscriptionTier, annual: Bool) -> Product? {
        switch tier {
        case .free, .academy:
            return nil
        case .instructor:
            return storeManager.coachProduct(for: annual ? .instructorAnnual : .instructorMonthly)
        case .proInstructor:
            return storeManager.coachProduct(for: annual ? .proInstructorAnnual : .proInstructorMonthly)
        }
    }

    /// Monthly-equivalent price for a paid tier under the current billing toggle
    /// (annual ÷ 12), in the product's currency format. nil for Free/Academy or
    /// before products load.
    private func effectiveMonthly(for tier: CoachSubscriptionTier) -> (amount: Decimal, format: Decimal.FormatStyle.Currency)? {
        guard let product = product(for: tier, annual: isAnnual) else { return nil }
        return (isAnnual ? product.price / 12 : product.price, product.priceFormatStyle)
    }

    private func perAthleteMonthlyLabel(for tier: CoachSubscriptionTier) -> String? {
        guard let monthly = effectiveMonthly(for: tier), tier.athleteLimit < .max else { return nil }
        return (monthly.amount / Decimal(tier.athleteLimit)).formatted(monthly.format)
    }

    private func accessibilitySummary(for tier: CoachSubscriptionTier) -> String {
        let athletes = tier.athleteLimit == .max ? "unlimited athletes" : "\(tier.athleteLimit) athletes"
        switch tier {
        case .free:
            return "Free, \(athletes)"
        case .academy:
            return "Contact us for pricing, \(athletes)"
        case .instructor, .proInstructor:
            guard let product = product(for: tier, annual: isAnnual),
                  let perAthlete = perAthleteMonthlyLabel(for: tier) else { return athletes }
            return "\(product.displayPrice) per \(isAnnual ? "year" : "month"), \(athletes), \(perAthlete) per athlete per month"
        }
    }

    // MARK: - CTA Button

    private var purchaseButton: some View {
        Group {
            if selectedTier == .academy {
                // Academy: Contact Us CTA
                Button {
                    if let url = URL(string: "mailto:\(AuthConstants.supportEmail)?subject=Academy%20Plan%20Inquiry"),
                       UIApplication.shared.canOpenURL(url) {
                        UIApplication.shared.open(url)
                    } else {
                        UIPasteboard.general.string = AuthConstants.supportEmail
                        showingEmailCopied = true
                    }
                } label: {
                    Text("Contact Us for Academy")
                        .font(.ppHeadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(LinearGradient(colors: [ppAccent, ppAccent.opacity(0.85)],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                                    in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                        .shadow(color: ppAccent.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(.plain)
            } else if storeManager.coachProducts.isEmpty && storeManager.isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading plans...")
                        .font(.ppHeadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.pillBorder, lineWidth: 0.5))
            } else if storeManager.coachProducts.isEmpty {
                Button {
                    Task { await storeManager.loadProducts() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                        Text("Unable to load plans. Tap to retry.")
                            .font(.ppSubheadline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.pillBorder, lineWidth: 0.5))
                    .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    guard !isPurchasing else { return }
                    isPurchasing = true
                    Task { await purchaseSelected() }
                } label: {
                    HStack(spacing: 8) {
                        Text(ctaButtonTitle)
                            .font(.ppHeadline)
                        if isPurchasing { ProgressView().tint(.white) }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(LinearGradient(colors: [ppAccent, ppAccent.opacity(0.85)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
                    .shadow(color: ppAccent.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .disabled(isPurchasing || effectiveCoachTier >= selectedTier)
                .buttonStyle(.plain)
            }
        }
    }

    private var ctaButtonTitle: String {
        if selectedTier != .free && selectedTier != .academy {
            if effectiveCoachTier == selectedTier { return "Current Plan" }
            if effectiveCoachTier > selectedTier { return "Included in \(effectiveCoachTier.displayName)" }
        }
        switch selectedTier {
        case .free:          return "Keep Free" // unreachable: Free isn't selectable
        case .instructor:    return "Get Instructor"
        case .proInstructor: return "Get Pro Instructor"
        case .academy:       return "Contact Us"
        }
    }

    // MARK: - Restore / Terms

    private var restoreButton: some View {
        Button {
            guard !isPurchasing else { return }
            isPurchasing = true
            Task {
                await storeManager.restorePurchases()
                isPurchasing = false
            }
        } label: {
            Text("Restore Purchase")
                .font(.ppSubheadline)
                .foregroundStyle(Theme.textSecondary)
        }
        .disabled(isPurchasing)
    }

    private var termsSection: some View {
        VStack(spacing: 6) {
            if let product = selectedCoachProduct {
                Text("\(product.displayName) — \(product.displayPrice) / \(isAnnual ? "1 year" : "1 month")")
                    .font(.ppCaptionBold)
                    .foregroundStyle(Theme.textPrimary)
            }
            Text("Subscription automatically renews unless cancelled at least 24 hours before the end of the current period. Payment will be charged to your Apple ID account at confirmation of purchase. Manage or cancel anytime in Settings > Subscriptions.")
                .font(.ppCaption)
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 16) {
                Button("Terms of Use (EULA)") { showingTerms = true }
                    .font(.ppCaption).foregroundStyle(ppAccent)
                Button("Privacy Policy") { showingPrivacyPolicy = true }
                    .font(.ppCaption).foregroundStyle(ppAccent)
            }
        }
        .multilineTextAlignment(.center)
    }

    /// nil for Free/Academy — neither has a StoreKit product.
    private var selectedCoachProduct: Product? {
        product(for: selectedTier, annual: isAnnual)
    }

    // MARK: - Purchase Logic

    private func purchaseSelected() async {
        guard selectedTier != .free, selectedTier != .academy else { return }

        // Never purchase the current plan or a lower tier — StoreKit would treat a
        // lower selection as a downgrade. The CTA is disabled in these states; this
        // guards programmatic/edge calls.
        guard effectiveCoachTier < selectedTier else {
            isPurchasing = false
            return
        }

        isPurchasing = true

        let product = selectedCoachProduct

        if let product {
            AnalyticsService.shared.trackPaywallPurchaseAttempted(
                source: analyticsSource,
                productID: product.id,
                tier: selectedTierName,
                isAnnual: isAnnual
            )
            let result = await storeManager.purchase(product)
            switch result {
            case .failed(let error):
                AnalyticsService.shared.trackPaywallPurchaseFailed(
                    source: analyticsSource,
                    productID: product.id,
                    tier: selectedTierName,
                    isAnnual: isAnnual,
                    reason: "failed",
                    errorCode: String((error as NSError).code)
                )
                isPurchasing = false
                return
            case .cancelled:
                AnalyticsService.shared.trackPaywallPurchaseFailed(
                    source: analyticsSource,
                    productID: product.id,
                    tier: selectedTierName,
                    isAnnual: isAnnual,
                    reason: "cancelled"
                )
                isPurchasing = false
                return
            case .pending:
                AnalyticsService.shared.trackPaywallPurchaseFailed(
                    source: analyticsSource,
                    productID: product.id,
                    tier: selectedTierName,
                    isAnnual: isAnnual,
                    reason: "pending"
                )
                isPurchasing = false
                showingPendingAlert = true
                return
            case .success:
                AnalyticsService.shared.trackPaywallPurchaseSucceeded(
                    source: analyticsSource,
                    productID: product.id,
                    tier: selectedTierName,
                    isAnnual: isAnnual,
                    price: product.displayPrice
                )
                // dismiss handled by onChange(of: currentCoachTier)
                break
            case .unknown:
                AnalyticsService.shared.trackPaywallPurchaseFailed(
                    source: analyticsSource,
                    productID: product.id,
                    tier: selectedTierName,
                    isAnnual: isAnnual,
                    reason: "unknown"
                )
                break
            }
        }

        isPurchasing = false
    }
}

// MARK: - Preview

#Preview {
    CoachPaywallView()
        .environmentObject(ComprehensiveAuthManager())
}
