//
//  ResetPasswordSheet.swift
//  PlayerPath
//
//  Extracted from MainAppView.swift
//

import SwiftUI

struct ResetPasswordSheet: View {
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @Environment(\.dismiss) private var dismiss
    @Binding var email: String

    @State private var resetEmail = ""
    @State private var isLoading = false
    @State private var showingSuccess = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "key.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                    .padding(.top, 32)

                VStack(spacing: 12) {
                    Text("Reset Password")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Enter your email address and we'll send you a link to reset your password.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                VStack(spacing: 16) {
                    TextField("Email", text: $resetEmail)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .padding(.horizontal)

                    Button {
                        sendResetEmail()
                    } label: {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            }
                            Text(isLoading ? "Sending..." : "Send Reset Link")
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(resetEmail.isEmpty || isLoading)
                    .padding(.horizontal)
                }

                Spacer()
            }
            .navigationTitle("Reset Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                resetEmail = email
            }
            .alert("Email Sent", isPresented: $showingSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Check your email for a password reset link.")
            }
        }
    }

    private func sendResetEmail() {
        isLoading = true
        Task {
            await authManager.resetPassword(email: resetEmail)
            await MainActor.run {
                isLoading = false
                showingSuccess = true
            }
        }
    }
}
