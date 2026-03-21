//
//  DashboardPremiumFeatureCard.swift
//  PlayerPath
//
//  Extracted from MainAppView.swift
//

import SwiftUI

struct DashboardPremiumFeatureCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let isPremium: Bool
    var badgeLabel: String = "PRO"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(color)
                        .symbolRenderingMode(.hierarchical)
                        .frame(maxWidth: .infinity, alignment: .center)

                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .minimumScaleFactor(0.9)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .padding(.horizontal, 8)

                // Premium badge overlay (only shown for non-premium users)
                if !isPremium {
                    Text(badgeLabel)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.brandGold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.brandGold.opacity(0.12))
                        )
                        .offset(x: -8, y: 8)
                }
            }
        }
        .appCard()
        .overlay {
            if !isPremium {
                RoundedRectangle(cornerRadius: .cornerXLarge)
                    .stroke(
                        LinearGradient(
                            colors: [Color.brandGold.opacity(0.5), Color.brandGold.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            }
        }
        .accessibilityElement(children: .combine)
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel(title + (isPremium ? "" : ", Premium feature"))
        .accessibilityHint(isPremium ? "Opens \(title)" : "Requires Premium subscription")
    }
}
