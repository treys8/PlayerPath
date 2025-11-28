//
//  FormValidator.swift
//  PlayerPath
//
//  Created by Assistant on 10/26/25.
//

import Foundation
import Combine

// MARK: - Validation Result
struct ValidationResult {
    let isValid: Bool
    let message: String
    
    static let valid = ValidationResult(isValid: true, message: "Valid")
    
    static func invalid(_ message: String) -> ValidationResult {
        ValidationResult(isValid: false, message: message)
    }
}

// MARK: - Form Validator
final class FormValidator: ObservableObject {
    static let shared = FormValidator()

    private init() {}

    // MARK: - Email Validation

    func validateEmail(_ email: String) -> ValidationResult {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedEmail.isEmpty else {
            return .invalid("Email cannot be empty")
        }

        // Improved email regex to prevent consecutive dots and @ symbols
        let emailRegex = "^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}$"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)

        guard emailPredicate.evaluate(with: trimmedEmail) else {
            return .invalid("Please enter a valid email address")
        }

        // Additional checks for invalid patterns
        guard !trimmedEmail.contains("..") else {
            return .invalid("Email cannot contain consecutive dots")
        }

        guard !trimmedEmail.contains("@@") else {
            return .invalid("Email cannot contain multiple @ symbols")
        }

        // Check that @ is not first or last character
        guard !trimmedEmail.hasPrefix("@") && !trimmedEmail.hasSuffix("@") else {
            return .invalid("Invalid email format")
        }

        return .valid
    }
    
    // MARK: - Password Validation
    
    func validatePasswordBasic(_ password: String) -> ValidationResult {
        guard !password.isEmpty else {
            return .invalid("Password cannot be empty")
        }
        
        return .valid
    }
    
    func validatePasswordStrong(_ password: String) -> ValidationResult {
        let requirements: [(Bool, String)] = [
            (password.count >= 8, "At least 8 characters"),
            (password.range(of: "[A-Z]", options: .regularExpression) != nil, "Contains uppercase letter"),
            (password.range(of: "[a-z]", options: .regularExpression) != nil, "Contains lowercase letter"),
            (password.range(of: "[0-9]", options: .regularExpression) != nil, "Contains number")
        ]
        
        let unmetRequirements = requirements.filter { !$0.0 }.map { $0.1 }
        
        if unmetRequirements.isEmpty {
            return .valid
        } else {
            return .invalid("Missing: \(unmetRequirements.joined(separator: ", "))")
        }
    }
    
    // MARK: - Display Name Validation

    func validateDisplayName(_ name: String) -> ValidationResult {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            return .invalid("Name cannot be empty")
        }

        guard trimmedName.count >= 2 else {
            return .invalid("Name must be at least 2 characters")
        }

        guard trimmedName.count <= 30 else {
            return .invalid("Name must be 30 characters or less")
        }

        let allowedCharacters = CharacterSet.letters.union(.whitespaces).union(CharacterSet(charactersIn: ".-'"))
        guard trimmedName.unicodeScalars.allSatisfy(allowedCharacters.contains) else {
            return .invalid("Name can only contain letters, spaces, periods, hyphens, and apostrophes")
        }

        // Prevent consecutive special characters
        let specialCharPatterns = [
            "--", "...", "''", "  ", ".-", "-.", ". ", " ."
        ]
        for pattern in specialCharPatterns {
            if trimmedName.contains(pattern) {
                return .invalid("Name cannot contain consecutive special characters or unusual spacing")
            }
        }

        // Name must contain at least one letter
        guard trimmedName.rangeOfCharacter(from: .letters) != nil else {
            return .invalid("Name must contain at least one letter")
        }

        return .valid
    }
    
    // MARK: - Athlete Name Validation

    func validateAthleteName(_ name: String, existingNames: [String] = []) -> ValidationResult {
        let displayNameResult = validateDisplayName(name)
        guard displayNameResult.isValid else {
            return displayNameResult
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedName.count <= 50 else {
            return .invalid("Name must be 50 characters or less")
        }

        // Optimized duplicate check using Set for O(1) lookup
        let lowercaseName = trimmedName.lowercased()
        let existingNamesSet = Set(existingNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })

        guard !existingNamesSet.contains(lowercaseName) else {
            return .invalid("An athlete with this name already exists")
        }

        return .valid
    }
    
    // MARK: - Form Submission Validation
    
    func canSubmitSignInForm(email: String, password: String, displayName: String, isSignUp: Bool) -> Bool {
        let emailValid = validateEmail(email).isValid
        let passwordValid = isSignUp ? validatePasswordStrong(password).isValid : validatePasswordBasic(password).isValid
        let displayNameValid = isSignUp ? (displayName.isEmpty || validateDisplayName(displayName).isValid) : true
        
        return emailValid && passwordValid && displayNameValid
    }
}

// MARK: - Password Requirements
extension FormValidator {
    func getPasswordRequirements(for password: String) -> [PasswordRequirement] {
        [
            PasswordRequirement(
                text: "At least 8 characters",
                isMet: password.count >= 8
            ),
            PasswordRequirement(
                text: "Contains uppercase letter",
                isMet: password.range(of: "[A-Z]", options: .regularExpression) != nil
            ),
            PasswordRequirement(
                text: "Contains lowercase letter",
                isMet: password.range(of: "[a-z]", options: .regularExpression) != nil
            ),
            PasswordRequirement(
                text: "Contains number",
                isMet: password.range(of: "[0-9]", options: .regularExpression) != nil
            )
        ]
    }
}

struct PasswordRequirement {
    let text: String
    let isMet: Bool
}