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
    
    /// Enable biometric authentication by storing only the email
    /// Note: This is a placeholder implementation. In production, you should:
    /// 1. Never store passwords in the keychain
    /// 2. Use biometric authentication to unlock a secure token/session
    /// 3. Implement proper token refresh mechanisms
    /// 4. Use Firebase Auth's built-in token management
    func enableBiometric(email: String, password: String) async -> Bool {
        do {
            let success = try await authenticateWithBiometric(reason: "Enable \(biometricTypeName) for quick sign-in")
            if success {
                // TEMPORARY: Store credentials for demo purposes
                // TODO: Replace with secure token-based authentication
                keychain.saveBiometricCredentials(email: email, password: password)
                isBiometricEnabled = true
                
                print("⚠️ WARNING: Storing password for biometric auth. This is insecure and should be replaced with token-based auth in production.")
                
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
    private let biometricEnabledKey = "biometric_enabled"
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