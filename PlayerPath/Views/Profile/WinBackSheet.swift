//
//  WinBackSheet.swift
//  PlayerPath
//
//  Cancellation-reason capture shown on app open after StoreKitManager
//  detects a subscription in grace period or billing retry. Sends the
//  reason to analytics and offers a "Manage Subscription" link so users
//  can fix payment issues or reactivate before the lapse becomes a churn.
//

import SwiftUI
import StoreKit

struct WinBackSheet: View {
    let opportunity: WinBackOpportunity
    let onClose: () -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.ppAccent) private var ppAccent
    @State private var selectedReason: CancellationReason?
    @State private var freeText: String = ""
    @State private var hasLoggedShown = false

    enum CancellationReason: String, CaseIterable, Identifiable {
        case tooExpensive = "too_expensive"
        case notUsing = "not_using_enough"
        case missingFeatures = "missing_features"
        case switching = "switching_apps"
        case technicalIssues = "technical_issues"
        case other = "other"

        var id: String { rawValue }
        var label: String {
            switch self {
            case .tooExpensive:    return "Too expensive"
            case .notUsing:        return "Not using it enough"
            case .missingFeatures: return "Missing features I need"
            case .switching:       return "Switching to another app"
            case .technicalIssues: return "Ran into technical issues"
            case .other:           return "Something else"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerSection
                    reasonSection
                    freeTextSection
                    actionsSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(Theme.surface)
            .navigationTitle("Before You Go")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Not Now") { dismissWithoutSubmitting() }
                }
            }
            .onAppear {
                guard !hasLoggedShown else { return }
                hasLoggedShown = true
                AnalyticsService.shared.trackWinBackShown(
                    productID: opportunity.productID,
                    tierName: opportunity.tierName,
                    reason: opportunity.reason.rawValue
                )
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(opportunity.reason == .billingRetry
                 ? "Your payment didn't go through"
                 : "Your subscription is about to lapse")
                .font(.title3).fontWeight(.semibold)
            Text(opportunity.reason == .billingRetry
                 ? "We weren't able to charge your Apple ID. Update your payment to keep your plan, or let us know why you're leaving."
                 : "We'd love to know what changed — your answer helps us improve PlayerPath for everyone.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var reasonSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Why are you cancelling?")
                .font(.subheadline).fontWeight(.medium)
            VStack(spacing: 0) {
                ForEach(CancellationReason.allCases) { reason in
                    reasonRow(reason)
                    if reason != CancellationReason.allCases.last {
                        Divider().padding(.leading, 44)
                    }
                }
            }
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func reasonRow(_ reason: CancellationReason) -> some View {
        Button {
            selectedReason = reason
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selectedReason == reason ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selectedReason == reason ? ppAccent : Color.secondary)
                Text(reason.label)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var freeTextSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Anything else? (optional)")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Tell us more…", text: $freeText, axis: .vertical)
                .lineLimit(2...5)
                .padding(10)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var actionsSection: some View {
        VStack(spacing: 12) {
            Button {
                submitReason()
                openManageSubscriptions()
            } label: {
                Text(opportunity.reason == .billingRetry
                     ? "Update Payment Method"
                     : "Manage Subscription")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            Button {
                submitReason()
                onClose()
            } label: {
                Text("Submit & Close")
                    .font(.subheadline).fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }
            .disabled(selectedReason == nil)
        }
        .padding(.top, 8)
    }

    private func submitReason() {
        // Log the reason ONLY if the user actually selected one; the primary
        // CTA ("Update Payment Method") is enabled without a reason because
        // recovering payment shouldn't be gated on telling us why. The
        // dismissWinBackOpportunity() call runs either way so the user doesn't
        // return from Manage Subscriptions to a still-presented sheet.
        if let reason = selectedReason {
            let trimmed = freeText.trimmingCharacters(in: .whitespacesAndNewlines)
            AnalyticsService.shared.trackWinBackReasonSubmitted(
                productID: opportunity.productID,
                tierName: opportunity.tierName,
                reason: opportunity.reason.rawValue,
                cancellationReason: reason.rawValue,
                hasFreeText: !trimmed.isEmpty
            )
        }
        StoreKitManager.shared.dismissWinBackOpportunity()
    }

    private func dismissWithoutSubmitting() {
        AnalyticsService.shared.trackWinBackDismissed(
            productID: opportunity.productID,
            tierName: opportunity.tierName,
            reason: opportunity.reason.rawValue
        )
        StoreKitManager.shared.dismissWinBackOpportunity()
        onClose()
    }

    private func openManageSubscriptions() {
        // iOS deep link to subscription management. Falls back gracefully if
        // unavailable (very old iOS or simulator without sandbox account).
        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
            openURL(url)
        }
    }
}
