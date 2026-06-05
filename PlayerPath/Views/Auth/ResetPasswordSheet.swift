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
    @Environment(\.ppAccent) private var ppAccent
    let email: String

    @State private var resetEmail = ""
    @State private var isLoading = false
    @State private var showingSuccess = false
    @State private var errorMessage: String?
    @FocusState private var emailFocused: Bool

    private var isValidEmail: Bool {
        resetEmail.isValidEmail
    }

    private var emailValidationState: FieldValidationState {
        guard !resetEmail.isEmpty else { return .idle }
        return isValidEmail ? .valid : .invalid
    }

    var body: some View {
        NavigationStack {
            ScrollView {
            VStack(spacing: 28) {
                // Icon with background
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [ppAccent.opacity(0.2), ppAccent.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 88, height: 88)

                    Image(systemName: showingSuccess ? "checkmark.circle.fill" : "key.fill")
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [ppAccent, ppAccent.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .padding(.top, 16)

                VStack(spacing: 10) {
                    Text(showingSuccess ? "Check Your Email" : "Reset Password")
                        .font(.displayMedium)

                    Text(showingSuccess
                         ? "If an account with that email has a password, we've sent a reset link. It can take a few minutes — be sure to check your spam folder."
                         : "Enter your email address and we'll send you a link to reset your password.")
                        .font(.bodyMedium)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }

                if showingSuccess {
                    VStack(spacing: 16) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "apple.logo")
                                .font(.body)
                                .foregroundColor(.secondary)
                            Text("Signed up with Apple? You don't have a password to reset — go back and tap **Sign in with Apple** instead.")
                                .font(.bodySmall)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)

                        Button {
                            dismiss()
                        } label: {
                            Text("Done")
                                .font(.headingMedium)
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .background(
                                    LinearGradient(
                                        colors: [ppAccent, ppAccent.opacity(0.85)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .foregroundColor(.white)
                                .cornerRadius(14)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                } else {
                VStack(spacing: 20) {
                    ModernTextField(
                        placeholder: "you@example.com",
                        text: $resetEmail,
                        icon: "envelope.fill",
                        keyboardType: .emailAddress,
                        textContentType: .emailAddress,
                        autocapitalization: .never,
                        validationState: emailValidationState,
                        submitLabel: .go,
                        onSubmit: {
                            if isValidEmail && !isLoading {
                                sendResetEmail()
                            }
                        },
                        focusedBinding: $emailFocused
                    )

                    if let errorMessage {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(errorMessage)
                                .font(.bodySmall)
                                .foregroundColor(.red)
                        }
                    }

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
                                .font(.headingMedium)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            LinearGradient(
                                colors: isValidEmail && !isLoading
                                    ? [ppAccent, ppAccent.opacity(0.85)]
                                    : [Color(.systemGray4), Color(.systemGray4)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(14)
                        .shadow(
                            color: isValidEmail && !isLoading ? ppAccent.opacity(0.3) : .clear,
                            radius: 8,
                            x: 0,
                            y: 4
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!isValidEmail || isLoading)

                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "apple.logo")
                            .font(.caption)
                        Text("Signed up with Apple? You won't have a password — close this and tap Sign in with Apple.")
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 20)
                }
            }
            .padding(.vertical, 16)
            .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.surface)
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
                emailFocused = true
            }
        }
    }

    private func sendResetEmail() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await authManager.resetPassword(email: resetEmail)
                isLoading = false
                showingSuccess = true
            } catch {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
