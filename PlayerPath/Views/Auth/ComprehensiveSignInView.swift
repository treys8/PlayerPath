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

    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                // Header
                VStack(spacing: 16) {
                    Text(isSignUpMode ? "Create Account" : "Sign In")
                        .font(.title)
                        .fontWeight(.bold)

                    Text(isSignUpMode ? (selectedRole == .athlete ? "Join PlayerPath to track your baseball journey" : "Join PlayerPath to coach your athletes") : "Welcome back to PlayerPath")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top)

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
                    .padding(.horizontal)
                }

                VStack(spacing: 20) {
                    if isSignUpMode {
                        TextField("Display Name", text: $displayName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .accessibilityLabel("Display name")
                            .accessibilityHint("Enter your preferred display name")

                        // Display name validation
                        if !displayName.isEmpty {
                            HStack {
                                Image(systemName: isValidDisplayName(displayName) ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundColor(isValidDisplayName(displayName) ? .green : .orange)
                                    .font(.caption)
                                Text(getDisplayNameValidationMessage(displayName))
                                    .font(.caption2)
                                    .foregroundColor(isValidDisplayName(displayName) ? .green : .orange)
                                Spacer()
                            }
                            .padding(.horizontal)
                        }
                    }

                    TextField("Email", text: $email)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .accessibilityLabel("Email address")
                        .accessibilityHint("Enter your email address")
                        .onSubmit {
                            if canSubmitForm() && !authManager.isLoading {
                                performAuth()
                            }
                        }
                        .submitLabel(isSignUpMode ? .next : .go)

                    // Email validation feedback
                    if !email.isEmpty {
                        HStack {
                            Image(systemName: isValidEmail(email) ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(isValidEmail(email) ? .green : .orange)
                                .font(.caption)
                            Text(isValidEmail(email) ? "Valid email format" : "Please enter a valid email address")
                                .font(.caption2)
                                .foregroundColor(isValidEmail(email) ? .green : .orange)
                            Spacer()
                        }
                        .padding(.horizontal)
                    }

                    SecureField("Password", text: $password)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .keyboardType(.asciiCapable)
                        .accessibilityLabel("Password")
                        .accessibilityHint("Enter your password")
                        .onSubmit {
                            if canSubmitForm() && !authManager.isLoading {
                                performAuth()
                            }
                        }
                        .submitLabel(.go)

                    // Password validation feedback
                    if !password.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: isValidPassword(password) ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundColor(isValidPassword(password) ? .green : .orange)
                                    .font(.caption)
                                Text(isValidPassword(password) ? "Strong password" : "Password requirements:")
                                    .font(.caption2)
                                    .foregroundColor(isValidPassword(password) ? .green : .orange)
                                Spacer()
                            }

                            if !isValidPassword(password) && isSignUpMode {
                                VStack(alignment: .leading, spacing: 2) {
                                    ValidationRequirement(
                                        text: "At least 8 characters",
                                        isMet: password.count >= 8
                                    )
                                    ValidationRequirement(
                                        text: "Contains uppercase letter",
                                        isMet: password.range(of: "[A-Z]", options: .regularExpression) != nil
                                    )
                                    ValidationRequirement(
                                        text: "Contains lowercase letter",
                                        isMet: password.range(of: "[a-z]", options: .regularExpression) != nil
                                    )
                                    ValidationRequirement(
                                        text: "Contains number",
                                        isMet: password.range(of: "[0-9]", options: .regularExpression) != nil
                                    )
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                // Form validation summary
                if !email.isEmpty || !password.isEmpty || (isSignUpMode && !displayName.isEmpty) {
                    HStack {
                        Image(systemName: canSubmitForm() ? "checkmark.circle.fill" : "info.circle.fill")
                            .foregroundColor(canSubmitForm() ? .green : .blue)
                            .font(.caption)

                        Text(getFormValidationSummary())
                            .font(.caption2)
                            .foregroundColor(canSubmitForm() ? .green : .blue)

                        Spacer()
                    }
                    .padding(.horizontal)
                }

                VStack(spacing: 15) {
                    Button(action: { Haptics.light(); performAuth() }) {
                        HStack {
                            if authManager.isLoading {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            }
                            Text(authManager.isLoading ? (isSignUpMode ? "Creating Account..." : "Signing In...") : (isSignUpMode ? "Create Account" : "Sign In"))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSubmitForm() || authManager.isLoading)

                    if !isSignUpMode {
                        Button("Forgot Password?") {
                            showingResetPasswordSheet = true
                        }
                        .foregroundColor(.gray)
                    }
                }

                if let errorMessage = authManager.errorMessage {
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                                .font(.caption)
                            Text("Authentication Error")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.red)
                            Spacer()

                            Button("Dismiss") {
                                authManager.clearError()
                            }
                            .font(.caption2)
                            .foregroundColor(.red)
                        }

                        Text(errorMessage)
                            .font(.caption2)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal)
                }

                Spacer()
            }
            .padding()
            .navigationTitle(isSignUpMode ? "Create Account" : "Sign In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
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
