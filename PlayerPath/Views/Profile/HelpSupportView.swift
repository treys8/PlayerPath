//
//  HelpSupportView.swift
//  PlayerPath
//
//  Help/support wrapper and About screen.
//

import SwiftUI

struct HelpSupportView: View {
    var body: some View {
        // Use the comprehensive HelpView created in Views/Help/HelpView.swift
        HelpView()
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "figure.baseball")
                .font(.system(size: 80))
                .foregroundColor(.blue)

            VStack(spacing: 10) {
                Text("PlayerPath")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Text("The ultimate baseball journal for tracking your athletic journey. Record videos, track statistics, and relive your greatest moments.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()

            Text("Made for baseball athletes")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}
