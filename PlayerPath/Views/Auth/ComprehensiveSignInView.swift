//
//  ComprehensiveSignInView.swift
//  PlayerPath
//
//  Extracted from MainAppView.swift
//

import SwiftUI

struct ComprehensiveSignInView: View {
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @Environment(\.dismiss) private var dismiss

    let isSignUpMode: Bool
    var onSwitchToSignIn: (() -> Void)?

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
                    .background(Color(.systemGroupedBackground))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button {
                                Task { await authManager.cancelEmailVerification() }
                                dismiss()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title3)
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(.secondary)
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
                .background(Color(.systemGroupedBackground))
                .onAppear { appleSignInManager.configure(with: authManager) }
                .onDisappear { appleSignInManager.cleanup() }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onAppear {
                    Task {
                        try? await Task.sleep(for: .milliseconds(600))
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

    // MARK: - Body Sections

    private var headerSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color.brandNavy.opacity(0.2), Color.brandNavy.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 80, height: 80)
                Image(systemName: isSignUpMode ? "person.crop.circle.badge.plus" : "person.crop.circle.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(LinearGradient(colors: [Color.brandNavy, Color.brandNavy.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            VStack(spacing: 8) {
                Text(isSignUpMode ? "Create Account" : "Welcome Back")
                    .font(.title2).fontWeight(.bold)
                Text(isSignUpMode ? (selectedRole == .athlete ? "Join PlayerPath to track your baseball journey" : "Join PlayerPath to coach your athletes") : "Sign in to continue to PlayerPath")
                    .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
            }
        }
        .padding(.top, 8)
    }

    private var roleSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("I am a:")
                .font(.subheadline).fontWeight(.semibold).foregroundColor(.secondary)
            HStack(spacing: 12) {
                RoleSelectionButton(role: .athlete, isSelected: selectedRole == .athlete, icon: "figure.baseball", title: "Athlete", description: "Track my progress") {
                    Haptics.light(); selectedRole = .athlete
                }
                if AppFeatureFlags.isCoachEnabled {
                    RoleSelectionButton(role: .coach, isSelected: selectedRole == .coach, icon: "person.2.fill", title: "Coach", description: "Work with athletes") {
                        Haptics.light(); selectedRole = .coach
                    }
                } else {
                    RoleSelectionButton(role: .coach, isSelected: false, icon: "person.2.fill", title: "Coach", description: "Coming Soon") {}
                        .opacity(0.5)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private var formFieldsSection: some View {
        VStack(spacing: 16) {
            if isSignUpMode {
                ModernTextField(placeholder: "Your name (optional)", text: $displayName, icon: "person.fill", textContentType: .name, autocapitalization: .words, validationState: displayNameValidationState, submitLabel: .next, onSubmit: { emailFocused = true }, focusedBinding: $nameFocused)
                    .id("nameField")
                    .accessibilityLabel("Display name")
                    .accessibilityHint("Enter your preferred display name")
            }

            ModernTextField(placeholder: "you@example.com", text: $email, icon: "envelope.fill", keyboardType: .emailAddress, textContentType: .emailAddress, autocapitalization: .never, validationState: emailValidationState, submitLabel: .next, onSubmit: { passwordFocused = true }, focusedBinding: $emailFocused)
                .id("emailField")
                .accessibilityLabel("Email address")
                .accessibilityHint("Enter your email address")

            ModernTextField(placeholder: "Password", text: $password, icon: "lock.fill", isSecure: true, textContentType: .password, autocapitalization: .never, validationState: passwordValidationState, submitLabel: .go, onSubmit: { if canSubmitForm() && !authManager.isLoading { performAuth() } }, focusedBinding: $passwordFocused)
                .accessibilityLabel("Password")
                .accessibilityHint("Enter your password")

            if isSignUpMode && !password.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    PasswordStrengthIndicator(password: password)
                    if !isValidPassword(password) {
                        PasswordRequirementsList(password: password).padding(.top, 4)
                    }
                }
                .padding(.horizontal, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: password.isEmpty)
    }

    private var ageAndTermsSection: some View {
        VStack(spacing: 16) {
            Button {
                confirmedAge.toggle(); Haptics.light()
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: confirmedAge ? "checkmark.square.fill" : "square")
                        .foregroundColor(confirmedAge ? .brandNavy : .gray).font(.title3)
                    Text("I confirm that I am at least 18 years old, or a parent/guardian creating this account on behalf of my child.")
                        .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.leading)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)
            .accessibilityLabel("Age confirmation")
            .accessibilityValue(confirmedAge ? "Confirmed" : "Not confirmed")

            VStack(spacing: 6) {
                Text("By creating an account, you agree to our").font(.caption).foregroundColor(.secondary)
                HStack(spacing: 4) {
                    Button("Terms of Service") { showingTerms = true }.font(.caption).foregroundColor(.brandNavy)
                    Text("and").font(.caption).foregroundColor(.secondary)
                    Button("Privacy Policy") { showingPrivacyPolicy = true }.font(.caption).foregroundColor(.brandNavy)
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
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity).frame(height: 54)
                .background(
                    LinearGradient(
                        colors: canSubmitForm() && !authManager.isLoading ? [Color.brandNavy, Color.brandNavy.opacity(0.85)] : [Color(.systemGray4), Color(.systemGray4)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .foregroundColor(.white).cornerRadius(14)
                .shadow(color: canSubmitForm() && !authManager.isLoading ? .brandNavy.opacity(0.3) : .clear, radius: 8, x: 0, y: 4)
            }
            .buttonStyle(ScaleButtonStyle())
            .disabled(!canSubmitForm() || authManager.isLoading || appleSignInManager.isLoading)

            // Divider
            HStack {
                Rectangle().frame(height: 1).foregroundColor(.secondary.opacity(0.3))
                Text("or").font(.subheadline).foregroundColor(.secondary)
                Rectangle().frame(height: 1).foregroundColor(.secondary.opacity(0.3))
            }

            // Sign in with Apple (required by App Store Guideline 4.8)
            if appleSignInManager.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            } else {
                SignInWithAppleButton(isSignUp: isSignUpMode) {
                    appleSignInManager.pendingRole = selectedRole
                    appleSignInManager.signInWithApple()
                }
                .disabled(authManager.isLoading || (isSignUpMode && !confirmedAge))
                .opacity(isSignUpMode && !confirmedAge ? 0.5 : 1)
            }

            if !isSignUpMode {
                Button { Haptics.light(); showingResetPasswordSheet = true } label: {
                    Text("Forgot Password?").font(.subheadline).fontWeight(.medium).foregroundColor(.brandNavy)
                }
            }

            if isSignUpMode {
                HStack(spacing: 4) {
                    Text("Already have an account?").font(.subheadline).foregroundColor(.secondary)
                    Button { Haptics.light(); dismiss(); onSwitchToSignIn?() } label: {
                        Text("Sign in").font(.subheadline).fontWeight(.medium).foregroundColor(.brandNavy)
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
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill").font(.title3).foregroundColor(.red)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Authentication Error").font(.subheadline).fontWeight(.semibold).foregroundColor(.red)
                    Text(errorMessage).font(.caption).foregroundColor(.red.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button {
                    Haptics.light()
                    authManager.clearError()
                    appleSignInManager.errorMessage = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.title3).foregroundColor(.red.opacity(0.6))
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12).fill(Color.red.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.2), lineWidth: 1))
            )
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func performAuth() {
        guard !authManager.isLoading else { return }
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
        let emailValid = isValidEmail(email)
        let passwordValid = isValidPassword(password)
        let displayNameValid = isSignUpMode ? (displayName.isEmpty || isValidDisplayName(displayName)) : true
        let ageConfirmed = isSignUpMode ? confirmedAge : true

        return emailValid && passwordValid && displayNameValid && ageConfirmed
    }

}
