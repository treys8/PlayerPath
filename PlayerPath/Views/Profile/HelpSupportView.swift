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
    @Environment(\.ppAccent) private var ppAccent
    @EnvironmentObject private var authManager: ComprehensiveAuthManager

    private var isCoach: Bool { authManager.userRole == .coach }

    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 80))
                .foregroundColor(ppAccent)

            VStack(spacing: 10) {
                Text("PlayerPath")
                    .font(.displayMedium)

                Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")")
                    .font(.bodyMedium)
                    .foregroundColor(.secondary)
            }

            Text(isCoach
                 ? "Review your athletes' clips, leave precise feedback, and run live sessions — all in one place."
                 : "The ultimate journal for tracking your athletic journey. Record videos, track statistics, and relive your greatest moments.")
                .font(.bodyMedium)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()

            Text(isCoach ? "Made for coaches" : "Made for athletes")
                .font(.bodySmall)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface)
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}
