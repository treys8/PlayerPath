# Settings Bug Fixes (Weekly Stats, Subscription Copy, Coach Detection) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix three defects from the 2026-09-25 settings review: turning off Weekly Statistics leaves the other athletes' summaries scheduled, the Subscription screen sells coach sharing as a paid feature, and the Notifications screen decides "coach" from a missing athlete id.

**Architecture:** Three small, independent edits to existing SwiftUI views. No model, sync, schema, or Cloud Function changes. Each task is its own commit.

**Tech Stack:** SwiftUI (iOS 17+), SwiftData, UserNotifications, StoreKit 2 (read-only here).

**Spec:** The review findings #1, #2 and #6 from the 2026-09-25 session (summarized in each task's "Why").

## Global Constraints

- The iOS app has **no test target**. Verification for every task = a clean CLI build + the listed manual checks on a simulator or device.
- Build command (the `DEVELOPER_DIR` prefix is required):
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PlayerPath.xcodeproj -scheme PlayerPath -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
  Transient SourceKit errors in the output are fine; trust the final `** BUILD SUCCEEDED **`.
- Do not bump version or build numbers (Trey owns them).
- New copy: sport-neutral, no "baseball" wording.
- Never use `try? context.save()`; use `ErrorHandlerService.shared.saveContext(_:caller:)`. (No task here needs a save.)
- Coach sharing is **free on every athlete tier** (Pricing Model V2: the coach's seat pays for the connection). The recruiting profile is **Pro-only** and shown only when `RecruitingFeature.isEnabled`.

## Review Focus

1. **Multi-athlete household turns Weekly Statistics off** → no `weekly_summary_*` request should remain pending for ANY athlete. (Task 1, Step 4 check A.)
2. **Notifications opened with a nil `athleteId` by an athlete** (not reachable today; a future call site could do it) → athlete sections render, and coach-only sections (Athlete Activity, Review Reminders) do not. (Task 3, Step 3 check B, forced via a temporary call-site edit.)
3. **Baseball FAQ "Can I share videos with my coach?"** → the answer no longer says it needs Pro. (Task 2, Step 3b.)
4. **Comped Pro user (Firestore comp, no StoreKit sub)** → Subscription screen shows the Pro list with the Recruiting Profile row, since `authManager.currentTier` already includes comps. (Task 2, Step 4 check C.)
5. **Free user opens the paywall comparison table** → the Recruiting Profile row shows ✗ / ✗ / ✓ and the Coach Sharing row still shows ✓ / ✓ / ✓. (Task 2, Step 4 check B.)

---

### Task 1: Weekly Statistics toggle cancels and schedules for every athlete

**Why:** Each athlete gets a separate one-shot request `weekly_summary_<athleteId>` (`WeeklySummaryScheduler.scheduleAll`). The toggle's off-branch cancels only the selected athlete's id, so in a household with several athletes the other summaries still fire on Sunday. The on-branch schedules only the selected athlete. (Siblings get picked up on the next foreground `scheduleAll`, so this half is cosmetic; the off-branch is the real bug.)

**Files:**
- Modify: `PlayerPath/Views/Profile/NotificationSettingsView.swift:194-219` (the `if !isCoach { Section { Toggle("Weekly Statistics" … } }` block)

**Interfaces:**
- Consumes (existing, unchanged):
  - `WeeklySummaryScheduler.scheduleAll(for user: User) async` (`PlayerPath/Services/WeeklySummaryScheduler.swift:162`). It already guards `weeklyStatsEnabled` and the kill switch.
  - `WeeklySummaryScheduler.cancelAll() async` (`:182`). It removes every pending `weekly_summary_*`.
- Produces: nothing new.

- [ ] **Step 1: Replace the Weekly Statistics `onChange`**

In `NotificationSettingsView.swift`, replace exactly this block:

```swift
                    Toggle("Weekly Statistics", isOn: $weeklyStats)
                        .onChange(of: weeklyStats) { _, enabled in
                            guard let athleteId else { return }
                            if enabled {
                                Task { @MainActor in
                                    if let athlete = findAthlete(id: athleteId) {
                                        await WeeklySummaryScheduler.schedule(for: athlete)
                                    }
                                }
                            } else {
                                Task { @MainActor in
                                    PushNotificationService.shared.cancelNotifications(
                                        withIdentifiers: ["weekly_summary_\(athleteId)"]
                                    )
                                }
                            }
                        }
```

with:

```swift
                    Toggle("Weekly Statistics", isOn: $weeklyStats)
                        .onChange(of: weeklyStats) { _, enabled in
                            // One global toggle, one pending request PER athlete
                            // (`weekly_summary_<id>`). Act on all of them — cancelling only
                            // the selected athlete left siblings' summaries firing on Sunday.
                            Task { @MainActor in
                                if enabled {
                                    if let user = try? modelContext.fetch(FetchDescriptor<User>()).first {
                                        await WeeklySummaryScheduler.scheduleAll(for: user)
                                    }
                                } else {
                                    await WeeklySummaryScheduler.cancelAll()
                                }
                            }
                        }
```

(The `try? modelContext.fetch(FetchDescriptor<User>()).first` form is the same pattern the Weekend Prep toggle uses a few lines below. It is a fetch, not a save, so the footgun hook does not apply.)

- [ ] **Step 2: Leave the `.task` block alone**

The `.task` at `:293-300` still schedules only the selected athlete when the screen appears. That is harmless: `MainTabView` already runs `scheduleAll` on foreground. Don't change it; this task only touches the toggle.

- [ ] **Step 3: Build**

Run the Global Constraints build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manual check (simulator, athlete account with 2+ athletes, at least one clip logged this week)**

Temporarily add this as the last line inside the `Task { @MainActor in … }` from Step 1 (lldb's `po` can't `await`, so use a print):

```swift
                                print("weekly pending:", await UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("weekly_summary_") })
```

A. Toggle Weekly Statistics **off** → the console prints `weekly pending: []`.
B. Toggle it back **on** → one `weekly_summary_<id>` per athlete that has activity this week. (`makeSummary` returns nil for athletes with no activity; that's expected.)
**Delete the temporary `print` before committing.**

- [ ] **Step 5: Commit**

```bash
git add PlayerPath/Views/Profile/NotificationSettingsView.swift
git commit -m "Notifications: Weekly Statistics toggle cancels/schedules every athlete's summary"
```

---

### Task 2: Subscription screen and paywall stop selling coach sharing and list the recruiting profile

**Why:** `SubscriptionView` lists "Coach Sharing" as a Pro-only feature (`:91-93`), and the Free-plan blurb says upgrading unlocks "coach sharing" (`:140`). Under Pricing Model V2, coach sharing is free on every plan, and `ImprovedPaywallView` already shows it that way. The one feature that really is Pro-only, the recruiting profile, appears on neither screen.

**Files:**
- Modify: `PlayerPath/Views/Profile/SubscriptionView.swift:85-95` (`tierFeaturesSection`) and `:130-148` (`upgradeBenefitsSection`)
- Modify: `PlayerPath/ImprovedPaywallView.swift:287-302` (comparison table, between "Season Compare" and "Coach Sharing")
- Modify: `PlayerPath/Views/Help/FAQView.swift:104` (the baseball FAQ answer that says Shared Folders needs "a Pro subscription". The golf twin at `:179` is already correct.)

**Interfaces:**
- Consumes: `RecruitingFeature.isEnabled` (`PlayerPath/RecruitingFeature.swift`, compile-time `Bool`), `SubscriptionFeatureRow(icon:title:description:)` (same file), `tableRow(feature:free:plus:pro:)` and `checkIcon(included:)` (private helpers in `ImprovedPaywallView`).
- Produces: nothing new.

- [ ] **Step 1: Rewrite `tierFeaturesSection`**

Replace the whole `tierFeaturesSection` property in `SubscriptionView.swift` with:

```swift
    private var tierFeaturesSection: some View {
        Section {
            SubscriptionFeatureRow(icon: "person.2.fill", title: "\(authManager.currentTier.athleteLimit) Athlete\(authManager.currentTier.athleteLimit == 1 ? "" : "s")", description: "Track up to \(authManager.currentTier.athleteLimit) athlete\(authManager.currentTier.athleteLimit == 1 ? "" : "s")")
            SubscriptionFeatureRow(icon: "internaldrive.fill", title: "\(authManager.currentTier.storageLimitGB) GB Storage", description: "Cloud backup and sync")
            SubscriptionFeatureRow(icon: "square.and.arrow.up", title: "Export Reports", description: "CSV and PDF statistics export")
            SubscriptionFeatureRow(icon: "star.fill", title: "Auto Highlights", description: "Automatically generated highlight reels")
            SubscriptionFeatureRow(icon: "chart.bar.xaxis", title: "Season Comparison", description: "Compare stats across seasons")
            if authManager.currentTier == .pro && RecruitingFeature.isEnabled {
                SubscriptionFeatureRow(icon: "graduationcap.fill", title: "Recruiting Profile", description: "A public page to share with college coaches")
            }
        } header: {
            Text("Your \(authManager.currentTier.displayName) Features")
        } footer: {
            // Pricing Model V2: the coach's seat pays for the connection, so
            // sharing is never a reason to upgrade. Say so rather than list it.
            Text("Sharing clips with a coach is included on every plan.")
        }
    }
```

- [ ] **Step 2: Fix the Free-plan blurb**

In `upgradeBenefitsSection`, replace:

```swift
                Text("More athletes, cloud storage, highlights, and coach sharing. See full plan details and current pricing below.")
```

with:

```swift
                Text(RecruitingFeature.isEnabled
                     ? "More athletes, more cloud storage, auto highlights, and stats export — plus a recruiting profile on Pro. Coach sharing is already included on every plan."
                     : "More athletes, more cloud storage, auto highlights, and stats export. Coach sharing is already included on every plan.")
```

- [ ] **Step 3: Add the Recruiting Profile row to the paywall table**

In `ImprovedPaywallView.swift`, insert this directly **above** the `// Coach sharing is free at every tier` comment (after the "Season Compare" `tableRow`):

```swift
            // Pro-only. Hidden with the rest of recruiting when the compile-time
            // flag is off (RecruitingFeature.swift) — never advertise a hidden feature.
            if RecruitingFeature.isEnabled {
                tableRow(feature: "Recruiting Profile") {
                    checkIcon(included: false)
                } plus: {
                    checkIcon(included: false)
                } pro: {
                    checkIcon(included: true)
                }
            }
```

`tierComparisonTable` is a `VStack` with a view-builder body, so the `if` compiles as-is. If the rows are separated by `Divider()`s, match whatever the neighbouring rows do. (As of this plan they aren't; `tableRow` draws its own separator.)

- [ ] **Step 3b: Fix the FAQ answer**

In `FAQView.swift:104`, replace:

```swift
            answer: "Yes! With a Pro subscription, you can create Shared Folders and invite coaches by email. Coaches can view your videos and leave notes and drawings directly on them. Go to More → Shared Folders to get started."
```

with:

```swift
            answer: "Yes — on any plan. Create a Shared Folder and invite your coach by email. Coaches can view your videos and leave notes and drawings directly on them. Go to More → Shared Folders to get started."
```

- [ ] **Step 4: Build and check**

Run the build command. Expected: `** BUILD SUCCEEDED **`. Then:
A. On a Plus sandbox account, More → Plan → the list shows Athletes, Storage, Export Reports, Auto Highlights, Season Comparison, and the footer about coach sharing. No Coach Sharing row, no Recruiting row.
B. On a Free account, More → Upgrade Plan → the blurb has the new wording. "View Plans & Pricing" → the table has a Recruiting Profile row (✗ ✗ ✓) and the Coach Sharing row is unchanged (✓ ✓ ✓).
C. On a Pro account (StoreKit or Firestore comp), the Recruiting Profile row appears in the list.
In the StoreKit test config, switch tiers with `PlayerPath/PlayerPathStoreKit.storekit` via Xcode → Debug → StoreKit → Manage Transactions.

- [ ] **Step 5: Commit**

```bash
git add PlayerPath/Views/Profile/SubscriptionView.swift PlayerPath/ImprovedPaywallView.swift PlayerPath/Views/Help/FAQView.swift
git commit -m "Subscription: coach sharing shown as included on every plan; list Pro recruiting profile"
```

---

### Task 3: Notifications screen decides coach vs athlete by role (hardening)

**Why:** `NotificationSettingsView.isCoach` is `athleteId == nil` (`:44`), which uses a missing parameter to mean "coach". **This can't be reached in today's app:** `UserMainFlow.swift:127-131` hands `MainTabView` the binding `selectedAthlete ?? athlete`, and shows `AddAthleteView` instead of the tabs when there are no athletes, so `ProfileView` always has an athlete. (The 2026-09-25 review overstated this one.) It's still worth one line: it's the only screen that guesses the role, `UserPreferencesView` and `AboutView` already read `authManager.userRole`, and any future call site that passes nil would silently get the coach layout.

**Files:**
- Modify: `PlayerPath/Views/Profile/NotificationSettingsView.swift:11-44`

**Interfaces:**
- Consumes: `ComprehensiveAuthManager.userRole: UserRole` (`@Published`, `PlayerPath/ComprehensiveAuthManager.swift:73`), from the environment. It's already injected into both More-tab stacks: `ProfileView` and `CoachProfileView` both read `@EnvironmentObject authManager`, and `UserPreferencesView`, pushed from the same stacks, relies on it today.
- Produces: nothing new. `athleteId` stays a parameter; it's still used for the golf noun, the inactivity reminder's in-season check, and the `.task` weekly schedule.

- [ ] **Step 1: Inject the auth manager and change `isCoach`**

Add this line directly under `@Environment(\.ppAccent) private var ppAccent` (line 12):

```swift
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
```

Replace exactly this (current source, lines 40-44):

```swift
    /// Coach context is signaled by a nil athleteId at the call site
    /// (`CoachProfileView` passes `athleteId: nil`). Game Reminders and
    /// Weekly Statistics are athlete-scoped and dead/no-op for coaches —
    /// gated off below to avoid showing irrelevant or broken toggles.
    private var isCoach: Bool { athleteId == nil }
```

with:

```swift
    /// Role, not `athleteId == nil`: an athlete account with no selected athlete
    /// (e.g. right after deleting its last one) also passes nil, and used to get
    /// the coach layout. Game Reminders and Weekly Statistics are athlete-scoped
    /// and dead/no-op for coaches — gated off below.
    private var isCoach: Bool { authManager.userRole == .coach }
```

- [ ] **Step 2: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Manual check**

A. Coach account → Profile → Notifications: Athlete Activity, Upload Notifications and Review Reminders appear. Game reminders and Weekly Statistics don't.
B. The nil case isn't reachable from the UI (see Why), so force it: temporarily change `ProfileView.swift:697` to `NotificationSettingsView(athleteId: nil)`, build, then as an athlete open More → Notifications. Athlete sections appear; Athlete Activity and Review Reminders don't. **Revert the temporary edit before committing.**
C. Athlete account with a golf athlete selected: headers still read "Tournament Notifications" (`athleteId` still flows through).

- [ ] **Step 4: Commit**

```bash
git add PlayerPath/Views/Profile/NotificationSettingsView.swift
git commit -m "Notifications: pick coach vs athlete layout from userRole, not a nil athleteId"
```

---

## Out of scope (tracked in the review, not this plan)

- #3 auto-delete vs highlight reels: its copy is handled in the layout plan (Task 2 there). Making the reel stitcher download cloud-only clips is separate work.
- #4 silent skip of clips over the size cap, and #5 the coach Storage screen.
