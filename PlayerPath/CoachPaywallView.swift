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
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @StateObject private var storeManager = StoreKitManager.shared

    @State private var selectedTier: CoachSubscriptionTier = .instructor
    @State private var isAnnual: Bool = false
    @State private var isPurchasing = false
    @State private var showingError = false
    @State private var showingTerms = false
    @State private var showingPrivacyPolicy = false

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
            .navigationTitle("Coach Plans")
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
                await storeManager.loadProducts()
            }
            .onChange(of: storeManager.currentCoachTier) { _, newTier in
                if newTier >= .instructor { dismiss() }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "whistle.fill")
                .font(.system(size: 52))
                .foregroundStyle(
                    LinearGradient(colors: [.green, .teal],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .padding(.top, 8)

            Text("Upgrade Your Coaching Plan")
                .font(.title2).fontWeight(.bold)

            Text("Coach more athletes with PlayerPath's pro coaching tools.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Billing Toggle

    private var billingToggle: some View {
        HStack(spacing: 0) {
            billingPill(title: "Monthly", selected: !isAnnual) { isAnnual = false }
            billingPill(title: "Annual (Save 25%)", selected: isAnnual) { isAnnual = true }
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
                .background(selected ? Color.green : Color.clear)
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
                coachFeatureHeaderCell("")
                coachTierHeaderCell("Free", tier: .free)
                coachTierHeaderCell("Instructor", tier: .instructor)
                coachTierHeaderCell("Pro", tier: .proInstructor)
                academyHeaderCell
            }

            Divider()

            // Price row
            coachTableRow(feature: "Price") {
                Text("Free").font(.caption).foregroundStyle(.secondary)
            } instructor: {
                coachPriceLabel(
                    monthly: storeManager.coachProduct(for: .instructorMonthly)?.displayPrice ?? "$9.99",
                    annual: storeManager.coachProduct(for: .instructorAnnual)?.displayPrice ?? "$89.99",
                    forAnnual: isAnnual
                )
            } proInstructor: {
                coachPriceLabel(
                    monthly: storeManager.coachProduct(for: .proInstructorMonthly)?.displayPrice ?? "$19.99",
                    annual: storeManager.coachProduct(for: .proInstructorAnnual)?.displayPrice ?? "$179.99",
                    forAnnual: isAnnual
                )
            } academy: {
                Text("Contact\nUs")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundStyle(.purple)
                    .multilineTextAlignment(.center)
            }

            // Athletes row
            coachTableRow(feature: "Athletes") {
                Text("2").font(.caption)
            } instructor: {
                Text("10").font(.caption)
            } proInstructor: {
                Text("30").font(.caption).foregroundStyle(.green)
            } academy: {
                Text("∞").font(.caption).foregroundStyle(.purple)
            }

            // Video Review row
            coachTableRow(feature: "Video Review") {
                Image(systemName: "checkmark").font(.caption).foregroundStyle(.green)
            } instructor: {
                Image(systemName: "checkmark").font(.caption).foregroundStyle(.green)
            } proInstructor: {
                Image(systemName: "checkmark").font(.caption).foregroundStyle(.green)
            } academy: {
                Image(systemName: "checkmark").font(.caption).foregroundStyle(.green)
            }

            // Annotations row
            coachTableRow(feature: "Annotations") {
                Image(systemName: "checkmark").font(.caption).foregroundStyle(.green)
            } instructor: {
                Image(systemName: "checkmark").font(.caption).foregroundStyle(.green)
            } proInstructor: {
                Image(systemName: "checkmark").font(.caption).foregroundStyle(.green)
            } academy: {
                Image(systemName: "checkmark").font(.caption).foregroundStyle(.green)
            }

            // Priority Support row
            coachTableRow(feature: "Priority Support") {
                Image(systemName: "xmark").font(.caption).foregroundStyle(.secondary)
            } instructor: {
                Image(systemName: "xmark").font(.caption).foregroundStyle(.secondary)
            } proInstructor: {
                Image(systemName: "checkmark").font(.caption).foregroundStyle(.green)
            } academy: {
                Image(systemName: "checkmark").font(.caption).foregroundStyle(.green)
            }
        }
        .background(Color(.secondarySystemBackground))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(.separator), lineWidth: 0.5))
    }

    private func coachTierHeaderCell(_ title: String, tier: CoachSubscriptionTier) -> some View {
        let isSelected = selectedTier == tier
        return Button {
            if tier != .free { withAnimation(.spring(response: 0.25)) { selectedTier = tier } }
        } label: {
            Text(title)
                .font(.caption).fontWeight(.semibold)
                .foregroundStyle(isSelected ? .white : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(isSelected ? Color.green : Color.clear)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }

    private var academyHeaderCell: some View {
        Button {
            withAnimation(.spring(response: 0.25)) { selectedTier = .academy }
        } label: {
            Text("Academy")
                .font(.caption).fontWeight(.semibold)
                .foregroundStyle(selectedTier == .academy ? .white : .purple)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(selectedTier == .academy ? Color.purple : Color.clear)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: selectedTier == .academy)
    }

    private func coachFeatureHeaderCell(_ title: String) -> some View {
        Text(title)
            .frame(width: 90)
            .padding(.vertical, 12)
    }

    private func coachTableRow<Free: View, Instructor: View, ProInstructor: View, Academy: View>(
        feature: String,
        @ViewBuilder free: () -> Free,
        @ViewBuilder instructor: () -> Instructor,
        @ViewBuilder proInstructor: () -> ProInstructor,
        @ViewBuilder academy: () -> Academy
    ) -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 0) {
                Text(feature)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .frame(width: 90, alignment: .leading)
                    .padding(.leading, 12)
                    .padding(.vertical, 11)

                Spacer(minLength: 0)

                coachCellFrame { free() }
                    .background(selectedTier == .free ? Color.green.opacity(0.06) : Color.clear)
                coachCellFrame { instructor() }
                    .background(selectedTier == .instructor ? Color.green.opacity(0.06) : Color.clear)
                coachCellFrame { proInstructor() }
                    .background(selectedTier == .proInstructor ? Color.green.opacity(0.06) : Color.clear)
                coachCellFrame { academy() }
            }
        }
    }

    private func coachCellFrame<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
    }

    private func coachPriceLabel(monthly: String, annual: String, forAnnual: Bool) -> some View {
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
        Group {
            if selectedTier == .academy {
                // Academy: Contact Us CTA
                Button {
                    if let url = URL(string: "mailto:support@playerpath.app?subject=Academy%20Plan%20Inquiry") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Contact Us for Academy")
                        .font(.headline).fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(LinearGradient(colors: [.purple, .purple.opacity(0.8)], startPoint: .leading, endPoint: .trailing))
                        .foregroundStyle(.white)
                        .cornerRadius(14)
                        .shadow(color: Color.purple.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(.plain)
            } else if selectedTier == .free {
                Button {} label: {
                    Text("Keep Free Plan")
                        .font(.headline).fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color(.systemGray5))
                        .foregroundStyle(.secondary)
                        .cornerRadius(14)
                }
                .disabled(true)
            } else {
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
                    .background(LinearGradient(colors: [.green, .green.opacity(0.8)], startPoint: .leading, endPoint: .trailing))
                    .foregroundStyle(.white)
                    .cornerRadius(14)
                    .shadow(color: Color.green.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .disabled(isPurchasing)
                .buttonStyle(.plain)
            }
        }
    }

    private var ctaButtonTitle: String {
        switch selectedTier {
        case .free:          return "Keep Free"
        case .instructor:    return "Get Instructor"
        case .proInstructor: return "Get Pro Instructor"
        case .academy:       return "Contact Us"
        }
    }

    // MARK: - Restore / Terms

    private var restoreButton: some View {
        Button {
            Task {
                isPurchasing = true
                await storeManager.restorePurchases()
                isPurchasing = false
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
                    .font(.caption).foregroundStyle(.green)
                Button("Privacy Policy") { showingPrivacyPolicy = true }
                    .font(.caption).foregroundStyle(.green)
            }
        }
        .multilineTextAlignment(.center)
    }

    // MARK: - Purchase Logic

    private func purchaseSelected() async {
        guard selectedTier != .free, selectedTier != .academy else { return }

        isPurchasing = true

        let product: Product? = {
            switch selectedTier {
            case .instructor:
                return isAnnual
                    ? storeManager.coachProduct(for: .instructorAnnual)
                    : storeManager.coachProduct(for: .instructorMonthly)
            case .proInstructor:
                return isAnnual
                    ? storeManager.coachProduct(for: .proInstructorAnnual)
                    : storeManager.coachProduct(for: .proInstructorMonthly)
            default:
                return nil
            }
        }()

        if let product {
            let result = await storeManager.purchase(product)
            if case .failed = result { isPurchasing = false; showingError = true; return }
            if case .cancelled = result { isPurchasing = false; return }
        }

        isPurchasing = false
    }
}

// MARK: - Preview

#Preview {
    CoachPaywallView()
        .environmentObject(ComprehensiveAuthManager())
}
