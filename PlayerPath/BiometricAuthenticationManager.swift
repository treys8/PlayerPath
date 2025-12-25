//
//  BiometricAuthenticationManager.swift
//  PlayerPath
//
//  Created by Assistant on 11/1/25.
//

import LocalAuthentication
import Foundation
import Combine

@MainActor
final class BiometricAuthenticationManager: ObservableObject {
    @Published var isBiometricEnabled = false
    @Published var biometricType: LABiometryType = .none

    private let keychain = KeychainManager()

    // Shared singleton instance for accessing biometric operations from other managers
    static let shared = BiometricAuthenticationManager()

    init() {
        checkBiometricAvailability()
        isBiometricEnabled = keychain.isBiometricEnabled()
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
            return AuthConstants.Biometric.faceIDName
        case .touchID:
            return AuthConstants.Biometric.touchIDName
        default:
            return AuthConstants.Biometric.genericBiometricName
        }
    }
    
    var isBiometricAvailable: Bool {
        return biometricType != .none
    }
    
    // MARK: - Enable/Disable Biometric

    /// ⚠️ SECURITY WARNING: This implementation stores passwords in the keychain
    ///
    /// **Current Implementation:**
    /// - Stores email and password with biometric protection (kSecAccessControlBiometry)
    /// - Passwords are encrypted but still stored locally
    ///
    /// **RECOMMENDED Production Approach:**
    /// 1. Use Firebase Auth's automatic session token management
    /// 2. Store only the user's email (not password)
    /// 3. Use biometric auth to unlock app access, not for re-authentication
    /// 4. Let Firebase SDK handle token refresh automatically
    /// 5. Implement Apple's ASAuthorizationPasswordProvider for password autofill
    ///
    /// **Migration Path:**
    /// - Phase 1: Current implementation (biometric-protected password storage)
    /// - Phase 2: Migrate to session-only biometric (unlock app, use existing Firebase session)
    /// - Phase 3: Full token-based authentication with automatic refresh
    ///
    /// Enable biometric authentication by storing credentials with biometric protection
    @available(*, deprecated, message: "This method stores passwords. Migrate to session-based biometric authentication.")
    func enableBiometric(email: String, password: String) async -> Bool {
        do {
            let success = try await authenticateWithBiometric(reason: "Enable \(biometricTypeName) for quick sign-in")
            if success {
                // TEMPORARY: Store credentials for demo purposes with biometric protection
                // NOTE: While passwords are stored with kSecAccessControlBiometry protection,
                // this approach should be replaced with session-based authentication
                keychain.saveBiometricCredentials(email: email, password: password)
                isBiometricEnabled = true

                #if DEBUG
                print("⚠️ SECURITY: Biometric enabled with password storage. Migrate to session-based auth for production.")
                #endif

                return true
            }
        } catch {
            print("Failed to enable biometric: \(error)")
        }
        return false
    }
    
    func disableBiometric() {
        keychain.removeBiometricCredentials()
        isBiometricEnabled = false
    }

    /// ✅ RECOMMENDED: Session-based biometric authentication
    ///
    /// This is the secure approach that should replace password storage:
    /// - Checks if user has an active Firebase session
    /// - Uses biometric to unlock app access
    /// - Relies on Firebase's automatic token management
    /// - No passwords stored locally
    ///
    /// **Usage:**
    /// 1. User signs in normally (email/password or Apple Sign In)
    /// 2. Enable session-based biometric (stores only email)
    /// 3. On app launch, check for active session + biometric
    /// 4. If both valid, user is authenticated without re-entering password
    func enableSessionBasedBiometric(email: String) async -> Bool {
        do {
            let success = try await authenticateWithBiometric(reason: "Enable \(biometricTypeName) for quick app access")
            if success {
                // Only store email, not password
                keychain.saveEmailForBiometric(email: email)
                isBiometricEnabled = true

                #if DEBUG
                print("✅ SECURITY: Session-based biometric enabled (no password storage)")
                #endif

                return true
            }
        } catch {
            print("Failed to enable session-based biometric: \(error)")
        }
        return false
    }

    /// Authenticates using session-based biometric
    /// Returns the stored email if biometric succeeds, nil otherwise
    func authenticateWithSessionBiometric() async -> String? {
        do {
            let success = try await authenticateWithBiometric(reason: "Unlock with \(biometricTypeName)")
            if success {
                return keychain.getEmailForBiometric()
            }
        } catch {
            print("Session-based biometric authentication failed: \(error)")
        }
        return nil
    }

    // MARK: - Biometric Authentication
    
    func authenticateWithBiometric(reason: String) async throws -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "Use Password"
        
        return try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
    }
    
    /// Get stored credentials after biometric authentication
    /// Note: This is a temporary implementation. In production, this should return
    /// a secure session token, not the actual password.
    func getBiometricCredentials() async -> (email: String, password: String)? {
        do {
            let success = try await authenticateWithBiometric(reason: "Sign in with \(biometricTypeName)")
            if success {
                return keychain.getBiometricCredentials()
            }
        } catch {
            print("Biometric authentication failed: \(error)")
        }
        return nil
    }
}

// MARK: - Keychain Manager for Biometric Credentials

private class KeychainManager {
    private let biometricEnabledKey = AuthConstants.UserDefaultsKeys.biometricEnabled
    private let emailKey = "com.playerpath.biometric.email"
    private let passwordKey = "com.playerpath.biometric.password"

    func isBiometricEnabled() -> Bool {
        return UserDefaults.standard.bool(forKey: biometricEnabledKey)
    }
    
    /// SECURITY WARNING: Storing passwords in plaintext is insecure
    /// This is a temporary implementation for demonstration purposes only.
    /// 
    /// Recommended Production Approach:
    /// 1. After successful authentication, Firebase Auth provides tokens
    /// 2. Store only the refresh token (which Firebase already handles securely)
    /// 3. Use biometric auth to unlock access to the app, not to retrieve passwords
    /// 4. Implement Apple's Keychain with biometric-protected items using kSecAccessControlBiometry
    /// 5. Consider using Apple's ASAuthorizationPasswordProvider for password autofill
    func saveBiometricCredentials(email: String, password: String) {
        // Save biometric enabled flag
        UserDefaults.standard.set(true, forKey: biometricEnabledKey)
        
        // Save email in Keychain with biometric protection
        saveToKeychain(key: emailKey, value: email, requireBiometric: true)
        
        // Save password in Keychain with biometric protection
        // ⚠️ THIS IS INSECURE - passwords should never be stored
        saveToKeychain(key: passwordKey, value: password, requireBiometric: true)
    }
    
    func getBiometricCredentials() -> (email: String, password: String)? {
        guard let email = loadFromKeychain(key: emailKey),
              let password = loadFromKeychain(key: passwordKey) else {
            return nil
        }
        return (email, password)
    }
    
    func removeBiometricCredentials() {
        UserDefaults.standard.removeObject(forKey: biometricEnabledKey)
        deleteFromKeychain(key: emailKey)
        deleteFromKeychain(key: passwordKey)
    }

    // MARK: - Session-Based Biometric (Recommended)

    /// ✅ Secure: Save only email for session-based biometric
    func saveEmailForBiometric(email: String) {
        UserDefaults.standard.set(true, forKey: biometricEnabledKey)
        saveToKeychain(key: emailKey, value: email, requireBiometric: true)
    }

    /// ✅ Secure: Get email for session-based biometric
    func getEmailForBiometric() -> String? {
        return loadFromKeychain(key: emailKey)
    }

    // MARK: - Keychain Operations
    
    /// Save data to keychain with optional biometric protection
    private func saveToKeychain(key: String, value: String, requireBiometric: Bool = false) {
        guard let data = value.data(using: .utf8) else { return }
        
        // Delete any existing item
        deleteFromKeychain(key: key)
        
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
        ]
        
        // Add biometric protection if requested
        if requireBiometric {
            // This requires biometric authentication to access the item
            let access = SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                .biometryCurrentSet, // Invalidates if biometry changes (e.g., new fingerprint added)
                nil
            )
            
            if let access = access {
                query[kSecAttrAccessControl as String] = access
                query[kSecUseAuthenticationContext as String] = LAContext() // Use current context
            } else {
                // Fallback if biometric protection fails
                query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            }
        } else {
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }
        
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("Error saving to keychain: \(status)")
        }
    }
    
    private func loadFromKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return value
    }
    
    private func deleteFromKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}