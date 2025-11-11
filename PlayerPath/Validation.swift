import Foundation

/// A utility struct providing validation methods for common data types.
public struct Validators {
    // MARK: - Patterns & Predicates
    private struct Patterns {
        // Basic RFC 5322 email regex pattern
        static let email = "(?:[a-zA-Z0-9!#$%\\&'*+/=?^_`{|}~-]+(?:\\." +
        "[a-zA-Z0-9!#$%\\&'*+/=?^_`{|}~-]+)*|\"" +
        "(?:[\u{01}-\u{08}\u{0b}\u{0c}\u{0e}-\u{1f}" +
        "\u{21}\u{23}-\u{5b}\u{5d}-\u{7f}]|" +
        "\\\\[\u{01}-\u{09}\u{0b}\u{0c}\u{0e}-\u{7f}])*\"" +
        ")@(?:(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]*" +
        "[a-zA-Z0-9])?\\.)+[a-zA-Z0-9]" +
        "(?:[a-zA-Z0-9-]*[a-zA-Z0-9])?|" +
        "\\[(?:(?:(2(5[0-5]|[0-4][0-9])|" +
        "1[0-9][0-9]|[1-9]?[0-9]))\\.){3}" +
        "(?:(2(5[0-5]|[0-4][0-9])|" +
        "1[0-9][0-9]|[1-9]?[0-9])|" +
        "[a-zA-Z0-9-]*[a-zA-Z0-9]:" +
        "(?:[\u{01}-\u{08}\u{0b}\u{0c}\u{0e}-\u{1f}" +
        "\u{21}-\u{5a}\u{53}-\u{7f}]|" +
        "\\\\[\u{01}-\u{09}\u{0b}\u{0c}\u{0e}-\u{7f}])+)\\])"

        // Person name: letters (unicode), spaces, hyphens, apostrophes; >= 2 chars
        static let personName = "^[\\p{L}][\\p{L} '\\-]{1,}$"

        // E.164 international phone numbers (e.g., +14155552671)
        static let phoneE164 = "^\\+[1-9]\\d{1,14}$"

        // URL basic validation (scheme://host ...); use URL initializer for strictness
        static let url = "^([a-zA-Z][a-zA-Z0-9+.-]*):\\/\\/[^\\s]+$"

        // Password: min 8, at least 1 lowercase, 1 uppercase, 1 digit; optional special char
        static let passwordStrong = "^(?=.*[a-z])(?=.*[A-Z])(?=.*\\d)[A-Za-z\\d!@#$%^&*()_+=\\-{}\\[\\]\\|:;\"'<>,.?/]{8,}$"
    }

    private static let emailPredicate = NSPredicate(format: "SELF MATCHES[c] %@", Patterns.email)
    private static let personNamePredicate = NSPredicate(format: "SELF MATCHES %@", Patterns.personName)
    private static let phonePredicate = NSPredicate(format: "SELF MATCHES %@", Patterns.phoneE164)
    private static let urlPredicate = NSPredicate(format: "SELF MATCHES[c] %@", Patterns.url)
    private static let passwordPredicate = NSPredicate(format: "SELF MATCHES %@", Patterns.passwordStrong)
    
    // MARK: - Helpers
    @inline(__always)
    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Normalize to NFC to reduce spurious differences in composed/ decomposed forms
    private static func normalizedNFC(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping
    }

    /// Validates if the given string is a valid email address.
    ///
    /// - Parameter email: The email string to validate.
    /// - Returns: `true` if the email is valid, otherwise `false`.
    public static func isValidEmail(_ email: String) -> Bool {
        let trimmed = trimmed(email)
        // Lowercase only the domain part for normalization
        let normalizedEmail: String = {
            guard let atIndex = trimmed.firstIndex(of: "@") else { return trimmed }
            let local = trimmed[..<atIndex]
            let domain = trimmed[trimmed.index(after: atIndex)...].lowercased()
            return String(local) + "@" + domain
        }()
        return emailPredicate.evaluate(with: normalizedEmail)
    }
    
    /// Validates if the given string is a valid person name.
    ///
    /// This checks if the name contains only letters (including Unicode), spaces, apostrophes, and hyphens.
    /// It also requires the name to be at least two characters long.
    ///
    /// - Parameter name: The person name string to validate.
    /// - Returns: `true` if the name is valid, otherwise `false`.
    public static func isValidPersonName(_ name: String) -> Bool {
        let trimmedName = trimmed(name)
        guard trimmedName.count >= 2 else { return false }
        let normalized = normalizedNFC(trimmedName)
        return personNamePredicate.evaluate(with: normalized)
    }
    
    /// Validates if the given string is a non-empty value after trimming whitespace and newlines.
    public static func isNonEmpty(_ text: String) -> Bool {
        !trimmed(text).isEmpty
    }

    /// Validates if the given string is a valid E.164 phone number (e.g., +14155552671).
    public static func isValidPhoneE164(_ phone: String) -> Bool {
        let trimmed = trimmed(phone)
        return phonePredicate.evaluate(with: trimmed)
    }

    /// Validates if the given string looks like a URL. Uses URL initializer for stricter validation.
    public static func isValidURL(_ urlString: String) -> Bool {
        let trimmed = trimmed(urlString)
        guard urlPredicate.evaluate(with: trimmed) else { return false }
        guard let url = URL(string: trimmed), let scheme = url.scheme, let host = url.host, !scheme.isEmpty, !host.isEmpty else {
            return false
        }
        return true
    }

    /// Validates password strength: at least 8 characters, 1 uppercase, 1 lowercase, and 1 digit.
    public static func isStrongPassword(_ password: String) -> Bool {
        passwordPredicate.evaluate(with: password)
    }

    /// Validates a username: 3-32 chars, letters, digits, underscore, dot; cannot start/end with dot or underscore; no consecutive dots.
    public static func isValidUsername(_ username: String) -> Bool {
        let u = trimmed(username)
        // Quick length check
        guard (3...32).contains(u.count) else { return false }
        // Pattern enforces allowed chars and simple placement rules
        let pattern = "^(?![._])(?!.*[.]{2})[A-Za-z0-9._]{3,32}(?<![._])$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", pattern)
        return predicate.evaluate(with: u)
    }

    /// Checks whether the text contains only letters (Unicode).
    public static func isLettersOnly(_ text: String) -> Bool {
        let t = trimmed(text)
        guard !t.isEmpty else { return false }
        let pattern = "^[\\p{L}]+$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", pattern)
        return predicate.evaluate(with: t)
    }

    /// Checks whether the text is at least a given length after trimming.
    public static func hasMinimumLength(_ text: String, _ min: Int) -> Bool {
        trimmed(text).count >= max(0, min)
    }

    /// Checks whether the text is alphanumeric (letters or digits, Unicode letters allowed).
    public static func isAlphanumeric(_ text: String) -> Bool {
        let t = trimmed(text)
        guard !t.isEmpty else { return false }
        let pattern = "^[\\p{L}0-9]+$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", pattern)
        return predicate.evaluate(with: t)
    }
    
    /// Validates a string using the Luhn algorithm (e.g., credit card numbers). Non-digits are ignored.
    public static func isValidLuhn(_ input: String) -> Bool {
        let digits = trimmed(input).filter { $0.isNumber }
        guard digits.count >= 2 else { return false }
        var sum = 0
        var doubleIt = false
        for ch in digits.reversed() {
            guard let d = ch.wholeNumberValue else { return false }
            var add = d
            if doubleIt {
                add *= 2
                if add > 9 { add -= 9 }
            }
            sum += add
            doubleIt.toggle()
        }
        return sum % 10 == 0
    }

    /// Checks that the string contains no control characters (including newlines) after trimming.
    public static func containsNoControlCharacters(_ input: String) -> Bool {
        let t = trimmed(input)
        let controlSet = CharacterSet.controlCharacters
        return t.unicodeScalars.allSatisfy { !controlSet.contains($0) }
    }
}

