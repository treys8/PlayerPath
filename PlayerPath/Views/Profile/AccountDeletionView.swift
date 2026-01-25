//
//  AccountDeletionView.swift
//  PlayerPath
//
//  GDPR-compliant account deletion
//  Allows users to permanently delete their account and all associated data
//

import SwiftUI
import FirebaseAuth

struct AccountDeletionView: View {
    @EnvironmentObject var authManager: ComprehensiveAuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var showConfirmation = false
    @State private var showPasswordPrompt = false
    @State private var password = ""
    @State private var isDeleting = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var userUnderstands = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.red)

                    Text("Delete Account")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("This action is permanent and cannot be undone. Please read carefully before proceeding.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            }

            Section("What Will Be Deleted") {
                DeletionItem(icon: "person.fill.xmark", title: "Your Account", description: "Login credentials and profile")
                DeletionItem(icon: "figure.baseball", title: "All Athletes", description: "All athlete profiles you created")
                DeletionItem(icon: "calendar.badge.minus", title: "All Seasons", description: "Season data and settings")
                DeletionItem(icon: "sportscourt", title: "All Games", description: "Game records and live game data")
                DeletionItem(icon: "chart.bar.xaxis", title: "All Statistics", description: "Batting averages and performance data")
                DeletionItem(icon: "video.slash", title: "Video Metadata", description: "Tags, timestamps, and video references")
                DeletionItem(icon: "cloud.slash", title: "Cloud Sync Data", description: "All data synced to Firestore")
            }

            Section("What Happens to Videos") {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Video files on your device will remain until you uninstall the app, but will no longer be accessible in PlayerPath.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("To keep videos, save them to your Photos app before deleting your account.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fontWeight(.medium)
                    }
                }
            }

            Section("Before You Delete") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("We recommend:")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 8) {
                        RecommendationRow(number: 1, text: "Export your data (Settings → Export Data)")
                        RecommendationRow(number: 2, text: "Save important videos to Photos")
                        RecommendationRow(number: 3, text: "Screenshot key statistics if needed")
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Data Deletion Timeline") {
                TimelineRow(title: "Immediate", description: "Account is deleted and you're signed out")
                TimelineRow(title: "Within 24 hours", description: "Data removed from active servers")
                TimelineRow(title: "Within 30 days", description: "All backups permanently deleted")
            }

            Section {
                Toggle(isOn: $userUnderstands) {
                    Text("I understand this action is permanent and cannot be undone")
                        .font(.callout)
                }
            }

            Section {
                Button(role: .destructive) {
                    showConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "trash.fill")
                        Text("Delete My Account Permanently")
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(!userUnderstands || isDeleting)

                if isDeleting {
                    HStack {
                        ProgressView()
                        Text("Deleting account...")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Delete Account")
        .confirmationDialog("Are You Absolutely Sure?", isPresented: $showConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Yes, Delete My Account", role: .destructive) {
                showPasswordPrompt = true
            }
        } message: {
            Text("This will permanently delete your account and all associated data. This action cannot be undone.")
        }
        .alert("Verify Your Password", isPresented: $showPasswordPrompt) {
            SecureField("Password", text: $password)
            Button("Cancel", role: .cancel) {
                password = ""
            }
            Button("Delete Account", role: .destructive) {
                Task {
                    await deleteAccount()
                }
            }
        } message: {
            Text("Please enter your password to confirm account deletion.")
        }
        .alert("Deletion Failed", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Account Deletion Logic

    private func deleteAccount() async {
        guard !password.isEmpty else {
            errorMessage = "Password is required to delete your account."
            showError = true
            return
        }

        isDeleting = true
        defer {
            isDeleting = false
            password = ""
        }

        do {
            // Re-authenticate user before deletion (Firebase requirement)
            guard let email = authManager.userEmail else {
                throw DeletionError.noEmail
            }

            let credential = EmailAuthProvider.credential(withEmail: email, password: password)
            try await Auth.auth().currentUser?.reauthenticate(with: credential)

            // Delete account via AuthManager (handles both Firebase Auth and Firestore)
            try await authManager.deleteAccount()

            print("✅ Account deleted successfully")

            // AuthManager will automatically sign out the user
            // The UI will return to WelcomeFlow

        } catch let error as NSError {
            if error.code == AuthErrorCode.wrongPassword.rawValue {
                errorMessage = "Incorrect password. Please try again."
            } else if error.code == AuthErrorCode.userNotFound.rawValue {
                errorMessage = "Account not found. You may already be signed out."
            } else if error.code == AuthErrorCode.requiresRecentLogin.rawValue {
                errorMessage = "For security, please sign out and sign back in, then try again."
            } else {
                errorMessage = "Failed to delete account: \(error.localizedDescription)"
            }
            showError = true
            print("❌ Account deletion failed: \(error)")
        }
    }
}

// MARK: - Supporting Views

struct DeletionItem: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.red)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct RecommendationRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.body)
                .foregroundColor(.secondary)
                .frame(width: 20, alignment: .leading)

            Text(text)
                .font(.body)
        }
    }
}

struct TimelineRow: View {
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            VStack {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .fontWeight(.semibold)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .frame(minHeight: 44)
    }
}

// MARK: - Errors

enum DeletionError: LocalizedError {
    case noEmail

    var errorDescription: String? {
        switch self {
        case .noEmail:
            return "Could not find email address for account deletion"
        }
    }
}

#Preview {
    NavigationStack {
        AccountDeletionView()
            .environmentObject(ComprehensiveAuthManager())
    }
}
