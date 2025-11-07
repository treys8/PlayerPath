//
//  SignInView.swift
//  PlayerPath
//
//  Created by Assistant on 10/26/25.
//

import SwiftUI
import FirebaseAuth

struct SignInView: View {
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var isSignUp = false
    @State private var showingForgotPassword = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                AppLogoSection()
                
                AuthenticationHeaderSection(isSignUp: isSignUp)
                
                AuthenticationFormSection(
                    email: $email,
                    password: $password,
                    displayName: $displayName,
                    isSignUp: isSignUp
                )
                
                FormValidationSummary(
                    email: email,
                    password: password,
                    displayName: displayName,
                    isSignUp: isSignUp
                )
                
                AuthenticationButtonSection(
                    isSignUp: $isSignUp,
                    showingForgotPassword: $showingForgotPassword,
                    canSubmitForm: canSubmitForm(),
                    performAuth: performAuth
                )
                
                ErrorDisplaySection()
                
                Spacer()
            }
            .padding()
            .navigationBarHidden(true)
        }
        .alert("Reset Password", isPresented: $showingForgotPassword) {
            TextField("Email", text: $email)
            Button("Send Reset Email") {
                Task {
                    await authManager.resetPassword(email: email)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Enter your email address to receive a password reset link.")
        }
    }
    
    // MARK: - Private Methods
    
    private func performAuth() {
        Task {
            let normalizedEmail = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if isSignUp {
                await authManager.signUp(
                    email: normalizedEmail,
                    password: password,
                    displayName: trimmedDisplayName.isEmpty ? nil : trimmedDisplayName
                )
            } else {
                await authManager.signIn(email: normalizedEmail, password: password)
            }
            
            if authManager.isSignedIn {
                HapticManager.shared.authenticationSuccess()
            }
        }
    }
    
    private func canSubmitForm() -> Bool {
        FormValidator.shared.canSubmitSignInForm(
            email: email,
            password: password,
            displayName: displayName,
            isSignUp: isSignUp
        )
    }
}

// MARK: - Component Views

private struct AppLogoSection: View {
    var body: some View {
        VStack {
            Image(systemName: "diamond.fill")
                .font(.system(size: 80))
                .foregroundColor(.blue)
            
            Text("PlayerPath")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Text("Your Baseball Journey Starts Here")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.bottom, 20)
    }
}

private struct AuthenticationHeaderSection: View {
    let isSignUp: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            Text(isSignUp ? "Create Account" : "Sign In")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(isSignUp ? "Join PlayerPath to track your baseball journey" : "Welcome back to PlayerPath")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

private struct AuthenticationFormSection: View {
    @Binding var email: String
    @Binding var password: String
    @Binding var displayName: String
    let isSignUp: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            if isSignUp {
                TextField("Display Name", text: $displayName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .accessibilityLabel("Display name")
                    .accessibilityHint("Enter your preferred display name")
                
                // Display name validation
                if !displayName.isEmpty {
                    ValidationFeedbackView(
                        result: FormValidator.shared.validateDisplayName(displayName)
                    )
                }
            }
            
            TextField("Email", text: $email)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .accessibilityLabel("Email address")
                .accessibilityHint("Enter your email address")
                .submitLabel(.next)
            
            // Email validation feedback
            if !email.isEmpty {
                ValidationFeedbackView(
                    result: FormValidator.shared.validateEmail(email)
                )
            }
            
            SecureField("Password", text: $password)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .accessibilityLabel("Password")
                .accessibilityHint("Enter your password")
                .submitLabel(.go)
            
            // Password validation feedback
            if !password.isEmpty {
                if isSignUp {
                    PasswordValidationView(password: password)
                } else {
                    ValidationFeedbackView(
                        result: FormValidator.shared.validatePasswordBasic(password)
                    )
                }
            }
        }
    }
}

private struct ValidationFeedbackView: View {
    let result: ValidationResult
    
    var body: some View {
        HStack {
            Image(systemName: result.isValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(result.isValid ? .green : .orange)
                .font(.caption)
            Text(result.message)
                .font(.caption2)
                .foregroundColor(result.isValid ? .green : .orange)
            Spacer()
        }
        .padding(.horizontal)
    }
}

private struct PasswordValidationView: View {
    let password: String
    
    var body: some View {
        let result = FormValidator.shared.validatePasswordStrong(password)
        
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: result.isValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(result.isValid ? .green : .orange)
                    .font(.caption)
                Text(result.isValid ? "Strong password" : "Password requirements:")
                    .font(.caption2)
                    .foregroundColor(result.isValid ? .green : .orange)
                Spacer()
            }
            .padding(.horizontal)
            
            if !result.isValid {
                VStack(alignment: .leading, spacing: 2) {
                    PasswordRequirement(
                        text: "At least 8 characters",
                        isMet: password.count >= 8
                    )
                    PasswordRequirement(
                        text: "Contains uppercase letter",
                        isMet: password.range(of: "[A-Z]", options: .regularExpression) != nil
                    )
                    PasswordRequirement(
                        text: "Contains lowercase letter",
                        isMet: password.range(of: "[a-z]", options: .regularExpression) != nil
                    )
                    PasswordRequirement(
                        text: "Contains number",
                        isMet: password.range(of: "[0-9]", options: .regularExpression) != nil
                    )
                }
                .padding(.horizontal)
            }
        }
    }
}

private struct PasswordRequirement: View {
    let text: String
    let isMet: Bool
    
    var body: some View {
        HStack {
            Image(systemName: isMet ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isMet ? .green : .gray)
                .font(.caption2)
            Text(text)
                .font(.caption2)
                .foregroundColor(isMet ? .green : .gray)
        }
    }
}

private struct FormValidationSummary: View {
    let email: String
    let password: String
    let displayName: String
    let isSignUp: Bool
    
    var body: some View {
        if !email.isEmpty || !password.isEmpty || (isSignUp && !displayName.isEmpty) {
            HStack {
                Image(systemName: canSubmitForm ? "checkmark.circle.fill" : "info.circle.fill")
                    .foregroundColor(canSubmitForm ? .green : .blue)
                    .font(.caption)
                
                Text(getFormValidationSummary())
                    .font(.caption2)
                    .foregroundColor(canSubmitForm ? .green : .blue)
                
                Spacer()
            }
            .padding(.horizontal)
        }
    }
    
    private var canSubmitForm: Bool {
        FormValidator.shared.canSubmitSignInForm(
            email: email,
            password: password,
            displayName: displayName,
            isSignUp: isSignUp
        )
    }
    
    private func getFormValidationSummary() -> String {
        let requirements = [
            ("Valid email", FormValidator.shared.validateEmail(email).isValid),
            ("Strong password", isSignUp ? FormValidator.shared.validatePasswordStrong(password).isValid : FormValidator.shared.validatePasswordBasic(password).isValid),
            ("Valid display name", isSignUp ? (displayName.isEmpty || FormValidator.shared.validateDisplayName(displayName).isValid) : true)
        ]
        
        let metCount = requirements.filter { $0.1 }.count
        let totalCount = isSignUp ? 3 : 2
        
        if metCount == totalCount {
            return "Ready to \(isSignUp ? "create account" : "sign in")!"
        } else {
            return "\(metCount) of \(totalCount) requirements met"
        }
    }
}

private struct AuthenticationButtonSection: View {
    @Binding var isSignUp: Bool
    @Binding var showingForgotPassword: Bool
    let canSubmitForm: Bool
    let performAuth: () -> Void
    
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    
    var body: some View {
        VStack(spacing: 15) {
            Button(action: performAuth) {
                HStack {
                    if authManager.isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    }
                    Text(authManager.isLoading ? (isSignUp ? "Creating Account..." : "Signing In...") : (isSignUp ? "Create Account" : "Sign In"))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSubmitForm || authManager.isLoading)
            
            Button(action: { isSignUp.toggle() }) {
                Text(isSignUp ? "Already have an account? Sign In" : "Don't have an account? Sign Up")
                    .foregroundColor(.blue)
            }
            
            if !isSignUp {
                Button("Forgot Password?") {
                    showingForgotPassword = true
                }
                .foregroundColor(.gray)
            }
        }
    }
}

private struct ErrorDisplaySection: View {
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    
    var body: some View {
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
                        authManager.errorMessage = nil
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
    }
}