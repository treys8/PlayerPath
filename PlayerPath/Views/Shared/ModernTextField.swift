//
//  ModernTextField.swift
//  PlayerPath
//
//  Modern text field with animated focus states and validation feedback
//

import SwiftUI

// MARK: - Validation State

enum FieldValidationState {
    case idle
    case valid
    case invalid
    case warning

    var borderColor: Color {
        switch self {
        case .idle: return Color(.systemGray4)
        case .valid: return .green
        case .invalid: return .red
        case .warning: return .orange
        }
    }

    var iconName: String? {
        switch self {
        case .idle: return nil
        case .valid: return "checkmark.circle.fill"
        case .invalid: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .idle: return .clear
        case .valid: return .green
        case .invalid: return .red
        case .warning: return .orange
        }
    }
}

// MARK: - Modern Text Field

struct ModernTextField: View {
    let placeholder: String
    @Binding var text: String
    var icon: String? = nil
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType? = nil
    var autocapitalization: TextInputAutocapitalization = .sentences
    var validationState: FieldValidationState = .idle
    var onSubmit: (() -> Void)? = nil

    @FocusState private var isFocused: Bool
    @State private var showPassword: Bool = false

    private var shouldShowSecure: Bool {
        isSecure && !showPassword
    }

    var body: some View {
        HStack(spacing: 12) {
            // Leading icon
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(isFocused ? .blue : Color(.systemGray2))
                    .frame(width: 24)
                    .animation(.easeInOut(duration: 0.2), value: isFocused)
            }

            // Text field
            Group {
                if shouldShowSecure {
                    SecureField(placeholder, text: $text)
                        .textContentType(textContentType)
                } else {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboardType)
                        .textContentType(textContentType)
                        .textInputAutocapitalization(autocapitalization)
                }
            }
            .font(.body)
            .focused($isFocused)
            .disableAutocorrection(isSecure || keyboardType == .emailAddress)
            .onSubmit {
                onSubmit?()
            }

            // Trailing icons
            HStack(spacing: 8) {
                // Password visibility toggle
                if isSecure && !text.isEmpty {
                    Button {
                        Haptics.light()
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                            .font(.system(size: 16))
                            .foregroundColor(Color(.systemGray2))
                    }
                    .buttonStyle(.plain)
                }

                // Validation indicator
                if let iconName = validationState.iconName, !text.isEmpty {
                    Image(systemName: iconName)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(validationState.iconColor)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: validationState)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(
                    color: isFocused ? .blue.opacity(0.15) : .black.opacity(0.04),
                    radius: isFocused ? 8 : 4,
                    x: 0,
                    y: isFocused ? 4 : 2
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isFocused ? Color.blue : validationState.borderColor,
                    lineWidth: isFocused ? 2 : 1
                )
        )
        .animation(.easeInOut(duration: 0.2), value: isFocused)
        .animation(.easeInOut(duration: 0.2), value: validationState)
    }
}

// MARK: - Modern Text Field with Label

struct LabeledModernTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var icon: String? = nil
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType? = nil
    var autocapitalization: TextInputAutocapitalization = .sentences
    var validationState: FieldValidationState = .idle
    var validationMessage: String? = nil
    var onSubmit: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Label
            Text(label)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            // Text field
            ModernTextField(
                placeholder: placeholder,
                text: $text,
                icon: icon,
                isSecure: isSecure,
                keyboardType: keyboardType,
                textContentType: textContentType,
                autocapitalization: autocapitalization,
                validationState: validationState,
                onSubmit: onSubmit
            )

            // Validation message
            if let message = validationMessage, !text.isEmpty {
                HStack(spacing: 4) {
                    if let iconName = validationState.iconName {
                        Image(systemName: iconName)
                            .font(.caption2)
                    }
                    Text(message)
                        .font(.caption)
                }
                .foregroundColor(validationState.iconColor)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.2), value: validationMessage)
            }
        }
    }
}

// MARK: - Password Strength Indicator

struct PasswordStrengthIndicator: View {
    let password: String

    private var strength: (level: Int, text: String, color: Color) {
        var score = 0

        if password.count >= 8 { score += 1 }
        if password.count >= 12 { score += 1 }
        if password.range(of: "[A-Z]", options: .regularExpression) != nil { score += 1 }
        if password.range(of: "[a-z]", options: .regularExpression) != nil { score += 1 }
        if password.range(of: "[0-9]", options: .regularExpression) != nil { score += 1 }
        if password.range(of: "[^A-Za-z0-9]", options: .regularExpression) != nil { score += 1 }

        switch score {
        case 0...2: return (1, "Weak", .red)
        case 3...4: return (2, "Medium", .orange)
        case 5: return (3, "Strong", .green)
        default: return (4, "Very Strong", .green)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Strength bars
            HStack(spacing: 4) {
                ForEach(1...4, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(index <= strength.level ? strength.color : Color(.systemGray5))
                        .frame(height: 4)
                }
            }

            // Strength label
            Text(strength.text)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(strength.color)
        }
        .animation(.easeInOut(duration: 0.2), value: strength.level)
    }
}

// MARK: - Password Requirements List

struct PasswordRequirementsList: View {
    let password: String

    private var requirements: [(String, Bool)] {
        [
            ("At least 8 characters", password.count >= 8),
            ("Uppercase letter", password.range(of: "[A-Z]", options: .regularExpression) != nil),
            ("Lowercase letter", password.range(of: "[a-z]", options: .regularExpression) != nil),
            ("Number", password.range(of: "[0-9]", options: .regularExpression) != nil)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(requirements, id: \.0) { requirement, isMet in
                HStack(spacing: 8) {
                    Image(systemName: isMet ? "checkmark.circle.fill" : "circle")
                        .font(.caption)
                        .foregroundColor(isMet ? .green : Color(.systemGray3))

                    Text(requirement)
                        .font(.caption)
                        .foregroundColor(isMet ? .primary : .secondary)
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Modern Text Field") {
    VStack(spacing: 20) {
        ModernTextField(
            placeholder: "Enter email",
            text: .constant(""),
            icon: "envelope.fill",
            keyboardType: .emailAddress
        )

        ModernTextField(
            placeholder: "Enter email",
            text: .constant("test@example.com"),
            icon: "envelope.fill",
            keyboardType: .emailAddress,
            validationState: .valid
        )

        ModernTextField(
            placeholder: "Enter password",
            text: .constant("password"),
            icon: "lock.fill",
            isSecure: true,
            validationState: .warning
        )
    }
    .padding()
}

#Preview("Labeled Field") {
    LabeledModernTextField(
        label: "Email",
        placeholder: "you@example.com",
        text: .constant("test@example.com"),
        icon: "envelope.fill",
        keyboardType: .emailAddress,
        validationState: .valid,
        validationMessage: "Valid email address"
    )
    .padding()
}

#Preview("Password Strength") {
    VStack(spacing: 20) {
        PasswordStrengthIndicator(password: "abc")
        PasswordStrengthIndicator(password: "Abc12345")
        PasswordStrengthIndicator(password: "Abc12345!@#")
    }
    .padding()
}
