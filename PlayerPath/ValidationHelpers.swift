import Foundation

// MARK: - Validation Enum (Simple Helpers)

/// Simple validation helpers for common input fields.
public enum Validation {
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

    /// Loose shape check: `something@something.tld`, no spaces. Catches typos
    /// ("name@gmail", "name gmail.com") without rejecting real-but-odd addresses —
    /// used to WARN, never to block.
    public static func isPlausibleEmail(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(" "),
              let at = trimmed.firstIndex(of: "@"),
              trimmed.filter({ $0 == "@" }).count == 1 else { return false }
        let local = trimmed[..<at]
        let domain = trimmed[trimmed.index(after: at)...]
        guard !local.isEmpty, let dot = domain.lastIndex(of: ".") else { return false }
        return domain.startIndex < dot && domain.index(after: dot) < domain.endIndex
    }
}
