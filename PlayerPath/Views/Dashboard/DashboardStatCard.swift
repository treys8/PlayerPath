//
//  DashboardStatCard.swift
//  PlayerPath
//
//  Extracted from MainAppView.swift
//

import SwiftUI

struct DashboardStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(color)
                .symbolRenderingMode(.hierarchical)

            Text(value)
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.primary, .primary.opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .monospacedDigit()
                .contentTransition(.numericText())
                .scaleEffect(isAnimating ? 1.0 : 0.5)
                .opacity(isAnimating ? 1.0 : 0)

            Text(title)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            ZStack {
                // Base background
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))

                // Bottom accent line
                VStack {
                    Spacer()
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(height: 3)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                }
            }
        )
        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
        .accessibilityElement(children: .combine)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.1)) {
                isAnimating = true
            }
        }
    }
}
