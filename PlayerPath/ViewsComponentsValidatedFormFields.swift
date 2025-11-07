//
//  ValidatedFormFields.swift
//  PlayerPath
//
//  Created by Assistant on 10/26/25.
//

import SwiftUI

// MARK: - Validated Text Field
struct ValidatedTextField: View {
    let title: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .sentences
    var disableAutocorrection: Bool = false
    var accessibilityLabel: String? = nil
    var accessibilityHint: String? = nil
    var submitLabel: SubmitLabel = .next
    var onSubmit: (() -> Void)? = nil
    let validator: (String) -> ValidationResult
    
    @State private var validationResult: ValidationResult?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(title, text: $text)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .keyboardType(keyboardType)
                .textInputAutocapitalization(autocapitalization)
                .disableAutocorrection(disableAutocorrection)
                .accessibilityLabel(accessibilityLabel ?? title)
                .accessibilityHint(accessibilityHint ?? "Enter your \(title.lowercased())")
                .submitLabel(submitLabel)
                .onSubmit {
                    onSubmit?()
                }
                .onChange(of: text) { _, newValue in
                    if !newValue.isEmpty {
                        validationResult = validator(newValue)
                    } else {
                        validationResult = nil
                    }
                }
            
            if let result = validationResult {
                ValidationFeedbackView(result: result)
            }
        }
    }
}

// MARK: - Validated Secure Field
struct ValidatedSecureField: View {
    let title: String
    @Binding var text: String
    var isSignUp: Bool = false
    var accessibilityLabel: String? = nil
    var accessibilityHint: String? = nil
    var submitLabel: SubmitLabel = .go
    var onSubmit: (() -> Void)? = nil
    let validator: (String) -> ValidationResult
    
    @State private var validationResult: ValidationResult?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SecureField(title, text: $text)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .accessibilityLabel(accessibilityLabel ?? title)
                .accessibilityHint(accessibilityHint ?? "Enter your \(title.lowercased())")
                .submitLabel(submitLabel)
                .onSubmit {
                    onSubmit?()
                }
                .onChange(of: text) { _, newValue in
                    if !newValue.isEmpty {
                        validationResult = validator(newValue)
                    } else {
                        validationResult = nil
                    }
                }
            
            if let result = validationResult {
                if isSignUp && !result.isValid {
                    PasswordRequirementsView(password: text)
                } else {
                    ValidationFeedbackView(result: result)
                }
            }
        }
    }
}

// MARK: - Validation Feedback View
struct ValidationFeedbackView: View {
    let result: ValidationResult
    
    var body: some View {
        HStack {
            Image(systemName: result.isValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(result.isValid ? .green : .orange)
                .font(.caption)
            Text(result.message)
                .font(.caption2)
                .foregroundColor(result.isValid ? .green : .orange)
            Spacer()
        }
        .padding(.horizontal)
    }
}

// MARK: - Password Requirements View
struct PasswordRequirementsView: View {
    let password: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
                    .font(.caption)
                Text("Password requirements:")
                    .font(.caption2)
                    .foregroundColor(.blue)
                Spacer()
            }
            .padding(.horizontal)
            
            VStack(alignment: .leading, spacing: 2) {
                ForEach(FormValidator.shared.getPasswordRequirements(for: password), id: \.text) { requirement in
                    ValidationRequirementRow(requirement: requirement)
                }
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - Validation Requirement Row
struct ValidationRequirementRow: View {
    let requirement: PasswordRequirement
    
    var body: some View {
        HStack {
            Image(systemName: requirement.isMet ? "checkmark.circle.fill" : "circle")
                .foregroundColor(requirement.isMet ? .green : .gray)
                .font(.caption2)
            Text(requirement.text)
                .font(.caption2)
                .foregroundColor(requirement.isMet ? .green : .gray)
        }
    }
}