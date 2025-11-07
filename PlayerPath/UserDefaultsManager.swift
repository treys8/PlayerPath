//
//  UserDefaultsManager.swift
//  PlayerPath
//
//  Created by Assistant on 11/1/25.
//

import Foundation

/// Manages UserDefaults operations with sandbox safety and convenience methods
final class UserDefaultsManager {
    static let shared = UserDefaultsManager()
    
    private let userDefaults: UserDefaults
    
    private init() {
        // Use standard UserDefaults for the main app
        self.userDefaults = UserDefaults.standard
    }
    
    // MARK: - Generic Storage Methods
    
    func set(_ value: Any?, forKey key: String) {
        userDefaults.set(value, forKey: key)
    }
    
    func object(forKey key: String) -> Any? {
        return userDefaults.object(forKey: key)
    }
    
    func removeObject(forKey key: String) {
        userDefaults.removeObject(forKey: key)
    }
    
    // MARK: - Typed Accessors
    
    func string(forKey key: String) -> String? {
        return userDefaults.string(forKey: key)
    }
    
    func bool(forKey key: String) -> Bool {
        return userDefaults.bool(forKey: key)
    }
    
    func integer(forKey key: String) -> Int {
        return userDefaults.integer(forKey: key)
    }
    
    func double(forKey key: String) -> Double {
        return userDefaults.double(forKey: key)
    }
    
    func data(forKey key: String) -> Data? {
        return userDefaults.data(forKey: key)
    }
    
    func array(forKey key: String) -> [Any]? {
        return userDefaults.array(forKey: key)
    }
    
    func dictionary(forKey key: String) -> [String: Any]? {
        return userDefaults.dictionary(forKey: key)
    }
    
    // MARK: - Typed Setters
    
    func set(_ value: String?, forKey key: String) {
        userDefaults.set(value, forKey: key)
    }
    
    func set(_ value: Bool, forKey key: String) {
        userDefaults.set(value, forKey: key)
    }
    
    func set(_ value: Int, forKey key: String) {
        userDefaults.set(value, forKey: key)
    }
    
    func set(_ value: Double, forKey key: String) {
        userDefaults.set(value, forKey: key)
    }
    
    func set(_ value: Data?, forKey key: String) {
        userDefaults.set(value, forKey: key)
    }
    
    func set(_ value: [Any]?, forKey key: String) {
        userDefaults.set(value, forKey: key)
    }
    
    func set(_ value: [String: Any]?, forKey key: String) {
        userDefaults.set(value, forKey: key)
    }
    
    // MARK: - Utility Methods
    
    func synchronize() -> Bool {
        return userDefaults.synchronize()
    }
    
    func hasValue(forKey key: String) -> Bool {
        return userDefaults.object(forKey: key) != nil
    }
    
    // MARK: - Batch Operations
    
    func setMultiple(_ values: [String: Any]) {
        for (key, value) in values {
            userDefaults.set(value, forKey: key)
        }
    }
    
    func removeMultiple(keys: [String]) {
        for key in keys {
            userDefaults.removeObject(forKey: key)
        }
    }
    
    // MARK: - Debug Helpers
    
    func allKeys() -> [String] {
        return Array(userDefaults.dictionaryRepresentation().keys)
    }
    
    func printAll() {
        let dict = userDefaults.dictionaryRepresentation()
        print("UserDefaults contents:")
        for (key, value) in dict.sorted(by: { $0.key < $1.key }) {
            print("  \(key): \(value)")
        }
    }
}