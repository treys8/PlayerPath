//
//  EmptyStatisticsView.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//
//  Visual overhaul — the batting-line empty state. Shown both when there are
//  no statistics at all and when stats exist but at-bats == 0 (so a zeroed
//  .000/.000/.000 slash line never greets a new user). One centered cream card:
//  serif line, muted subtitle, single accent action. No gradients.
//

import SwiftUI
import TipKit

struct EmptyStatisticsView: View {
    let isQuickEntryEnabled: Bool
    let hasGames: Bool
    let showQuickEntry: () -> Void
    let showGameSelection: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var isAnimating = false
    private let tip = EmptyStatsTip()

    var body: some View {
        VStack(spacing: .spacingLarge) {
            Image(systemName: "chart.bar")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(Theme.accent)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: .spacingSmall) {
                Text("No at-bats yet")
                    .font(.ppTitle2)
                    .foregroundStyle(Theme.textPrimary)

                Text(hasGames
                     ? "Record at-bats to see your batting line."
                     : "Log your first game to see your batting line.")
                    .font(.ppSubheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: .spacingMedium) {
                if isQuickEntryEnabled {
                    primaryButton("Record Live Game Stats", systemImage: "chart.bar.doc.horizontal.fill") {
                        Haptics.medium()
                        showQuickEntry()
                    }
                } else {
                    primaryButton("Go to Games", systemImage: "baseball.fill") {
                        Haptics.medium()
                        NotificationCenter.default.post(name: .switchToGamesTab, object: nil)
                        dismiss()
                    }
                }

                secondaryButton("Add Past Game Statistics", systemImage: "plus.circle") {
                    Haptics.light()
                    showGameSelection()
                }
            }
            .onboardingTip(tip, arrowEdge: .top, also: hasGames)
        }
        .padding(.spacingXLarge)
        .frame(maxWidth: .infinity)
        .ppCard()
        .padding(.horizontal, 18)
        .opacity(isAnimating ? 1 : 0)
        .offset(y: isAnimating ? 0 : 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(Theme.surface)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
                isAnimating = true
            }
        }
    }

    // MARK: - Buttons

    /// Accent capsule — the one orange action.
    private func primaryButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.body)
                Text(title)
                    .font(.ppHeadline)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: 260)
            .padding(.vertical, 14)
            .background(Capsule().fill(Theme.accent))
        }
        .buttonStyle(StatsPremiumButtonStyle())
    }

    /// Outline secondary.
    private func secondaryButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.body)
                Text(title)
                    .font(.ppCallout)
            }
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: 260)
            .padding(.vertical, 12)
            .background(Capsule().strokeBorder(Theme.accent.opacity(0.4), lineWidth: 1.5))
        }
        .buttonStyle(StatsPremiumButtonStyle())
    }
}
