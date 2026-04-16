//
//  EmptyStatisticsView.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import SwiftUI
import TipKit

struct EmptyStatisticsView: View {
    let isQuickEntryEnabled: Bool
    let showQuickEntry: () -> Void
    let showGameSelection: () -> Void
    let tipsEnabled: Bool
    @Environment(\.dismiss) private var dismiss

    @State private var isAnimating = false
    @State private var floatOffset: CGFloat = 0
    private let tip = EmptyStatsTip()

    var body: some View {
        ZStack {
            // Subtle background decoration
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.brandNavy.opacity(0.08), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 200
                    )
                )
                .frame(width: 300, height: 300)
                .blur(radius: 60)
                .offset(y: -50)

            VStack(spacing: 20) {
                // Floating icon with glow
                ZStack {
                    // Glow effect
                    Image(systemName: "chart.bar")
                        .font(.system(size: 56, weight: .light))
                        .foregroundStyle(Color.brandNavy.opacity(0.3))
                        .blur(radius: 20)

                    Image(systemName: "chart.bar")
                        .font(.system(size: 56, weight: .light))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.brandNavy, Color.brandNavy.opacity(0.6)],
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
                    Text("No Statistics Yet")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)

                    Text("Record plays to start\nbuilding your stats")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(2)
                }
                .opacity(isAnimating ? 1.0 : 0.0)
                .offset(y: isAnimating ? 0 : 10)

                VStack(spacing: 12) {
                    if isQuickEntryEnabled {
                        Button {
                            Haptics.medium()
                            showQuickEntry()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "chart.bar.doc.horizontal.fill")
                                    .font(.body)
                                Text("Record Live Game Stats")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: 240)
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
                        .buttonStyle(StatsPremiumButtonStyle())

                        Button {
                            Haptics.light()
                            showGameSelection()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.body)
                                Text("Add Past Game Statistics")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(Color.brandNavy)
                            .frame(maxWidth: 240)
                            .padding(.vertical, 12)
                            .background(
                                Capsule()
                                    .strokeBorder(Color.brandNavy.opacity(0.3), lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(StatsPremiumButtonStyle())
                    } else {
                        Button {
                            Haptics.medium()
                            NotificationCenter.default.post(name: .switchToGamesTab, object: nil)
                            dismiss()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "baseball.fill")
                                    .font(.body)
                                Text("Go to Games")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: 200)
                            .padding(.vertical, 14)
                            .background(
                                LinearGradient(
                                    colors: [Color.brandNavy, Color.brandNavy.opacity(0.85)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .clipShape(Capsule())
                            .shadow(color: Color.brandNavy.opacity(0.3), radius: 12, x: 0, y: 6)
                        }
                        .buttonStyle(StatsPremiumButtonStyle())

                        Button {
                            Haptics.light()
                            showGameSelection()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.body)
                                Text("Add Past Game Statistics")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(Color.brandNavy)
                            .frame(maxWidth: 240)
                            .padding(.vertical, 12)
                            .background(
                                Capsule()
                                    .strokeBorder(Color.brandNavy.opacity(0.3), lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(StatsPremiumButtonStyle())
                    }
                }
                .opacity(isAnimating ? 1.0 : 0.0)
                .offset(y: isAnimating ? 0 : 20)
                .popoverTipIfEnabled(tip, arrowEdge: .top, enabled: tipsEnabled)
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
