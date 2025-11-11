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
    
    func enableBiometric(email: String, password: String) async -> Bool {
        do {
            let success = try await authenticateWithBiometric(reason: "Enable \(biometricTypeName) for quick sign-in")
            if success {
                keychain.saveBiometricCredentials(email: email, password: password)
                isBiometricEnabled = true
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
    
    func saveBiometricCredentials(email: String, password: String) {
        // Save biometric enabled flag
        UserDefaults.standard.set(true, forKey: biometricEnabledKey)
        
        // Save email in Keychain
        saveToKeychain(key: emailKey, value: email)
        
        // Save password in Keychain
        saveToKeychain(key: passwordKey, value: password)
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
    
    private func saveToKeychain(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        
        // Delete any existing item
        deleteFromKeychain(key: key)
        
        // Create new keychain item
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
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