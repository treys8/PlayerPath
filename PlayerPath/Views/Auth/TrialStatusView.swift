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
        if authManager.currentTier == .free {
            HStack(spacing: 14) {
                freeStatusIcon
                freeStatusText
                Spacer()
                upgradeButton
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(LinearGradient(
                        colors: [Color.blue.opacity(0.10), Color.blue.opacity(0.06)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.blue.opacity(0.25), lineWidth: 1.5)
            )
            .shadow(color: Color.blue.opacity(0.15), radius: 8, x: 0, y: 4)
        }
    }

    private var freeStatusIcon: some View {
        ZStack {
            Circle()
                .fill(Color.blue.opacity(0.12))
                .frame(width: 40, height: 40)

            Image(systemName: "crown")
                .foregroundColor(.blue)
                .font(.system(size: 18, weight: .semibold))
        }
    }

    private var freeStatusText: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Free Plan")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)

            Text("1 athlete · 1 GB storage")
                .font(.caption)
                .foregroundColor(.secondary)
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
            if let user = authManager.localUser {
                ImprovedPaywallView(user: user)
            }
        }
    }

}
