//
//  ForceUpdateView.swift
//  PlayerPath
//
//  Full-screen blocking view shown when the app version is below the minimum.
//

import SwiftUI

struct ForceUpdateView: View {
    let updateURL: String?

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.brandNavy.opacity(0.2), Color.brandNavy.opacity(0.05)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 100, height: 100)
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(LinearGradient(
                        colors: [Color.brandNavy, Color.brandNavy.opacity(0.7)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
            }

            VStack(spacing: 10) {
                Text("Update Required")
                    .font(.displayMedium)
                Text("A new version of PlayerPath is available with important updates. Please update to continue.")
                    .font(.bodyMedium)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            if let urlString = updateURL, let url = URL(string: urlString) {
                Link(destination: url) {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.up.circle.fill").font(.title3)
                        Text("Update Now").font(.headingMedium)
                    }
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .background(
                        LinearGradient(
                            colors: [Color.brandNavy, Color.brandNavy.opacity(0.85)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .foregroundColor(.white).cornerRadius(14)
                    .shadow(color: .brandNavy.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .padding(.horizontal, 20)
            }

            Text("Version \(Bundle.main.appVersion)")
                .font(.bodySmall)
                .foregroundColor(.secondary)

            Spacer()
        }
    }
}
