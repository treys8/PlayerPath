//
//  ChangePasswordView.swift
//  PlayerPath
//
//  Send a password reset email via Firebase Auth.
//

import SwiftUI
import FirebaseAuth

// MARK: - Change Password View

struct ChangePasswordView: View {
    let email: String
    @Environment(\.dismiss) private var dismiss
    @State private var isSending = false
    @State private var emailSent = false
    @State private var errorMessage = ""
    @State private var showError = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "lock.rotation")
                        .font(.largeTitle)
                        .foregroundColor(.brandNavy)

                    Text("Change Password")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("We'll send a password reset link to \(email). Follow the link to choose a new password.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            }

            if emailSent {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Email Sent")
                                .font(.headline)
                            Text("Check your inbox at \(email) and follow the link to reset your password.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } else {
                Section {
                    Button {
                        Task { await sendReset() }
                    } label: {
                        HStack {
                            Spacer()
                            if isSending {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Text(isSending ? "Sending…" : "Send Reset Email")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSending)
                } footer: {
                    Text("The link expires after 1 hour. Check your spam folder if you don't see it.")
                }
            }
        }
        .navigationTitle("Change Password")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Unable to Send", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }

    private func sendReset() async {
        isSending = true
        defer { isSending = false }
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
            withAnimation { emailSent = true }
            Haptics.success()
        } catch {
            ErrorHandlerService.shared.reportError(error, context: "ProfileView.resetPassword", message: $errorMessage, isPresented: $showError)
        }
    }
}
