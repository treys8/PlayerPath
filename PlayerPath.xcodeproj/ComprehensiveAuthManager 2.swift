//
//  ComprehensiveAuthManager.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/26/25.
//

import SwiftUI
import FirebaseAuth
import Combine

@MainActor
class ComprehensiveAuthManager: ObservableObject {
    @Published var isSignedIn = false
    @Published var currentUser: FirebaseAuth.User?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isPremiumUser = false
    @Published var trialDaysRemaining = 7 // Default trial period
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Listen to Firebase Auth state changes
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.currentUser = user
                self?.isSignedIn = user != nil
                
                // Check premium status when user signs in
                if user != nil {
                    self?.checkPremiumStatus()
                }
            }
        }
        
        // Set initial state
        self.currentUser = Auth.auth().currentUser
        self.isSignedIn = Auth.auth().currentUser != nil
        
        if isSignedIn {
            checkPremiumStatus()
        }
    }
    
    // MARK: - Authentication Methods
    
    func signIn(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            currentUser = result.user
            isSignedIn = true
            checkPremiumStatus()
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func signUp(email: String, password: String, displayName: String? = nil) async {
        isLoading = true
        errorMessage = nil
        
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            
            // Update display name if provided
            if let displayName = displayName {
                let changeRequest = result.user.createProfileChangeRequest()
                changeRequest.displayName = displayName
                try await changeRequest.commitChanges()
            }
            
            currentUser = result.user
            isSignedIn = true
            checkPremiumStatus()
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func signOut() {
        do {
            try Auth.auth().signOut()
            currentUser = nil
            isSignedIn = false
            isPremiumUser = false
            trialDaysRemaining = 7
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func resetPassword(email: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    // MARK: - Premium Features
    
    private func checkPremiumStatus() {
        // TODO: Implement actual premium status check
        // This could involve checking with StoreKit, Firebase Functions, or your backend
        
        // For now, simulate premium status based on user creation date
        // In a real app, you'd check the user's subscription status
        if let user = currentUser {
            // Simulate: users created more than 30 days ago get premium
            let thirtyDaysAgo = Date().timeIntervalSince1970 - (30 * 24 * 60 * 60)
            isPremiumUser = user.metadata.creationDate?.timeIntervalSince1970 ?? 0 < thirtyDaysAgo
            
            // Calculate trial days remaining
            if !isPremiumUser {
                let daysSinceCreation = Int((Date().timeIntervalSince1970 - (user.metadata.creationDate?.timeIntervalSince1970 ?? Date().timeIntervalSince1970)) / (24 * 60 * 60))
                trialDaysRemaining = max(0, 7 - daysSinceCreation)
            }
        }
    }
    
    func upgradeToPremium() async {
        isLoading = true
        errorMessage = nil
        
        // TODO: Implement actual premium upgrade
        // This would typically involve:
        // 1. StoreKit purchase flow
        // 2. Server-side receipt validation
        // 3. Updating user's premium status in your database
        
        // For now, simulate successful upgrade
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
        
        isPremiumUser = true
        isLoading = false
    }
    
    // MARK: - Helper Methods
    
    var isTrialExpired: Bool {
        return !isPremiumUser && trialDaysRemaining <= 0
    }
    
    var canAccessPremiumFeatures: Bool {
        return isPremiumUser || trialDaysRemaining > 0
    }
}

// MARK: - Simple Sign In Fallback

struct SimpleSignInFallback: View {
    let authManager: ComprehensiveAuthManager
    
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var isSignUp = false
    @State private var showingForgotPassword = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                // App Logo
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
                
                VStack(spacing: 20) {
                    if isSignUp {
                        TextField("Display Name", text: $displayName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    
                    TextField("Email", text: $email)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    SecureField("Password", text: $password)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                
                VStack(spacing: 15) {
                    Button(action: performAuth) {
                        HStack {
                            if authManager.isLoading {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            }
                            Text(isSignUp ? "Sign Up" : "Sign In")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(email.isEmpty || password.isEmpty || authManager.isLoading)
                    
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
                
                if let errorMessage = authManager.errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
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
    
    private func performAuth() {
        Task {
            if isSignUp {
                await authManager.signUp(
                    email: email,
                    password: password,
                    displayName: displayName.isEmpty ? nil : displayName
                )
            } else {
                await authManager.signIn(email: email, password: password)
            }
        }
    }
}

// MARK: - Comprehensive Sign In View (Placeholder)

struct ComprehensiveSignInView: View {
    var body: some View {
        Text("Comprehensive Sign In View")
            .font(.title)
        Text("Google Sign In and other providers will be implemented here")
            .font(.caption)
            .foregroundColor(.secondary)
    }
}

// MARK: - Trial Status View

struct TrialStatusView: View {
    let authManager: ComprehensiveAuthManager
    
    var body: some View {
        if !authManager.isPremiumUser {
            HStack {
                Image(systemName: authManager.trialDaysRemaining > 0 ? "clock" : "exclamationmark.triangle")
                    .foregroundColor(authManager.trialDaysRemaining > 0 ? .orange : .red)
                
                if authManager.trialDaysRemaining > 0 {
                    Text("Trial: \(authManager.trialDaysRemaining) days remaining")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else {
                    Text("Trial expired - Upgrade to continue")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                
                Spacer()
                
                Button("Upgrade") {
                    Task {
                        await authManager.upgradeToPremium()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(authManager.trialDaysRemaining > 0 ? Color.orange.opacity(0.1) : Color.red.opacity(0.1))
            .cornerRadius(8)
        }
    }
}