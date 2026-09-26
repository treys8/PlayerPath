# Settings Layout Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every setting one home, remove the three-deep nesting and the duplicate rows, and group the More tab so each section means one thing, for both athletes and coaches.

**Architecture:** Only views move; no stored preference, key, model or sync path changes. "Recording & Uploads" (`VideoRecordingSettingsView`) becomes the only home for recording, upload and on-device-copy options. "App Preferences" (`UserPreferencesView`) keeps haptics, tips, golf scoring defaults and analytics, and saves on change like every other screen. The old nested "Settings" screen (`SettingsView`) shrinks to "Account & Sign-In", and its other rows move up to the More tab.

**Tech Stack:** SwiftUI (iOS 17+), SwiftData (`@Query`, `@Model` `UserPreferences`), `@AppStorage`, TipKit.

**Spec:** The "Layout and consistency" findings from the 2026-09-25 settings review, restated as the target below.

### Target layout

**Athlete More tab (`ProfileView`), top to bottom:**
1. Payment-failed banner (unchanged), search results (unchanged), profile header (unchanged)
2. **Athletes** (unchanged)
3. **Coaching & Activity**: Shared Folders, Activity (with unread badge)
4. **Settings**: Account & Sign-In · Recording & Uploads · Notifications · App Preferences · Storage
5. **Help & Legal**: Help & Support · About PlayerPath · Privacy Policy · Terms of Use (EULA)
6. Spread the Word (unchanged)
7. **Account**: Plan · Redeem Code · Export My Data · Export Statistics · Delete Account · Sign Out
8. Version

**Account & Sign-In (`SettingsView`):** Profile (one row showing username + email → Edit Account) · Sign-In Method (provider, plus Change Password for email accounts).

**Recording & Uploads (`VideoRecordingSettingsView`):** existing sections, plus a new athlete-only **On This iPhone** section: Save to Photos Library and Remove After Upload, with honest copy about highlight reels.

**App Preferences (`UserPreferencesView`):** General (Haptic Feedback, both roles) · Interface (tips) · Golf Scoring (athletes with a golf profile) · Privacy & Analytics. No Save button.

**Coach Profile (`CoachProfileView`):** the "Video Recording" row is renamed "Recording & Uploads", and the top-level "Review Reminders" row is removed (it's still inside Notifications and still in search).

## Global Constraints

- The iOS app has **no test target**. Verification = clean CLI build + the manual checks listed in each task.
- Build (the `DEVELOPER_DIR` prefix is required): `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PlayerPath.xcodeproj -scheme PlayerPath -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`. Trust the final `** BUILD SUCCEEDED **` over transient SourceKit noise.
- The project uses **synchronized folder groups** (`PBXFileSystemSynchronizedRootGroup`): deleting a `.swift` file needs **no** `project.pbxproj` edit.
- Saves go through `ErrorHandlerService.shared.saveContext(modelContext, caller:)` (`@discardableResult`). Never `try? context.save()`.
- Don't change any stored key, `@Model` property or default value. Existing users' choices must carry over untouched.
- Use `Theme` / `ppAccent` / `Font+PlayerPath` or the existing fonts already in the file. No `.brandGold` or new legacy tokens.
- Keep the analytics screen name `"Settings"` in `SettingsView.onAppear` so the dashboard history continues.
- Do not bump version/build numbers.
- Do the tasks **in order**. Each one leaves the app fully usable: every setting stays reachable at every commit.

## Verified facts this plan relies on (checked 2026-09-25, don't re-derive)

- Highlights Only and Max File Size only matter when auto-upload is on. Every consumer guards `autoUploadToCloud` first (`UploadQueueManager.swift:453`, `BulkVideoImportViewModel.swift:279`, `CoachVideoPlayerViewModel.swift:968`, `ProjectedCloudStorage.swift:75`). So hiding them while auto-upload is off (as Recording & Uploads already does) hides nothing that's active.
- App Preferences' 3-way auto-upload picker and Recording & Uploads' auto-upload + cellular toggles write the same `autoUploadMode` (`allowCellularUploads` ⇔ `.always`, `UserPreferences.swift:24-42`). Removing the picker loses no state.
- Remove After Upload never touches coach clips: `processUpload` returns into `processCoachUpload` before the auto-delete block (`UploadQueueManager.swift:729`). Coach recordings don't use `ClipPersistenceService` either (it needs an `athlete`, `DirectCameraRecorderView.swift:471`).
- "Removed clips download again when you play them" is true: `VideoPlayerView.findVideoURL` downloads when the file is missing and `isUploaded` (`:959-998`), and auto-delete only runs after a successful upload.
- Known, accepted: `UserPreferences.shared(in:)` may insert the singleton while `body` is being evaluated if the `@Query` is empty. `NotificationSettingsView` already does exactly this, and `MainAppView` creates the singleton at launch, so in practice the fallback never runs.

## Review Focus

1. **Coach opens App Preferences** → General/Interface/Privacy only. No Golf section, no crash when the `User` `@Query` is empty. (Task 2, Step 5 check C.)
2. **Upgrade install where the user had toggled Analytics off (or changed any preference) under the old Save-button screen** → the value shows unchanged in the new screen, and toggling it now persists across a relaunch with no Save tap. (Task 2, Step 5 check B.)
3. **Push tap that deep-links to storage** (`.navigateToCloudStorage` → `MoreDestination.storageSettings`) → still opens the Storage screen. The view is unchanged; only the More-tab row moved. (Task 3, Step 6 check D.)
4. **Searching the More tab for "golf", "upload", "password", "redeem"** → each result opens the setting's new home. (Task 3, Step 6 check C.)
5. **Dual-sport athlete whose selected profile is baseball but who also has a golf profile** → App Preferences still shows Golf Scoring (it checks *any* athlete, as the old Settings screen did). (Task 2, Step 5 check D.)

---

### Task 1: "Recording & Uploads" becomes the only home for upload and on-device options

**Why:** Save to Photos Library and Auto-delete After Upload currently exist only in App Preferences (under a "Video Recording" header). Auto-upload, Highlights Only and Max File Size exist on **both** screens. Auto-delete also quietly shortens highlight reels (`ReelStitchCoordinator.swift:157` skips clips that aren't on the phone) and has no explanation. This task adds the two missing toggles here with honest copy. Task 2 then removes the duplicates from App Preferences.

**Files:**
- Modify: `PlayerPath/VideoRecordingSettingsView.swift`: `body` Form list (`:46-56`), navigation title (`:60`), and a new `deviceCopySection` property placed right after `cloudUploadFooter` (after `:334`)

**Interfaces:**
- Consumes: `UserPreferences.saveToPhotosLibrary: Bool`, `UserPreferences.autoDeleteAfterUpload: Bool` (existing `@Model` properties in `PlayerPath/UserPreferences.swift`), and the view's existing `preferences` / `modelContext` / `role` / `ppAccent`.
- Produces: the screen's title is now `"Recording & Uploads"`. Tasks 3 and 4 use the same string for row labels.

- [ ] **Step 1: Add the section to the Form**

In `body`, replace:

```swift
            cloudUploadSection
            workflowSection
```

with:

```swift
            cloudUploadSection
            if role == .athlete {
                deviceCopySection
            }
            workflowSection
```

- [ ] **Step 2: Rename the screen**

Replace `.navigationTitle("Recording Settings")` with `.navigationTitle("Recording & Uploads")`.

- [ ] **Step 3: Add `deviceCopySection`**

Insert directly after the closing brace of `cloudUploadFooter`:

```swift
    /// Athlete-only: what happens to the copy on this iPhone. Coach recordings
    /// don't go through ClipPersistenceService or the athlete upload queue, so
    /// neither toggle applies to them.
    @ViewBuilder
    private var deviceCopySection: some View {
        if let prefs = preferences {
            Section {
                Toggle(isOn: Binding(
                    get: { prefs.saveToPhotosLibrary },
                    set: { prefs.saveToPhotosLibrary = $0; ErrorHandlerService.shared.saveContext(modelContext, caller: "RecordingSettings.saveToPhotos") }
                )) {
                    HStack {
                        Image(systemName: "photo.on.rectangle")
                            .foregroundColor(ppAccent)
                        Text("Save to Photos Library")
                    }
                }

                Toggle(isOn: Binding(
                    get: { prefs.autoDeleteAfterUpload },
                    set: { prefs.autoDeleteAfterUpload = $0; ErrorHandlerService.shared.saveContext(modelContext, caller: "RecordingSettings.autoDelete") }
                )) {
                    HStack {
                        Image(systemName: "iphone.slash")
                            .foregroundColor(prefs.autoDeleteAfterUpload ? Theme.warning : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Remove After Upload")
                            Text("Frees space on this iPhone")
                                .font(.bodySmall)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("On This iPhone")
            } footer: {
                // Honest about the trade-off: VideoPlayerView re-downloads on play,
                // but the reel stitcher only uses clips present on this device.
                Text("Removed clips download again when you play them. Highlight reels can only include clips that are still on this iPhone.")
            }
        }
    }
```

- [ ] **Step 4: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Manual check**

A. Athlete → More → Video Recording (row label changes in Task 3): the title reads "Recording & Uploads", and the "On This iPhone" section appears under Cloud Upload.
B. Turn on Save to Photos Library, go back, open App Preferences (old screen, still present until Task 2): its Save to Photos toggle shows on. Same underlying value.
C. Coach → Profile → Video Recording: no "On This iPhone" section.

- [ ] **Step 6: Commit**

```bash
git add PlayerPath/VideoRecordingSettingsView.swift
git commit -m "Recording & Uploads: add On This iPhone section (save to Photos, remove after upload)"
```

---

### Task 2: App Preferences: one home per setting, saves on change, golf defaults move in

**Why:** App Preferences titles itself "Settings", duplicates the upload options (now covered by Task 1), files Haptic Feedback under "Video Recording" for athletes, and uses a Save button that doesn't really hold anything back: `update()` edits the live `@Model`, so changes take effect before Save, and the Analytics toggle applies instantly. Every other settings screen saves on change. The golf scoring toggles live in the Account-level Settings screen, which is the wrong home.

**Files:**
- Rewrite: `PlayerPath/UserPreferencesView.swift` (full file below)
- Delete: `PlayerPath/UserPreferencesViewModel.swift` (its only user is `UserPreferencesView`; `UserPreferences.example` inside it has no callers. Verified with `grep -rn "UserPreferencesViewModel\|UserPreferences.example" PlayerPath`)
- Modify: `PlayerPath/Views/Profile/SettingsView.swift`: remove the Golf section and its properties (lines `:19-26` and `:76-92`)

**Interfaces:**
- Consumes: `UserPreferences.shared(in: ModelContext) -> UserPreferences` (`PlayerPath/UserPreferences.swift:82`), `GolfPrefs.trackDetailedStats` / `GolfPrefs.preferredShotByShot` (`PlayerPath/Services/GolfPreferences.swift`), `AnalyticsService.shared.setCollection(enabled:)`, `ComprehensiveAuthManager.userRole`.
- Produces: `UserPreferencesView()` keeps its no-argument initializer, so every call site (`ProfileView`, `SettingsView`, `CoachProfileView`, `CoachProfileView+Search`) compiles unchanged. The title is now `"App Preferences"`.

- [ ] **Step 1: Replace `UserPreferencesView.swift` with:**

```swift
//
//  UserPreferencesView.swift
//  PlayerPath
//
//  App Preferences: haptics, onboarding tips, golf scoring defaults, analytics.
//  Recording, upload, and on-device copy options live in
//  VideoRecordingSettingsView ("Recording & Uploads") — one home per setting.
//

import SwiftUI
import SwiftData
import TipKit

struct UserPreferencesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.ppAccent) private var ppAccent
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @Query private var allPrefs: [UserPreferences]
    @Query private var users: [User]
    @State private var showingResetTipsConfirm = false

    // Haptics.swift reads this UserDefaults key directly, so the view writes to
    // it directly too — no SwiftData mirroring.
    @AppStorage("hapticFeedbackEnabled") private var hapticFeedbackEnabled: Bool = true
    @AppStorage(GolfPrefs.trackDetailedStats) private var trackDetailedGolfStats = false
    @AppStorage(GolfPrefs.preferredShotByShot) private var preferShotByShot = false

    private var isCoach: Bool { authManager.userRole == .coach }

    /// Same accessor as NotificationSettingsView: @Query for reactivity,
    /// shared(in:) as the safety net if the singleton isn't there yet.
    private var prefs: UserPreferences {
        allPrefs.first ?? UserPreferences.shared(in: modelContext)
    }

    /// Golf defaults are clutter for baseball-only and coach accounts. Any golf
    /// profile counts (a dual-sport person's golf row), matching the old gate.
    private var hasGolfAthlete: Bool {
        !isCoach && (users.first?.athletes?.contains { $0.sport == .golf } ?? false)
    }

    var body: some View {
        Form {
            generalSection
            interfaceSection
            if hasGolfAthlete {
                golfSection
            }
            privacyAnalyticsSection
        }
        .scrollContentBackground(.hidden)
        .background(Theme.surface)
        .tint(ppAccent)
        .navigationTitle("App Preferences")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Reset onboarding tips?",
            isPresented: $showingResetTipsConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                do {
                    try Tips.resetDatastore()
                } catch {
                    ErrorHandlerService.shared.handle(error, context: "Tips.resetDatastore", showAlert: false)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Hints you've already dismissed will show again the next time you visit each tab.")
        }
    }

    /// Write-through: every other settings screen saves on change, so this one
    /// does too (the old Save button implied a draft that never existed —
    /// edits hit the live model immediately).
    private func prefBinding(_ keyPath: ReferenceWritableKeyPath<UserPreferences, Bool>, caller: String) -> Binding<Bool> {
        Binding(
            get: { prefs[keyPath: keyPath] },
            set: { newValue in
                prefs[keyPath: keyPath] = newValue
                ErrorHandlerService.shared.saveContext(modelContext, caller: caller)
            }
        )
    }

    // MARK: - Sections

    private var generalSection: some View {
        Section("General") {
            Toggle("Haptic Feedback", isOn: $hapticFeedbackEnabled)
        }
    }

    private var interfaceSection: some View {
        Section("Interface") {
            Toggle("Show Onboarding Tips", isOn: prefBinding(\.showOnboardingTips, caller: "AppPreferences.tips"))

            Button("Reset Onboarding Tips") {
                showingResetTipsConfirm = true
            }
        }
    }

    private var golfSection: some View {
        Section("Golf Scoring") {
            Toggle(isOn: $trackDetailedGolfStats) {
                Label("Track Detailed Stats", systemImage: "flag.fill")
            }
            Text("Adds fairway, green-in-regulation, and penalty inputs when scoring a round.")
                .font(.bodySmall)
                .foregroundColor(.secondary)

            Toggle(isOn: $preferShotByShot) {
                Label("Default to Shot-by-Shot", systemImage: "scope")
            }
            Text("New rounds open the shot-by-shot card when you score a hole. You can still switch to Quick on any hole.")
                .font(.bodySmall)
                .foregroundColor(.secondary)
        }
    }

    private var privacyAnalyticsSection: some View {
        Section {
            Toggle("Enable Analytics", isOn: Binding(
                get: { prefs.enableAnalytics },
                set: { newValue in
                    prefs.enableAnalytics = newValue
                    AnalyticsService.shared.setCollection(enabled: newValue)
                    ErrorHandlerService.shared.saveContext(modelContext, caller: "AppPreferences.analytics")
                }
            ))
        } header: {
            Text("Privacy & Analytics")
        } footer: {
            Text("Help improve PlayerPath by sharing anonymous usage data.")
        }
    }
}
```

- [ ] **Step 2: Delete the view model**

```bash
git rm PlayerPath/UserPreferencesViewModel.swift
```

- [ ] **Step 3: Remove Golf from `SettingsView.swift`**

Delete these lines (`:19-26`):

```swift
    @AppStorage(GolfPrefs.trackDetailedStats) private var trackDetailedGolfStats = false
    @AppStorage(GolfPrefs.preferredShotByShot) private var preferShotByShot = false

    /// Only surface the golf detailed-stats toggle to users who actually have a
    /// golf athlete — it's clutter for baseball-only accounts.
    private var hasGolfAthlete: Bool {
        user.athletes?.contains { $0.sport == .golf } ?? false
    }
```

and the whole `if hasGolfAthlete { Section("Golf") { … } }` block (`:76-92`). Task 3 rewrites the rest of this file.

- [ ] **Step 4: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`. If the compiler rejects `prefs[keyPath:]` on the `@Model` class, change `prefBinding` to take a getter/setter pair (`get: () -> Bool, set: (Bool) -> Void`) and keep the same call semantics. Don't fall back to the deleted view model.

- [ ] **Step 5: Manual check**

A. Athlete → More → Settings → App Preferences: the title reads "App Preferences". Sections: General (Haptic Feedback), Interface, Privacy & Analytics. No Video Recording or Cloud Storage sections, no Save button.
B. Toggle Analytics off, force-quit, relaunch → still off. Repeat for Show Onboarding Tips.
C. Coach → Profile → App Preferences: General, Interface, Privacy & Analytics, no Golf. No crash.
D. Account with a golf profile (including a dual-sport person whose selected profile is baseball): Golf Scoring appears. Toggle Track Detailed Stats on, open a round's hole scoring → the fairway/GIR inputs show.

- [ ] **Step 6: Commit**

```bash
git add PlayerPath/UserPreferencesView.swift PlayerPath/Views/Profile/SettingsView.swift
git commit -m "App Preferences: save on change, haptics under General, golf defaults moved in, upload dupes removed"
```

---

### Task 3: Athlete More tab regrouped; nested Settings becomes "Account & Sign-In"

**Why:** App Preferences and Storage sit three levels deep (More → Settings → …). Username and email show three times. The More tab's "Settings" section mixes Shared Folders, a "Settings" row, Activity, Help and About. Legal is a two-row section of its own. Redeem Code hides under Settings → Subscription instead of next to the Plan row.

**Files:**
- Rewrite: `PlayerPath/Views/Profile/SettingsView.swift` (full file below; keeps `struct SettingsView` and `init(user:)`)
- Modify: `PlayerPath/ProfileView.swift`: `body` section list (`:44-54`), `settingsSection` (`:656-714`), `legalSection` (`:743-757`), `accountSection` (`:792-840`), search items "Settings" (`:243-255`), "Video Recording" (`:257-268`), "Manage Storage" (`:481-492`), "App Preferences" (`:494-505`)

**Interfaces:**
- Consumes: `SettingsView(user:)`, `VideoRecordingSettingsView()` (default role `.athlete`), `UserPreferencesView()`, `StorageSettingsView()`, `NotificationSettingsView(athleteId:)`, `RedeemOfferCodeRow()`, `AthleteFoldersListView(userID:athlete:)`, `NotificationInboxView()`, `HelpSupportView()`, `AboutView()`, `PrivacyPolicyView()`, `TermsOfServiceView()`. All exist; none of their signatures change.
- Produces: new `ProfileView` properties `coachingSection` and `helpLegalSection`; `legalSection` is deleted.

- [ ] **Step 1: Replace `SettingsView.swift` with:**

```swift
//
//  SettingsView.swift
//  PlayerPath
//
//  "Account & Sign-In": who you are and how you sign in. Storage, App
//  Preferences, and Redeem Code live on the More tab itself (2026-09 layout
//  pass) so nothing sits three levels deep; golf scoring defaults live in
//  App Preferences.
//

import SwiftUI
import SwiftData
import FirebaseAuth

struct SettingsView: View {
    let user: User

    @Environment(\.ppAccent) private var ppAccent

    var body: some View {
        Form {
            Section("Profile") {
                // One row instead of separate Username / Email rows plus an
                // "Edit Information" link — the same Apple-ID-style pattern iOS uses.
                NavigationLink {
                    EditAccountView(user: user)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.username)
                            .foregroundColor(.primary)
                        Text(user.email)
                            .font(.bodySmall)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .accessibilityLabel("Edit Information, \(user.username)")
                .accessibilityHint("Change your username, email, or profile picture")
            }

            let provider = Auth.auth().currentUser?.providerData.first?.providerID ?? "email"
            Section("Sign-In Method") {
                Label(
                    provider == "apple.com" ? "Sign in with Apple" : "Email & Password",
                    systemImage: provider == "apple.com" ? "apple.logo" : "envelope.fill"
                )

                if provider != "apple.com" {
                    NavigationLink {
                        ChangePasswordView(email: user.email)
                    } label: {
                        Label("Change Password", systemImage: "lock.rotation")
                    }
                }
            }
        }
        // Screen name kept as "Settings" so the analytics history stays continuous.
        .onAppear { AnalyticsService.shared.trackScreenView(screenName: "Settings", screenClass: "ProfileView") }
        .scrollContentBackground(.hidden)
        .background(Theme.surface)
        .tint(ppAccent)
        .navigationTitle("Account & Sign-In")
        .navigationBarTitleDisplayMode(.inline)
    }
}
```

- [ ] **Step 2: `ProfileView` section order**

Replace the `List { … }` contents in `body` (`:45-53`):

```swift
            billingRetrySection
            quickSearchSection
            userProfileSection
            athletesSection
            settingsSection
            legalSection
            shareSection
            accountSection
            appVersionSection
```

with:

```swift
            billingRetrySection
            quickSearchSection
            userProfileSection
            athletesSection
            coachingSection
            settingsSection
            helpLegalSection
            shareSection
            accountSection
            appVersionSection
```

- [ ] **Step 3: Replace `settingsSection` and add `coachingSection`**

Replace the entire `private var settingsSection: some View { … }` (`:656-714`) with:

```swift
    /// Coach sharing + the activity inbox — the "people" rows, kept apart from
    /// configuration so the Settings section below holds only settings.
    private var coachingSection: some View {
        Section("Coaching & Activity") {
            // Coach Sharing — free for athletes (the coach's seat covers the connection)
            if let folderAthlete = selectedAthlete ?? user.athletes?.first {
                NavigationLink {
                    AthleteFoldersListView(userID: authManager.userID, athlete: folderAthlete)
                } label: {
                    Label("Shared Folders", systemImage: "folder.badge.person.crop")
                }
            }

            NavigationLink {
                NotificationInboxView()
            } label: {
                HStack {
                    Label("Activity", systemImage: "bell.badge")
                    Spacer()
                    if activityNotifService.unreadCount > 0 {
                        Text("\(activityNotifService.unreadCount)")
                            .font(.custom("Inter18pt-SemiBold", size: 12, relativeTo: .caption))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.red, in: Capsule())
                    }
                }
            }
        }
    }

    private var settingsSection: some View {
        Section("Settings") {
            NavigationLink {
                SettingsView(user: user)
            } label: {
                Label("Account & Sign-In", systemImage: "person.crop.circle")
            }

            NavigationLink {
                VideoRecordingSettingsView()
            } label: {
                Label("Recording & Uploads", systemImage: "video.fill")
            }

            NavigationLink {
                NotificationSettingsView(athleteId: selectedAthlete?.id.uuidString)
            } label: {
                Label("Notifications", systemImage: "bell")
            }

            NavigationLink {
                UserPreferencesView()
            } label: {
                Label("App Preferences", systemImage: "slider.horizontal.3")
            }

            NavigationLink {
                StorageSettingsView()
            } label: {
                Label("Storage", systemImage: "internaldrive")
            }
        }
    }
```

(Shared Folders keeps its current `selectedAthlete ?? user.athletes?.first` fallback. Fixing that is audit item #4/#8, a separate change; don't touch it here.)

- [ ] **Step 4: Replace `legalSection` with `helpLegalSection`**

Replace the entire `private var legalSection: some View { … }` (`:743-757`) with:

```swift
    private var helpLegalSection: some View {
        Section("Help & Legal") {
            NavigationLink {
                HelpSupportView()
            } label: {
                Label("Help & Support", systemImage: "questionmark.circle")
            }

            NavigationLink {
                AboutView()
            } label: {
                Label("About PlayerPath", systemImage: "info.circle")
            }

            NavigationLink {
                PrivacyPolicyView()
            } label: {
                Label("Privacy Policy", systemImage: "hand.raised")
            }

            NavigationLink {
                TermsOfServiceView()
            } label: {
                Label("Terms of Use (EULA)", systemImage: "doc.text")
            }
        }
    }
```

- [ ] **Step 5: Redeem Code next to Plan; update search entries**

In `accountSection`, insert `RedeemOfferCodeRow()` directly after the Plan `NavigationLink`'s closing brace, before `// Data Export (GDPR Compliance)`:

```swift
            // Redeem sits beside the plan it changes (was Settings → Subscription).
            RedeemOfferCodeRow()
```

In `allSearchableItems`, make four replacements:

"Settings" item (`:243-255`) →
```swift
        items.append(SearchResult(
            title: "Account & Sign-In",
            icon: "person.crop.circle",
            keywords: ["account", "sign in", "sign-in", "username", "email", "apple", "settings"],
            link: AnyView(
                NavigationLink {
                    SettingsView(user: user)
                } label: {
                    Label("Account & Sign-In", systemImage: "person.crop.circle")
                }
            )
        ))
```

"Video Recording" item (`:257-268`) →
```swift
        items.append(SearchResult(
            title: "Recording & Uploads",
            icon: "video.fill",
            keywords: ["video", "recording", "4k", "quality", "camera", "resolution", "fps", "upload", "cloud", "wifi", "cellular", "highlights only", "photos library", "remove after upload", "trimmer"],
            link: AnyView(
                NavigationLink {
                    VideoRecordingSettingsView()
                } label: {
                    Label("Recording & Uploads", systemImage: "video.fill")
                }
            )
        ))
```

"Manage Storage" item (`:481-492`): change `title: "Manage Storage"` to `title: "Storage"` and the `Label` text to `"Storage"`. Keep the keywords as they are; `"manage"` is already among them, so "manage storage" still matches.

"App Preferences" item (`:494-505`): replace its keywords with
```swift
            keywords: ["app", "preferences", "haptics", "tips", "analytics", "interface", "golf", "shot-by-shot", "detailed stats", "fairway"],
```
(`"auto-upload"` leaves this item; it now matches "Recording & Uploads" through `"upload"`.)

Update the comment above "Edit Information" (`:466-467`) to: `// Nested children — surfaced so search finds screens one level down (Edit Info / Password).`

- [ ] **Step 6: Build and manual check**

Run the build command. Expected: `** BUILD SUCCEEDED **`. Then, as an athlete:
A. The More tab matches the Target layout's section order and row labels exactly. No row appears in two sections.
B. Account & Sign-In: one Profile row (username over email) → Edit Account; Sign-In Method shows the provider; email accounts get Change Password, Apple accounts don't.
C. Search: "golf" → App Preferences; "upload" → Recording & Uploads; "password" → Change Password (email account); "redeem" → Redeem Code; "storage" → Storage. Tap each → the right screen.
D. Trigger the storage deep link: from a temporary debug button, or `po NotificationCenter.default.post(name: .navigateToCloudStorage, object: nil)` at a breakpoint, post `Notification.Name.navigateToCloudStorage` (observed at `MainTabView.swift:494`, which calls `navigateToMore(.storageSettings)`). The Storage screen should open.
E. Redeem Code in the Account section opens Apple's sheet on a device (the simulator can't show it; see `RedeemOfferCodeRow` header).

- [ ] **Step 7: Commit**

```bash
git add PlayerPath/Views/Profile/SettingsView.swift PlayerPath/ProfileView.swift
git commit -m "More tab: regroup into Coaching & Activity / Settings / Help & Legal / Account; flatten Account & Sign-In"
```

---

### Task 4: Coach Profile matches the new names and loses the duplicate row

**Why:** "Review Reminders" is a top-level row in the coach's Settings section (`CoachProfileView.swift:225-227`) **and** a row inside Notifications (`NotificationSettingsView.swift:273-286`). Coach labels should match the athlete-side names from Tasks 1–3.

**Files:**
- Modify: `PlayerPath/CoachProfileView.swift:213-227`
- Modify: `PlayerPath/CoachProfileView+Search.swift:48-51`

**Interfaces:**
- Consumes: `VideoRecordingSettingsView(role: .coach)`, `CoachReviewReminderSettingsView()` (unchanged).
- Produces: nothing.

- [ ] **Step 1: Coach Settings section**

In `CoachProfileView.swift`, replace:

```swift
                    NavigationLink(destination: VideoRecordingSettingsView(role: .coach)) {
                        Label("Video Recording", systemImage: "video.fill")
                    }
```

with:

```swift
                    NavigationLink(destination: VideoRecordingSettingsView(role: .coach)) {
                        Label("Recording & Uploads", systemImage: "video.fill")
                    }
```

and delete:

```swift
                    NavigationLink(destination: CoachReviewReminderSettingsView()) {
                        Label("Review Reminders", systemImage: "bell.badge")
                    }
```

(It stays reachable from Notifications → Review Reminders and from search.)

- [ ] **Step 2: Coach search entry**

In `CoachProfileView+Search.swift`, replace:

```swift
            searchItem("Video Recording", icon: "video.fill",
                       keywords: ["video", "recording", "quality", "camera", "resolution", "fps", "4k"]) {
```

with:

```swift
            searchItem("Recording & Uploads", icon: "video.fill",
                       keywords: ["video", "recording", "quality", "camera", "resolution", "fps", "4k", "upload", "cellular", "wifi"]) {
```

Leave the "Review Reminders" search item as it is: search is exactly where a deep row should be findable.

- [ ] **Step 3: Build and manual check**

Build. Expected: `** BUILD SUCCEEDED **`. Coach → Profile: Settings shows App Preferences, Recording & Uploads, Manage Storage, Notifications, Change Password (email accounts). No Review Reminders row there. Notifications → Review Reminders still opens. Search "review" → Review Reminders.

- [ ] **Step 4: Commit**

```bash
git add PlayerPath/CoachProfileView.swift PlayerPath/CoachProfileView+Search.swift
git commit -m "Coach profile: Recording & Uploads label, drop duplicate Review Reminders row"
```

---

## After all tasks

- Update memory `project_profile_settings_audit_2026_08.md`: mark #2 (auto-upload dual UI) and #3 (App Preferences title) done, and add a note on the layout pass.
- Still open, **not** in this plan: #4/#8 athlete context (flat athlete list, Shared Folders fallback), #6 export gaps, the coach Storage screen (review finding #5), reel stitching of cloud-only clips (#3 beyond the copy), and the silent max-file-size skip (#4).
