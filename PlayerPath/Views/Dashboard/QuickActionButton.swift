//
//  QuickActionButton.swift
//  PlayerPath
//
//  Extracted from MainAppView.swift
//

import SwiftUI

struct QuickActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void

    /// Fixed layout height for the icon so glyphs of differing intrinsic
    /// height (e.g. `figure.golf` vs `plus.circle.fill`) don't make paired
    /// buttons render at different heights. Scales with Dynamic Type so the
    /// box still contains the glyph at larger text sizes.
    @ScaledMetric(relativeTo: .title2) private var iconHeight: CGFloat = 28

    var body: some View {
        Button(action: { Haptics.light(); action() }) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.white)
                    .symbolRenderingMode(.hierarchical)
                    .frame(height: iconHeight)

                Text(title)
                    .font(.headingSmall)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: .cornerLarge)
                    .fill(
                        LinearGradient(
                            colors: [color, color.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .shadow(color: color.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(ScaleButtonStyle())
    }
}
