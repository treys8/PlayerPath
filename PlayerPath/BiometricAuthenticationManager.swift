//
//  BiometricAuthenticationManager.swift
//  PlayerPath
//
//  Created by Assistant on 11/1/25.
//

import LocalAuthentication
import Foundation

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
        
        if context.canEvaluatePolicy(.biometryAny, error: &error) {
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
        
        return try await context.evaluatePolicy(.biometryAny, localizedReason: reason)
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
    private let emailKey = "biometric_email"
    private let passwordKey = "biometric_password"
    
    func isBiometricEnabled() -> Bool {
        return UserDefaults.standard.bool(forKey: biometricEnabledKey)
    }
    
    func saveBiometricCredentials(email: String, password: String) {
        // In a real implementation, you'd use Keychain Services
        // For now, using UserDefaults (NOT recommended for production)
        UserDefaults.standard.set(true, forKey: biometricEnabledKey)
        UserDefaults.standard.set(email, forKey: emailKey)
        // NOTE: Never store passwords in UserDefaults in production!
        // Use Keychain Services instead
    }
    
    func getBiometricCredentials() -> (email: String, password: String)? {
        guard let email = UserDefaults.standard.string(forKey: emailKey),
              let password = UserDefaults.standard.string(forKey: passwordKey) else {
            return nil
        }
        return (email, password)
    }
    
    func removeBiometricCredentials() {
        UserDefaults.standard.removeObject(forKey: biometricEnabledKey)
        UserDefaults.standard.removeObject(forKey: emailKey)
        UserDefaults.standard.removeObject(forKey: passwordKey)
    }
}