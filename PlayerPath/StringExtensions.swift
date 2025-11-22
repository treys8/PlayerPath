//
//  StringExtensions.swift
//  PlayerPath
//
//  Created by Assistant on 11/22/25.
//  Useful string utilities and validation
//

import Foundation

extension String {
    
    // MARK: - Validation
    
    /// Check if string is a valid email address
    var isValidEmail: Bool {
        let emailRegex = "^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}$"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: self.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    
    /// Check if string is not empty after trimming whitespace
    var isNotEmpty: Bool {
        !self.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    /// Get trimmed version of string
    var trimmed: String {
        self.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Formatting
    
    /// Capitalize first letter only
    var capitalizedFirst: String {
        guard let first = self.first else { return self }
        return first.uppercased() + self.dropFirst()
    }
    
    /// Remove all whitespace
    var removingWhitespace: String {
        self.replacingOccurrences(of: " ", with: "")
    }
    
    /// Phone number formatting (simple US format)
    var formattedPhoneNumber: String {
        let digits = self.filter { $0.isNumber }
        guard digits.count == 10 else { return self }
        
        let areaCode = String(digits.prefix(3))
        let middle = String(digits.dropFirst(3).prefix(3))
        let last = String(digits.suffix(4))
        
        return "(\(areaCode)) \(middle)-\(last)"
    }
}

// MARK: - Localized Strings

extension String {
    /// Easy localization helper
    /// Usage: "profile.title".localized
    var localized: String {
        NSLocalizedString(self, comment: "")
    }
    
    /// Localized with arguments
    /// Usage: "profile.count".localized(count)
    func localized(_ arguments: CVarArg...) -> String {
        String(format: self.localized, arguments: arguments)
    }
}

// MARK: - Profile String Constants

enum ProfileStrings {
    // Main sections
    static let title = "Profile & Settings"
    static let athletes = "Athletes"
    static let settings = "Settings"
    static let account = "Account"
    
    // Actions
    static let signOut = "Sign Out"
    static let save = "Save"
    static let cancel = "Cancel"
    static let delete = "Delete"
    static let edit = "Edit"
    static let done = "Done"
    
    // Premium
    static let upgradeToPremium = "Upgrade to Premium"
    static let premiumMember = "Premium Member"
    static let premiumRequired = "Premium Required"
    
    // Messages
    static let signOutConfirmation = "Are you sure you want to sign out? You can always sign back in later."
    static let deleteAthleteConfirmation = "This will delete the athlete and related data. This action cannot be undone."
    static let premiumCoachMessage = "Share folders with your coaches to get personalized feedback. Upgrade to Premium to unlock coach collaboration features."
    
    // Errors
    static let deleteFailed = "Failed to delete athlete: %@"
    static let saveFailed = "Failed to save changes: %@"
    static let pleaseRetry = "Please try again."
}

// MARK: - Validation Helpers
// Note: ValidationResult is defined in UtilitiesFormValidator.swift

extension String {
    /// Validate username
    func validateUsername() -> ValidationResult {
        guard self.isNotEmpty else {
            return .invalid("Username cannot be empty")
        }
        
        guard self.count >= 3 else {
            return .invalid("Username must be at least 3 characters")
        }
        
        guard self.count <= 30 else {
            return .invalid("Username must be less than 30 characters")
        }
        
        return .valid
    }
    
    /// Validate email
    func validateEmail() -> ValidationResult {
        guard self.isNotEmpty else {
            return .invalid("Email cannot be empty")
        }
        
        guard self.isValidEmail else {
            return .invalid("Please enter a valid email address")
        }
        
        return .valid
    }
}
