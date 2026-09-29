//
//  ComprehensiveSignInView.swift
//  PlayerPath
//
//  Extracted from MainAppView.swift
//

import SwiftUI
import Combine

struct ComprehensiveSignInView: View {
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.ppAccent) private var ppAccent

    let isSignUpMode: Bool
    var onSwitchToSignIn: (() -> Void)?
    var onSwitchToSignUp: (() -> Void)?

    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""

    @State private var showingResetPasswordSheet = false
    @State private var selectedRole: UserRole = .athlete

    @State private var confirmedAge = false
    @State private var showingTerms = false
    @State private var showingPrivacyPolicy = false
    @StateObject private var appleSignInManager = AppleSignInManager()

    @FocusState private var nameFocused: Bool
    @FocusState private var emailFocused: Bool
    @FocusState private var passwordFocused: Bool

    // Computed validation states
    private var emailValidationState: FieldValidationState {
        guard !email.isEmpty else { return .idle }
        if isValidEmail(email) { return .valid }
        // Don't show the error icon while the user is still typing — only flag it
        // once they've typed something that looks like a complete email attempt.
        return email.contains("@") && email.contains(".") ? .invalid : .idle
    }

    private var passwordValidationState: FieldValidationState {
        guard !password.isEmpty else { return .idle }
        if isValidPassword(password) { return .valid }
        // Don't show the warning icon while the user is still building up to the minimum
        // length — only flag it once they've typed enough to have a "complete" attempt.
        return password.count >= 8 ? .warning : .idle
    }

    private var displayNameValidationState: FieldValidationState {
        guard !displayName.isEmpty else { return .idle }
        return isValidDisplayName(displayName) ? .valid : .warning
    }

    var body: some View {
        NavigationStack {
            if authManager.needsEmailVerification {
                EmailVerificationView()
                    .environmentObject(authManager)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button {
                                Task { await authManager.cancelEmailVerification() }
                                dismiss()
                            } label: {
                                closeButtonLabel
                            }
                        }
                    }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 28) {
                            headerSection
                            if isSignUpMode { roleSelectionSection }
                            formFieldsSection
                            if isSignUpMode { ageAndTermsSection }
                            actionButtonsSection
                            authErrorSection
                            if appleSignInManager.accountCreationBlocked { appleNoAccountSection }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .padding(.bottom, 40)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: nameFocused) { _, focused in
                        if focused { withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo("nameField", anchor: .center) } }
                    }
                    .onChange(of: emailFocused) { _, focused in
                        if focused { withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo("emailField", anchor: .center) } }
                    }
                    .onChange(of: passwordFocused) { _, focused in
                        if focused { withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo("actionButtons", anchor: .bottom) } }
                    }
                }
                .background(Theme.surface)
                .onAppear { appleSignInManager.configure(with: authManager) }
                .onDisappear { appleSignInManager.cleanup() }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: {
                            closeButtonLabel
                        }
                    }
                }
                .onAppear {
                    Task { @MainActor in
                        // Without this delay, the focus mutation can land during
                        // _reloadInputViewsForKeyWindowSceneResponder and deadlock
                        // SwiftUI's Update lock against CALayer's unfair lock.
                        try? await Task.sleep(for: .milliseconds(750))
                        guard !Task.isCancelled else { return }
                        if isSignUpMode { nameFocused = true } else { emailFocused = true }
                    }
                }
            }
        }
        .sheet(isPresented: $showingResetPasswordSheet) { ResetPasswordSheet(email: email) }
        .sheet(isPresented: $showingTerms) { TermsOfServiceView() }
        .sheet(isPresented: $showingPrivacyPolicy) { PrivacyPolicyView() }
        .onChange(of: authManager.isSignedIn) { _, isSignedIn in
            if isSignedIn {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(100))
                    dismiss()
                }
            }
        }
    }

    /// iOS 26 wraps toolbar buttons in glass, so a filled circle would draw a
    /// circle inside the capsule — `ToolbarSymbol.close` drops to a plain X there.
    private var closeButtonLabel: some View {
        Image(systemName: ToolbarSymbol.close)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(Theme.textSecondary)
            .accessibilityLabel("Close")
    }

    // MARK: - Body Sections

    private var headerSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [ppAccent.opacity(0.2), ppAccent.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 80, height: 80)
                Image(systemName: isSignUpMode ? "person.crop.circle.badge.plus" : "person.crop.circle.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(LinearGradient(colors: [ppAccent, ppAccent.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            VStack(spacing: 8) {
                Text(isSignUpMode ? "Create Account" : "Welcome Back")
                    .font(.displayMedium)
                    .foregroundColor(Theme.textPrimary)
                Text(isSignUpMode ? (selectedRole == .athlete ? "Join PlayerPath to track your sports journey" : "Join PlayerPath to coach your athletes") : "Sign in to continue to PlayerPath")
                    .font(.bodyMedium).foregroundColor(Theme.textSecondary).multilineTextAlignment(.center)
            }
        }
        .padding(.top, 8)
    }

    private var roleSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Account type")
                .font(.headingSmall).foregroundColor(Theme.textSecondary)
            HStack(spacing: 12) {
                RoleSelectionButton(role: .athlete, isSelected: selectedRole == .athlete, icon: "figure.baseball", title: "Athlete", description: "Track my progress") {
                    Haptics.light(); selectedRole = .athlete
                }
                RoleSelectionButton(role: .coach, isSelected: selectedRole == .coach, icon: "person.2.fill", title: "Coach", description: "Work with athletes") {
                    Haptics.light(); selectedRole = .coach
                }
            }
        }
    }

    private var formFieldsSection: some View {
        VStack(spacing: 16) {
            if isSignUpMode {
                VStack(alignment: .leading, spacing: 6) {
                    ModernTextField(placeholder: "Your name (optional)", text: $displayName, icon: "person.fill", textContentType: .name, autocapitalization: .words, validationState: displayNameValidationState, submitLabel: .next, onSubmit: { emailFocused = true }, focusedBinding: $nameFocused)
                        .id("nameField")
                        .accessibilityLabel(selectedRole == .athlete ? "Account holder name, optional" : "Your name, optional")
                        .accessibilityHint(selectedRole == .athlete ? "Enter the account holder's name. You'll add your athlete's name next." : "Enter your preferred display name")

                    // The account holder isn't necessarily the player (e.g. a
                    // parent), so clarify that the athlete's name comes next —
                    // this is where users otherwise enter the wrong name.
                    if selectedRole == .athlete {
                        Text("This is the account holder's name. You'll add your athlete's name in the next step.")
                            .font(.bodySmall)
                            .foregroundColor(Theme.textSecondary)
                            .padding(.leading, 4)
                            .accessibilityHidden(true)
                    }
                }
            }

            ModernTextField(placeholder: "you@example.com", text: $email, icon: "envelope.fill", keyboardType: .emailAddress, textContentType: .username, autocapitalization: .never, validationState: emailValidationState, submitLabel: .next, onSubmit: { passwordFocused = true }, focusedBinding: $emailFocused)
                .id("emailField")
                .accessibilityLabel("Email address")
                .accessibilityHint("Enter your email address")

            ModernTextField(placeholder: "Password", text: $password, icon: "lock.fill", isSecure: true, textContentType: isSignUpMode ? .newPassword : .password, autocapitalization: .never, validationState: passwordValidationState, submitLabel: .go, onSubmit: { if canSubmitForm() && !authManager.isLoading { performAuth() } }, focusedBinding: $passwordFocused)
                .accessibilityLabel("Password")
                .accessibilityHint("Enter your password")

            if isSignUpMode && (passwordFocused || !password.isEmpty) {
                VStack(alignment: .leading, spacing: 8) {
                    if !password.isEmpty {
                        PasswordStrengthIndicator(password: password)
                    }
                    if !isValidPassword(password) {
                        PasswordRequirementsList(password: password).padding(.top, 4)
                    }
                }
                .padding(.horizontal, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: password.isEmpty)
        .animation(.easeInOut(duration: 0.2), value: passwordFocused)
    }

    private var ageAndTermsSection: some View {
        VStack(spacing: 16) {
            Button {
                confirmedAge.toggle(); Haptics.light()
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: confirmedAge ? "checkmark.square.fill" : "square")
                        .foregroundColor(confirmedAge ? ppAccent : Theme.textTertiary).font(.title3)
                    Text("I confirm that I am at least 18 years old, or a parent/guardian creating this account on behalf of my child.")
                        .font(.bodySmall).foregroundColor(Theme.textSecondary).multilineTextAlignment(.leading)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)
            .accessibilityLabel("Age confirmation")
            .accessibilityValue(confirmedAge ? "Confirmed" : "Not confirmed")

            VStack(spacing: 6) {
                Text("By creating an account, you agree to our").font(.bodySmall).foregroundColor(Theme.textSecondary)
                HStack(spacing: 4) {
                    Button("Terms of Use (EULA)") { showingTerms = true }.font(.bodySmall).foregroundColor(ppAccent)
                    Text("and").font(.bodySmall).foregroundColor(Theme.textSecondary)
                    Button("Privacy Policy") { showingPrivacyPolicy = true }.font(.bodySmall).foregroundColor(ppAccent)
                }
            }
            .multilineTextAlignment(.center)
        }
    }

    private var actionButtonsSection: some View {
        VStack(spacing: 16) {
            EmptyView().id("actionButtons")

            Button(action: { Haptics.medium(); performAuth() }) {
                HStack(spacing: 10) {
                    if authManager.isLoading {
                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white)).scaleEffect(0.9)
                    } else {
                        Image(systemName: isSignUpMode ? "arrow.right.circle.fill" : "arrow.forward.circle.fill").font(.title3)
                    }
                    Text(authManager.isLoading ? (isSignUpMode ? "Creating Account..." : "Signing In...") : (isSignUpMode ? "Create Account" : "Sign In"))
                        .font(.headingMedium)
                }
                .frame(maxWidth: .infinity).frame(height: 54)
                .background(
                    LinearGradient(
                        colors: canSubmitForm() && !authManager.isLoading ? [ppAccent, ppAccent.opacity(0.85)] : [Theme.textTertiary, Theme.textTertiary],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .foregroundColor(.white).cornerRadius(14)
                .shadow(color: canSubmitForm() && !authManager.isLoading ? ppAccent.opacity(0.3) : .clear, radius: 8, x: 0, y: 4)
            }
            .buttonStyle(ScaleButtonStyle())
            .disabled(!canSubmitForm() || authManager.isLoading || appleSignInManager.isLoading)

            // Divider
            HStack {
                Rectangle().frame(height: 1).foregroundColor(Theme.divider)
                Text("or").font(.bodyMedium).foregroundColor(Theme.textSecondary)
                Rectangle().frame(height: 1).foregroundColor(Theme.divider)
            }

            // Sign in with Apple (required by App Store Guideline 4.8)
            if appleSignInManager.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            } else {
                SignInWithAppleButton(isSignUp: isSignUpMode) {
                    appleSignInManager.pendingRole = selectedRole
                    appleSignInManager.allowsAccountCreation = isSignUpMode && confirmedAge
                    authManager.clearError()
                    appleSignInManager.signInWithApple()
                }
                .disabled(authManager.isLoading || (isSignUpMode && !confirmedAge))
                .opacity(isSignUpMode && !confirmedAge ? 0.5 : 1)
            }

            if !isSignUpMode {
                Button { Haptics.light(); showingResetPasswordSheet = true } label: {
                    Text("Forgot Password?").font(.labelLarge).foregroundColor(ppAccent)
                }
            }

            if !isSignUpMode, onSwitchToSignUp != nil {
                HStack(spacing: 4) {
                    Text("New to PlayerPath?").font(.bodyMedium).foregroundColor(Theme.textSecondary)
                    Button { Haptics.light(); dismiss(); onSwitchToSignUp?() } label: {
                        Text("Create an account").font(.labelLarge).foregroundColor(ppAccent)
                    }
                }
            }

            if isSignUpMode {
                HStack(spacing: 4) {
                    Text("Already have an account?").font(.bodyMedium).foregroundColor(Theme.textSecondary)
                    Button { Haptics.light(); dismiss(); onSwitchToSignIn?() } label: {
                        Text("Sign in").font(.labelLarge).foregroundColor(ppAccent)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var authErrorSection: some View {
        // Show errors from either auth manager or Apple Sign In manager
        let displayError = authManager.errorMessage ?? appleSignInManager.errorMessage
        if let errorMessage = displayError {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.title3).foregroundColor(Theme.warning)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(isSignUpMode ? "Couldn't create your account" : "Couldn't sign you in")
                            .font(.headingSmall).foregroundColor(Theme.textPrimary)
                        Text(errorMessage).font(.bodySmall).foregroundColor(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button {
                        Haptics.light()
                        authManager.clearError()
                        appleSignInManager.errorMessage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill").font(.title3).foregroundColor(Theme.textTertiary)
                    }
                    .accessibilityLabel("Dismiss error")
                }
                if let recovery = errorRecovery {
                    Button {
                        Haptics.light()
                        recovery.perform()
                    } label: {
                        Text(recovery.title).font(.labelLarge).foregroundColor(ppAccent)
                    }
                    .padding(.leading, 36)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12).fill(Theme.warning.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.warning.opacity(0.25), lineWidth: 1))
            )
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    /// One next step for the error on screen. Email enumeration protection makes
    /// "wrong password" and "no such user" indistinguishable (invalidCredential),
    /// so all three credential messages offer a reset. Network, lockout and
    /// generic errors get no action — a reset link would be misleading there.
    private var errorRecovery: (title: String, perform: () -> Void)? {
        let message = authManager.errorMessage
        if isSignUpMode, message == AuthConstants.ErrorMessages.emailAlreadyInUse {
            return ("Sign in instead", {
                authManager.clearError()
                dismiss()
                onSwitchToSignIn?()
            })
        }
        let credentialMessages = [
            AuthConstants.ErrorMessages.invalidCredential,
            AuthConstants.ErrorMessages.wrongPassword,
            AuthConstants.ErrorMessages.userNotFound,
        ]
        if !isSignUpMode, let message, credentialMessages.contains(message) {
            return ("Reset your password", { showingResetPasswordSheet = true })
        }
        return nil
    }

    private var appleNoAccountSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "apple.logo").font(.title3).foregroundColor(Theme.textPrimary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("No account for this Apple ID yet").font(.headingSmall).foregroundColor(Theme.textPrimary)
                    Text("Create one first — it takes a minute, and you can keep using Sign in with Apple.")
                        .font(.bodySmall).foregroundColor(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button {
                Haptics.light()
                appleSignInManager.accountCreationBlocked = false
                dismiss()
                onSwitchToSignUp?()
            } label: {
                Text("Create an account").font(.labelLarge).foregroundColor(ppAccent)
            }
            .padding(.leading, 36)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12).fill(Theme.card)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.divider, lineWidth: 1))
        )
    }

    private func performAuth() {
        guard !authManager.isLoading else { return }
        appleSignInManager.accountCreationBlocked = false
        // Dismiss keyboard so the error message (if any) is visible
        nameFocused = false
        emailFocused = false
        passwordFocused = false
        Task {
            let normalizedEmail = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !Task.isCancelled else { return }

            #if DEBUG
            print("🔵 Attempting authentication:")
            print("  - Email: \(normalizedEmail.isEmpty ? "EMPTY" : "***@***")")
            print("  - Password length: \(password.count)")
            print("  - Is sign up: \(isSignUpMode)")
            print("  - Role: \(selectedRole.rawValue)")
            #endif

            if isSignUpMode {
                if selectedRole == .coach {
                    await authManager.signUpAsCoach(
                        email: normalizedEmail,
                        password: password,
                        displayName: trimmedDisplayName.isEmpty ? "Coach" : trimmedDisplayName
                    )
                } else {
                    await authManager.signUp(
                        email: normalizedEmail,
                        password: password,
                        displayName: trimmedDisplayName.isEmpty ? nil : trimmedDisplayName
                    )
                }
            } else {
                await authManager.signIn(email: normalizedEmail, password: password)
            }

            guard !Task.isCancelled else { return }

            // Add haptic feedback on successful authentication
            if authManager.isSignedIn {
                await MainActor.run {
                    Haptics.light()
                }
            }
        }
    }

    // MARK: - Validation Functions

    private func isValidEmail(_ email: String) -> Bool {
        email.isValidEmail
    }

    private func isValidPassword(_ password: String) -> Bool {
        if isSignUpMode {
            return password.count >= 8 &&
                   password.range(of: "[A-Z]", options: .regularExpression) != nil &&
                   password.range(of: "[a-z]", options: .regularExpression) != nil &&
                   password.range(of: "[0-9]", options: .regularExpression) != nil
        } else {
            return !password.isEmpty
        }
    }

    private func isValidDisplayName(_ name: String) -> Bool {
        Validation.isValidPersonName(name, min: 2, max: 30)
    }

    private func canSubmitForm() -> Bool {
        // Read authManager.lockoutTick so SwiftUI re-evaluates each tick.
        let _ = authManager.lockoutTick
        if authManager.isSignInLocked { return false }

        let emailValid = isValidEmail(email)
        let passwordValid = isValidPassword(password)
        let displayNameValid = isSignUpMode ? (displayName.isEmpty || isValidDisplayName(displayName)) : true
        let ageConfirmed = isSignUpMode ? confirmedAge : true

        return emailValid && passwordValid && displayNameValid && ageConfirmed
    }

}
