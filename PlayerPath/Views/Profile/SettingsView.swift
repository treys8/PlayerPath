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
                    Text("Name")
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

            Section {
                RedeemOfferCodeRow()
            } header: {
                Text("Subscription")
            } footer: {
                Text("Have a PlayerPath promo code? Redeem it here to apply a free or discounted plan.")
            }

            Section("Preferences") {
                NavigationLink {
                    UserPreferencesView()
                } label: {
                    Label("App Preferences", systemImage: "slider.horizontal.3")
                }
            }

            if hasGolfAthlete {
                Section {
                    Toggle(isOn: $trackDetailedGolfStats) {
                        Label("Track Detailed Stats", systemImage: "flag.fill")
                    }
                } header: {
                    Text("Golf")
                } footer: {
                    Text("Adds fairway, green-in-regulation, and penalty inputs when scoring a round.")
                }

                Section {
                    Toggle(isOn: $preferShotByShot) {
                        Label("Default to Shot-by-Shot", systemImage: "scope")
                    }
                } footer: {
                    Text("New rounds open the shot-by-shot card when you score a hole. You can still switch to Quick on any hole.")
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
