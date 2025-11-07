import Foundation

/// A utility struct providing validation methods for common data types.
public struct Validation {
    
    /// Validates if the given string is a valid email address.
    ///
    /// - Parameter email: The email string to validate.
    /// - Returns: `true` if the email is valid, otherwise `false`.
    public static func isValidEmail(_ email: String) -> Bool {
        // Basic RFC 5322 email regex pattern
        let emailRegex =
        "(?:[a-zA-Z0-9!#$%\\&'*+/=?^_`{|}~-]+(?:\\." +
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
        
        let predicate = NSPredicate(format: "SELF MATCHES[c] %@", emailRegex)
        return predicate.evaluate(with: email)
    }
    
    /// Validates if the given string is a valid person name.
    ///
    /// This checks if the name contains only letters (including Unicode), spaces, apostrophes, and hyphens.
    /// It also requires the name to be at least two characters long.
    ///
    /// - Parameter name: The person name string to validate.
    /// - Returns: `true` if the name is valid, otherwise `false`.
    public static func isValidPersonName(_ name: String) -> Bool {
        // Regex allowing letters, spaces, hyphens, apostrophes; minimum length 2
        let nameRegex = "^[\\p{L}][\\p{L} '\\-]{1,}$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", nameRegex)
        return predicate.evaluate(with: name)
    }
}
