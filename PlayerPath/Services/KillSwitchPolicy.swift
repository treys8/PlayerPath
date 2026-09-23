//
//  KillSwitchPolicy.swift
//  PlayerPath
//
//  Pure parsing for the remote kill switches in Firestore `appConfig/killSwitches`.
//  Foundation-only on purpose: tools/KillSwitchPolicyCheck compiles this file on
//  its own to check the parsing, since the app has no test target.
//

import Foundation

/// A feature that can be switched OFF remotely. Kill-only: every case ships ON
/// (the state App Review saw), and the remote doc can only take it away — it can
/// never reveal anything, which is what App Store guideline 2.3.1 cares about.
///
/// Recruiting is deliberately NOT a case. See `RecruitingFeature`: a remote flip
/// could strand a published page with no route to its unpublish control, and its
/// server half already has a stronger kill (a rules or `serveRecruitingProfile` deploy).
enum KillSwitch: String, CaseIterable {
    case bulkVideoImport
    case bulkPhotoImport
    case reelGeneration
    case engagementNudges
}

/// Doc shape, one map per switch (anything else is ignored):
///
///     bulkVideoImport: { off: true, upToVersion: "6.4.5", message: "…" }
///
/// `upToVersion` and `message` are optional.
enum KillSwitchPolicy {
    static let maxMessageLength = 200

    /// The switches that are OFF for `appVersion`, keyed by raw value, each with
    /// its user-facing message ("" means use the default copy).
    static func activeKills(in data: [String: Any], appVersion: String) -> [String: String] {
        var kills: [String: String] = [:]
        for kill in KillSwitch.allCases {
            guard let entry = data[kill.rawValue] as? [String: Any],
                  isOff(entry["off"]),
                  appliesTo(appVersion: appVersion, upToVersion: entry["upToVersion"]) else { continue }
            kills[kill.rawValue] = message(entry["message"])
        }
        return kills
    }

    /// `true`, or the string "true" in any case. The Firebase console defaults a
    /// new field to string, so that's the likeliest way the flag gets typed.
    static func isOff(_ value: Any?) -> Bool {
        if let flag = value as? Bool { return flag }
        if let text = value as? String {
            return text.trimmingCharacters(in: .whitespaces).lowercased() == "true"
        }
        return false
    }

    /// No `upToVersion` → every version. A dotted-number `upToVersion` → only app
    /// versions at or below it, so the build that fixes the bug comes back on by
    /// itself. Anything unreadable (a typo, a number instead of a string, an app
    /// version that isn't dotted numbers) covers every version: the author meant
    /// to kill, and for a kill switch the safe failure is "off".
    static func appliesTo(appVersion: String, upToVersion: Any?) -> Bool {
        guard let raw = upToVersion as? String,
              !raw.trimmingCharacters(in: .whitespaces).isEmpty,
              let limit = versionComponents(raw),
              let current = versionComponents(appVersion) else { return true }
        return compare(current, limit) <= 0
    }

    /// "6.4.5" → [6, 4, 5]. Nil unless every dot-separated part is a non-negative integer.
    static func versionComponents(_ version: String) -> [Int]? {
        let parts = version.trimmingCharacters(in: .whitespaces)
            .split(separator: ".", omittingEmptySubsequences: false)
        var components: [Int] = []
        for part in parts {
            guard let number = Int(part), number >= 0 else { return nil }
            components.append(number)
        }
        return components.isEmpty ? nil : components
    }

    /// Numeric, missing parts count as 0 ("6.4" == "6.4.0"). -1 / 0 / 1.
    static func compare(_ lhs: [Int], _ rhs: [Int]) -> Int {
        for i in 0..<max(lhs.count, rhs.count) {
            let l = i < lhs.count ? lhs[i] : 0
            let r = i < rhs.count ? rhs[i] : 0
            if l != r { return l < r ? -1 : 1 }
        }
        return 0
    }

    /// Trimmed and capped; "" when absent or not a string.
    static func message(_ value: Any?) -> String {
        guard let text = value as? String else { return "" }
        return String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxMessageLength))
    }
}
