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

    var body: some View {
        Button(action: action) {
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
        }
        .appCard()
        .accessibilityElement(children: .combine)
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel(title)
        .accessibilityHint("Opens \(title)")
    }
}
