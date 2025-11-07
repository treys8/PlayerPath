import Foundation

/// Validation helpers for common input fields.
public enum Validation {
    /// Validates an email string using a reasonable regex.
    public static func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let predicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return predicate.evaluate(with: email)
    }

    /// Validates a person-like display name with allowed characters and length.
    /// - Parameters:
    ///   - name: The input string.
    ///   - min: Minimum length (default 2).
    ///   - max: Maximum length (default 50).
    public static func isValidPersonName(_ name: String, min: Int = 2, max: Int = 50) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count >= min, trimmed.count <= max else { return false }
        return trimmed.allSatisfy { ch in
            ch.isLetter || ch.isWhitespace || ch == "." || ch == "-" || ch == "'"
        }
    }
}
