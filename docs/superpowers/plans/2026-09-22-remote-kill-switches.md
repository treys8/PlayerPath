# Remote Kill Switches Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let Trey switch OFF four risky features for every user from the Firebase console, in seconds and without an App Store build: bulk video import, bulk photo import, highlight-reel rendering, and the local engagement nudges.

**Architecture:** A new Firestore doc, `appConfig/killSwitches`, holds one small map per feature. A pure, Foundation-only parser (`KillSwitchPolicy`) turns the doc into the set of features that are off for *this app version*. A `@MainActor` singleton (`KillSwitchService`) caches that set in `UserDefaults`, refreshes it on sign-in and on every foreground, and answers `isKilled(_:)` synchronously. Each feature has exactly one choke point, and the gate goes on the **action** there, never on the screen or route.

**Tech Stack:** Swift 5 mode (`SWIFT_VERSION = 5.0`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`), SwiftUI, FirebaseFirestore, FirebaseAuth, UserNotifications, Firestore rules emulator tests (`@firebase/rules-unit-testing`).

**Spec:** No separate spec. The design came out of the 2026-09-22 conversation, and its decisions are copied into Global Constraints below. Every code claim here was read at commit `06d3f1fd` and re-checked at `ae0f2833`, after the Liquid Glass commits landed. The parallel session keeps moving line numbers in `MainTabView.swift`, so this plan anchors every edit on quoted code, not line numbers.

## Known limits (say these out loud; don't discover them in an incident)

- **A switch reaches a device only when the app next comes to the foreground or signs in.** Someone using the app when you flip it gets it on their next background → foreground.
- **`engagementNudges` can't recall notifications already scheduled on a device whose owner doesn't open the app.** Those nudges live in iOS, not on our server. The inactivity nudge is aimed at exactly those users (it fires 7 days after the last open), so if the inactivity copy itself is the problem, expect it to keep firing for about a week on idle devices. Fixing that would take a silent push to wake every device, which iOS throttles and doesn't guarantee. That's out of scope.
- **`upToVersion` compares the marketing version (`CFBundleShortVersionString`) only, not the build number.** If a fix ships as a new build of the *same* version, lift the switch by hand once that build is out.

## Why kill-only, not general feature flags

`PlayerPath/RecruitingFeature.swift:16-21` already rejects driving a feature *on* from `appConfig`: showing a feature App Review never saw breaks App Store guideline 2.3.1. So this system is **kill-only**. Every switch ships ON, which is the state App Review saw, and the remote doc can only turn features off. Unknown keys are ignored, so the doc can never reveal anything.

Recruiting is **not** a switch, and that's deliberate. The same file explains that a remote flip could strand a published page with no route back to its only Unpublish control. Its server half already has a stronger kill anyway: a rules deploy or a `serveRecruitingProfile` redeploy.

## Global Constraints

- Deployment target stays **iOS 17.0**. No new APIs above that.
- **Kill-only.** Default is always ON. A missing doc, missing key, fetch failure with an empty cache, or unknown key means the feature is ON.
- **Malformed values fail toward OFF only where intent is unambiguous.** An entry is a map with `off: true`. A malformed `upToVersion` kills every version, because the author clearly meant to kill. An entry that isn't a map is ignored, because it has no clear intent.
- **Gate the action, never the route** (memory `feedback_gate_the_action_not_the_route`). Buttons stay visible and explain why when tapped.
- No change to `firestore.rules`. `appConfig/{docID}` is already `allow read: if isAuthenticated()` with no write rule (`firestore.rules:1036-1038`), so clients can't write it. Task 6 pins that with a test.
- `appConfig` is readable by every signed-in user (memory `feedback_appconfig_is_world_readable`). Put nothing secret in the doc: no UIDs, no internal notes.
- Don't touch `RecruitingFeature.swift`, `AppUpdateManager.swift`, `MainTabView.swift`, `AppDelegate.swift` or `CoachTabView.swift`. The parallel Liquid Glass session (`docs/superpowers/plans/2026-09-22-ios26-liquid-glass-chrome.md`) is editing the last three.
- Logging: OSLog `Logger(subsystem: "com.playerpath.app", category: "KillSwitch")`.
- Colors and type in new UI: none needed. The gates reuse existing alert and failed-state UI.
- Never set or bump version or build numbers.
- Commit directly to `main`, one commit per task. **Stage only the files the task lists** (`git add <paths>`, never `git add -A`), because another session has uncommitted work in the same tree.
- There's no Swift test target. For Swift, "test" means a clean build, plus the standalone policy harness (Task 1), plus the manual checks each task lists.

## Verified facts this plan depends on

| Fact | Source |
|---|---|
| `appConfig` reads need auth; no client write rule exists | `firestore.rules:1036-1038` |
| `FC.appConfig == "appConfig"` | `PlayerPath/FirestoreCollections.swift:21` |
| `appConfig/current` is used by force-update / What's New; left untouched | `PlayerPath/Services/AppUpdateManager.swift:36` |
| `Bundle.main.appVersion` = `CFBundleShortVersionString` or `"Unknown"` | `PlayerPath/Services/AnalyticsService.swift:637-639` |
| Only `PlayerPath/` is a synchronized folder group, so new files there are auto-included and files outside it (e.g. `tools/`) are not built into the app | `project.pbxproj` (one `PBXFileSystemSynchronizedRootGroup`, `path = PlayerPath`) |
| All 5 bulk *video* import entry points funnel through `BulkImportAttach`'s `onChange(of: trigger)` | `PlayerPath/Views/Videos/BulkImportAttach.swift:68-89`; callers `VideoClipsView:281`, `SeasonDetailView:242`, `GameDetailView:595`, `PracticeDetailView:309`, `JournalView:361` |
| Bulk *photo* import has the mirror choke point | `PlayerPath/Views/Photos/BulkPhotoImportAttach.swift:72-85` |
| Every reel render goes through `ReelStitchCoordinator.generate` (the only caller of `VideoStitchingService.stitch`); Retry calls it again | `ReelStitchCoordinator.swift:47-110`; callers `GenerateReelView:55,136,256`, `TodaysReelHeroCard:273` |
| `.failed(String)` is shown to the user with a Retry button | `GenerateReelView.swift:93-94,125-145`; `TodaysReelHeroCard.swift:76-77` |
| The 5 nudge services and their entry points: `WeeklySummaryScheduler.schedule(for:)`/`scheduleAll(for:)`, `WeekendPrepScheduler.schedule(for:)`, `InactivityReminderService.reschedule(isInSeason:)`, `ClipTaggingReminderService.scheduleIfNeeded(...)`, `MilestoneReminderService.fireNudge(...)` | read; all `@MainActor` |
| Cancel paths exist for 4 of the 5; weekly summary has none across athletes (ids `weekly_summary_<athleteId>`) | `WeekendPrepScheduler.cancel()`, `InactivityReminderService.cancel()`, `ClipTaggingReminderService.cancelAll()`, `MilestoneReminderService.cancel()`; `PushNotificationService.swift:545` |
| Foreground nudge scheduling runs in **unawaited** Tasks (`if phase == .active { Task(operation: { await WeeklySummaryScheduler.scheduleAll(for: user) }) … }`) | `MainTabView.swift:288-291` at `ae0f2833` (was `:185-193` at `06d3f1fd`) |
| LLDB can't evaluate `await`, so pending notifications are verified through a DEBUG log line, not the debugger | Task 2 Step 2 |
| Sign-in setup block with the Firebase UID, both roles | `AuthenticatedFlow.swift:187-193` |
| Foreground hook for every role | `PlayerPathApp.swift:217-249` (`ScenePhaseSaveHandler`, `case .active`) |
| `PushNotificationService.scheduleLocalNotification` is also used by user-requested game reminders, the coach review reminder and upload-complete alerts, so it is **not** gated | `PushNotificationService.swift:328-470,570` |
| Rules tests: each file needs a distinct `projectId`; anon context = `testEnv.unauthenticatedContext()` | `sharedFolders.test.mjs:70-83`; `recruitingProfiles.test.mjs:110` |

## Review Focus

1. **Trey types `off` as the string `"true"` in the console** (the Firebase console's default field type is string). Expected: the feature is still killed. Pinned by `isOff` accepting `"true"` in any case (Task 1 harness).
2. **Trey types `upToVersion` as a number (`6.5`) or with a typo (`6.4.x`).** Expected: the kill applies to every version, not to none. Pinned in Task 1.
3. **Version comparison is numeric, not text.** `6.10` must count as newer than `6.9`. Pinned in Task 1.
4. **User is offline at launch while a kill is live.** Expected: the kill still holds from the cached state. Pinned in Task 2 (the cache is read in `init`) and checked manually in Task 7.
5. **A nudge gets scheduled after the kill flips** (the foreground Tasks are unawaited, so they race the refresh). Expected: no nudge from the killed family survives the next refresh. Pinned by the sweep running on *every* refresh while killed (Task 2), and checked in Task 5.

---

### Task 1: Pure policy + standalone harness

**Files:**
- Create: `PlayerPath/Services/KillSwitchPolicy.swift`
- Create: `tools/KillSwitchPolicyCheck/main.swift`

**Interfaces:**
- Produces:
  - `enum KillSwitch: String, CaseIterable { case bulkVideoImport, bulkPhotoImport, reelGeneration, engagementNudges }`
  - `enum KillSwitchPolicy` with `static func activeKills(in data: [String: Any], appVersion: String) -> [String: String]` (key = `KillSwitch.rawValue` of each feature that's OFF; value = custom message, `""` for default copy), plus `isOff(_:)`, `appliesTo(appVersion:upToVersion:)`, `versionComponents(_:)`, `compare(_:_:)`, `message(_:)`, `maxMessageLength`.

- [ ] **Step 1: Write the harness (the failing test)**

Create `tools/KillSwitchPolicyCheck/main.swift`:

```swift
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
```

- [ ] **Step 2: Run it and confirm it fails**

Run:
```bash
cd /Users/Trey/Desktop/PlayerPath && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -swift-version 5 \
  tools/KillSwitchPolicyCheck/main.swift -o "$TMPDIR/killswitch-check"
```
Expected: compile error `cannot find 'KillSwitchPolicy' in scope`.

- [ ] **Step 3: Write the policy**

Create `PlayerPath/Services/KillSwitchPolicy.swift`:

```swift
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
```

- [ ] **Step 4: Run the harness and confirm it passes**

Run:
```bash
cd /Users/Trey/Desktop/PlayerPath && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -swift-version 5 \
  PlayerPath/Services/KillSwitchPolicy.swift tools/KillSwitchPolicyCheck/main.swift \
  -o "$TMPDIR/killswitch-check" && "$TMPDIR/killswitch-check"
```
Expected: every line `PASS`, last line `ALL PASS`, exit 0.

- [ ] **Step 5: Build the app**

Run:
```bash
cd /Users/Trey/Desktop/PlayerPath && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project PlayerPath.xcodeproj -scheme PlayerPath -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`. That shows the file compiles under MainActor default isolation, and that `tools/` isn't pulled into the target.

- [ ] **Step 6: Commit**

```bash
git add PlayerPath/Services/KillSwitchPolicy.swift tools/KillSwitchPolicyCheck/main.swift
git commit -m "Kill switches: pure appConfig/killSwitches policy + standalone harness"
```

---

### Task 2: `KillSwitchService` — cache, refresh, nudge sweep

**Files:**
- Create: `PlayerPath/Services/KillSwitchService.swift`
- Modify: `PlayerPath/Services/WeeklySummaryScheduler.swift` (add `cancelAll()` after `scheduleAll(for:)`, which ends at `:176`)
- Modify: `PlayerPath/Views/Navigation/AuthenticatedFlow.swift:187-193`
- Modify: `PlayerPath/PlayerPathApp.swift:217-222` (`ScenePhaseSaveHandler`, `case .active`)

**Interfaces:**
- Consumes: `KillSwitch`, `KillSwitchPolicy.activeKills(in:appVersion:)` (Task 1).
- Produces:
  - `KillSwitchService.shared` (`@MainActor final class`)
  - `func isKilled(_ feature: KillSwitch) -> Bool`
  - `func message(for feature: KillSwitch) -> String`
  - `func refresh() async`
  - `WeeklySummaryScheduler.cancelAll() async`

- [ ] **Step 1: Add `WeeklySummaryScheduler.cancelAll()`**

In `PlayerPath/Services/WeeklySummaryScheduler.swift`, directly after the closing brace of `static func scheduleAll(for user: User) async { … }` (the `}` after the `for summary in summaries { await send(summary) }` loop), insert:

```swift

    /// Cancel every pending weekly summary across all athletes (ids are
    /// `weekly_summary_<athleteId>`, set in PushNotificationService.scheduleWeeklySummary).
    /// Used by the `engagementNudges` kill switch.
    static func cancelAll() async {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { $0.hasPrefix("weekly_summary_") }
        if !ids.isEmpty {
            PushNotificationService.shared.cancelNotifications(withIdentifiers: ids)
        }
    }
```

(`ClipTaggingReminderService.swift:110` uses `UNUserNotificationCenter` with the same imports, `Foundation` only, so no new import is needed. If the build says otherwise, add `import UserNotifications`.)

- [ ] **Step 2: Create the service**

Create `PlayerPath/Services/KillSwitchService.swift`:

```swift
//
//  KillSwitchService.swift
//  PlayerPath
//
//  Remote kill switches. Reads Firestore `appConfig/killSwitches` (parsed by
//  KillSwitchPolicy) and answers "is this feature switched off?" for the gated
//  call sites. Gates read a cached answer synchronously; `refresh()` updates it
//  on sign-in and on every foreground. Kill-only — see `KillSwitch`.
//
//  Runbook: docs/quick-reference/KILL_SWITCHES.md
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import UserNotifications
import os

private let killLog = Logger(subsystem: "com.playerpath.app", category: "KillSwitch")

@MainActor
final class KillSwitchService {
    static let shared = KillSwitchService()

    private static let docID = "killSwitches"
    /// Last successfully fetched state, so a kill still holds on an offline launch.
    private static let cacheKey = "killSwitches.active.v1"

    /// Switched-off features (raw value) → message ("" = default copy).
    private var kills: [String: String]
    private var isRefreshing = false

    private init() {
        kills = UserDefaults.standard.dictionary(forKey: Self.cacheKey) as? [String: String] ?? [:]
    }

    func isKilled(_ feature: KillSwitch) -> Bool {
        #if DEBUG
        if Self.debugForced.contains(feature) { return true }
        #endif
        return kills[feature.rawValue] != nil
    }

    /// The doc's `message` when set, otherwise copy that says the pause is
    /// temporary and nothing was lost.
    func message(for feature: KillSwitch) -> String {
        if let custom = kills[feature.rawValue], !custom.isEmpty { return custom }
        switch feature {
        case .bulkVideoImport, .bulkPhotoImport:
            return "Importing from Photos is paused while we fix an issue. Nothing you've already saved is affected."
        case .reelGeneration:
            return "Building new reels is paused while we fix an issue. Your clips are safe — try again later."
        case .engagementNudges:
            return ""
        }
    }

    /// Fetch the doc and replace the cached state. A missing doc means nothing is
    /// off; a failed fetch keeps the cache. Safe to call often — overlapping
    /// calls collapse into the one in flight.
    func refresh() async {
        guard !isRefreshing else { return }
        // appConfig reads require auth (firestore.rules), so signed-out is a no-op.
        guard Auth.auth().currentUser != nil else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let snapshot = try await Firestore.firestore()
                .collection(FC.appConfig).document(Self.docID).getDocument()
            let fresh = KillSwitchPolicy.activeKills(in: snapshot.data() ?? [:], appVersion: Bundle.main.appVersion)
            if fresh != kills {
                killLog.notice("Kill switches changed → off: [\(fresh.keys.sorted().joined(separator: ", "), privacy: .public)]")
            }
            kills = fresh
            UserDefaults.standard.set(fresh, forKey: Self.cacheKey)
        } catch {
            killLog.warning("Kill switch fetch failed, keeping cached state: \(error.localizedDescription, privacy: .public)")
        }

        // Every refresh while killed, not only on the flip: the foreground nudge
        // scheduling in MainTabView runs in unawaited Tasks and can land after
        // this refresh, so sweeping each time limits a stray to one foreground.
        if isKilled(.engagementNudges) {
            await sweepNudges()
        }

        #if DEBUG
        // Proves a refresh ran, and is how the manual checks read pending
        // notifications (LLDB can't evaluate `await`).
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier)
        killLog.debug("Refreshed. off: [\(self.kills.keys.sorted().joined(separator: ", "), privacy: .public)] pending: [\(pending.sorted().joined(separator: ", "), privacy: .public)]")
        #endif
    }

    private func sweepNudges() async {
        WeekendPrepScheduler.cancel()
        InactivityReminderService.shared.cancel()
        await WeeklySummaryScheduler.cancelAll()
        await ClipTaggingReminderService.shared.cancelAll()
        await MilestoneReminderService.shared.cancel()
        killLog.info("Swept pending engagement nudges")
    }

    #if DEBUG
    /// Simulator testing without touching prod: add the launch argument
    /// `-KillSwitchForce bulkVideoImport,reelGeneration` in Edit Scheme → Run → Arguments.
    /// Launch arguments land in the volatile argument domain, so nothing persists.
    private static let debugForced: Set<KillSwitch> = {
        guard let raw = UserDefaults.standard.string(forKey: "KillSwitchForce") else { return [] }
        return Set(raw.split(separator: ",").compactMap {
            KillSwitch(rawValue: $0.trimmingCharacters(in: .whitespaces))
        })
    }()
    #endif
}
```

- [ ] **Step 3: Refresh on sign-in (both roles)**

In `PlayerPath/Views/Navigation/AuthenticatedFlow.swift`, the block currently reads:

```swift
            if let firebaseUID = authManager.currentFirebaseUser?.uid {
                ActivityNotificationService.shared.startListening(forUserID: firebaseUID)
                // Re-assert the push token against the current user — handles
                // sign-out→sign-in where the cached token is unchanged.
                Task { await PushNotificationService.shared.reassociateTokenWithCurrentUser() }
            }
```

Replace it with:

```swift
            if let firebaseUID = authManager.currentFirebaseUser?.uid {
                ActivityNotificationService.shared.startListening(forUserID: firebaseUID)
                // Re-assert the push token against the current user — handles
                // sign-out→sign-in where the cached token is unchanged.
                Task { await PushNotificationService.shared.reassociateTokenWithCurrentUser() }
                // Remote kill switches (appConfig/killSwitches). Not awaited: gates
                // read the cached state meanwhile, and the refresh sweeps any nudge
                // scheduled before it lands.
                Task { await KillSwitchService.shared.refresh() }
            }
```

- [ ] **Step 4: Refresh on every foreground**

In `PlayerPath/PlayerPathApp.swift`, inside `ScenePhaseSaveHandler.handleScenePhaseChange`, `case .active:` currently begins:

```swift
        case .active:
            appLog.info("App became active")

            // Mark the foreground transition so ActivityNotificationService can
```

Change it to:

```swift
        case .active:
            appLog.info("App became active")

            // Pick up kill-switch flips (appConfig/killSwitches) without a relaunch.
            // No-op when signed out.
            Task { await KillSwitchService.shared.refresh() }

            // Mark the foreground transition so ActivityNotificationService can
```

- [ ] **Step 5: Build**

Run the Task 1 Step 5 build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Manual check (simulator, no prod doc yet)**

Run from Xcode, signed in. In Console.app, filter on subsystem `com.playerpath.app`, category `KillSwitch`, and turn on Action → Include Debug Messages.
Expected: a `Refreshed. off: [] pending: [...]` line after sign-in and after each background → foreground, and no `fetch failed` line. The doc doesn't exist yet, so `fresh == [:] == kills` and the "changed" line stays silent. A `fetch failed … permission` line would mean the auth guard or rules assumption is wrong. Stop and investigate if you see one.

- [ ] **Step 7: Commit**

```bash
git add PlayerPath/Services/KillSwitchService.swift PlayerPath/Services/WeeklySummaryScheduler.swift \
  PlayerPath/Views/Navigation/AuthenticatedFlow.swift PlayerPath/PlayerPathApp.swift
git commit -m "Kill switches: KillSwitchService (cache + refresh on sign-in/foreground + nudge sweep)"
```

---

### Task 3: Gate bulk video + photo import

**Files:**
- Modify: `PlayerPath/Views/Videos/BulkImportAttach.swift` (state at `:57`, trigger handler `:68-89`, modifier chain `:113-115`)
- Modify: `PlayerPath/Views/Photos/BulkPhotoImportAttach.swift` (state near `:62`, trigger handler `:72-85`)

**Interfaces:**
- Consumes: `KillSwitchService.shared.isKilled(_:)`, `.message(for:)`, `KillSwitch.bulkVideoImport` / `.bulkPhotoImport`.

Why an alert and not the existing toast: the toast auto-dismisses after 2.5s (`BulkImportAttach.swift:218`) and is sized for short copy. The pause message is a full sentence the user needs time to read.

- [ ] **Step 1: Video import — add state**

In `BulkImportAttach.swift`, after `@State private var pendingResume = false` (`:57`), add:

```swift
    /// Set when a tap is refused by the `bulkVideoImport` kill switch.
    @State private var pausedMessage: String?
```

- [ ] **Step 2: Video import — gate the trigger**

In the `.onChange(of: trigger)` handler, after the line
`guard pendingOutcome == nil, storageContext == nil else { return }`
and before `// A fresh pick is never a resume.`, insert:

```swift
                // Remote kill switch (appConfig/killSwitches). Gates the action, not
                // the entry point: every Import button stays put and says why.
                if KillSwitchService.shared.isKilled(.bulkVideoImport) {
                    pausedMessage = KillSwitchService.shared.message(for: .bulkVideoImport)
                    return
                }
```

It sits after the in-flight guard on purpose. When a storage sheet is pending, the tap is already ignored, and presenting an alert over that sheet is the dropped-presentation trap the `:48-52` comment describes.

- [ ] **Step 3: Video import — present the alert**

In `body`, directly after the `.sheet(item: $storageContext, onDismiss: storageSheetDismissed) { … }` modifier and before `.overlay(alignment: .bottom)`, add:

```swift
            .alert(
                "Import Paused",
                isPresented: Binding(
                    get: { pausedMessage != nil },
                    set: { if !$0 { pausedMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(pausedMessage ?? "")
            }
```

- [ ] **Step 4: Photo import — same three edits**

In `BulkPhotoImportAttach.swift`:

(a) After `@State private var isResume = false`, add:

```swift
    /// Set when a tap is refused by the `bulkPhotoImport` kill switch.
    @State private var pausedMessage: String?
```

(b) In `.onChange(of: trigger)`, after `guard pendingOutcome == nil, storageContext == nil else { return }` and before `isResume = false`, insert:

```swift
                // Remote kill switch (appConfig/killSwitches). Gates the action, not
                // the entry point: every Import button stays put and says why.
                if KillSwitchService.shared.isKilled(.bulkPhotoImport) {
                    pausedMessage = KillSwitchService.shared.message(for: .bulkPhotoImport)
                    return
                }
```

(c) Directly after the `.onChange(of: pickerItems) { … }` modifier, add the same `.alert("Import Paused", …)` block as Step 3.

- [ ] **Step 5: Build**

Run the Task 1 Step 5 build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Manual check (simulator)**

1. Edit Scheme → Run → Arguments → add `-KillSwitchForce bulkVideoImport` → run.
2. Videos tab → Upload/Import. Expected: an "Import Paused" alert with the default copy, and **no** Photos picker.
3. Open a game → import videos. Expected: the same alert.
4. Import *photos* (Journal or a game's photo import). Expected: the picker opens normally, because only video is killed.
5. Change the argument to `-KillSwitchForce bulkPhotoImport` → run. Expected: photo import shows the alert and video import opens the picker.
6. Remove the argument → run. Expected: both open the picker.

- [ ] **Step 7: Commit**

```bash
git add PlayerPath/Views/Videos/BulkImportAttach.swift PlayerPath/Views/Photos/BulkPhotoImportAttach.swift
git commit -m "Kill switches: gate bulk video + photo import at the trigger"
```

---

### Task 4: Gate reel rendering

**Files:**
- Modify: `PlayerPath/Views/Highlights/ReelStitchCoordinator.swift:61-67`

**Interfaces:**
- Consumes: `KillSwitchService.shared.isKilled(.reelGeneration)`, `.message(for: .reelGeneration)`.

- [ ] **Step 1: Insert the gate after the cache hit**

In `generate(clips:scopeKey:options:)`, the code currently reads:

```swift
        // Cache hit — same scope + options + clip set already stitched.
        if let cached = StitchedReelCache.cachedURLIfPresent(scopeKey: effectiveScope, clips: localClips) {
            state = .ready(cached)
            return
        }

        let outputURL = StitchedReelCache.url(scopeKey: effectiveScope, clips: localClips)
```

Insert between the cache-hit block and `let outputURL`:

```swift
        // Remote kill switch (appConfig/killSwitches). After the cache hit on
        // purpose: a reel already on disk was rendered before the kill and stays
        // playable and shareable; only new renders stop. Retry re-enters here, so
        // it keeps saying "paused" until the switch is lifted.
        if KillSwitchService.shared.isKilled(.reelGeneration) {
            state = .failed(KillSwitchService.shared.message(for: .reelGeneration))
            return
        }
```

- [ ] **Step 2: Build**

Run the Task 1 Step 5 build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Manual check (simulator)**

1. Without any launch argument, generate a game reel (Game → Generate Reel) so a cached one exists.
2. Add `-KillSwitchForce reelGeneration` → run.
3. Open the same game's reel. Expected: the cached reel still shows as ready.
4. Generate a reel for a **different** game or season, or change an export option (9:16), which makes a different cache key. Expected: the "Couldn't Build Reel" view with the paused copy. Tap Retry. Expected: the same view again.
5. Remove the argument → Retry. Expected: it renders.

- [ ] **Step 4: Commit**

```bash
git add PlayerPath/Views/Highlights/ReelStitchCoordinator.swift
git commit -m "Kill switches: gate new reel renders (cached reels unaffected)"
```

---

### Task 5: Gate the five engagement nudges

**Files:**
- Modify: `PlayerPath/Services/WeeklySummaryScheduler.swift` (`schedule(for:)` `:152-156`, `scheduleAll(for:)` `:161-162`)
- Modify: `PlayerPath/Services/WeekendPrepScheduler.swift:34-37`
- Modify: `PlayerPath/Services/InactivityReminderService.swift:33-39`
- Modify: `PlayerPath/Services/ClipTaggingReminderService.swift:45-55`
- Modify: `PlayerPath/Services/MilestoneReminderService.swift` (`fireNudge`, `:162`)

**Interfaces:**
- Consumes: `KillSwitchService.shared.isKilled(.engagementNudges)`.

Out of scope on purpose, because the user asked for these or they're transactional: game reminders (`PushNotificationService.scheduleGameReminder`), the coach review reminder (a user-set time), upload-complete alerts, and the end-game reminders (`GameAlertService`).

- [ ] **Step 1: Weekly summary**

In `schedule(for athlete:)`, change `guard weeklyStatsEnabled else { return }` to:

```swift
        guard weeklyStatsEnabled, !KillSwitchService.shared.isKilled(.engagementNudges) else { return }
```

In `scheduleAll(for user:)`, make the same change to its first line, `guard weeklyStatsEnabled else { return }`.

- [ ] **Step 2: Weekend prep**

In `WeekendPrepScheduler.schedule(for:)`, directly after the first line
`PushNotificationService.shared.cancelNotifications(withIdentifiers: [notifID])`, insert:

```swift
        // Remote kill switch: the cancel above already cleared any pending one.
        guard !KillSwitchService.shared.isKilled(.engagementNudges) else { return }
```

- [ ] **Step 3: Inactivity**

In `InactivityReminderService.reschedule(isInSeason:)`, directly after
`PushNotificationService.shared.cancelNotifications(withIdentifiers: [Self.notifID])`, insert:

```swift
        // Remote kill switch: the cancel above already cleared any pending one.
        guard !KillSwitchService.shared.isKilled(.engagementNudges) else { return }
```

- [ ] **Step 4: Clip tagging**

In `ClipTaggingReminderService.scheduleIfNeeded(...)`, directly after `guard untaggedCount > 0 else { return }`, insert:

```swift
        guard !KillSwitchService.shared.isKilled(.engagementNudges) else { return }
```

- [ ] **Step 5: Milestone**

In `MilestoneReminderService.fireNudge(titles:seasonID:athleteID:)`, make the first line:

```swift
        // Gate only the push. processGameEnd's seen-set bookkeeping and the
        // in-app celebration still run, so lifting the switch doesn't replay
        // a backlog of old milestones.
        guard !KillSwitchService.shared.isKilled(.engagementNudges) else { return }
```

- [ ] **Step 6: Build**

Run the Task 1 Step 5 build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Manual check (simulator)**

Read pending requests from the `Refreshed. … pending: [...]` DEBUG line (Task 2) in Console.app, category `KillSwitch`, with debug messages included. Each background → foreground prints a fresh one. The foreground scheduling Tasks race the refresh, so always go by the line from the *second* foreground.

1. Without an argument, sign in as an athlete with an in-season athlete and grant notifications. Background → foreground twice. Expected: `pending` includes `weekly_summary_<id>` and `inactivity-reminder`, plus `weekend-prep` if a tournament season is active.
2. Add `-KillSwitchForce engagementNudges` → run → background → foreground twice. Expected: `pending` has none of `weekly_summary_`, `weekend-prep`, `inactivity-reminder`, `clip-tagging-`, `milestone-nudge`. `game_reminder_*` and `coach_review_reminder`, if you have any, are still there. This also covers Review Focus #5, the unawaited foreground Tasks.
3. End a game that has untagged clips, then background → foreground. Expected: no `clip-tagging-` entry and no milestone push. The in-app milestone celebration still shows if one was earned.
4. Remove the argument → run → background → foreground twice. Expected: `weekly_summary_<id>` and `inactivity-reminder` come back.

- [ ] **Step 8: Commit**

```bash
git add PlayerPath/Services/WeeklySummaryScheduler.swift PlayerPath/Services/WeekendPrepScheduler.swift \
  PlayerPath/Services/InactivityReminderService.swift PlayerPath/Services/ClipTaggingReminderService.swift \
  PlayerPath/Services/MilestoneReminderService.swift
git commit -m "Kill switches: gate the five local engagement nudges"
```

---

### Task 6: Rules test — clients can read but never write `appConfig`

**Files:**
- Create: `firebase/rules-tests/appConfig.test.mjs`

**Interfaces:** none. This pins `firestore.rules:1036-1038`, so a future rules edit can't let any signed-in user flip everyone's kill switches.

- [ ] **Step 1: Write the test**

Create `firebase/rules-tests/appConfig.test.mjs`:

```js
/**
 * Firestore rules tests for `appConfig/{docID}`.
 *
 * appConfig/killSwitches can switch features OFF for every user, so the rule
 * that matters is the one that ISN'T there: no client write path. Reads are
 * open to any signed-in user (and only them) — which is also why nothing
 * secret may live in these docs.
 *
 * Run: npm test   (from firebase/rules-tests/ — boots the Firestore emulator)
 */

import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { deleteDoc, doc, getDoc, setDoc, updateDoc } from 'firebase/firestore';

const KILL_DOC = 'appConfig/killSwitches';

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    // Distinct projectId: test FILES run in parallel against one emulator and
    // projectId namespaces their data (see sharedFolders.test.mjs).
    projectId: 'demo-playerpath-rules-appconfig',
    firestore: {
      rules: readFileSync('../../firestore.rules', 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
});

after(async () => {
  await testEnv?.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), KILL_DOC), {
      bulkVideoImport: { off: false },
    });
  });
});

describe('appConfig', () => {
  it('lets a signed-in user read the kill switches', async () => {
    const db = testEnv.authenticatedContext('any-user').firestore();
    await assertSucceeds(getDoc(doc(db, KILL_DOC)));
  });

  it('denies signed-out reads', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, KILL_DOC)));
  });

  it('denies a signed-in user flipping a switch', async () => {
    const db = testEnv.authenticatedContext('any-user').firestore();
    await assertFails(updateDoc(doc(db, KILL_DOC), { 'bulkVideoImport.off': true }));
  });

  it('denies a signed-in user overwriting or creating a config doc', async () => {
    const db = testEnv.authenticatedContext('any-user').firestore();
    await assertFails(setDoc(doc(db, KILL_DOC), { reelGeneration: { off: true } }));
    await assertFails(setDoc(doc(db, 'appConfig/current'), { minimumVersion: '99.0' }));
  });

  it('denies a signed-in user deleting a config doc', async () => {
    const db = testEnv.authenticatedContext('any-user').firestore();
    await assertFails(deleteDoc(doc(db, KILL_DOC)));
  });
});
```

- [ ] **Step 2: Run the suite**

Run: `cd /Users/Trey/Desktop/PlayerPath/firebase/rules-tests && npm test`
Expected: every test passes, including the existing `sharedFolders`, `recruitingProfiles` and `adversarial-review` files. There's no "red" step: this test pins existing correct behavior. To see it fail once, temporarily add `allow write: if isAuthenticated();` to the `appConfig` match in `firestore.rules`, run it, **revert**, and run again.

- [ ] **Step 3: Commit**

```bash
git add firebase/rules-tests/appConfig.test.mjs
git commit -m "Rules tests: pin appConfig as client-read-only"
```

---

### Task 7: Runbook, CLAUDE.md, end-to-end check in prod

**Files:**
- Create: `docs/quick-reference/KILL_SWITCHES.md`
- Modify: `CLAUDE.md` (Key Services → Infrastructure bullet only). CLAUDE.md now says the rules suite "runs every `*.test.mjs`", so the new test file needs no mention there.

- [ ] **Step 1: Write the runbook**

Create `docs/quick-reference/KILL_SWITCHES.md`:

````markdown
# Kill Switches — Runbook

Switch a feature OFF for every user, in seconds, with no App Store build.
Code: `PlayerPath/Services/KillSwitchService.swift` + `KillSwitchPolicy.swift`.

## The switches

| Key | What stops | What users see |
|---|---|---|
| `bulkVideoImport` | Importing videos from Photos (all 5 entry points) | "Import Paused" alert on tap |
| `bulkPhotoImport` | Importing photos from Photos | "Import Paused" alert on tap |
| `reelGeneration` | Rendering NEW highlight reels (already-rendered reels still play and share) | "Couldn't Build Reel" + paused message |
| `engagementNudges` | Weekly summary, weekend prep, inactivity, clip-tagging and milestone local notifications; pending ones are cleared | Nothing (they just stop) |

Not switchable, on purpose: recruiting (see `RecruitingFeature.swift`), uploads,
game reminders, coach review reminders.

## Flip one

Firebase console → Firestore → `appConfig` → `killSwitches` (create the doc if
missing) → add a **map** field named after the key:

```
bulkVideoImport  (map)
  off          (boolean) true
  upToVersion  (string)  "6.4.5"        ← optional: only builds ≤ this; the fix build is unaffected
  message      (string)  "…"            ← optional: ≤200 chars, shown instead of the default copy
```

- `off` as the string `"true"` also works. A bare `bulkVideoImport: true` (not a map) is **ignored**.
- A mistyped `upToVersion` kills **every** version (safe direction).
- To lift: set `off` to `false`, or delete the field.
- `upToVersion` is the marketing version only (not the build number). A fix shipped as a new build of the same version is still covered, so lift it by hand.

## What it can't do

- It reaches a device only when the app next opens or comes to the foreground.
- `engagementNudges` can't pull back notifications already scheduled on a device whose owner never opens the app. The inactivity nudge in particular can keep firing for up to about a week on idle devices.
- Everyone can read this doc once signed in. Never put UIDs or internal notes in it.

## How fast it lands

When the app is next foregrounded or signed into. A user already inside the app
picks it up on the next background → foreground. Offline users keep their last
fetched state.

## Test without touching prod

Xcode → Edit Scheme → Run → Arguments → `-KillSwitchForce bulkVideoImport,reelGeneration`
(DEBUG builds only).
````

- [ ] **Step 2: Update CLAUDE.md, but only if nobody else has uncommitted edits in it**

First run `git diff --stat CLAUDE.md`. If it shows changes you didn't make (at planning time, another session had 19 uncommitted lines in it), **don't edit or stage it**. `git add CLAUDE.md` would sweep their work into this commit, and interactive `git add -p` isn't available here. Skip this step, tell Trey the one line below still needs adding, and drop `CLAUDE.md` from Step 4's `git add`.

If it's clean, then in **Key Services → In `PlayerPath/Services/` → Infrastructure**, append to the bullet:
`, \`KillSwitchService\` (remote kill-only switches from \`appConfig/killSwitches\` — runbook \`docs/quick-reference/KILL_SWITCHES.md\`)`

- [ ] **Step 3: End-to-end check in prod (Trey decides the window)**

This touches the live doc, so every signed-in user who taps Import during the window sees the pause. Keep it to about 2 minutes.

1. Run the app (DEBUG, **no** launch argument) on a device, signed in.
2. Console: create `appConfig/killSwitches` with `bulkVideoImport` = map `{ off: true, message: "Test — back in 2 minutes." }`.
3. Background → foreground the app. Tap Import on the Videos tab. Expected: "Import Paused" with the custom message. Console.app: `Kill switches changed → off: [bulkVideoImport]`.
4. Turn on Airplane Mode, force-quit, relaunch, tap Import. Expected: still paused (cached). This covers Review Focus #4.
5. Turn off Airplane Mode. In the console, set `off` to `false`. Background → foreground → tap Import. Expected: the picker opens. Log: `off: []`.
6. Leave the doc in place with every switch `off: false`, so the next incident is a one-field edit.

- [ ] **Step 4: Commit**

```bash
git add docs/quick-reference/KILL_SWITCHES.md CLAUDE.md
git commit -m "Kill switches: runbook + CLAUDE.md"
```

---

## Deliberate non-changes

- **`AppUpdateManager`** keeps its own `isVersion(_:lessThan:)`. Sharing `KillSwitchPolicy.compare` with it would be DRY, but it would put the force-update path, the one path that can lock every user out, inside this change's blast radius. Fold it in later as its own reviewed commit if wanted.
- **No snapshot listener.** A one-doc listener would pick up flips mid-session, but it adds a listener lifecycle tied to sign-in and sign-out. Refreshing on foreground is enough for an incident switch.
- **No server-side switches.** Cloud Functions can already be fixed by redeploying, and recruiting's server half is killed by a rules or CF deploy.
