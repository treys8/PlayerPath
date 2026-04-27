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
                        .font(.displayMedium)

                    Text("Enter your email address and we'll send you a link to reset your password.")
                        .font(.bodyMedium)
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
            }
            .padding(.vertical, 16)
            .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
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
                emailFocused = true
            }
            .toast(isPresenting: $showingSuccess, message: "Reset Email Sent")
            .onChange(of: showingSuccess) { _, new in
                if !new { dismiss() }
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
