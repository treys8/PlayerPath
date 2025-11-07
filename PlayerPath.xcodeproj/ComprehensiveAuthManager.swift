//
//  ComprehensiveAuthManager.swift
//  PlayerPath
//
//  Full authentication system with Apple Sign-In, Google Sign-In, Face ID, and trials
//

import Foundation
import SwiftUI
import LocalAuthentication
// import FirebaseAuth
// import AuthenticationServices
// import GoogleSignIn

@MainActor
class ComprehensiveAuthManager: ObservableObject {
    @Published var isSignedIn = false
    @Published var currentUser: AuthenticatedUser?
    @Published var isLoading = false
    @Published var errorMessage = ""
    @Published var showingBiometricPrompt = false
    
    // Trial and subscription state
    @Published var isInFreeTrial = false
    @Published var trialDaysRemaining = 0
    @Published var isPremiumUser = false
    
    private let keychain = KeychainManager()
    private let biometricManager = BiometricAuthManager()
    
    init() {
        checkAuthenticationState()
        checkTrialStatus()
    }
    
    // MARK: - Authentication State Management
    
    func checkAuthenticationState() {
        // Check if user has valid stored credentials
        if let storedUser = keychain.getStoredUser() {
            currentUser = storedUser
            isSignedIn = true
            checkTrialStatus()
        }
        
        // TODO: Check Firebase auth state when Firebase is enabled
        /*
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.handleFirebaseAuthChange(user)
            }
        }
        */
    }
    
    func checkTrialStatus() {
        guard let user = currentUser else { return }
        
        let trialStartDate = user.trialStartDate ?? Date()
        let trialEndDate = Calendar.current.date(byAdding: .day, value: 14, to: trialStartDate) ?? Date()
        let daysRemaining = Calendar.current.dateComponents([.day], from: Date(), to: trialEndDate).day ?? 0
        
        trialDaysRemaining = max(0, daysRemaining)
        isInFreeTrial = trialDaysRemaining > 0 && !user.isPremium
        isPremiumUser = user.isPremium
    }
    
    // MARK: - Apple Sign-In (Placeholder until AuthenticationServices is imported)
    
    func signInWithApple() async {
        isLoading = true
        errorMessage = ""
        
        // TODO: Implement when AuthenticationServices is imported
        /*
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        
        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        // ... implementation
        */
        
        // Temporary placeholder
        await createTemporaryUser(
            id: UUID().uuidString,
            email: "apple.user@example.com",
            displayName: "Apple User",
            provider: .apple
        )
        
        isLoading = false
    }
    
    // MARK: - Google Sign-In (Placeholder until GoogleSignIn is imported)
    
    func signInWithGoogle() async {
        isLoading = true
        errorMessage = ""
        
        // TODO: Implement when GoogleSignIn is imported
        /*
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            errorMessage = "Could not find root view controller"
            isLoading = false
            return
        }
        
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
            // ... Firebase integration
        } catch {
            errorMessage = "Google Sign In failed: \(error.localizedDescription)"
        }
        */
        
        // Temporary placeholder
        await createTemporaryUser(
            id: UUID().uuidString,
            email: "google.user@example.com",
            displayName: "Google User",
            provider: .google
        )
        
        isLoading = false
    }
    
    // MARK: - Email/Password Sign-In
    
    func signInWithEmail(_ email: String, password: String) async {
        isLoading = true
        errorMessage = ""
        
        // TODO: Implement Firebase email authentication
        /*
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            // Handle success
        } catch {
            errorMessage = "Sign in failed: \(error.localizedDescription)"
        }
        */
        
        // Temporary implementation - validate email format
        guard isValidEmail(email) else {
            errorMessage = "Please enter a valid email address"
            isLoading = false
            return
        }
        
        guard password.count >= 6 else {
            errorMessage = "Password must be at least 6 characters"
            isLoading = false
            return
        }
        
        await createTemporaryUser(
            id: UUID().uuidString,
            email: email,
            displayName: email.components(separatedBy: "@").first ?? "User",
            provider: .email
        )
        
        isLoading = false
    }
    
    func createAccountWithEmail(_ email: String, password: String, displayName: String) async {
        isLoading = true
        errorMessage = ""
        
        // TODO: Implement Firebase account creation
        /*
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            let changeRequest = result.user.createProfileChangeRequest()
            changeRequest.displayName = displayName
            try await changeRequest.commitChanges()
        } catch {
            errorMessage = "Account creation failed: \(error.localizedDescription)"
        }
        */
        
        // Temporary implementation
        guard isValidEmail(email) else {
            errorMessage = "Please enter a valid email address"
            isLoading = false
            return
        }
        
        guard password.count >= 6 else {
            errorMessage = "Password must be at least 6 characters"
            isLoading = false
            return
        }
        
        await createTemporaryUser(
            id: UUID().uuidString,
            email: email,
            displayName: displayName,
            provider: .email
        )
        
        isLoading = false
    }
    
    // MARK: - Biometric Authentication
    
    func enableBiometricAuthentication() async {
        guard await biometricManager.isBiometricAvailable() else {
            errorMessage = "Biometric authentication is not available on this device"
            return
        }
        
        let success = await biometricManager.authenticateUser()
        if success {
            currentUser?.hasBiometricEnabled = true
            saveUserToKeychain()
        } else {
            errorMessage = "Failed to enable biometric authentication"
        }
    }
    
    func authenticateWithBiometrics() async -> Bool {
        guard let user = currentUser, user.hasBiometricEnabled else {
            return false
        }
        
        return await biometricManager.authenticateUser()
    }
    
    // MARK: - Trial and Subscription Management
    
    func startFreeTrial() {
        guard let user = currentUser else { return }
        
        if user.trialStartDate == nil {
            currentUser?.trialStartDate = Date()
            saveUserToKeychain()
            checkTrialStatus()
        }
    }
    
    func upgradeToPremium() async {
        // TODO: Implement StoreKit subscription flow
        /*
        do {
            // Purchase premium subscription
            // Update user's premium status
            currentUser?.isPremium = true
            saveUserToKeychain()
            checkTrialStatus()
        } catch {
            errorMessage = "Failed to upgrade to premium: \(error.localizedDescription)"
        }
        */
        
        // Temporary implementation for testing
        currentUser?.isPremium = true
        saveUserToKeychain()
        checkTrialStatus()
    }
    
    // MARK: - Sign Out
    
    func signOut() {
        // TODO: Sign out from Firebase
        /*
        do {
            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
        } catch {
            errorMessage = "Sign out failed: \(error.localizedDescription)"
        }
        */
        
        keychain.clearStoredUser()
        currentUser = nil
        isSignedIn = false
        isInFreeTrial = false
        trialDaysRemaining = 0
        isPremiumUser = false
    }
    
    // MARK: - Helper Methods
    
    private func createTemporaryUser(id: String, email: String, displayName: String, provider: AuthProvider) async {
        let user = AuthenticatedUser(
            id: id,
            email: email,
            displayName: displayName,
            provider: provider,
            trialStartDate: Date(),
            isPremium: false,
            hasBiometricEnabled: false
        )
        
        currentUser = user
        isSignedIn = true
        saveUserToKeychain()
        startFreeTrial()
    }
    
    private func saveUserToKeychain() {
        guard let user = currentUser else { return }
        keychain.saveUser(user)
    }
    
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegEx = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPred = NSPredicate(format:"SELF MATCHES %@", emailRegEx)
        return emailPred.evaluate(with: email)
    }
}

// MARK: - Supporting Data Models

struct AuthenticatedUser: Codable {
    let id: String
    let email: String
    let displayName: String
    let provider: AuthProvider
    var trialStartDate: Date?
    var isPremium: Bool
    var hasBiometricEnabled: Bool
}

enum AuthProvider: String, Codable {
    case apple = "apple"
    case google = "google"
    case email = "email"
    case anonymous = "anonymous"
}

// MARK: - Keychain Manager

class KeychainManager {
    private let service = "com.playerpath.auth"
    private let account = "current_user"
    
    func saveUser(_ user: AuthenticatedUser) {
        do {
            let data = try JSONEncoder().encode(user)
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecValueData as String: data
            ]
            
            // Delete any existing item
            SecItemDelete(query as CFDictionary)
            
            // Add new item
            SecItemAdd(query as CFDictionary, nil)
        } catch {
            print("Failed to save user to keychain: \(error)")
        }
    }
    
    func getStoredUser() -> AuthenticatedUser? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        
        do {
            return try JSONDecoder().decode(AuthenticatedUser.self, from: data)
        } catch {
            print("Failed to decode stored user: \(error)")
            return nil
        }
    }
    
    func clearStoredUser() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Biometric Authentication Manager

class BiometricAuthManager {
    private let context = LAContext()
    
    func isBiometricAvailable() async -> Bool {
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }
    
    func getBiometricType() -> String {
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return "None"
        }
        
        switch context.biometryType {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        case .opticID:
            return "Optic ID"
        default:
            return "Biometrics"
        }
    }
    
    func authenticateUser() async -> Bool {
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return false
        }
        
        do {
            let reason = "Authenticate to access PlayerPath"
            let result = try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
            return result
        } catch {
            print("Biometric authentication failed: \(error)")
            return false
        }
    }
}