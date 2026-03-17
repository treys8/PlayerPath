//
//  FeatureHighlight.swift
//  PlayerPath
//
//  Extracted from MainAppView.swift
//

import SwiftUI

struct FeatureHighlight: View {
    let icon: String
    let title: String
    let description: String
    var color: Color = .blue

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            // Icon with gradient background
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.15), color.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)

                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [color, color.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    VStack(spacing: 16) {
        FeatureHighlight(
            icon: "video.circle.fill",
            title: "Record & Analyze",
            description: "Capture practice sessions and games with smart analysis"
        )

        FeatureHighlight(
            icon: "chart.line.uptrend.xyaxis.circle.fill",
            title: "Track Statistics",
            description: "Monitor batting averages and performance metrics",
            color: .green
        )

        FeatureHighlight(
            icon: "arrow.triangle.2.circlepath.circle.fill",
            title: "Sync Everywhere",
            description: "Your data syncs securely across all devices",
            color: .purple
        )
    }
    .padding()
}
