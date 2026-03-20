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

                NavigationLink {
                    SimpleCloudStorageView()
                } label: {
                    Label("Cloud Upload Queue", systemImage: "icloud.and.arrow.up")
                }
            }

            Section("Preferences") {
                NavigationLink {
                    UserPreferencesView()
                } label: {
                    Label("App Preferences", systemImage: "slider.horizontal.3")
                }

                NavigationLink {
                    BiometricSettingsView()
                } label: {
                    Label("Face ID / Touch ID", systemImage: "faceid")
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
                        .font(.caption)
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
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}
