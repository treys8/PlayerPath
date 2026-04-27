//
//  EmailVerificationView.swift
//  PlayerPath
//
//  Shown after email/password signup until the user verifies their email.
//

import SwiftUI

struct EmailVerificationView: View {
    @EnvironmentObject private var authManager: ComprehensiveAuthManager

    @State private var isCheckingVerification = false
    @State private var isResending = false
    @State private var statusMessage: String?
    @State private var isError = false
    @State private var pollTimer: Timer?

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.brandNavy.opacity(0.2), Color.brandNavy.opacity(0.05)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 100, height: 100)
                Image(systemName: "envelope.badge.shield.half.filled")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(LinearGradient(
                        colors: [Color.brandNavy, Color.brandNavy.opacity(0.7)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
            }

            // Heading
            VStack(spacing: 10) {
                Text("Verify Your Email")
                    .font(.displayMedium)
                Text("We sent a verification link to:")
                    .font(.bodyMedium).foregroundColor(.secondary)
                Text(authManager.userEmail ?? "your email")
                    .font(.headingSmall)
                    .foregroundColor(.brandNavy)
            }

            // Instructions
            VStack(spacing: 8) {
                instructionRow(icon: "1.circle.fill", text: "Open the email from PlayerPath")
                instructionRow(icon: "2.circle.fill", text: "Tap the verification link")
                instructionRow(icon: "3.circle.fill", text: "Come back here and tap the button below")
            }
            .padding(.horizontal, 8)

            // Status message
            if let statusMessage {
                HStack(spacing: 8) {
                    Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundColor(isError ? .red : .green)
                    Text(statusMessage)
                        .font(.bodySmall)
                        .foregroundColor(isError ? .red : .green)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill((isError ? Color.red : Color.green).opacity(0.1))
                )
            }

            // Actions
            VStack(spacing: 14) {
                // Primary: Check verification
                Button {
                    Haptics.medium()
                    Task { await checkVerification() }
                } label: {
                    HStack(spacing: 10) {
                        if isCheckingVerification {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.9)
                        } else {
                            Image(systemName: "checkmark.circle.fill").font(.title3)
                        }
                        Text(isCheckingVerification ? "Checking..." : "I've Verified My Email")
                            .font(.headingMedium)
                    }
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .background(
                        LinearGradient(
                            colors: [Color.brandNavy, Color.brandNavy.opacity(0.85)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .foregroundColor(.white).cornerRadius(14)
                    .shadow(color: .brandNavy.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .disabled(isCheckingVerification || isResending)

                // Secondary: Resend email
                Button {
                    Haptics.light()
                    Task { await resendEmail() }
                } label: {
                    HStack(spacing: 8) {
                        if isResending {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        Text(isResending ? "Sending..." : "Resend Verification Email")
                    }
                    .font(.labelLarge)
                    .foregroundColor(.brandNavy)
                }
                .disabled(isCheckingVerification || isResending)

                // Tertiary: Use different account
                Button {
                    Haptics.light()
                    Task { await authManager.cancelEmailVerification() }
                } label: {
                    Text("Use a Different Account")
                        .font(.labelLarge)
                        .foregroundColor(.secondary)
                }
                .disabled(isCheckingVerification || isResending)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .onAppear { startPolling() }
        .onDisappear { stopPolling() }
    }

    // MARK: - Helpers

    private func instructionRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.brandNavy)
                .frame(width: 28)
            Text(text)
                .font(.bodyMedium)
                .foregroundColor(.primary)
            Spacer()
        }
    }

    private func checkVerification() async {
        isCheckingVerification = true
        statusMessage = nil
        let verified = await authManager.checkEmailVerification()
        isCheckingVerification = false

        if !verified {
            isError = true
            statusMessage = "Email not verified yet. Check your inbox and try again."
        }
    }

    private func resendEmail() async {
        isResending = true
        statusMessage = nil
        do {
            try await authManager.resendVerificationEmail()
            isError = false
            statusMessage = AuthConstants.SuccessMessages.emailVerificationSent
        } catch {
            isError = true
            statusMessage = AuthConstants.ErrorMessages.emailVerificationFailed
        }
        isResending = false
    }

    /// Polls Firebase every 5 seconds to auto-detect verification.
    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            Task { @MainActor in
                let verified = await authManager.checkEmailVerification()
                if verified { stopPolling() }
            }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
