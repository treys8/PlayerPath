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
    @State private var selectedRole: UserRole = .athlete
    @State private var showSuccessAnimation = false
    @State private var shakeOffset: CGFloat = 0
    @State private var showCoachOnboarding = false
    @State private var showAthleteOnboarding = false
    
    @FocusState private var focusedField: AuthField?
    
    // Task management for proper cancellation
    @State private var authTask: Task<Void, Never>?
    @State private var biometricTask: Task<Void, Never>?
    
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
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
                        SocialSignInSection(
                            appleSignInManager: appleSignInManager,
                            isLoading: authManager.isLoading || appleSignInManager.isLoading,
                            isSignUp: isSignUp
                        )
                        
                        DividerWithText(text: "or")
                        
                        // Role Selection FIRST (for sign up)
                        if isSignUp {
                            RoleSelectionSection(selectedRole: $selectedRole)
                        }
                        
                        AuthenticationHeaderSection(isSignUp: isSignUp, selectedRole: selectedRole)
                        
                        AuthenticationFormSection(
                            email: $email,
                            password: $password,
                            displayName: $displayName,
                            isSignUp: isSignUp,
                            isLoading: authManager.isLoading,
                            focusedField: $focusedField
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
                                // Keep role selection - user might have chosen deliberately
                                authManager.errorMessage = nil
                            }
                        )
                        .id("submitButton")
                        
                        ErrorDisplaySection()
                        
                        Spacer(minLength: 0)
                    }
                    .padding()
                }
                .onChange(of: focusedField) { _, newValue in
                    // Scroll to show submit button when on last field
                    if newValue == .password {
                        Task {
                            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
                            guard !Task.isCancelled else { return }
                            await MainActor.run {
                                withAnimation {
                                    proxy.scrollTo("submitButton", anchor: .bottom)
                                }
                            }
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationBarHidden(true)
            .offset(x: shakeOffset)
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
            // Loading overlay
            .overlay {
                if authManager.isLoading {
                    ZStack {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                        
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(.white)
                            Text(isSignUp ? "Creating your account..." : "Signing in...")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                        .padding(32)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .shadow(radius: 20)
                    }
                    .transition(.opacity)
                }
            }
            // Success animation overlay
            .overlay {
                if showSuccessAnimation {
                    ZStack {
                        Color.green.opacity(0.95)
                            .ignoresSafeArea()
                        
                        VStack(spacing: 20) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 80))
                                .foregroundColor(.white)
                            Text(isSignUp ? "Welcome to PlayerPath!" : "Welcome back!")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                    }
                    .transition(.scale.combined(with: .opacity))
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
        .fullScreenCover(isPresented: $showCoachOnboarding) {
            CoachOnboardingView(onFinish: {
                showCoachOnboarding = false
                // Navigation to coach dashboard handled automatically by MainAppView
                // based on authManager.userRole == .coach
            })
            .environmentObject(authManager)
        }
        .fullScreenCover(isPresented: $showAthleteOnboarding) {
            AthleteOnboardingView(onFinish: {
                showAthleteOnboarding = false
                // Navigation to athlete tabs handled automatically by MainAppView
                // based on authManager.userRole == .athlete
            })
            .environmentObject(authManager)
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
                // Shake animation on error
                Task {
                    await performShakeAnimation()
                }

                UIAccessibility.post(notification: .announcement, argument: "Authentication error")
                Haptics.error()
            }
        }
        .onChange(of: appleSignInManager.errorMessage) { _, newValue in
            if newValue != nil {
                authManager.errorMessage = newValue
                appleSignInManager.errorMessage = nil
            }
        }
        // Note: Email cleaning is handled in performAuth() to avoid onChange loops
        .onAppear {
            appleSignInManager.configure(with: authManager)
        }
        .onDisappear {
            // Cancel any in-flight tasks to prevent memory leaks and unwanted side effects
            authTask?.cancel()
            biometricTask?.cancel()
            // Clear the reference to authManager to prevent potential retain cycles
            appleSignInManager.cleanup()
        }
    }
    
    // MARK: - Private Methods

    private enum AnimationTiming {
        static let successDelayNanoseconds: UInt64 = 1_200_000_000 // 1.2 seconds
        static let biometricPromptDelayNanoseconds: UInt64 = 1_500_000_000 // 1.5 seconds
        static let shakeStepNanoseconds: UInt64 = 100_000_000 // 0.1 seconds
        static let authTimeoutNanoseconds: UInt64 = 30_000_000_000 // 30 seconds
    }

    @MainActor
    private func withTimeout<T>(nanoseconds: UInt64, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: nanoseconds)
                throw CancellationError()
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    @MainActor
    private func performShakeAnimation() async {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.3)) {
            shakeOffset = 10
        }
        try? await Task.sleep(nanoseconds: AnimationTiming.shakeStepNanoseconds)
        guard !Task.isCancelled else { return }

        withAnimation(.spring(response: 0.2, dampingFraction: 0.3)) {
            shakeOffset = -10
        }
        try? await Task.sleep(nanoseconds: AnimationTiming.shakeStepNanoseconds)
        guard !Task.isCancelled else { return }

        withAnimation(.spring(response: 0.2, dampingFraction: 0.3)) {
            shakeOffset = 0
        }
    }
    
    private func performAuth() {
        guard !authManager.isLoading else { return }

        // Cancel any existing auth task
        authTask?.cancel()

        // Clean email thoroughly once before submission
        email = email.replacingOccurrences(of: " ", with: "")
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        Haptics.light()

        print("🔐 Starting authentication - isSignUp: \(isSignUp), role: \(selectedRole.rawValue)")

        authTask = Task {
            defer { authTask = nil }
            // Check for cancellation early
            guard !Task.isCancelled else { return }

            let normalizedEmail = email
            let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            
            do {
                // Wrap authentication in timeout to prevent hanging on network issues
                try await withTimeout(nanoseconds: AnimationTiming.authTimeoutNanoseconds) {
                    if isSignUp {
                        // Route to appropriate sign-up method based on selected role
                        print("🔵 Signing up as \(selectedRole.rawValue) with email: \(normalizedEmail)")

                        if selectedRole == .coach {
                            await authManager.signUpAsCoach(
                                email: normalizedEmail,
                                password: password,
                                displayName: trimmedDisplayName.isEmpty ? normalizedEmail : trimmedDisplayName
                            )
                        } else {
                            await authManager.signUp(
                                email: normalizedEmail,
                                password: password,
                                displayName: trimmedDisplayName.isEmpty ? nil : trimmedDisplayName
                            )
                        }
                    } else {
                        print("🔵 Signing in with email: \(normalizedEmail)")
                        await authManager.signIn(email: normalizedEmail, password: password)
                    }
                }
            } catch {
                // Timeout or other error
                await MainActor.run {
                    authManager.errorMessage = "Request timed out. Please check your connection and try again."
                }
                return
            }
            
            // Check for cancellation after auth completes
            guard !Task.isCancelled else { return }
            
            if authManager.isSignedIn {
                print("✅ Authentication successful - userRole: \(authManager.userRole.rawValue)")
                print("📋 User profile loaded: \(authManager.userProfile != nil)")
                if let profile = authManager.userProfile {
                    print("📋 Profile role from Firestore: \(profile.userRole.rawValue)")
                }

                // Clear password immediately for security (both signup and signin)
                await MainActor.run {
                    password = ""
                }

                // Show success animation
                await MainActor.run {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                        showSuccessAnimation = true
                    }
                }

                Haptics.success()

                // Decide which onboarding to show based on the loaded profile role when available
                if isSignUp {
                    // Prefer the role from the authenticated profile if present; fallback to the selected role
                    let effectiveRole: UserRole = authManager.userProfile?.userRole ?? authManager.userRole
                    // Small delay so the success animation is perceived
                    try? await Task.sleep(nanoseconds: AnimationTiming.successDelayNanoseconds)

                    // Check cancellation after sleep
                    guard !Task.isCancelled else { return }

                    await MainActor.run {
                        guard authManager.isSignedIn else { return }
                        switch effectiveRole {
                        case .coach:
                            showCoachOnboarding = true
                        case .athlete:
                            showAthleteOnboarding = true
                        }
                    }
                }
                
                // Offer biometric enrollment for new sign-ins (not sign-ups)
                if !isSignUp && biometricManager.isBiometricAvailable && !biometricManager.isBiometricEnabled {
                    // Small delay so user sees success first
                    try? await Task.sleep(nanoseconds: AnimationTiming.biometricPromptDelayNanoseconds)
                    
                    // Check cancellation after sleep
                    guard !Task.isCancelled else { return }
                    
                    await MainActor.run {
                        // Only show if still signed in
                        if authManager.isSignedIn {
                            showBiometricPrompt = true
                        }
                    }
                }
            } else if authManager.errorMessage != nil {
                print("❌ Authentication failed: \(authManager.errorMessage ?? "unknown")")
                // Clear password on failed authentication for security
                await MainActor.run {
                    password = ""
                }
            }
        }
    }
    
    private func performBiometricSignIn() {
        Haptics.light()

        // Cancel any existing biometric task
        biometricTask?.cancel()
        
        biometricTask = Task {
            defer { biometricTask = nil }
            guard !Task.isCancelled else { return }
            
            if let credentials = await biometricManager.getBiometricCredentials() {
                guard !Task.isCancelled else { return }
                
                await authManager.signIn(email: credentials.email, password: credentials.password)
                
                guard !Task.isCancelled else { return }
                
                if authManager.isSignedIn {
                    Haptics.success()
                }
            }
        }
    }

    private func enableBiometric() {
        Task {
            let success = await biometricManager.enableBiometric(email: email, password: password)
            if success {
                Haptics.success()
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
    let selectedRole: UserRole
    
    var body: some View {
        VStack(spacing: 16) {
            Text(isSignUp ? "Create Account" : "Sign In")
                .font(.title2)
                .fontWeight(.semibold)
                .accessibilityAddTraits(.isHeader)
            
            if isSignUp {
                Text(selectedRole == .athlete ? "Join PlayerPath as an athlete to track your baseball journey" : "Join PlayerPath as a coach to review shared folders and provide feedback — coaches don’t create athletes")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .animation(.easeInOut, value: selectedRole)
            } else {
                Text("Welcome back to PlayerPath")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
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
                TextField("Your Name", text: $displayName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .keyboardType(.default)
                    .textInputAutocapitalization(.words)
                    .accessibilityLabel("Your name")
                    .accessibilityHint("Enter your full name")
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
                .animation(.easeInOut(duration: 0.2), value: email)
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
                
                Button(action: {
                    showPassword.toggle()
                    // Announce password visibility change for accessibility
                    UIAccessibility.post(
                        notification: .announcement,
                        argument: showPassword ? "Password visible" : "Password hidden"
                    )
                    Haptics.selection()
                }) {
                    Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                        .foregroundColor(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
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
                .font(.subheadline)
                .foregroundColor(.blue)
                .padding(.top, 4)
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
    let isSignUp: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            SignInWithAppleButton(isSignUp: isSignUp) {
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
            .toggleStyle(SwitchToggleStyle(tint: .green))
            
            if !agreedToTerms {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                    Text("You must agree to continue")
                        .font(.caption2)
                        .foregroundColor(.red)
                    Spacer()
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(agreedToTerms ? Color.green.opacity(0.1) : Color.red.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(agreedToTerms ? Color.green.opacity(0.3) : Color.red.opacity(0.3), lineWidth: 2)
        )
        .animation(.easeInOut(duration: 0.3), value: agreedToTerms)
    }
}

private struct RoleSelectionSection: View {
    @Binding var selectedRole: UserRole
    
    var body: some View {
        VStack(spacing: 12) {
            roleSelectionHeader
            
            VStack(spacing: 12) {
                RoleOptionButton(
                    role: .athlete,
                    title: "Athlete",
                    description: "Track your performance, games, and progress",
                    icon: "figure.baseball",
                    accentColor: .blue,
                    isSelected: selectedRole == .athlete,
                    onSelect: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedRole = .athlete
                        }
                        Haptics.selection()
                    }
                )

                RoleOptionButton(
                    role: .coach,
                    title: "Coach",
                    description: "View and provide feedback on athlete videos",
                    icon: "person.fill.checkmark",
                    accentColor: .green,
                    isSelected: selectedRole == .coach,
                    onSelect: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedRole = .coach
                        }
                        Haptics.selection()
                    }
                )
            }
        }
        .padding(.vertical)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    private var roleSelectionHeader: some View {
        HStack {
            Image(systemName: "person.2.fill")
                .foregroundColor(.blue)
                .font(.title3)
            Text("Choose your role:")
                .font(.headline)
                .fontWeight(.semibold)
            Spacer()
        }
        .padding(.horizontal)
    }
}

private struct RoleOptionButton: View {
    let role: UserRole
    let title: String
    let description: String
    let icon: String
    let accentColor: Color
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            buttonContent
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint("Sign up as \(title.lowercased())")
        .accessibility(addTraits: isSelected ? [.isButton, .isSelected] : [.isButton])
        .accessibility(value: Text(isSelected ? "Selected" : "Not selected"))
    }
    
    private var buttonContent: some View {
        HStack(spacing: 12) {
            selectionIndicator
            roleDetails
            Spacer()
            roleIcon
        }
        .padding()
        .background(backgroundStyle)
        .overlay(borderStyle)
    }
    
    private var selectionIndicator: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundColor(isSelected ? accentColor : .gray)
    }
    
    private var roleDetails: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    private var roleIcon: some View {
        Image(systemName: icon)
            .font(.title2)
            .foregroundColor(isSelected ? accentColor : .gray)
    }
    
    private var backgroundStyle: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(isSelected ? accentColor.opacity(0.1) : Color(.tertiarySystemBackground))
    }
    
    private var borderStyle: some View {
        RoundedRectangle(cornerRadius: 12)
            .stroke(isSelected ? accentColor : Color.clear, lineWidth: 2)
    }
}

// MARK: - Coach Onboarding View

private struct CoachOnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    let onFinish: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 12) {
                        Image(systemName: "person.fill.checkmark")
                            .font(.largeTitle)
                            .foregroundStyle(.green)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Welcome, Coach")
                                .font(.title)
                                .fontWeight(.bold)
                                .accessibilityAddTraits(.isHeader)
                            Text("Here's how PlayerPath works for coaches")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }

                    Group {
                        onboardingCard(
                            title: "Review shared folders",
                            message: "You’ll see only folders that athletes share with you. Open a folder to watch videos and view notes.",
                            icon: "folder.shared")

                        onboardingCard(
                            title: "Provide feedback",
                            message: "Leave time-stamped comments and notes on athlete videos to help them improve.",
                            icon: "text.bubble.fill")

                        onboardingCard(
                            title: "No athlete creation",
                            message: "Coaches don’t create athletes or manage their profiles. Athletes control what they share with you.",
                            icon: "person.crop.circle.badge.xmark")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Next: Shared Folders")
                            .font(.headline)
                        Text("Continue to see folders that have been shared with you. If you don’t see any yet, ask your athletes to share.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Button(action: finish) {
                        Text("Continue to Shared Folders")
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
                    .accessibilityLabel("Continue to Shared Folders")
                    .accessibilityHint("Complete onboarding and view shared folders from athletes")
                }
                .padding()
            }
            .navigationTitle("Coach Onboarding")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { finish() }
                }
            }
        }
    }

    private func finish() {
        Haptics.success()
        onFinish()
        // Don't call dismiss() - the binding change in onFinish() automatically dismisses the cover
    }

    private func onboardingCard(title: String, message: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.headline)
            }
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.separator), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityHint(message)
    }
}

private struct AthleteOnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    let onFinish: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 12) {
                        Image(systemName: "figure.baseball")
                            .font(.largeTitle)
                            .foregroundStyle(.blue)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Welcome, Athlete")
                                .font(.title)
                                .fontWeight(.bold)
                                .accessibilityAddTraits(.isHeader)
                            Text("Let's get you set up to track your journey")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }

                    Group {
                        onboardingCard(
                            title: "Record and upload",
                            message: "Capture your swings and drills. Upload videos to your library for analysis.",
                            icon: "video.fill")

                        onboardingCard(
                            title: "Organize into folders",
                            message: "Create folders for sessions, drills, or goals so everything stays organized.",
                            icon: "folder.fill")

                        onboardingCard(
                            title: "Share with your coach",
                            message: "Share specific folders with your coach to get targeted feedback when you’re ready.",
                            icon: "person.crop.circle.badge.checkmark")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Next: Your Library")
                            .font(.headline)
                        Text("Continue to start recording or upload your first videos.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Button(action: finish) {
                        Text("Continue to My Library")
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
                    .accessibilityLabel("Continue to My Library")
                    .accessibilityHint("Complete onboarding and start recording videos")
                }
                .padding()
            }
            .navigationTitle("Athlete Onboarding")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { finish() }
                }
            }
        }
    }

    private func finish() {
        Haptics.success()
        onFinish()
        // Don't call dismiss() - the binding change in onFinish() automatically dismisses the cover
    }

    private func onboardingCard(title: String, message: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.headline)
            }
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.separator), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityHint(message)
    }
}

