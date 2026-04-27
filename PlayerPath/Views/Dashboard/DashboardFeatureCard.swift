//
//  DashboardFeatureCard.swift
//  PlayerPath
//
//  Extracted from MainAppView.swift
//

import SwiftUI

struct DashboardFeatureCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let action: () -> Void

    @State private var isAnimating = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                // Icon with glow effect
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(color)
                    .symbolRenderingMode(.hierarchical)
                .frame(height: 36)
                .scaleEffect(isAnimating ? 1.0 : 0.8)
                .opacity(isAnimating ? 1.0 : 0)

                VStack(spacing: 4) {
                    Text(title)
                        .font(.headingMedium)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .minimumScaleFactor(0.9)

                    Text(subtitle)
                        .font(.labelSmall)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .opacity(isAnimating ? 1.0 : 0)
                .offset(y: isAnimating ? 0 : 8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            .background(
                ZStack {
                    // Base background
                    RoundedRectangle(cornerRadius: .cornerXLarge, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))

                    // Subtle color tint at top
                    VStack {
                        RoundedRectangle(cornerRadius: .cornerXLarge, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [color.opacity(0.08), .clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                            .frame(height: 60)
                        Spacer()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: .cornerXLarge, style: .continuous))

                    // Top accent line
                    VStack {
                        HStack {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(color)
                                .frame(width: 40, height: 3)
                            Spacer()
                        }
                        .padding(.leading, 16)
                        .padding(.top, 10)
                        Spacer()
                    }
                }
            )
            .shadow(color: color.opacity(0.15), radius: 8, x: 0, y: 4)
            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
            .scaleEffect(isPressed ? 0.96 : 1.0)
        }
        .buttonStyle(FeatureCardButtonStyle(isPressed: $isPressed))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityHint("Opens \(title)")
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(Double.random(in: 0...0.2))) {
                isAnimating = true
            }
        }
    }
}

struct FeatureCardButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, newValue in
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                    isPressed = newValue
                }
            }
    }
}
