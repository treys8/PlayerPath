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
@MainActor
final class FormValidator: ObservableObject {
    static let shared = FormValidator()

    private init() {}
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
