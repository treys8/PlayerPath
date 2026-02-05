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

    private var isValidEmail: Bool {
        Validation.isValidEmail(resetEmail)
    }

    private var emailValidationState: FieldValidationState {
        guard !resetEmail.isEmpty else { return .idle }
        return isValidEmail ? .valid : .invalid
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                // Icon with background
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.orange.opacity(0.2), .orange.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 88, height: 88)

                    Image(systemName: "key.fill")
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.orange, .orange.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .padding(.top, 16)

                VStack(spacing: 10) {
                    Text("Reset Password")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Enter your email address and we'll send you a link to reset your password.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }

                VStack(spacing: 20) {
                    ModernTextField(
                        placeholder: "you@example.com",
                        text: $resetEmail,
                        icon: "envelope.fill",
                        keyboardType: .emailAddress,
                        textContentType: .emailAddress,
                        autocapitalization: .never,
                        validationState: emailValidationState,
                        onSubmit: {
                            if isValidEmail && !isLoading {
                                sendResetEmail()
                            }
                        }
                    )

                    Button {
                        Haptics.medium()
                        sendResetEmail()
                    } label: {
                        HStack(spacing: 10) {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.9)
                            } else {
                                Image(systemName: "paperplane.fill")
                                    .font(.body)
                            }
                            Text(isLoading ? "Sending..." : "Send Reset Link")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            LinearGradient(
                                colors: isValidEmail && !isLoading
                                    ? [.orange, .orange.opacity(0.85)]
                                    : [Color(.systemGray4), Color(.systemGray4)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(14)
                        .shadow(
                            color: isValidEmail && !isLoading ? .orange.opacity(0.3) : .clear,
                            radius: 8,
                            x: 0,
                            y: 4
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!isValidEmail || isLoading)
                }
                .padding(.horizontal, 20)

                Spacer()
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
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
