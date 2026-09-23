// Standalone checks for PlayerPath/Services/KillSwitchPolicy.swift.
// The app has no test target, so this compiles the policy file on its own:
//
//   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -swift-version 5 \
//     PlayerPath/Services/KillSwitchPolicy.swift tools/KillSwitchPolicyCheck/main.swift \
//     -o "$TMPDIR/killswitch-check" && "$TMPDIR/killswitch-check"

import Foundation

var failures = 0

func check(_ condition: Bool, _ label: String) {
    if condition {
        print("PASS  \(label)")
    } else {
        print("FAIL  \(label)")
        failures += 1
    }
}

func kills(_ data: [String: Any], version: String = "6.4.5") -> [String: String] {
    KillSwitchPolicy.activeKills(in: data, appVersion: version)
}

// Defaults: nothing in the doc → nothing off.
check(kills([:]).isEmpty, "empty doc kills nothing")

// Basic shape.
check(kills(["bulkVideoImport": ["off": true]]) == ["bulkVideoImport": ""], "off:true kills, default message")
check(kills(["bulkVideoImport": ["off": false]]).isEmpty, "off:false kills nothing")
check(kills(["bulkVideoImport": [:] as [String: Any]]).isEmpty, "missing off kills nothing")

// Console typing: string "true" in any case counts.
check(kills(["reelGeneration": ["off": "true"]]).keys.contains("reelGeneration"), "off:\"true\" kills")
check(kills(["reelGeneration": ["off": " TRUE "]]).keys.contains("reelGeneration"), "off:\" TRUE \" kills")
check(kills(["reelGeneration": ["off": "yes"]]).isEmpty, "off:\"yes\" kills nothing")

// Non-map entries and unknown keys are ignored.
check(kills(["reelGeneration": true]).isEmpty, "non-map entry ignored")
check(kills(["recruiting": ["off": true]]).isEmpty, "unknown key ignored (recruiting is not a switch)")

// upToVersion: numeric comparison, inclusive.
let capped: [String: Any] = ["bulkPhotoImport": ["off": true, "upToVersion": "6.4.5"]]
check(!kills(capped, version: "6.4.5").isEmpty, "same version is covered")
check(!kills(capped, version: "6.4").isEmpty, "6.4 == 6.4.0 <= 6.4.5 is covered")
check(!kills(capped, version: "6.4.4").isEmpty, "older version is covered")
check(kills(capped, version: "6.4.6").isEmpty, "newer patch is not covered")
check(kills(capped, version: "6.5").isEmpty, "newer minor is not covered")
let tenVsNine: [String: Any] = ["bulkPhotoImport": ["off": true, "upToVersion": "6.9"]]
check(kills(tenVsNine, version: "6.10").isEmpty, "6.10 is newer than 6.9 (numeric, not lexicographic)")

// Malformed upToVersion → kill everywhere (the author meant to kill).
check(!kills(["bulkPhotoImport": ["off": true, "upToVersion": "6.4.x"]], version: "9.0").isEmpty, "typo upToVersion kills all")
check(!kills(["bulkPhotoImport": ["off": true, "upToVersion": ""]], version: "9.0").isEmpty, "empty upToVersion kills all")
check(!kills(["bulkPhotoImport": ["off": true, "upToVersion": 6.5]], version: "9.0").isEmpty, "numeric upToVersion kills all")
check(!kills(capped, version: "Unknown").isEmpty, "unreadable app version is covered")

// Messages: trimmed, capped.
check(kills(["engagementNudges": ["off": true, "message": "  Back soon.  "]]) == ["engagementNudges": "Back soon."], "message trimmed")
let long = String(repeating: "a", count: 250)
check(kills(["engagementNudges": ["off": true, "message": long]])["engagementNudges"]?.count == KillSwitchPolicy.maxMessageLength, "message capped")
check(kills(["engagementNudges": ["off": true, "message": 42]]) == ["engagementNudges": ""], "non-string message → default")

// Several at once.
let multi: [String: Any] = [
    "bulkVideoImport": ["off": true],
    "reelGeneration": ["off": true, "upToVersion": "1.0"],
    "engagementNudges": ["off": true],
]
check(Set(kills(multi).keys) == ["bulkVideoImport", "engagementNudges"], "multiple switches, version-scoped one excluded")

print(failures == 0 ? "\nALL PASS" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
