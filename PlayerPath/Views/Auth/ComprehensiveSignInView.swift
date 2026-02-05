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

    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var showingForgotPassword = false
    @State private var showingResetPasswordSheet = false
    @State private var selectedRole: UserRole = .athlete

    // Computed validation states
    private var emailValidationState: FieldValidationState {
        guard !email.isEmpty else { return .idle }
        return isValidEmail(email) ? .valid : .invalid
    }

    private var passwordValidationState: FieldValidationState {
        guard !password.isEmpty else { return .idle }
        return isValidPassword(password) ? .valid : .warning
    }

    private var displayNameValidationState: FieldValidationState {
        guard !displayName.isEmpty else { return .idle }
        return isValidDisplayName(displayName) ? .valid : .warning
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    // Header with icon
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [.blue.opacity(0.2), .blue.opacity(0.05)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 80, height: 80)

                            Image(systemName: isSignUpMode ? "person.crop.circle.badge.plus" : "person.crop.circle.fill")
                                .font(.system(size: 36, weight: .medium))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.blue, .blue.opacity(0.7)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }

                        VStack(spacing: 8) {
                            Text(isSignUpMode ? "Create Account" : "Welcome Back")
                                .font(.title2)
                                .fontWeight(.bold)

                            Text(isSignUpMode ? (selectedRole == .athlete ? "Join PlayerPath to track your baseball journey" : "Join PlayerPath to coach your athletes") : "Sign in to continue to PlayerPath")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.top, 8)

                    // Role Selection (Sign Up only)
                    if isSignUpMode {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("I am a:")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)

                            HStack(spacing: 12) {
                                RoleSelectionButton(
                                    role: .athlete,
                                    isSelected: selectedRole == .athlete,
                                    icon: "figure.baseball",
                                    title: "Athlete",
                                    description: "Track my progress"
                                ) {
                                    Haptics.light()
                                    selectedRole = .athlete
                                }

                                RoleSelectionButton(
                                    role: .coach,
                                    isSelected: selectedRole == .coach,
                                    icon: "person.2.fill",
                                    title: "Coach",
                                    description: "Work with athletes"
                                ) {
                                    Haptics.light()
                                    selectedRole = .coach
                                }
                            }
                        }
                    }

                    // Form Fields
                    VStack(spacing: 16) {
                        if isSignUpMode {
                            ModernTextField(
                                placeholder: "Your name",
                                text: $displayName,
                                icon: "person.fill",
                                textContentType: .name,
                                autocapitalization: .words,
                                validationState: displayNameValidationState
                            )
                            .accessibilityLabel("Display name")
                            .accessibilityHint("Enter your preferred display name")
                        }

                        ModernTextField(
                            placeholder: "you@example.com",
                            text: $email,
                            icon: "envelope.fill",
                            keyboardType: .emailAddress,
                            textContentType: .emailAddress,
                            autocapitalization: .never,
                            validationState: emailValidationState,
                            onSubmit: {
                                if canSubmitForm() && !authManager.isLoading {
                                    performAuth()
                                }
                            }
                        )
                        .accessibilityLabel("Email address")
                        .accessibilityHint("Enter your email address")

                        ModernTextField(
                            placeholder: "Password",
                            text: $password,
                            icon: "lock.fill",
                            isSecure: true,
                            textContentType: isSignUpMode ? .newPassword : .password,
                            autocapitalization: .never,
                            validationState: passwordValidationState,
                            onSubmit: {
                                if canSubmitForm() && !authManager.isLoading {
                                    performAuth()
                                }
                            }
                        )
                        .accessibilityLabel("Password")
                        .accessibilityHint("Enter your password")

                        // Password strength indicator for sign up
                        if isSignUpMode && !password.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                PasswordStrengthIndicator(password: password)

                                if !isValidPassword(password) {
                                    PasswordRequirementsList(password: password)
                                        .padding(.top, 4)
                                }
                            }
                            .padding(.horizontal, 4)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: password.isEmpty)

                    // Action Buttons
                    VStack(spacing: 16) {
                        Button(action: { Haptics.medium(); performAuth() }) {
                            HStack(spacing: 10) {
                                if authManager.isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.9)
                                } else {
                                    Image(systemName: isSignUpMode ? "arrow.right.circle.fill" : "arrow.forward.circle.fill")
                                        .font(.title3)
                                }
                                Text(authManager.isLoading ? (isSignUpMode ? "Creating Account..." : "Signing In...") : (isSignUpMode ? "Create Account" : "Sign In"))
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(
                                LinearGradient(
                                    colors: canSubmitForm() && !authManager.isLoading
                                        ? [.blue, .blue.opacity(0.85)]
                                        : [Color(.systemGray4), Color(.systemGray4)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .foregroundColor(.white)
                            .cornerRadius(14)
                            .shadow(
                                color: canSubmitForm() && !authManager.isLoading ? .blue.opacity(0.3) : .clear,
                                radius: 8,
                                x: 0,
                                y: 4
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSubmitForm() || authManager.isLoading)

                        if !isSignUpMode {
                            Button {
                                Haptics.light()
                                showingResetPasswordSheet = true
                            } label: {
                                Text("Forgot Password?")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.blue)
                            }
                        }
                    }

                    // Error Message
                    if let errorMessage = authManager.errorMessage {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.title3)
                                .foregroundColor(.red)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Authentication Error")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.red)

                                Text(errorMessage)
                                    .font(.caption)
                                    .foregroundColor(.red.opacity(0.8))
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer()

                            Button {
                                Haptics.light()
                                authManager.clearError()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title3)
                                    .foregroundColor(.red.opacity(0.6))
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.red.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.red.opacity(0.2), lineWidth: 1)
                                )
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
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
        }
        .sheet(isPresented: $showingResetPasswordSheet) {
            ResetPasswordSheet(email: $email)
        }
        // Auto-dismiss on successful authentication
        .onChange(of: authManager.isSignedIn) { _, isSignedIn in
            if isSignedIn {
                // Add small delay to ensure view hierarchy is stable before dismissing
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(100))
                    dismiss()
                }
            }
        }
    }

    private func performAuth() {
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
        Validation.isValidEmail(email)
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

    private func getDisplayNameValidationMessage(_ name: String) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedName.isEmpty {
            return "Name cannot be empty"
        } else if trimmedName.count < 2 {
            return "Name must be at least 2 characters"
        } else if trimmedName.count > 30 {
            return "Name must be 30 characters or less"
        } else if Validation.isValidPersonName(trimmedName, min: 2, max: 30) {
            return "Valid display name"
        } else {
            return "Name can only contain letters, spaces, periods, hyphens, and apostrophes"
        }
    }

    private func canSubmitForm() -> Bool {
        let emailValid = isValidEmail(email)
        let passwordValid = isValidPassword(password)
        let displayNameValid = isSignUpMode ? (displayName.isEmpty || isValidDisplayName(displayName)) : true

        return emailValid && passwordValid && displayNameValid
    }

    private func getFormValidationSummary() -> String {
        var requirements: [(String, Bool)] = [
            ("Valid email", isValidEmail(email)),
            ("Valid password", isValidPassword(password))
        ]

        if isSignUpMode {
            requirements.append(("Valid display name", displayName.isEmpty || isValidDisplayName(displayName)))
        }

        let metCount = requirements.filter { $0.1 }.count
        let totalCount = requirements.count

        if metCount == totalCount {
            return "Ready to \(isSignUpMode ? "create account" : "sign in")!"
        } else {
            return "\(metCount) of \(totalCount) requirements met"
        }
    }
}
