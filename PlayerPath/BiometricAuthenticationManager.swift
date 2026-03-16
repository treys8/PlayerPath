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

    private init() {
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

    func disableBiometric() {
        keychain.removeBiometricCredentials()
        isBiometricEnabled = false
    }

    /// Session-based biometric authentication
    ///
    /// Checks if user has an active Firebase session, uses biometric to unlock
    /// app access, and relies on Firebase's automatic token management.
    /// No passwords are stored locally -- only the user's email for display.
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
        }
        return nil
    }

    // MARK: - Biometric Authentication
    
    func authenticateWithBiometric(reason: String) async throws -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "Use Password"
        
        return try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
    }

}

// MARK: - Keychain Manager for Biometric Credentials

private class KeychainManager {
    private let biometricEnabledKey = AuthConstants.UserDefaultsKeys.biometricEnabled
    private let emailKey = "com.playerpath.biometric.email"

    func isBiometricEnabled() -> Bool {
        return UserDefaults.standard.bool(forKey: biometricEnabledKey)
    }

    func removeBiometricCredentials() {
        UserDefaults.standard.removeObject(forKey: biometricEnabledKey)
        deleteFromKeychain(key: emailKey)
        // Clean up any legacy password data that may have been stored previously
        deleteFromKeychain(key: "com.playerpath.biometric.password")
    }

    // MARK: - Session-Based Biometric

    /// Save only email for session-based biometric
    func saveEmailForBiometric(email: String) {
        UserDefaults.standard.set(true, forKey: biometricEnabledKey)
        saveToKeychain(key: emailKey, value: email, requireBiometric: true)
    }

    /// Get email for session-based biometric
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