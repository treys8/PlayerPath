//
//  INTEGRATION_EXAMPLES.swift
//  PlayerPath
//
//  Created by Assistant on 11/10/25.
//

import SwiftUI

// MARK: - Integration Examples

/*
 
 ==========================================
 HOW TO INTEGRATE THE NEW AUTH FEATURES
 ==========================================
 
 */

// MARK: - Example 1: Add Biometric Settings to Profile/Settings View

/*
struct ProfileView: View {
    var body: some View {
        Form {
            // ... existing profile sections ...
            
            // Add biometric settings
            BiometricSettingsView()
            
            // ... more settings ...
        }
        .navigationTitle("Settings")
    }
}
*/

// MARK: - Example 2: Conditional Sign In with Apple Button

/*
struct CustomSignInView: View {
    @StateObject private var appleSignInManager = AppleSignInManager()
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    
    var body: some View {
        VStack(spacing: 20) {
            // Show Apple Sign In if available
            SignInWithAppleButton {
                appleSignInManager.signInWithApple()
            }
            
            // Traditional sign in
            // ... your existing sign in form ...
        }
        .onAppear {
            appleSignInManager.configure(with: authManager)
        }
    }
}
*/

// MARK: - Example 3: Quick Biometric Sign In Button

/*
struct QuickSignInButton: View {
    @StateObject private var biometricManager = BiometricAuthenticationManager()
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    
    var body: some View {
        if biometricManager.isBiometricEnabled {
            Button(action: {
                Task {
                    if let credentials = await biometricManager.getBiometricCredentials() {
                        await authManager.signIn(
                            email: credentials.email,
                            password: credentials.password
                        )
                    }
                }
            }) {
                HStack {
                    Image(systemName: biometricManager.biometricType == .faceID ? "faceid" : "touchid")
                    Text("Quick Sign In")
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
*/

// MARK: - Example 4: Password Reset in Existing View

/*
struct AccountRecoveryView: View {
    @State private var showingPasswordReset = false
    
    var body: some View {
        VStack {
            Text("Having trouble signing in?")
            
            Button("Reset Password") {
                showingPasswordReset = true
            }
            .buttonStyle(.borderedProminent)
        }
        .sheet(isPresented: $showingPasswordReset) {
            PasswordResetView()
        }
    }
}
*/

// MARK: - Example 5: Privacy Policy Link in Existing View

/*
struct AboutView: View {
    @State private var showingPrivacyPolicy = false
    @State private var showingTerms = false
    
    var body: some View {
        Form {
            Section("Legal") {
                Button("Privacy Policy") {
                    showingPrivacyPolicy = true
                }
                
                Button("Terms of Service") {
                    showingTerms = true
                }
            }
        }
        .sheet(isPresented: $showingPrivacyPolicy) {
            PrivacyPolicyView()
        }
        .sheet(isPresented: $showingTerms) {
            TermsOfServiceView()
        }
    }
}
*/

// MARK: - Example 6: Onboarding with Biometric Setup

/*
struct OnboardingView: View {
    @StateObject private var biometricManager = BiometricAuthenticationManager()
    @State private var showingBiometricSetup = false
    @Binding var hasCompletedOnboarding: Bool
    
    var body: some View {
        VStack(spacing: 30) {
            Text("Welcome to PlayerPath!")
                .font(.largeTitle)
            
            // ... onboarding content ...
            
            if biometricManager.isBiometricAvailable {
                Button("Enable \(biometricManager.biometricTypeName)") {
                    showingBiometricSetup = true
                }
                .buttonStyle(.borderedProminent)
                
                Button("Skip for Now") {
                    hasCompletedOnboarding = true
                }
                .foregroundColor(.secondary)
            } else {
                Button("Get Started") {
                    hasCompletedOnboarding = true
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .sheet(isPresented: $showingBiometricSetup) {
            // Show biometric setup
            // After successful setup:
            hasCompletedOnboarding = true
        }
    }
}
*/

// MARK: - Example 7: Authentication State Handling

/*
struct AppRootView: View {
    @EnvironmentObject var authManager: ComprehensiveAuthManager
    @StateObject private var biometricManager = BiometricAuthenticationManager()
    @State private var attemptedBiometricSignIn = false
    
    var body: some View {
        Group {
            if authManager.isSignedIn {
                MainAppView()
            } else {
                if !attemptedBiometricSignIn && biometricManager.isBiometricEnabled {
                    // Automatically attempt biometric sign-in on app launch
                    ProgressView("Signing in...")
                        .task {
                            await attemptBiometricSignIn()
                        }
                } else {
                    SignInView()
                }
            }
        }
    }
    
    private func attemptBiometricSignIn() async {
        defer { attemptedBiometricSignIn = true }
        
        if let credentials = await biometricManager.getBiometricCredentials() {
            await authManager.signIn(
                email: credentials.email,
                password: credentials.password
            )
        }
    }
}
*/

// MARK: - Example 8: Custom Haptic Feedback Usage

/*
struct CustomButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            HapticManager.shared.buttonTap()
            action()
        }) {
            Text("Tap Me")
        }
    }
}

struct SuccessView: View {
    var body: some View {
        VStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text("Success!")
        }
        .onAppear {
            HapticManager.shared.success()
        }
    }
}

struct ErrorView: View {
    var body: some View {
        VStack {
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
            Text("Error")
        }
        .onAppear {
            HapticManager.shared.error()
        }
    }
}
*/

// MARK: - Example 9: Sign Out with Cleanup

/*
extension ComprehensiveAuthManager {
    func signOutWithCleanup() async {
        // Clean up biometric credentials before signing out
        let biometricManager = BiometricAuthenticationManager()
        biometricManager.disableBiometric()
        
        // Sign out from Firebase
        await signOut()
        
        // Additional cleanup if needed
        // Clear cached data, cancel network requests, etc.
    }
}
*/

// MARK: - Example 10: Account Deletion with Security Check

/*
struct DeleteAccountView: View {
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @StateObject private var biometricManager = BiometricAuthenticationManager()
    @State private var showingConfirmation = false
    @State private var requiresBiometric = false
    
    var body: some View {
        VStack {
            Text("Delete Account")
                .font(.title)
                .foregroundColor(.red)
            
            Button("Delete My Account") {
                if biometricManager.isBiometricEnabled {
                    requiresBiometric = true
                } else {
                    showingConfirmation = true
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .alert("Delete Account?", isPresented: $showingConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    await deleteAccount()
                }
            }
        } message: {
            Text("This action cannot be undone. All your data will be permanently deleted.")
        }
        .task(id: requiresBiometric) {
            if requiresBiometric {
                if await biometricManager.getBiometricCredentials() != nil {
                    // Biometric auth succeeded
                    await MainActor.run {
                        showingConfirmation = true
                    }
                }
                requiresBiometric = false
            }
        }
    }
    
    private func deleteAccount() async {
        // 1. Disable biometric
        biometricManager.disableBiometric()
        
        // 2. Delete user data from Firebase/backend
        // await deleteUserData()
        
        // 3. Delete Firebase auth account
        // try? await authManager.currentFirebaseUser?.delete()
        
        // 4. Sign out
        await authManager.signOut()
    }
}
*/

// MARK: - Usage Tips

/*
 
 ==========================================
 TIPS FOR USING THE NEW AUTH FEATURES
 ==========================================
 
 1. BIOMETRIC AUTHENTICATION
    - Always check `isBiometricAvailable` before showing biometric options
    - Offer biometric enrollment after first successful password sign-in
    - Provide a way to disable biometric auth in settings
    - Handle biometric failures gracefully (show password field)
 
 2. SIGN IN WITH APPLE
    - Configure in Xcode capabilities and Firebase
    - Test on physical devices (simulator support limited)
    - Handle user cancellation without showing errors
    - Extract name from Apple ID when available
 
 3. PASSWORD RESET
    - Use the dedicated PasswordResetView sheet instead of alerts
    - Validate email before allowing submission
    - Show clear success state with instructions
    - Handle "email not found" errors carefully (security)
 
 4. PRIVACY & TERMS
    - Make terms/privacy easily accessible
    - Require agreement for sign-ups (checkbox)
    - Update dates when content changes
    - Provide contact information
 
 5. HAPTIC FEEDBACK
    - Use success() for positive actions
    - Use error() for failures
    - Use buttonTap() for interactions
    - Use warning() for caution alerts
    - Use selectionChanged() for picker/toggle changes
 
 6. KEYCHAIN SECURITY
    - Credentials are encrypted automatically
    - Data persists across app reinstalls
    - Only accessible when device unlocked
    - Use for sensitive data only
 
 7. ERROR HANDLING
    - Show user-friendly error messages
    - Don't reveal account existence in errors
    - Provide recovery paths (reset password link)
    - Log technical details for debugging
 
 8. TESTING
    - Test all flows on physical devices
    - Test with Face ID simulator features
    - Test with poor network conditions
    - Test rapid button tapping (prevent double submissions)
 
 ==========================================
 
 */
