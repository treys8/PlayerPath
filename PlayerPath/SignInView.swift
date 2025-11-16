//
//  SignInView.swift
//  PlayerPath
//
//  Created by Assistant on 10/26/25.
//

import SwiftUI
import FirebaseAuth
import UIKit
import LocalAuthentication

fileprivate enum AuthField { case displayName, email, password }

struct SignInView: View {
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @StateObject private var appleSignInManager = AppleSignInManager()
    @StateObject private var biometricManager = BiometricAuthenticationManager()
    
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var isSignUp = false
    @State private var showingForgotPassword = false
    @State private var showingPrivacyPolicy = false
    @State private var showingTermsOfService = false
    @State private var showBiometricPrompt = false
    @State private var agreedToTerms = false
    
    @FocusState private var focusedField: AuthField?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 30) {
                    AppLogoSection()
                    
                    // Biometric Sign In (for returning users)
                    if !isSignUp && biometricManager.isBiometricEnabled {
                        BiometricSignInSection(
                            biometricManager: biometricManager,
                            onBiometricSignIn: performBiometricSignIn
                        )
                    }
                    
                    // Social Sign In Options
                    if !isSignUp {
                        SocialSignInSection(
                            appleSignInManager: appleSignInManager,
                            isLoading: authManager.isLoading || appleSignInManager.isLoading
                        )
                        
                        DividerWithText(text: "or")
                    }
                    
                    AuthenticationHeaderSection(isSignUp: isSignUp)
                    
                    AuthenticationFormSection(
                        email: $email,
                        password: $password,
                        displayName: $displayName,
                        isSignUp: isSignUp,
                        isLoading: authManager.isLoading,
                        focusedField: $focusedField
                    )
                    
                    FormValidationSummary(
                        email: email,
                        password: password,
                        displayName: displayName,
                        isSignUp: isSignUp
                    )
                    
                    // Terms Agreement for Sign Up
                    if isSignUp {
                        TermsAgreementSection(
                            agreedToTerms: $agreedToTerms,
                            showingPrivacyPolicy: $showingPrivacyPolicy,
                            showingTermsOfService: $showingTermsOfService
                        )
                    }
                    
                    AuthenticationButtonSection(
                        isSignUp: $isSignUp,
                        showingForgotPassword: $showingForgotPassword,
                        canSubmitForm: canSubmitForm(),
                        performAuth: performAuth,
                        onModeSwitched: {
                            // Clear fields when switching modes for better UX
                            email = ""
                            password = ""
                            displayName = ""
                            authManager.errorMessage = nil
                        }
                    )
                    
                    ErrorDisplaySection()
                    
                    Spacer(minLength: 0)
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationBarHidden(true)
            .onSubmit {
                switch focusedField {
                case .displayName:
                    focusedField = .email
                case .email:
                    focusedField = .password
                case .password, .none:
                    if canSubmitForm() && !authManager.isLoading { performAuth() }
                }
            }
        }
        .sheet(isPresented: $showingForgotPassword) {
            PasswordResetView()
        }
        .sheet(isPresented: $showingPrivacyPolicy) {
            PrivacyPolicyView()
        }
        .sheet(isPresented: $showingTermsOfService) {
            TermsOfServiceView()
        }
        .alert("Enable \(biometricManager.biometricTypeName)?", isPresented: $showBiometricPrompt) {
            Button("Enable") {
                enableBiometric()
            }
            Button("Not Now", role: .cancel) { }
        } message: {
            Text("Sign in faster next time using \(biometricManager.biometricTypeName).")
        }
        .onChange(of: authManager.errorMessage) { _, newValue in
            if newValue != nil {
                UIAccessibility.post(notification: .announcement, argument: "Authentication error")
                HapticManager.shared.error()
            }
        }
        .onChange(of: appleSignInManager.errorMessage) { _, newValue in
            if newValue != nil {
                authManager.errorMessage = newValue
                appleSignInManager.errorMessage = nil
            }
        }
        .onChange(of: email) { _, newValue in
            // Remove spaces and trim whitespace from email
            let cleaned = newValue.replacingOccurrences(of: " ", with: "")
            if cleaned != newValue {
                email = cleaned
            }
        }
        .onAppear {
            appleSignInManager.configure(with: authManager)
        }
    }
    
    // MARK: - Private Methods
    
    private func performAuth() {
        guard !authManager.isLoading else { return }
        
        HapticManager.shared.buttonTap()
        
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
                
                // Offer biometric enrollment for new sign-ins (not sign-ups)
                if !isSignUp && biometricManager.isBiometricAvailable && !biometricManager.isBiometricEnabled {
                    // Small delay so user sees success first
                    try? await Task.sleep(for: .milliseconds(500))
                    await MainActor.run {
                        // Only show if still signed in
                        if authManager.isSignedIn {
                            showBiometricPrompt = true
                        }
                    }
                }
            } else if authManager.errorMessage != nil {
                // Clear password on failed authentication for security
                await MainActor.run {
                    password = ""
                }
            }
        }
    }
    
    private func performBiometricSignIn() {
        HapticManager.shared.buttonTap()
        
        Task {
            if let credentials = await biometricManager.getBiometricCredentials() {
                await authManager.signIn(email: credentials.email, password: credentials.password)
                
                if authManager.isSignedIn {
                    HapticManager.shared.authenticationSuccess()
                }
            }
        }
    }
    
    private func enableBiometric() {
        Task {
            let success = await biometricManager.enableBiometric(email: email, password: password)
            if success {
                HapticManager.shared.success()
            }
        }
    }
    
    private func canSubmitForm() -> Bool {
        let formValid = FormValidator.shared.canSubmitSignInForm(
            email: email,
            password: password,
            displayName: displayName,
            isSignUp: isSignUp
        )
        
        // For sign up, also require terms agreement
        if isSignUp {
            return formValid && agreedToTerms
        }
        
        return formValid
    }
}

// MARK: - Component Views

private struct AppLogoSection: View {
    var body: some View {
        VStack {
            // Your custom PlayerPath logo with proper fallback
            Group {
                if let _ = UIImage(named: "PlayerPathLogo") {
                    Image("PlayerPathLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                        .cornerRadius(16)
                } else {
                    // Fallback to system icon if custom logo isn't found
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.blue.gradient)
                        .frame(width: 80, height: 80)
                }
            }
            
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
                .accessibilityAddTraits(.isHeader)
            
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
    let isLoading: Bool
    @FocusState.Binding var focusedField: AuthField?
    @State private var showPassword = false
    
    var body: some View {
        VStack(spacing: 20) {
            if isSignUp {
                TextField("Display Name", text: $displayName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .keyboardType(.default)
                    .textInputAutocapitalization(.words)
                    .accessibilityLabel("Display name")
                    .accessibilityHint("Enter your preferred display name")
                    .textContentType(.name)
                    .focused($focusedField, equals: .displayName)
                    .submitLabel(.next)
                    .disabled(isLoading)
                
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
                .textContentType(.username)
                .focused($focusedField, equals: .email)
                .submitLabel(.next)
                .disabled(isLoading)
            
            // Email validation feedback
            if !email.isEmpty {
                ValidationFeedbackView(
                    result: FormValidator.shared.validateEmail(email)
                )
            }
            
            HStack {
                Group {
                    if showPassword {
                        TextField("Password", text: $password)
                            .textContentType(isSignUp ? .newPassword : .password)
                    } else {
                        SecureField("Password", text: $password)
                            .textContentType(isSignUp ? .newPassword : .password)
                    }
                }
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .focused($focusedField, equals: .password)
                .submitLabel(.go)
                .disabled(isLoading)
                
                Button(action: { showPassword.toggle() }) {
                    Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                        .foregroundColor(.secondary)
                }
                .disabled(isLoading)
                .accessibilityLabel(showPassword ? "Hide password" : "Show password")
            }
            
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
                    ForEach(FormValidator.shared.getPasswordRequirements(for: password), id: \.text) { requirement in
                        ValidationRequirementRow(requirement: requirement)
                    }
                }
                .padding(.horizontal)
            }
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
    let onModeSwitched: () -> Void
    
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
            .accessibilityLabel(isSignUp ? "Create Account" : "Sign In")
            .accessibilityHint(isSignUp ? "Create a new PlayerPath account" : "Sign in to your account")
            
            Button(action: { 
                withAnimation(.easeInOut(duration: 0.3)) {
                    isSignUp.toggle()
                    onModeSwitched()
                }
            }) {
                Text(isSignUp ? "Already have an account? Sign In" : "Don't have an account? Sign Up")
                    .foregroundColor(.blue)
            }
            .accessibilityLabel(isSignUp ? "Switch to Sign In" : "Switch to Sign Up")
            
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

// MARK: - New Modern iOS Feature Components

private struct BiometricSignInSection: View {
    @ObservedObject var biometricManager: BiometricAuthenticationManager
    let onBiometricSignIn: () -> Void
    
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    
    var body: some View {
        VStack(spacing: 12) {
            Button(action: onBiometricSignIn) {
                HStack {
                    if authManager.isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: biometricManager.biometricType == .faceID ? "faceid" : "touchid")
                            .font(.title3)
                    }
                    Text("Sign in with \(biometricManager.biometricTypeName)")
                        .font(.system(size: 17, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .foregroundColor(.white)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [.blue, .blue.opacity(0.8)]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(10)
            }
            .disabled(authManager.isLoading)
            .accessibilityLabel("Sign in with \(biometricManager.biometricTypeName)")
            .accessibilityHint("Use biometric authentication to sign in quickly")
        }
    }
}

private struct SocialSignInSection: View {
    @ObservedObject var appleSignInManager: AppleSignInManager
    let isLoading: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            SignInWithAppleButton {
                appleSignInManager.signInWithApple()
            }
            .disabled(isLoading)
            .opacity(isLoading ? 0.6 : 1.0)
            
            // You can add more social sign-in options here
            // GoogleSignInButton(), FacebookSignInButton(), etc.
        }
    }
}

private struct DividerWithText: View {
    let text: String
    
    var body: some View {
        HStack {
            VStack { Divider() }
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
            VStack { Divider() }
        }
        .padding(.vertical, 8)
    }
}

private struct TermsAgreementSection: View {
    @Binding var agreedToTerms: Bool
    @Binding var showingPrivacyPolicy: Bool
    @Binding var showingTermsOfService: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            Toggle(isOn: $agreedToTerms) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("I agree to the Terms and Privacy Policy")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 4) {
                        Button("Terms of Service") {
                            showingTermsOfService = true
                        }
                        .font(.caption)
                        
                        Text("and")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Button("Privacy Policy") {
                            showingPrivacyPolicy = true
                        }
                        .font(.caption)
                    }
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: .blue))
            
            if !agreedToTerms {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                        .font(.caption)
                    Text("Please agree to continue")
                        .font(.caption2)
                        .foregroundColor(.blue)
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Privacy Policy & Terms Views

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Privacy Policy")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Last updated: November 10, 2025")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Divider()
                    
                    // Add your actual privacy policy content here
                    Group {
                        SectionHeader(title: "Information We Collect")
                        PolicyText(text: """
                        PlayerPath collects information you provide directly to us, including:
                        • Account information (name, email, password)
                        • Athletic performance data and statistics
                        • Videos and photos you upload
                        • Usage data and analytics
                        """)
                        
                        SectionHeader(title: "How We Use Your Information")
                        PolicyText(text: """
                        We use the information we collect to:
                        • Provide and improve our services
                        • Track and analyze your athletic performance
                        • Send you updates and notifications
                        • Respond to your requests and support inquiries
                        """)
                        
                        SectionHeader(title: "Data Security")
                        PolicyText(text: """
                        We implement appropriate security measures to protect your personal information. Your data is encrypted in transit and at rest.
                        """)
                        
                        SectionHeader(title: "Your Rights")
                        PolicyText(text: """
                        You have the right to:
                        • Access your personal data
                        • Request data deletion
                        • Export your data
                        • Opt-out of marketing communications
                        """)
                        
                        SectionHeader(title: "Contact Us")
                        PolicyText(text: """
                        If you have questions about this Privacy Policy, please contact us at:
                        privacy@playerpath.com
                        """)
                    }
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct TermsOfServiceView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Terms of Service")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Last updated: November 10, 2025")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Divider()
                    
                    // Add your actual terms of service content here
                    Group {
                        SectionHeader(title: "Acceptance of Terms")
                        PolicyText(text: """
                        By accessing or using PlayerPath, you agree to be bound by these Terms of Service. If you do not agree to these terms, please do not use our service.
                        """)
                        
                        SectionHeader(title: "User Accounts")
                        PolicyText(text: """
                        You are responsible for:
                        • Maintaining the confidentiality of your account
                        • All activities that occur under your account
                        • Providing accurate and complete information
                        """)
                        
                        SectionHeader(title: "Content Ownership")
                        PolicyText(text: """
                        You retain ownership of any content you upload to PlayerPath. By uploading content, you grant us a license to use, store, and display your content as necessary to provide our services.
                        """)
                        
                        SectionHeader(title: "Acceptable Use")
                        PolicyText(text: """
                        You agree not to:
                        • Violate any laws or regulations
                        • Upload harmful or offensive content
                        • Interfere with the service's operation
                        • Attempt to access other users' accounts
                        """)
                        
                        SectionHeader(title: "Termination")
                        PolicyText(text: """
                        We reserve the right to suspend or terminate your account if you violate these Terms of Service or engage in harmful behavior.
                        """)
                        
                        SectionHeader(title: "Contact")
                        PolicyText(text: """
                        Questions about these Terms? Contact us at:
                        legal@playerpath.com
                        """)
                    }
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Policy View Helpers

private struct SectionHeader: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(.headline)
            .fontWeight(.semibold)
            .padding(.top, 8)
    }
}

private struct PolicyText: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

