//
//  WhatsNewView.swift
//  PlayerPath
//
//  Shown once per version after update, driven by Firestore appConfig.
//

import SwiftUI

struct WhatsNewView: View {
    let items: [String]
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 36))
                    .foregroundColor(.brandNavy)
                Text("What's New")
                    .font(.title2).fontWeight(.bold)
                Text("Version \(Bundle.main.appVersion)")
                    .font(.caption).foregroundColor(.secondary)
            }
            .padding(.top, 24)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.brandNavy)
                            .font(.title3)
                            .frame(width: 24)
                        Text(item)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            Button(action: onDismiss) {
                Text("Continue")
                    .fontWeight(.semibold)
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
            .padding(.bottom, 32)
        }
    }
}
