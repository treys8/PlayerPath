//
//  SecureBiometricAuthManager.swift
//  PlayerPath
//
//  Production-ready biometric authentication without password storage
//

import LocalAuthentication
import Foundation
import FirebaseAuth
import Combine
import SwiftUI

/// A secure biometric authentication manager that doesn't store passwords.
/// Instead, it leverages Firebase Auth's built-in token persistence and uses
/// biometrics only to unlock the app session.
///
/// Usage:
/// 1. After successful email/password sign-in, offer to enable biometric unlock
/// 2. When user returns, use biometrics to unlock the app
/// 3. Firebase Auth automatically manages tokens in the background
@MainActor
final class SecureBiometricAuthManager: ObservableObject {
    @Published var isBiometricEnabled = false
    @Published var biometricType: LABiometryType = .none
    @Published var isLocked = true
    
    private let biometricEnabledKey = "com.playerpath.biometric.enabled"
    private let lastAuthUserIDKey = "com.playerpath.biometric.lastUserID"
    
    init() {
        checkBiometricAvailability()
        loadBiometricSettings()
        
        // Check if we have an active Firebase session
        if Auth.auth().currentUser != nil {
            isLocked = isBiometricEnabled // Lock if biometric is enabled
        }
    }
    
    // MARK: - Biometric Availability
    
    func checkBiometricAvailability() {
        let context = LAContext()
        var error: NSError?
        
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            biometricType = context.biometryType
        } else {
            biometricType = .none
        }
    }
    
    var biometricTypeName: String {
        switch biometricType {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        default:
            return "Biometric"
        }
    }
    
    var isBiometricAvailable: Bool {
        return biometricType != .none
    }
    
    // MARK: - Enable/Disable Biometric
    
    /// Enable biometric unlock for the current user session
    /// This does NOT store the password, only enables biometric unlock
    func enableBiometricUnlock() async -> Bool {
        guard let currentUser = Auth.auth().currentUser else {
            print("No user signed in")
            return false
        }
        
        do {
            let success = try await authenticateWithBiometric(
                reason: "Enable \(biometricTypeName) to quickly unlock PlayerPath"
            )
            
            if success {
                // Store that biometric is enabled for this user
                UserDefaults.standard.set(true, forKey: biometricEnabledKey)
                UserDefaults.standard.set(currentUser.uid, forKey: lastAuthUserIDKey)
                
                isBiometricEnabled = true
                isLocked = false
                
                print("✅ Biometric unlock enabled for user: \(currentUser.uid)")
                return true
            }
        } catch {
            print("❌ Failed to enable biometric: \(error)")
        }
        
        return false
    }
    
    /// Disable biometric unlock
    func disableBiometricUnlock() {
        UserDefaults.standard.set(false, forKey: biometricEnabledKey)
        UserDefaults.standard.removeObject(forKey: lastAuthUserIDKey)
        isBiometricEnabled = false
        isLocked = false
        print("✅ Biometric unlock disabled")
    }
    
    // MARK: - Biometric Unlock
    
    /// Unlock the app using biometric authentication
    /// This verifies the user with Face ID/Touch ID and unlocks access to the existing session
    func unlockWithBiometric() async -> Bool {
        guard isBiometricEnabled else {
            print("⚠️ Biometric unlock not enabled")
            return false
        }
        
        // Check if Firebase still has an active session
        guard let currentUser = Auth.auth().currentUser else {
            print("⚠️ No active Firebase session")
            // Session expired, disable biometric and require re-authentication
            disableBiometricUnlock()
            return false
        }
        
        // Verify it's the same user who enabled biometric
        let savedUserID = UserDefaults.standard.string(forKey: lastAuthUserIDKey)
        guard savedUserID == currentUser.uid else {
            print("⚠️ User mismatch, disabling biometric")
            disableBiometricUnlock()
            return false
        }
        
        do {
            let success = try await authenticateWithBiometric(
                reason: "Unlock PlayerPath"
            )
            
            if success {
                isLocked = false
                print("✅ App unlocked with \(biometricTypeName)")
                
                // Optional: Refresh the Firebase token to ensure it's still valid
                _ = try? await currentUser.getIDToken(forcingRefresh: true)
                
                return true
            }
        } catch {
            print("❌ Biometric authentication failed: \(error)")
        }
        
        return false
    }
    
    /// Lock the app (requires biometric to unlock)
    func lockApp() {
        guard isBiometricEnabled else { return }
        isLocked = true
        print("🔒 App locked")
    }
    
    // MARK: - Session Management
    
    /// Check if the current session should be locked
    func shouldLockApp() -> Bool {
        return isBiometricEnabled && Auth.auth().currentUser != nil
    }
    
    /// Handle sign out - clean up biometric settings
    func handleSignOut() {
        disableBiometricUnlock()
        isLocked = false
    }
    
    // MARK: - Private Methods
    
    private func authenticateWithBiometric(reason: String) async throws -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "Use Password"
        context.localizedCancelTitle = "Cancel"
        
        return try await context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: reason
        )
    }
    
    private func loadBiometricSettings() {
        isBiometricEnabled = UserDefaults.standard.bool(forKey: biometricEnabledKey)
        
        // Verify the saved user matches the current user
        if isBiometricEnabled,
           let savedUserID = UserDefaults.standard.string(forKey: lastAuthUserIDKey),
           let currentUserID = Auth.auth().currentUser?.uid,
           savedUserID != currentUserID {
            // Different user, disable biometric
            disableBiometricUnlock()
        }
    }
}

// MARK: - App Lifecycle Integration

extension SecureBiometricAuthManager {
    /// Call this when app enters background
    func handleAppDidEnterBackground() {
        if isBiometricEnabled {
            lockApp()
        }
    }
    
    /// Call this when app becomes active
    func handleAppDidBecomeActive() {
        // App will remain locked until user unlocks with biometric
        // This is handled in your UI
    }
}

// MARK: - Integration Example

/*
 
 // In your SignInView.swift, after successful sign-in:
 
 if authManager.isSignedIn {
     HapticManager.shared.authenticationSuccess()
     
     // Offer biometric enrollment
     if !isSignUp && 
        secureBiometricManager.isBiometricAvailable && 
        !secureBiometricManager.isBiometricEnabled {
         try? await Task.sleep(for: .milliseconds(500))
         await MainActor.run {
             showBiometricPrompt = true
         }
     }
 }
 
 // In your MainAppView.swift or ScenePhase handler:
 
 @Environment(\.scenePhase) private var scenePhase
 
 .onChange(of: scenePhase) { oldPhase, newPhase in
     switch newPhase {
     case .background:
         secureBiometricManager.handleAppDidEnterBackground()
     case .active:
         secureBiometricManager.handleAppDidBecomeActive()
     default:
         break
     }
 }
 
 // In your app's root view:
 
 if authManager.isSignedIn && secureBiometricManager.isLocked {
     BiometricUnlockView(secureBiometricManager: secureBiometricManager)
 } else {
     MainContentView()
 }
 
 */

// MARK: - BiometricUnlockView Example

struct BiometricUnlockView: View {
    @ObservedObject var biometricManager: SecureBiometricAuthManager
    @EnvironmentObject var authManager: ComprehensiveAuthManager
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: biometricManager.biometricType == .faceID ? "faceid" : "touchid")
                .font(.system(size: 60))
                .foregroundStyle(.blue.gradient)
            
            Text("PlayerPath is Locked")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Use \(biometricManager.biometricTypeName) to unlock")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Button {
                Task {
                    await unlockApp()
                }
            } label: {
                HStack {
                    Image(systemName: biometricManager.biometricType == .faceID ? "faceid" : "touchid")
                    Text("Unlock with \(biometricManager.biometricTypeName)")
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            
            Button("Sign Out") {
                Task {
                    await authManager.signOut()
                    biometricManager.handleSignOut()
                }
            }
            .foregroundColor(.secondary)
        }
        .padding()
        .task {
            // Automatically prompt for biometric on appear
            await unlockApp()
        }
    }
    
    private func unlockApp() async {
        let success = await biometricManager.unlockWithBiometric()
        if success {
            HapticManager.shared.authenticationSuccess()
        } else {
            HapticManager.shared.error()
        }
    }
}
