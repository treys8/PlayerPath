//
//  TrialStatusView.swift
//  PlayerPath
//
//  Extracted from MainAppView.swift
//

import SwiftUI

struct TrialStatusView: View {
    let authManager: ComprehensiveAuthManager
    @State private var showingUpgrade = false

    var body: some View {
        if !authManager.isPremiumUser {
            HStack(spacing: 14) {
                statusIcon
                statusText
                Spacer()
                upgradeButton
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(statusBackgroundGradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(statusBorderColor, lineWidth: 1.5)
            )
            .shadow(color: statusShadowColor.opacity(0.2), radius: 8, x: 0, y: 4)
            .animation(.easeInOut(duration: 0.3), value: authManager.trialDaysRemaining)
        }
    }

    private var statusIcon: some View {
        ZStack {
            Circle()
                .fill(statusIconBackground)
                .frame(width: 40, height: 40)

            Image(systemName: authManager.trialDaysRemaining > 0 ? "clock.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(statusIconColor)
                .font(.system(size: 18, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
        }
    }

    private var statusText: some View {
        VStack(alignment: .leading, spacing: 3) {
            if authManager.trialDaysRemaining > 0 {
                Text("Free Trial")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Text("\(authManager.trialDaysRemaining) days remaining")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            } else {
                Text("Trial Expired")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.red)

                Text("Upgrade to continue")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var upgradeButton: some View {
        Button(action: { Haptics.light(); showingUpgrade = true }) {
            Text("Upgrade")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    LinearGradient(
                        colors: [.blue, .blue.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .cornerRadius(10)
                .shadow(color: .blue.opacity(0.3), radius: 4, x: 0, y: 2)
        }
        .sheet(isPresented: $showingUpgrade) {
            NavigationStack {
                VStack(spacing: 24) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.yellow, .orange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .symbolRenderingMode(.hierarchical)

                    Text("Premium Features")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Coming Soon...")
                        .foregroundColor(.secondary)
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showingUpgrade = false
                        }
                    }
                }
            }
        }
    }

    // MARK: - Style Helpers

    private var statusBackgroundGradient: LinearGradient {
        if authManager.trialDaysRemaining > 0 {
            return LinearGradient(
                colors: [Color.orange.opacity(0.12), Color.orange.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [Color.red.opacity(0.12), Color.red.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var statusBorderColor: Color {
        authManager.trialDaysRemaining > 0 ? .orange.opacity(0.3) : .red.opacity(0.3)
    }

    private var statusShadowColor: Color {
        authManager.trialDaysRemaining > 0 ? .orange : .red
    }

    private var statusIconBackground: Color {
        authManager.trialDaysRemaining > 0 ? .orange.opacity(0.15) : .red.opacity(0.15)
    }

    private var statusIconColor: Color {
        authManager.trialDaysRemaining > 0 ? .orange : .red
    }
}
