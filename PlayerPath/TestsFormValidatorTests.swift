//
//  FormValidatorTests.swift
//  PlayerPathTests
//
//  Created by Assistant on 10/26/25.
//

import Testing
@testable import PlayerPath

@Suite("Form Validation Tests")
struct FormValidatorTests {
    
    // MARK: - Email Validation Tests
    
    @Test("Valid email addresses")
    func validEmailAddresses() async throws {
        let validator = FormValidator.shared
        let validEmails = [
            "user@example.com",
            "test.email@domain.co.uk",
            "user+tag@example.org",
            "123@example.com"
        ]
        
        for email in validEmails {
            let result = validator.validateEmail(email)
            #expect(result.isValid, "Email \(email) should be valid")
        }
    }
    
    @Test("Invalid email addresses")
    func invalidEmailAddresses() async throws {
        let validator = FormValidator.shared
        let invalidEmails = [
            "",
            "invalid",
            "@example.com",
            "user@",
            "user space@example.com",
            "user@.com"
        ]
        
        for email in invalidEmails {
            let result = validator.validateEmail(email)
            #expect(!result.isValid, "Email \(email) should be invalid")
        }
    }
    
    // MARK: - Password Validation Tests
    
    @Test("Strong password validation")
    func strongPasswordValidation() async throws {
        let validator = FormValidator.shared
        
        let validPasswords = [
            "Password123",
            "MyStr0ngP@ss",
            "ComplexPass1"
        ]
        
        for password in validPasswords {
            let result = validator.validatePasswordStrong(password)
            #expect(result.isValid, "Password \(password) should be valid")
        }
    }
    
    @Test("Weak password validation")
    func weakPasswordValidation() async throws {
        let validator = FormValidator.shared
        
        let weakPasswords = [
            "short",           // Too short
            "nouppercase123",  // No uppercase
            "NOLOWERCASE123",  // No lowercase
            "NoNumbers",       // No numbers
            ""                 // Empty
        ]
        
        for password in weakPasswords {
            let result = validator.validatePasswordStrong(password)
            #expect(!result.isValid, "Password \(password) should be invalid")
        }
    }
    
    // MARK: - Display Name Validation Tests
    
    @Test("Valid display names")
    func validDisplayNames() async throws {
        let validator = FormValidator.shared
        let validNames = [
            "John Doe",
            "Mary-Jane",
            "O'Connor",
            "Dr. Smith"
        ]
        
        for name in validNames {
            let result = validator.validateDisplayName(name)
            #expect(result.isValid, "Name \(name) should be valid")
        }
    }
    
    @Test("Invalid display names")
    func invalidDisplayNames() async throws {
        let validator = FormValidator.shared
        let invalidNames = [
            "",                    // Empty
            "A",                   // Too short
            "A".repeated(31),      // Too long
            "John123",             // Contains numbers
            "John@Doe"             // Invalid characters
        ]
        
        for name in invalidNames {
            let result = validator.validateDisplayName(name)
            #expect(!result.isValid, "Name \(name) should be invalid")
        }
    }
    
    // MARK: - Athlete Name Validation Tests
    
    @Test("Athlete name validation with duplicates")
    func athleteNameValidationWithDuplicates() async throws {
        let validator = FormValidator.shared
        let existingNames = ["John Doe", "Jane Smith"]
        
        // Test unique name
        let uniqueResult = validator.validateAthleteName("Mike Johnson", existingNames: existingNames)
        #expect(uniqueResult.isValid, "Unique name should be valid")
        
        // Test duplicate name
        let duplicateResult = validator.validateAthleteName("John Doe", existingNames: existingNames)
        #expect(!duplicateResult.isValid, "Duplicate name should be invalid")
        
        // Test case-insensitive duplicate
        let caseInsensitiveResult = validator.validateAthleteName("JOHN DOE", existingNames: existingNames)
        #expect(!caseInsensitiveResult.isValid, "Case-insensitive duplicate should be invalid")
    }
}

// MARK: - Helper Extensions
private extension String {
    func repeated(_ count: Int) -> String {
        String(repeating: self, count: count)
    }
}