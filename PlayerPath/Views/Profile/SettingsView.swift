//
//  SettingsView.swift
//  PlayerPath
//
//  Account, storage, and preferences settings screen.
//

import SwiftUI
import SwiftData
import FirebaseAuth

// MARK: - Settings Views

struct SettingsView: View {
    let user: User

    @Environment(\.ppAccent) private var ppAccent

    @AppStorage(GolfPrefs.trackDetailedStats) private var trackDetailedGolfStats = false
    @AppStorage(GolfPrefs.preferredShotByShot) private var preferShotByShot = false

    /// Only surface the golf detailed-stats toggle to users who actually have a
    /// golf athlete — it's clutter for baseball-only accounts.
    private var hasGolfAthlete: Bool {
        user.athletes?.contains { $0.sport == .golf } ?? false
    }

    var body: some View {
        Form {
            Section("Account") {
                HStack {
                    Text("Username")
                    Spacer()
                    Text(user.username)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Email")
                    Spacer()
                    Text(user.email)
                        .foregroundColor(.secondary)
                }

                NavigationLink {
                    EditAccountView(user: user)
                } label: {
                    Label("Edit Information", systemImage: "pencil")
                }
            }

            Section("Storage") {
                NavigationLink {
                    StorageSettingsView()
                } label: {
                    Label("Manage Storage", systemImage: "internaldrive")
                }
            }

            Section("Preferences") {
                NavigationLink {
                    UserPreferencesView()
                } label: {
                    Label("App Preferences", systemImage: "slider.horizontal.3")
                }
            }

            if hasGolfAthlete {
                Section("Golf") {
                    Toggle(isOn: $trackDetailedGolfStats) {
                        Label("Track Detailed Stats", systemImage: "flag.fill")
                    }
                    Text("Adds fairway, green-in-regulation, and penalty inputs when scoring a round.")
                        .font(.bodySmall)
                        .foregroundColor(.secondary)

                    Toggle(isOn: $preferShotByShot) {
                        Label("Default to Shot-by-Shot", systemImage: "scope")
                    }
                    Text("New rounds open the shot-by-shot card when you score a hole. You can still switch to Quick on any hole.")
                        .font(.bodySmall)
                        .foregroundColor(.secondary)
                }
            }

            let provider = Auth.auth().currentUser?.providerData.first?.providerID ?? "email"
            Section("Sign-In Method") {
                HStack {
                    Label(
                        provider == "apple.com" ? "Sign in with Apple" : "Email & Password",
                        systemImage: provider == "apple.com" ? "apple.logo" : "envelope.fill"
                    )
                    Spacer()
                    Text(user.email)
                        .font(.bodySmall)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                if provider != "apple.com" {
                    NavigationLink {
                        ChangePasswordView(email: user.email)
                    } label: {
                        Label("Change Password", systemImage: "lock.rotation")
                    }
                }
            }
        }
        .onAppear { AnalyticsService.shared.trackScreenView(screenName: "Settings", screenClass: "ProfileView") }
        .scrollContentBackground(.hidden)
        .background(Theme.surface)
        .tint(ppAccent)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}
