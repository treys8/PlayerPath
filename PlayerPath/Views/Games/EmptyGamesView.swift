//
//  EmptyGamesView.swift
//  PlayerPath
//
//  Empty state view shown when no games exist.
//

import SwiftUI

struct EmptyGamesView: View {
    let onAddGame: () -> Void

    @State private var isAnimating = false
    @State private var floatOffset: CGFloat = 0

    var body: some View {
        ZStack {
            // Subtle background decoration
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.green.opacity(0.08), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 200
                    )
                )
                .frame(width: 400, height: 400)
                .blur(radius: 60)
                .offset(y: -50)

            VStack(spacing: 28) {
                // Floating icon with glow
                ZStack {
                    // Glow effect
                    Image(systemName: "baseball.diamond.bases")
                        .font(.system(size: 72, weight: .light))
                        .foregroundStyle(.green.opacity(0.3))
                        .blur(radius: 20)

                    Image(systemName: "baseball.diamond.bases")
                        .font(.system(size: 72, weight: .light))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.green, .green.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .symbolRenderingMode(.hierarchical)
                }
                .offset(y: floatOffset)
                .scaleEffect(isAnimating ? 1.0 : 0.8)
                .opacity(isAnimating ? 1.0 : 0.0)

                VStack(spacing: 10) {
                    Text("No Games Yet")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)

                    Text("Create your first game to record\nand track performance")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(2)
                }
                .opacity(isAnimating ? 1.0 : 0.0)
                .offset(y: isAnimating ? 0 : 10)

                Button {
                    Haptics.medium()
                    onAddGame()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.body)
                        Text("Add Game")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: 200)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [.green, .green.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(Capsule())
                    .shadow(color: .green.opacity(0.3), radius: 12, x: 0, y: 6)
                }
                .buttonStyle(PremiumButtonStyle())
                .opacity(isAnimating ? 1.0 : 0.0)
                .offset(y: isAnimating ? 0 : 20)
            }
            .padding(.horizontal, 40)
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                isAnimating = true
            }
            // Floating animation
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                floatOffset = -8
            }
        }
    }
}
