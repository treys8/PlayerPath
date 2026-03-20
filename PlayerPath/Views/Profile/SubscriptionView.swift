//
//  SubscriptionView.swift
//  PlayerPath
//
//  Subscription status, features, and upgrade prompts.
//

import SwiftUI

// MARK: - Subscription View

struct SubscriptionView: View {
    let user: User
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @ObservedObject private var storeManager = StoreKitManager.shared
    @Environment(\.openURL) private var openURL
    @State private var showingPaywall = false

    var body: some View {
        List {
            if authManager.currentTier >= .plus {
                tierActiveSection
                tierFeaturesSection
                managementSection
            } else {
                upgradeBenefitsSection
                pricingSection
            }
        }
        .navigationTitle("Subscription")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPaywall) {
            ImprovedPaywallView(user: user)
        }
    }

    private var tierActiveSection: some View {
        Section {
            HStack {
                Image(systemName: "crown.fill")
                    .foregroundColor(.yellow)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(authManager.currentTier.displayName) Plan")
                        .font(.headline)
                        .fontWeight(.bold)
                    Text(storeManager.isInBillingRetryPeriod
                         ? "There's an issue with your payment."
                         : "Thank you for your support!")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if storeManager.isInBillingRetryPeriod {
                    Text("Payment Issue")
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .accessibilityLabel("Payment Issue")
                } else {
                    Text("Active")
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .accessibilityLabel("Subscription Active")
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var tierFeaturesSection: some View {
        Section("Your \(authManager.currentTier.displayName) Features") {
            SubscriptionFeatureRow(icon: "person.2.fill", title: "\(authManager.currentTier.athleteLimit) Athlete\(authManager.currentTier.athleteLimit == 1 ? "" : "s")", description: "Track up to \(authManager.currentTier.athleteLimit) athlete\(authManager.currentTier.athleteLimit == 1 ? "" : "s")")
            SubscriptionFeatureRow(icon: "internaldrive.fill", title: "\(authManager.currentTier.storageLimitGB) GB Storage", description: "Cloud backup and sync")
            SubscriptionFeatureRow(icon: "square.and.arrow.up", title: "Export Reports", description: "CSV and PDF statistics export")
            SubscriptionFeatureRow(icon: "star.fill", title: "Auto Highlights", description: "Automatically generated highlight reels")
            if authManager.currentTier == .pro {
                SubscriptionFeatureRow(icon: "person.badge.shield.checkmark.fill", title: "Coach Sharing", description: "Share videos and get coach feedback")
            }
        }
    }

    private var managementSection: some View {
        Section("Manage Subscription") {
            Button("Manage in App Store") {
                // Open App Store subscription management
                if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                    openURL(url)
                }
            }
            .foregroundColor(.blue)
        }
    }

    private var upgradeBenefitsSection: some View {
        Section {
            VStack(spacing: 16) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.yellow)

                Text("Unlock Plus & Pro")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("More athletes, cloud storage, highlights, and coach sharing. See full plan details and current pricing below.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    private var pricingSection: some View {
        Section {
            Button(action: { showingPaywall = true }) {
                HStack {
                    Text("View Plans & Pricing")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: "arrow.right")
                        .foregroundColor(.white)
                }
                .padding()
                .background(Color.blue)
                .cornerRadius(12)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
        }
    }
}

struct SubscriptionFeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .font(.title3)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Search Result Helper

struct SearchResult: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let keywords: [String]
    let link: AnyView
}
