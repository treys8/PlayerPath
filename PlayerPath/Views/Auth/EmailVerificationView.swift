//
//  EmailVerificationView.swift
//  PlayerPath
//
//  Shown after email/password signup until the user verifies their email.
//

import SwiftUI

struct EmailVerificationView: View {
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @Environment(\.ppAccent) private var ppAccent
    @Environment(\.scenePhase) private var scenePhase

    @State private var isCheckingVerification = false
    @State private var isResending = false
    @State private var statusMessage: String?
    @State private var isError = false
    @State private var pollTimer: Timer?
    // Guards startPolling() so an in-flight scenePhase check that completes
    // after the view has gone away (e.g. "Use a Different Account" or X)
    // can't resurrect a Timer nothing will ever invalidate.
    @State private var isVisible = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [ppAccent.opacity(0.2), ppAccent.opacity(0.05)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 100, height: 100)
                Image(systemName: "envelope.badge.shield.half.filled")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(LinearGradient(
                        colors: [ppAccent, ppAccent.opacity(0.7)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
            }

            // Heading
            VStack(spacing: 10) {
                Text("Verify Your Email")
                    .font(.displayMedium)
                    .foregroundColor(Theme.textPrimary)
                Text("We sent a verification link to:")
                    .font(.bodyMedium).foregroundColor(Theme.textSecondary)
                Text(authManager.userEmail ?? "your email")
                    .font(.headingSmall)
                    .foregroundColor(ppAccent)
            }

            // Instructions
            VStack(spacing: 8) {
                instructionRow(icon: "1.circle.fill", text: "Open the email from PlayerPath")
                instructionRow(icon: "2.circle.fill", text: "Tap the verification link")
                instructionRow(icon: "3.circle.fill", text: "Come back here and tap the button below")
            }
            .padding(.horizontal, 8)

            if authManager.verificationEmailSendFailed && statusMessage == nil {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(Theme.warning)
                    Text("We couldn't send the email. Tap Resend below.")
                        .font(.bodySmall).foregroundColor(Theme.warning)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.warning.opacity(0.1)))
            }

            // Status message
            if let statusMessage {
                HStack(spacing: 8) {
                    Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundColor(isError ? Theme.warning : Theme.success)
                    Text(statusMessage)
                        .font(.bodySmall)
                        .foregroundColor(isError ? Theme.warning : Theme.success)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill((isError ? Theme.warning : Theme.success).opacity(0.1))
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
                            colors: [ppAccent, ppAccent.opacity(0.85)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .foregroundColor(.white).cornerRadius(14)
                    .shadow(color: ppAccent.opacity(0.3), radius: 8, x: 0, y: 4)
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
                    .foregroundColor(ppAccent)
                }
                .disabled(isCheckingVerification || isResending)

                // Tertiary: Use different account
                Button {
                    Haptics.light()
                    Task { await authManager.cancelEmailVerification() }
                } label: {
                    Text("Use a Different Account")
                        .font(.labelLarge)
                        .foregroundColor(Theme.textSecondary)
                }
                .disabled(isCheckingVerification || isResending)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface)
        .onAppear {
            isVisible = true
            startPolling()
        }
        .onDisappear {
            isVisible = false
            stopPolling()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                // Coming back from Mail/Safari is the moment they verified —
                // check now instead of waiting up to 5s for the next tick.
                // Check FIRST, then resume polling, so ordering alone avoids an
                // immediate double tick; checkEmailVerification() itself coalesces
                // any remaining overlap (e.g. a timer tick already in flight when
                // the app backgrounded) so isHandlingVerification and the success
                // path only ever run once.
                Task {
                    let verified = await authManager.checkEmailVerification()
                    if !verified { startPolling() }
                }
            } else {
                stopPolling()
            }
        }
    }

    // MARK: - Helpers

    private func instructionRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(ppAccent)
                .frame(width: 28)
            Text(text)
                .font(.bodyMedium)
                .foregroundColor(Theme.textPrimary)
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
        stopPolling()
        // The view may have disappeared while an awaited check (e.g. from the
        // scenePhase handler) was in flight; don't schedule a timer for a gone view.
        guard isVisible else { return }
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
