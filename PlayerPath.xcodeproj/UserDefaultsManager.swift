//
//  UserDefaultsManager.swift
//  PlayerPath
//
//  Created by Assistant on [Date]
//  Provides sandbox-safe UserDefaults access for iOS archiving
//

import Foundation

/// A sandbox-safe UserDefaults manager that prevents archive issues
final class UserDefaultsManager {
    static let shared = UserDefaultsManager()
    
    private let userDefaults: UserDefaults
    
    private init() {
        // Create a unique suite name to avoid sandbox violations
        let bundleId = Bundle.main.bundleIdentifier ?? "com.playerpath.app"
        let suiteName = "\(bundleId).storage"
        
        // Create our own UserDefaults suite
        if let suite = UserDefaults(suiteName: suiteName) {
            self.userDefaults = suite
            print("✅ Created UserDefaults suite: \(suiteName)")
        } else {
            // Fallback to standard if suite creation fails
            self.userDefaults = UserDefaults.standard
            print("⚠️ Using standard UserDefaults (suite creation failed)")
        }
    }
    
    // MARK: - String Methods
    
    func string(forKey key: String) -> String? {
        return userDefaults.string(forKey: key)
    }
    
    func set(_ value: String?, forKey key: String) {
        userDefaults.set(value, forKey: key)
        synchronize()
    }
    
    // MARK: - Data Methods
    
    func data(forKey key: String) -> Data? {
        return userDefaults.data(forKey: key)
    }
    
    func set(_ value: Data?, forKey key: String) {
        userDefaults.set(value, forKey: key)
        synchronize()
    }
    
    // MARK: - Bool Methods
    
    func bool(forKey key: String) -> Bool {
        return userDefaults.bool(forKey: key)
    }
    
    func set(_ value: Bool, forKey key: String) {
        userDefaults.set(value, forKey: key)
        synchronize()
    }
    
    // MARK: - Integer Methods
    
    func integer(forKey key: String) -> Int {
        return userDefaults.integer(forKey: key)
    }
    
    func set(_ value: Int, forKey key: String) {
        userDefaults.set(value, forKey: key)
        synchronize()
    }
    
    // MARK: - Object Methods
    
    func object(forKey key: String) -> Any? {
        return userDefaults.object(forKey: key)
    }
    
    func set(_ value: Any?, forKey key: String) {
        userDefaults.set(value, forKey: key)
        synchronize()
    }
    
    // MARK: - Remove Methods
    
    func removeObject(forKey key: String) {
        userDefaults.removeObject(forKey: key)
        synchronize()
    }
    
    // MARK: - Synchronization
    
    @discardableResult
    private func synchronize() -> Bool {
        return userDefaults.synchronize()
    }
    
    // MARK: - Cleanup
    
    func removeAllObjects() {
        let domain = userDefaults.dictionaryRepresentation()
        for key in domain.keys {
            userDefaults.removeObject(forKey: key)
        }
        synchronize()
    }
}