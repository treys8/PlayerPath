//
//  SettingsView.swift
//  PlayerPath
//
//  "Account & Sign-In": who you are and how you sign in. Storage, App
//  Preferences, and Redeem Code live on the More tab itself (2026-09 layout
//  pass) so nothing sits three levels deep; golf scoring defaults live in
//  App Preferences.
//

import SwiftUI
import SwiftData
import FirebaseAuth

struct SettingsView: View {
    let user: User

    @Environment(\.ppAccent) private var ppAccent

    var body: some View {
        Form {
            Section("Profile") {
                // One row instead of separate Username / Email rows plus an
                // "Edit Information" link — the same Apple-ID-style pattern iOS uses.
                NavigationLink {
                    EditAccountView(user: user)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.username)
                            .foregroundColor(.primary)
                        Text(user.email)
                            .font(.bodySmall)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .accessibilityLabel("Edit Information, \(user.username)")
                .accessibilityHint("Change your username, email, or profile picture")
            }

            let provider = Auth.auth().currentUser?.providerData.first?.providerID ?? "email"
            Section("Sign-In Method") {
                Label(
                    provider == "apple.com" ? "Sign in with Apple" : "Email & Password",
                    systemImage: provider == "apple.com" ? "apple.logo" : "envelope.fill"
                )

                if provider != "apple.com" {
                    NavigationLink {
                        ChangePasswordView(email: user.email)
                    } label: {
                        Label("Change Password", systemImage: "lock.rotation")
                    }
                }
            }
        }
        // Screen name kept as "Settings" so the analytics history stays continuous.
        .onAppear { AnalyticsService.shared.trackScreenView(screenName: "Settings", screenClass: "ProfileView") }
        .scrollContentBackground(.hidden)
        .background(Theme.surface)
        .tint(ppAccent)
        .navigationTitle("Account & Sign-In")
        .navigationBarTitleDisplayMode(.inline)
    }
}
