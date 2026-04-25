//
//  GolfPlaceholderView.swift
//  PlayerPath
//

import SwiftUI

struct GolfPlaceholderView: View {
    let athlete: Athlete

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "figure.golf")
                .font(.system(size: 88))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.brandNavy, .green],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: 12) {
                Text("Golf coming soon")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Tournaments, scoring, and club tagging arrive in v6.0.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Text(athlete.name)
                .font(.footnote)
                .foregroundColor(.secondary)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
