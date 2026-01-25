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
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 32, weight: .medium))
                        .foregroundColor(color)
                        .symbolRenderingMode(.hierarchical)
                        .frame(maxWidth: .infinity, alignment: .center)

                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .padding(.horizontal, 8)

                // Premium badge overlay (only shown for non-premium users)
                if !isPremium {
                    HStack(spacing: 3) {
                        Image(systemName: "crown.fill")
                            .font(.caption2)
                            .fontWeight(.bold)
                        Text("Premium")
                            .font(.caption2)
                            .fontWeight(.bold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        LinearGradient(
                            colors: [.yellow, .orange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(Capsule())
                    .shadow(color: .orange.opacity(0.4), radius: 4, x: 0, y: 2)
                    .offset(x: -6, y: 6)
                }
            }
        }
        .appCard()
        .overlay {
            if !isPremium {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            colors: [.yellow.opacity(0.5), .orange.opacity(0.5)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            }
        }
        .accessibilityElement(children: .combine)
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.96 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .accessibilityLabel(title + (isPremium ? "" : ", Premium feature"))
        .accessibilityHint(isPremium ? "Opens \(title)" : "Requires Premium subscription")
    }
}
