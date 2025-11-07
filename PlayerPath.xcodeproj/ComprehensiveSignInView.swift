//
//  ComprehensiveSignInView.swift
//  PlayerPath
//
//  Complete authentication UI with Apple Sign-In, Google Sign-In, Email, Face ID, and Trial
//

import SwiftUI

struct ComprehensiveSignInView: View {
    @StateObject private var authManager = ComprehensiveAuthManager()
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var displayName = ""
    @State private var isCreatingAccount = false
    @State private var showingBiometricSetup = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 30) {
                    // App Branding
                    AppBrandingHeader()
                    
                    // Free Trial Banner
                    FreeTrialBanner()
                    
                    // Social Sign-In Options
                    SocialSignInSection(authManager: authManager)
                    
                    // Divider
                    DividerWithText("or")
                    
                    // Email/Password Section
                    EmailPasswordSection(
                        authManager: authManager,
                        email: $email,
                        password: $password,
                        confirmPassword: $confirmPassword,
                        displayName: $displayName,
                        isCreatingAccount: $isCreatingAccount
                    )
                    
                    // Account Toggle
                    AccountToggleButton(isCreatingAccount: $isCreatingAccount)
                    
                    // Biometric Setup (after sign in)
                    if authManager.isSignedIn && !authManager.currentUser?.hasBiometricEnabled ?? true {
                        BiometricSetupSection(authManager: authManager)
                    }
                    
                    // Terms and Privacy
                    TermsAndPrivacySection()
                    
                    Spacer()
                }
                .padding()
            }
            .navigationBarHidden(true)
            .alert("Authentication Error", isPresented: .constant(!authManager.errorMessage.isEmpty)) {
                Button("OK") {
                    authManager.errorMessage = ""
                }
            } message: {
                Text(authManager.errorMessage)
            }
        }
        .overlay {
            if authManager.isLoading {
                LoadingOverlay()
            }
        }
    }
}

// MARK: - App Branding Header

struct AppBrandingHeader: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "figure.baseball")
                .font(.system(size: 80))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            VStack(spacing: 8) {
                Text("PlayerPath")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text("Track Your Baseball Journey")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Text("Record videos, track stats, analyze performance")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

// MARK: - Free Trial Banner

struct FreeTrialBanner: View {
    var body: some View {
        HStack {
            Image(systemName: "gift.fill")
                .foregroundColor(.yellow)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("14-Day Free Trial")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text("Full access to all premium features")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text("FREE")
                .font(.caption)
                .fontWeight(.bold)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(6)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

// MARK: - Social Sign-In Section

struct SocialSignInSection: View {
    @ObservedObject var authManager: ComprehensiveAuthManager
    
    var body: some View {
        VStack(spacing: 15) {
            // Apple Sign-In Button
            Button(action: {
                Task {
                    await authManager.signInWithApple()
                }
            }) {
                HStack {
                    Image(systemName: "applelogo")
                        .font(.title3)
                    Text("Continue with Apple")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.black)
                .cornerRadius(12)
            }
            .disabled(authManager.isLoading)
            
            // Google Sign-In Button
            Button(action: {
                Task {
                    await authManager.signInWithGoogle()
                }
            }) {
                HStack {
                    Image(systemName: "globe")
                        .font(.title3)
                    Text("Continue with Google")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
                .cornerRadius(12)
            }
            .disabled(authManager.isLoading)
        }
    }
}

// MARK: - Email/Password Section

struct EmailPasswordSection: View {
    @ObservedObject var authManager: ComprehensiveAuthManager
    @Binding var email: String
    @Binding var password: String
    @Binding var confirmPassword: String
    @Binding var displayName: String
    @Binding var isCreatingAccount: Bool
    
    var body: some View {
        VStack(spacing: 15) {
            if isCreatingAccount {
                TextField("Full Name", text: $displayName)
                    .textFieldStyle(ModernTextFieldStyle())
            }
            
            TextField("Email", text: $email)
                .textFieldStyle(ModernTextFieldStyle())
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .autocorrectionDisabled()
            
            SecureField("Password", text: $password)
                .textFieldStyle(ModernTextFieldStyle())
            
            if isCreatingAccount {
                SecureField("Confirm Password", text: $confirmPassword)
                    .textFieldStyle(ModernTextFieldStyle())
            }
            
            Button(action: handleAuthentication) {
                Text(isCreatingAccount ? "Start Free Trial" : "Sign In")
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
            }
            .disabled(authManager.isLoading || !isFormValid)
        }
    }
    
    private var isFormValid: Bool {
        if isCreatingAccount {
            return !email.isEmpty && 
                   !password.isEmpty && 
                   !displayName.isEmpty && 
                   password == confirmPassword &&
                   password.count >= 6
        } else {
            return !email.isEmpty && !password.isEmpty
        }
    }
    
    private func handleAuthentication() {
        Task {
            if isCreatingAccount {
                await authManager.createAccountWithEmail(email, password: password, displayName: displayName)
            } else {
                await authManager.signInWithEmail(email, password: password)
            }
        }
    }
}

// MARK: - Account Toggle Button

struct AccountToggleButton: View {
    @Binding var isCreatingAccount: Bool
    
    var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.3)) {
                isCreatingAccount.toggle()
            }
        }) {
            Text(isCreatingAccount ? "Already have an account? Sign In" : "Don't have an account? Start Free Trial")
                .foregroundColor(.blue)
                .font(.subheadline)
        }
    }
}

// MARK: - Biometric Setup Section

struct BiometricSetupSection: View {
    @ObservedObject var authManager: ComprehensiveAuthManager
    @State private var biometricType = "Biometrics"
    
    var body: some View {
        VStack(spacing: 15) {
            HStack {
                Image(systemName: biometricType == "Face ID" ? "faceid" : "touchid")
                    .font(.title2)
                    .foregroundColor(.green)
                
                VStack(alignment: .leading) {
                    Text("Enable \(biometricType)")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text("Sign in faster and more securely")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("Enable") {
                    Task {
                        await authManager.enableBiometricAuthentication()
                    }
                }
                .buttonStyle(.bordered)
                .tint(.green)
            }
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(12)
        .onAppear {
            biometricType = BiometricAuthManager().getBiometricType()
        }
    }
}

// MARK: - Terms and Privacy Section

struct TermsAndPrivacySection: View {
    var body: some View {
        VStack(spacing: 10) {
            Text("By continuing, you agree to our")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(spacing: 4) {
                Button("Terms of Service") {
                    // Handle terms tap
                }
                .font(.caption)
                .foregroundColor(.blue)
                
                Text("and")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button("Privacy Policy") {
                    // Handle privacy tap
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
        }
    }
}

// MARK: - Supporting Views

struct DividerWithText: View {
    let text: String
    
    var body: some View {
        HStack {
            Rectangle()
                .frame(height: 1)
                .foregroundColor(.gray.opacity(0.3))
            
            Text(text)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            Rectangle()
                .frame(height: 1)
                .foregroundColor(.gray.opacity(0.3))
        }
    }
}

struct LoadingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.5)
                
                Text("Signing you in...")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            .padding(30)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
        }
    }
}

struct ModernTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
    }
}

// MARK: - Trial Status View (for after sign-in)

struct TrialStatusView: View {
    @ObservedObject var authManager: ComprehensiveAuthManager
    
    var body: some View {
        Group {
            if authManager.isInFreeTrial {
                TrialBanner(daysRemaining: authManager.trialDaysRemaining, authManager: authManager)
            } else if !authManager.isPremiumUser {
                UpgradeBanner(authManager: authManager)
            }
        }
    }
}

struct TrialBanner: View {
    let daysRemaining: Int
    @ObservedObject var authManager: ComprehensiveAuthManager
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Free Trial")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text("\(daysRemaining) days remaining")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("Upgrade") {
                Task {
                    await authManager.upgradeToPremium()
                }
            }
            .buttonStyle(.bordered)
            .tint(.blue)
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
    }
}

struct UpgradeBanner: View {
    @ObservedObject var authManager: ComprehensiveAuthManager
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Trial Expired")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.red)
                
                Text("Upgrade to continue using premium features")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("Upgrade Now") {
                Task {
                    await authManager.upgradeToPremium()
                }
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(12)
    }
}

#Preview {
    ComprehensiveSignInView()
}