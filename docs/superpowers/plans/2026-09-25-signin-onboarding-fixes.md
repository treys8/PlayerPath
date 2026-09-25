# Sign-in & Onboarding Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the two real sign-in/onboarding bugs, close three open items from the 2026-09-05 review, finish the color pass on the auth screens, and make four small sign-in UX improvements.

**Architecture:** All client-side Swift. Durable onboarding state is a UID-scoped UserDefaults marker, re-armed into the existing session-only `isNewUser` flag at the three places that flip `isSignedIn = true`. Apple sign-in gating suppresses the auth listener for the Apple flow (`isHandlingSignIn`), which means the listener's "restore session" body gets extracted into a shared method. The color pass maps system colors to existing `Theme` tokens and adds one alias (`Theme.success`).

**Tech Stack:** SwiftUI (iOS 17+), SwiftData, FirebaseAuth, UserDefaults.

**Spec:** The 2026-09-25 sign-in/onboarding review in this conversation. Its findings are summarized under **Background** below. Memory: `project_onboarding_review_2026_09_05.md`, `project_edit_athlete_name_todo.md` (option A chosen).

## Background (what's broken and why)

1. **Onboarding is lost on relaunch.** `ComprehensiveAuthManager.isNewUser` is session-only (`ComprehensiveAuthManager.swift:24`, reasoning at `:171-175`). Here's the sequence: a user signs up by email, switches to Mail, and iOS kills the app. On relaunch `isNewUser == false`, so `AuthenticatedFlow.loadUser()` (`AuthenticatedFlow.swift:353-359`) marks onboarding complete for **any** role. The coach flow, the athlete season/backup steps and the walkthrough are all skipped.
2. **Apple on the Sign In sheet creates unconsented accounts.** The age checkbox gates the Apple button only in sign-up mode (`ComprehensiveSignInView.swift:297`). A first-time Apple ID tapping it on the Sign In sheet gets a new account (`AppleSignInManager.swift:238-276`) with no age attestation and `pendingRole == .athlete`.
3. **Open items.** `pendingCoachInvitations` is written at coach sign-up and never read. Settings shows auto-upload "Off" for nil `autoUploadMode` rows while uploads actually run. Athletes can't be renamed.
4. **Auth screens are half-themed.** Buttons and icons are terracotta, but backgrounds and text are system gray (`systemGroupedBackground`, `.secondary`, `systemGray4`, `.red/.green`).

## Global Constraints

- iOS 17+ deployment target. App is light-mode only (`MainAppView.swift:80` `.preferredColorScheme(.light)`).
- Never use `HTTPSCallable` (none needed here).
- SwiftData saves in views go through `ErrorHandlerService.shared.saveContext(_:caller:)`, never `try? context.save()`.
- New UI uses `Theme` colors. Keep the surrounding file's type scale (these files use `.bodySmall/.headingMedium`…; don't mix in `.pp*` mid-file).
- New Swift files stay small and focused.
- Do NOT touch version/build numbers (Trey owns them).
- There is no Swift test target. Each task's verification = CLI build + the listed manual simulator checks.
- Build command (used by every task):
  ```bash
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
    xcodebuild -project PlayerPath.xcodeproj -scheme PlayerPath -sdk iphonesimulator \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
  ```
  Expected: `** BUILD SUCCEEDED **` (ignore transient SourceKit noise).
- Commit messages end with: `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`

**Out of scope, deliberately:**
- Age-posture wording: a lawyer question (`project_age_posture_contradiction.md`).
- Parent-voiced walkthrough copy: depends on the age decision.
- The 750 ms focus delay in `ComprehensiveSignInView`: guards a real deadlock and can't be verified here.
- The baseball welcome logo: a brand call.

## Review Focus

1. **Existing Apple user taps Apple on the Sign In sheet.** They must land signed in with their real role (coach stays coach). Task 2 suppresses the listener for this path, so a missed step = stuck on "Welcome back!" or the wrong role. Test in Task 2, Step 6.
2. **App killed during email verification, then relaunched.** Athlete resumes at Add Athlete; coach resumes the coach flow. Test in Task 1, Step 6.
3. **"Use a Different Account", then later sign back into the unfinished account.** Onboarding resumes; the marker is NOT cleared on sign-out. Test in Task 1, Step 6.
4. **New Apple ID blocked on the Sign In sheet.** No Firebase user remains, no local `User` row, and "Create an account" then works. Test in Task 2, Step 6.
5. **Renaming a dual-sport athlete.** Same-named linked rows rename together; a deliberately different sibling name is left alone; the duplicate check doesn't flag a sibling. Test in Task 5, Step 4 (cases 2 and 2b).

---

### Task 1: Durable "onboarding pending" marker

**Files:**
- Modify: `PlayerPath/AuthConstants.swift:53-59`
- Modify: `PlayerPath/ComprehensiveAuthManager+Onboarding.swift`
- Modify: `PlayerPath/ComprehensiveAuthManager.swift:235-254` (`resetNewUserFlag`, `updateCurrentUser`)
- Modify: `PlayerPath/ComprehensiveAuthManager+Auth.swift` (listener `:91-97`, `signIn` `:151`, `signUp` `:201`, `signUpAsCoach` `:268`, `checkEmailVerification` `:463-465`)
- Modify: `PlayerPath/Views/Navigation/AuthenticatedFlow.swift:33-39` (comment only)

**Interfaces:**
- Produces: `func markOnboardingPending(uid: String)`, `func clearPendingOnboarding()`, `func restorePendingOnboardingIfNeeded(for user: FirebaseAuth.User)` on `ComprehensiveAuthManager`. Task 2 relies on `restorePendingOnboardingIfNeeded` being called inside the listener body it extracts.

- [ ] **Step 1: Add the key**

In `AuthConstants.swift`, inside `enum UserDefaultsKeys`, after `signInLockedUntil`:

```swift
        /// UID whose sign-up finished but onboarding hasn't. Survives relaunch
        /// and sign-out on purpose — see ComprehensiveAuthManager+Onboarding.
        static let pendingOnboardingUID = "pendingOnboardingUID"
```

Do NOT add it to `clearPersistedUserDefaults()`.

- [ ] **Step 2: Add the helpers**

In `ComprehensiveAuthManager+Onboarding.swift`, add `import FirebaseAuth` under `import SwiftData`, and append inside the extension:

```swift
    // MARK: - Pending onboarding (survives relaunch)

    /// `isNewUser` is session-only (see init). This UID-scoped marker is the
    /// durable record that sign-up happened but onboarding hasn't finished, so a
    /// relaunch during email verification (Mail → tap link → iOS kills us) still
    /// routes to onboarding. Deliberately NOT cleared on sign-out: "Use a
    /// Different Account" followed by signing back in must resume it.
    func markOnboardingPending(uid: String) {
        UserDefaults.standard.set(uid, forKey: AuthConstants.UserDefaultsKeys.pendingOnboardingUID)
    }

    func clearPendingOnboarding() {
        UserDefaults.standard.removeObject(forKey: AuthConstants.UserDefaultsKeys.pendingOnboardingUID)
    }

    /// Re-arms `isNewUser` for a session whose onboarding never finished.
    /// Call AFTER the profile load (a true `isNewUser` makes profile loads keep
    /// the pre-set role instead of Firestore's) and BEFORE `isSignedIn = true`
    /// (AuthenticatedFlow reads `isNewUser` as it appears).
    func restorePendingOnboardingIfNeeded(for user: FirebaseAuth.User) {
        guard !isNewUser,
              UserDefaults.standard.string(forKey: AuthConstants.UserDefaultsKeys.pendingOnboardingUID) == user.uid
        else { return }
        // Bounded so a stale marker (e.g. onboarding finished on another
        // device) can't drop an established account back into setup forever.
        let created = user.metadata.creationDate ?? .distantPast
        guard Date().timeIntervalSince(created) < 14 * 24 * 60 * 60 else {
            clearPendingOnboarding()
            return
        }
        isNewUser = true
    }
```

- [ ] **Step 3: Clear on completion, mark on Apple sign-up**

In `ComprehensiveAuthManager.swift`, replace `resetNewUserFlag()`:

```swift
    func resetNewUserFlag() {
        isNewUser = false
        // Both onboarding finish lines (OnboardingBackupView for athletes,
        // completeOnboarding for coaches) come through here.
        clearPendingOnboarding()
    }
```

In `updateCurrentUser(_:isNewUser:role:)`, change the trailing block to:

```swift
        if isNewUser {
            markOnboardingPending(uid: user.uid)
            isSignedIn = true
        }
```

- [ ] **Step 4: Mark on email sign-up, restore before every `isSignedIn = true`**

In `ComprehensiveAuthManager+Auth.swift`:

`signUp` — right after `currentFirebaseUser = result.user` (line ~201):
```swift
            markOnboardingPending(uid: result.user.uid)
```

`signUpAsCoach` — right after `currentFirebaseUser = result.user` (line ~268):
```swift
            markOnboardingPending(uid: result.user.uid)
```

`signIn` — replace the `isSignedIn = true` at line ~151 with:
```swift
            restorePendingOnboardingIfNeeded(for: result.user)
            isSignedIn = true
```

Auth listener — replace `self?.isSignedIn = true` at line ~97 with:
```swift
                    if let user { self?.restorePendingOnboardingIfNeeded(for: user) }
                    self?.isSignedIn = true
```

`checkEmailVerification` — replace the two lines `needsEmailVerification = false` / `isSignedIn = true` with:
```swift
                needsEmailVerification = false
                restorePendingOnboardingIfNeeded(for: refreshedUser)
                isSignedIn = true
```

- [ ] **Step 5: Fix the stale routing comment**

In `AuthenticatedFlow.swift`, replace the comment at lines 33-39 with:

```swift
                // Coaches are the only role with a dedicated onboarding flow.
                // A relaunch or re-sign-in mid-onboarding re-arms isNewUser from
                // the pending-onboarding marker (restorePendingOnboardingIfNeeded)
                // before isSignedIn flips, so loadUser()'s `!isNewUser` branch —
                // which marks onboarding complete — never catches an unfinished
                // coach. Athletes have no separate flow: loadUser() marks them
                // complete and their setup steps are branches of UserMainFlow.
```

- [ ] **Step 6: Build and verify manually**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

On the simulator (use fresh `+tagN@` email addresses):
1. Athlete sign-up → verification screen → stop the app from Xcode → verify the email in a browser → relaunch → tap "I've Verified My Email". **Expected:** "Create First Athlete" screen. Then season → backup → walkthrough.
2. Same with a **Coach** account. **Expected:** CoachOnboardingFlow page 1, not the Dashboard.
3. Athlete sign-up → verify → create athlete → kill on the season screen → relaunch. **Expected:** season screen again.
4. Sign-up → verification screen → "Use a Different Account" → Sign In with the same credentials after verifying. **Expected:** onboarding starts.
5. Sign in with an existing, onboarded account. **Expected:** straight to Home, no walkthrough.

- [ ] **Step 7: Commit**

```bash
git add PlayerPath/AuthConstants.swift PlayerPath/ComprehensiveAuthManager.swift PlayerPath/ComprehensiveAuthManager+Onboarding.swift PlayerPath/ComprehensiveAuthManager+Auth.swift PlayerPath/Views/Navigation/AuthenticatedFlow.swift
git commit -m "Onboarding: survive a relaunch or re-sign-in mid-onboarding

isNewUser is session-only, so an app kill during email verification
skipped all onboarding (coach flow included). A UID-scoped marker now
re-arms it before isSignedIn flips; cleared when onboarding finishes.

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Apple on the Sign In sheet never creates an account

**Files:**
- Modify: `PlayerPath/ComprehensiveAuthManager+Auth.swift:56-105` (extract listener body)
- Modify: `PlayerPath/AppleSignInManager.swift` (flag, listener suppression, blocked branch, returning-user finish)
- Modify: `PlayerPath/Views/Auth/ComprehensiveSignInView.swift` (pass the flag, "no account" card, `onSwitchToSignUp`)
- Modify: `PlayerPath/Views/Auth/WelcomeFlow.swift:189-201`

**Interfaces:**
- Consumes: `restorePendingOnboardingIfNeeded(for:)` (Task 1).
- Produces: `func finishSessionRestore(for user: FirebaseAuth.User) async` on `ComprehensiveAuthManager`. On `AppleSignInManager`: `var allowsAccountCreation: Bool` and `@Published var accountCreationBlocked: Bool`. On `ComprehensiveSignInView`: `var onSwitchToSignUp: (() -> Void)?`.

- [ ] **Step 1: Extract the listener's restore path**

In `ComprehensiveAuthManager+Auth.swift`, replace the whole final `else { ... }` branch of the listener (from `} else {` after the `isHandlingSignIn` check through the closing brace before the Task ends) with:

```swift
                } else if let user {
                    await self?.finishSessionRestore(for: user)
                }
```

Add this method to the extension, directly after `setupAuthStateListener()`:

```swift
    /// The "existing session" path: app relaunch, and Apple sign-in for a
    /// returning user (which suppresses the listener via isHandlingSignIn and
    /// calls this itself). Loads the profile BEFORE setting isSignedIn so the UI
    /// routes to the correct role.
    func finishSessionRestore(for user: FirebaseAuth.User) async {
        // signUp/signUpAsCoach/Apple-new create the profile themselves.
        if !isNewUser {
            authLog.debug("Restoring session — loading profile for existing user")
            // Retry: a single-shot load swallows errors and leaves the stale
            // default role; backoff gives Firestore time after a cold launch.
            await loadUserProfileWithRetry(maxAttempts: 3)
        }

        // Sync local SwiftData user AFTER profile load so the correct role is written.
        await ensureLocalUser()

        // Block unverified non-grandfathered accounts.
        if requiresEmailVerification(user) {
            needsEmailVerification = true
            authLog.info("Session restore — email not verified, blocking access")
            return
        }

        // Established accounts verified under older builds can carry a cached
        // token whose email_verified claim is still false. Refresh only when
        // the claim diverges, so normal launches pay nothing.
        if user.isEmailVerified,
           let result = try? await user.getIDTokenResult(),
           (result.claims["email_verified"] as? Bool) != true {
            _ = try? await user.getIDToken(forcingRefresh: true)
        }

        restorePendingOnboardingIfNeeded(for: user)
        isSignedIn = true

        // Apple can provide mixed-case emails; rules use the profile email.
        if let email = user.email, email != email.lowercased() {
            authLog.info("Firebase Auth email is not lowercase: \(email, privacy: .private) — handled via profile email lookup in security rules")
        }
    }
```

This moves code without changing behavior. Diff it against the removed listener body and confirm every statement survived. Task 1's `restorePendingOnboardingIfNeeded` call moves with it.

- [ ] **Step 2: AppleSignInManager — flag and published state**

Under `var pendingRole: UserRole = .athlete`, add:

```swift
    /// False on the Sign In sheet: a first-time Apple ID there has not
    /// confirmed age or chosen a role, so the just-created Firebase account is
    /// discarded and the UI offers the sign-up form instead.
    var allowsAccountCreation = true

    /// Set when a new Apple ID was turned away because allowsAccountCreation
    /// was false. The sign-in view shows a "create an account" card.
    @Published var accountCreationBlocked = false
```

In `signInWithApple()`, after `errorMessage = nil`, add:
```swift
        accountCreationBlocked = false
```

- [ ] **Step 3: AppleSignInManager — suppress the listener, gate new accounts, finish returning users**

In `authorizationController(controller:didCompleteWithAuthorization:)`, directly before the `do {` that follows the re-auth `if let continuation` block, add:

```swift
            // Capture strongly for the whole flow. ComprehensiveSignInView calls
            // cleanup() (authManager = nil) in onDisappear, and the sheet
            // dismisses 100ms after isSignedIn flips — which for a NEW user is
            // inside updateCurrentUser, BEFORE commitChanges/createUserProfile
            // finish. Reading self.authManager after that point races to nil
            // (pre-existing: it can silently skip createUserProfile) and would
            // leave isHandlingSignIn stuck true.
            let authManager = self.authManager

            // Own the whole Apple flow: the listener would otherwise race us —
            // loading a profile, creating a local User and flipping isSignedIn
            // for an account we may be about to discard.
            authManager?.isHandlingSignIn = true
            defer { authManager?.isHandlingSignIn = false }
```

Every later `authManager` reference in this method (the `updateCurrentUser` call, the `if isNewUser, let authManager = authManager` binding, and the calls added below) now resolves to this local. Also replace `self.authManager` in `discardUnconsentedAccount` by passing the manager in (see below).

Directly after `let isNewUser = result.additionalUserInfo?.isNewUser ?? false`, add:

```swift
                if isNewUser && !allowsAccountCreation {
                    await discardUnconsentedAccount(result.user, authorizationCode: appleIDCredential.authorizationCode, authManager: authManager)
                    currentNonce = nil
                    nonceTimestamp = nil
                    isLoading = false
                    accountCreationBlocked = true
                    return
                }
```

Inside the existing `if isNewUser, let authManager = authManager { do { try await authManager.createUserProfile(...) } catch {...} }` block, add after the `do/catch`:

```swift
                    await authManager.ensureLocalUser()
```

Directly before the final `await MainActor.run { isLoading = false ... Haptics.success() }`, add:

```swift
                // Returning user: the listener was suppressed above, so run its
                // restore path here (profile → local user → verification → isSignedIn).
                if !isNewUser {
                    await authManager?.finishSessionRestore(for: result.user)
                }
```

(`authManager` here is the local captured at the top of the flow.)

Add this private method to the class (next to `signInWithRetry`):

```swift
    /// Deletes a Firebase account Apple sign-in just created without consent
    /// (Sign In sheet). Revokes the Apple token first, like account deletion.
    /// Known residue: backfillInvitationsOnSignup may already have written
    /// invitation notifications under this UID (only if the email had
    /// pending invites) — harmless, unreachable. Revoking also makes Apple treat
    /// the next authorization as first-time, so the real sign-up still receives
    /// the user's full name.
    private func discardUnconsentedAccount(_ user: FirebaseAuth.User, authorizationCode: Data?, authManager: ComprehensiveAuthManager?) async {
        if let code = authorizationCode.flatMap({ String(data: $0, encoding: .utf8) }) {
            do {
                try await Auth.auth().revokeToken(withAuthorizationCode: code)
            } catch {
                ErrorHandlerService.shared.handle(error, context: "AppleSignIn.revokeUnconsented", showAlert: false)
            }
        }
        do {
            try await user.delete()
        } catch {
            ErrorHandlerService.shared.handle(error, context: "AppleSignIn.deleteUnconsented", showAlert: false)
            await authManager?.signOut()   // the parameter, not self.authManager
        }
    }
```

- [ ] **Step 4: ComprehensiveSignInView — pass the flag, add the card and the callback**

Under `var onSwitchToSignIn: (() -> Void)?`, add:
```swift
    var onSwitchToSignUp: (() -> Void)?
```

In `actionButtonsSection`, change the Apple button action to:
```swift
                SignInWithAppleButton(isSignUp: isSignUpMode) {
                    appleSignInManager.pendingRole = selectedRole
                    appleSignInManager.allowsAccountCreation = isSignUpMode && confirmedAge
                    appleSignInManager.signInWithApple()
                }
```

In `body`, change the section list to show the card after `authErrorSection`:
```swift
                            authErrorSection
                            if appleSignInManager.accountCreationBlocked { appleNoAccountSection }
```

Add the section:
```swift
    private var appleNoAccountSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "apple.logo").font(.title3).foregroundColor(Theme.textPrimary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("No account for this Apple ID yet").font(.headingSmall).foregroundColor(Theme.textPrimary)
                    Text("Create one first — it takes a minute, and you can keep using Sign in with Apple.")
                        .font(.bodySmall).foregroundColor(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button {
                Haptics.light()
                appleSignInManager.accountCreationBlocked = false
                dismiss()
                onSwitchToSignUp?()
            } label: {
                Text("Create an account").font(.labelLarge).foregroundColor(ppAccent)
            }
            .padding(.leading, 36)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12).fill(Theme.card)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.divider, lineWidth: 1))
        )
    }
```

- [ ] **Step 5: WelcomeFlow — wire both directions with labels**

Replace the `.sheet(item: $activeSheet)` switch body (`WelcomeFlow.swift:190-200`) with:

```swift
            switch sheet {
            case .signIn:
                ComprehensiveSignInView(isSignUpMode: false, onSwitchToSignUp: {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(400))
                        activeSheet = .signUp
                    }
                })
            case .signUp:
                ComprehensiveSignInView(isSignUpMode: true, onSwitchToSignIn: {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(400))
                        activeSheet = .signIn
                    }
                })
            }
```

- [ ] **Step 6: Build and verify manually**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

Device or simulator signed into an Apple ID:
1. **Returning Apple athlete** → Sign In sheet → Apple. **Expected:** Home. Repeat with a **returning Apple coach**. **Expected:** Coach Dashboard, not athlete UI.
2. **New Apple ID** (or one revoked under Settings → Apple ID → Sign in with Apple → PlayerPath → Stop Using) → Sign In sheet → Apple. **Expected:** "No account for this Apple ID yet" card, app still on Welcome. The Firebase console shows no new user.
3. Tap "Create an account" → sign-up sheet opens → pick Coach → check age → Apple. **Expected:** CoachOnboardingFlow.
4. Sign-up sheet, athlete, Apple, new ID. **Expected:** Add Athlete (unchanged behavior).
5. Relaunch while signed in (email account). **Expected:** Home with the correct role (listener path still works).

- [ ] **Step 7: Commit**

```bash
git add PlayerPath/ComprehensiveAuthManager+Auth.swift PlayerPath/AppleSignInManager.swift PlayerPath/Views/Auth/ComprehensiveSignInView.swift PlayerPath/Views/Auth/WelcomeFlow.swift
git commit -m "Auth: Apple on the Sign In sheet no longer creates unconsented accounts

A first-time Apple ID on Sign In skipped the age attestation and role
picker. The just-created account is now revoked + deleted and the sheet
offers the sign-up form. The Apple flow owns its session (listener
suppressed); returning users finish via the extracted finishSessionRestore.

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Show a new coach who's already waiting on them

**Files:**
- Modify: `PlayerPath/Views/Onboarding/CoachOnboardingFlow.swift` (`CoachReadyPage`, ~line 600)
- Modify: `PlayerPath/ComprehensiveAuthManager.swift:140-142` (delete property)
- Modify: `PlayerPath/ComprehensiveAuthManager+Auth.swift:287-298` (delete stash block)

**Interfaces:**
- Consumes: `CoachInvitationManager.shared.pendingInvitations: [CoachInvitation]` (`@Observable`). It's live because `AuthenticatedFlow.task` starts `CoachInvitationManager.shared.startListening(forEmail:)` for coaches while CoachOnboardingFlow is on screen. `CoachInvitation.athleteName: String`.

- [ ] **Step 1: Add the waiting card to CoachReadyPage**

Add a computed property to `CoachReadyPage`:

```swift
    private var waiting: [CoachInvitation] { CoachInvitationManager.shared.pendingInvitations }
```

In `pageContent`, directly after `Spacer().frame(height: 36)` and before `// Checklist`, insert:

```swift
                if !waiting.isEmpty {
                    HStack(spacing: 14) {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(ppAccent)
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(waiting.count == 1
                                 ? "\(waiting[0].athleteName) already invited you"
                                 : "\(waiting.count) athletes already invited you")
                                .font(.headingMedium)
                                .foregroundColor(Theme.textPrimary)
                            Text("Accept from your Dashboard to start coaching.")
                                .font(.bodyMedium)
                                .foregroundColor(Theme.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(ppAccent.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(ppAccent.opacity(0.35), lineWidth: 1))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                    .accessibilityElement(children: .combine)
                }
```

- [ ] **Step 2: Delete the dead stash**

In `ComprehensiveAuthManager.swift`, delete the property and its doc comment:
```swift
    /// Pending shared-folder invitations discovered during coach signup.
    /// Surfaced to the coach onboarding flow after email verification.
    @Published var pendingCoachInvitations: [CoachInvitation] = []
```

In `signUpAsCoach`, delete the whole `// Stash any pending invitations…` comment plus its `do { … } catch { … }` block.

Run `grep -rn "pendingCoachInvitations" PlayerPath --include='*.swift'`. Expected: no output. Keep `SharedFolderManager.checkPendingInvitations(forEmail:)` because `DeepLinkHandler.swift:228` still uses it.

- [ ] **Step 3: Build and verify**

Run the build command. Expected: `** BUILD SUCCEEDED **`.
Manual: from an athlete account, invite `coach+tagN@…`. Then sign up as that coach, verify, and page to "You're All Set". **Expected:** "<Athlete> already invited you" card. A coach with no invites sees the page unchanged.

- [ ] **Step 4: Commit**

```bash
git add PlayerPath/Views/Onboarding/CoachOnboardingFlow.swift PlayerPath/ComprehensiveAuthManager.swift PlayerPath/ComprehensiveAuthManager+Auth.swift
git commit -m "Coach onboarding: show athletes already waiting; drop dead signup stash

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Backfill nil `autoUploadMode` so Settings stops showing "Off"

**Files:**
- Modify: `PlayerPath/UserPreferences.swift:82-101`
- Modify: `PlayerPath/UserPreferencesView.swift:81`

**Interfaces:** none new. `UserPreferences.shared(in:)` already runs at launch (`MainAppView.swift:101`).

- [ ] **Step 1: Add the backfill and call it on both return paths**

Replace `shared(in:)` with:

```swift
    static func shared(in context: ModelContext) -> UserPreferences {
        // Fetch all and enforce single-instance semantics by keeping the newest
        let descriptor = FetchDescriptor<UserPreferences>()
        if let all = try? context.fetch(descriptor), let first = all.first {
            if all.count > 1 {
                // Keep the most recently modified, delete the rest
                let sorted = all.sorted { $0.lastModified > $1.lastModified }
                guard let keep = sorted.first else { return first }
                for extra in sorted.dropFirst() {
                    context.delete(extra)
                }
                do { try context.save() } catch { prefsLog.error("Failed to save after deduplicating preferences: \(error.localizedDescription)") }
                backfillAutoUploadMode(keep, in: context)
                return keep
            }
            backfillAutoUploadMode(first, in: context)
            return first
        }
        let prefs = UserPreferences()
        context.insert(prefs)
        return prefs
    }

    /// Rows from before 2026-01-29 (4d3a4cf7 replaced the stored Bool with this
    /// optional) can be nil. `autoUploadToCloud` already reads nil as ON and
    /// `uploadOnCellular` reads it as Wi-Fi-only, so `.wifiOnly` IS the live
    /// behavior — this only makes Settings stop claiming "Off".
    private static func backfillAutoUploadMode(_ prefs: UserPreferences, in context: ModelContext) {
        guard prefs.autoUploadMode == nil else { return }
        prefs.autoUploadMode = .wifiOnly
        do { try context.save() } catch { prefsLog.error("Failed to save autoUploadMode backfill: \(error.localizedDescription)") }
    }
```

- [ ] **Step 2: Make the picker fallback agree**

In `UserPreferencesView.swift:81`, change `?? .off` to `?? .wifiOnly`.

- [ ] **Step 3: Build and verify**

Run the build command. Expected: `** BUILD SUCCEEDED **`. You can't easily create a nil row now, so just confirm that Settings → Auto-Upload still shows the previously chosen value on an existing install.

- [ ] **Step 4: Commit**

```bash
git add PlayerPath/UserPreferences.swift PlayerPath/UserPreferencesView.swift
git commit -m "Prefs: backfill nil autoUploadMode to wifiOnly (Settings showed Off while uploading)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Rename an athlete (option A: local and synced row, accept coach-side drift)

**Files:**
- Create: `PlayerPath/Views/Athletes/AthleteNameSection.swift`
- Modify: `PlayerPath/Views/Athletes/EditAthleteView.swift:35-36` (insert the section first in the Form), and the header comment at `:5-8`

**Interfaces:**
- Consumes: `Athlete.name`, `Athlete.needsSync`, `Athlete.personGroupID`, `Athlete.id`, `Athlete.user?.athletes`; `Validation.isValidPersonName(_:min:max:)`; EditAthleteView's existing `onDisappear` sync (`SyncCoordinator.shared.syncAthletes(for:)` when `athlete.needsSync`). `name` is already a synced field (`FirestoreManager+EntitySync.swift:49`), and remote merge applies it (`SyncCoordinator+Athletes.swift:235`).
- Produces: `struct AthleteNameSection: View { let athlete: Athlete }`.

- [ ] **Step 1: Create the section**

`PlayerPath/Views/Athletes/AthleteNameSection.swift`:

```swift
//
//  AthleteNameSection.swift
//  PlayerPath
//
//  Rename for EditAthleteView. Dual-sport people are several rows sharing a
//  personGroupID. The split tool copies the name, but AddSportProfileSheet lets
//  the user type a different one ("Zain Golf") — so a rename carries over only
//  to linked rows that still share THIS row's current name.
//  Coach-side denormalized copies (folder/invitation/session names) are NOT
//  rewritten — accepted drift, see memory project_edit_athlete_name_todo.
//

import SwiftUI
import SwiftData

struct AthleteNameSection: View {
    let athlete: Athlete

    @Environment(\.modelContext) private var modelContext
    @Environment(\.ppAccent) private var ppAccent
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    private var linkedProfiles: [Athlete] {
        let groupID = athlete.personGroupID ?? athlete.id
        return (athlete.user?.athletes ?? []).filter { ($0.personGroupID ?? $0.id) == groupID }
    }

    /// Linked rows that follow a rename: same person AND same current name.
    private var renameTargets: [Athlete] {
        linkedProfiles.filter { $0.name == athlete.name }
    }

    private var trimmed: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isChanged: Bool { trimmed != athlete.name }

    private var validationMessage: String? {
        guard isChanged else { return nil }
        guard Validation.isValidPersonName(trimmed, min: 2, max: 50) else {
            return "Use 2–50 letters, spaces, periods, hyphens, or apostrophes."
        }
        let linkedIDs = Set(linkedProfiles.map(\.id))
        let taken = (athlete.user?.athletes ?? []).contains {
            !linkedIDs.contains($0.id)
                && $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == trimmed.lowercased()
        }
        return taken ? "Another athlete already has this name." : nil
    }

    private var canSave: Bool { isChanged && validationMessage == nil }

    var body: some View {
        Section {
            TextField("Athlete name", text: $draft)
                .textContentType(.name)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit(save)
            if canSave {
                Button("Save Name", action: save)
                    .foregroundColor(ppAccent)
            }
        } header: {
            Text("Name")
        } footer: {
            if let validationMessage {
                Text(validationMessage).foregroundColor(Theme.warning)
            } else {
                Text(renameTargets.count > 1
                     ? "Also renames this athlete's other sport profiles. Coaches may see the old name on folders you've already shared."
                     : "Coaches may see the old name on folders you've already shared.")
            }
        }
        .onAppear { draft = athlete.name }
    }

    private func save() {
        guard canSave else { return }
        let newName = trimmed
        for profile in renameTargets {
            profile.name = newName
            profile.needsSync = true
        }
        ErrorHandlerService.shared.saveContext(modelContext, caller: "AthleteNameSection.save")
        draft = newName
        isFocused = false
        Haptics.success()
    }
}
```

- [ ] **Step 2: Insert it into EditAthleteView**

In `EditAthleteView.swift`, make the first child of `Form {`:

```swift
            AthleteNameSection(athlete: athlete)

```

Update the header comment (`:5-8`) to start with: `Edits a single athlete's settings — name, sports, recruiting, stat tracking.`

- [ ] **Step 3: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Verify manually**

1. Single athlete "Jonh" → Athlete Settings → change to "John" → Save. **Expected:** the navigation title and athlete switcher show "John"; after relaunch still "John"; a second device signed into the same account shows "John" after sync.
2. Dual-sport person (Baseball + Golf rows, same name) → rename from the golf profile. **Expected:** both rows renamed; no "already has this name" error while typing the same name back.
2b. Dual-sport person whose golf row was named differently at creation ("Zain" / "Zain Golf") → rename "Zain" to "Zane". **Expected:** only the baseball row changes; "Zain Golf" is untouched.
3. Two different athletes "Ava" and "Ben" → rename Ben to "ava". **Expected:** warning footer, no Save button.
4. Type "J" → warning footer; clear back to the original → no Save button.

- [ ] **Step 5: Commit**

```bash
git add PlayerPath/Views/Athletes/AthleteNameSection.swift PlayerPath/Views/Athletes/EditAthleteView.swift
git commit -m "Athletes: rename from Athlete Settings (all linked sport profiles)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Theme the auth screens

**Files:**
- Modify: `PlayerPath/Theme/Theme.swift` (Status section, after `warning`)
- Modify: `PlayerPath/Views/Shared/ModernTextField.swift` (validation colors, icon grays, strength, requirements). Only the auth screens and `OnboardingSeasonCreationView` use it.
- Modify: `PlayerPath/Views/Auth/ComprehensiveSignInView.swift`, `RoleSelectionButton.swift`, `EmailVerificationView.swift`, `ResetPasswordSheet.swift`, `ForceUpdateView.swift`, `WhatsNewView.swift`
- Modify: `PlayerPath/MainAppView.swift` (verification toolbar X)

**Interfaces:**
- Produces: `Theme.success: Color`. Task 7 uses `Theme.warning`/`Theme.success` in the error card and verification hint.

Line numbers below are from before Task 2 inserted code into `ComprehensiveSignInView.swift`. Match by content, not by number.

Mapping rule for every file in this task:

| From | To |
|---|---|
| `Color(.systemGroupedBackground)` / no background | `Theme.surface` |
| `Color(.systemBackground)`, `Color(.secondarySystemBackground)` (cards) | `Theme.card` |
| `.foregroundColor(.secondary)` / `.foregroundStyle(.secondary)` | `Theme.textSecondary` |
| `.foregroundColor(.primary)`, un-colored titles | `Theme.textPrimary` |
| `Color(.systemGray4)` borders | `Theme.pillBorder` |
| `Color(.systemGray4)` disabled button fill | `Theme.textTertiary` |
| `Color(.systemGray2/3)`, `.gray` (inactive icons) | `Theme.textTertiary` |
| `Color(.systemGray5)` (empty strength bar) | `Theme.divider` |
| `.secondary.opacity(0.3)` divider lines | `Theme.divider` |
| `.red` / `Color.red` (recoverable errors, invalid field) | `Theme.warning` |
| `.green` (valid / met / sent) | `Theme.success` |
| `.orange` ("Medium" strength) | `Theme.textSecondary` |

Leave `.foregroundColor(.white)` on accent buttons and SF Symbol `.font(.title3/.body/.caption)` icon sizing as they are.

- [ ] **Step 1: Add the token**

In `Theme.swift`, after `static let warning = …`:

```swift
    /// Confirmation — valid field, met requirement, "email sent". Same forest as
    /// `chipGreenText` so "good" reads identically everywhere.
    static let success = chipGreenText
```

- [ ] **Step 2: ModernTextField.swift**

`FieldValidationState.borderColor`: `.idle: Theme.pillBorder`, `.valid: Theme.success`, `.invalid: Theme.warning`.
`FieldValidationState.iconColor`: `.valid: Theme.success`, `.invalid: Theme.warning`.
Lines ~79 and ~119: `Color(.systemGray2)` → `Theme.textTertiary`.
`PasswordStrengthIndicator.strength`: `(1, "Weak", Theme.warning)`, `(2, "Medium", Theme.textSecondary)`, `(3, "Strong", Theme.success)`, `(4, "Very Strong", Theme.success)`; empty bar `Color(.systemGray5)` → `Theme.divider`.
`PasswordRequirementsList`: icon `isMet ? Theme.success : Theme.textTertiary`; text `isMet ? Theme.textPrimary : Theme.textSecondary`.

- [ ] **Step 3: ComprehensiveSignInView.swift** (except `authErrorSection`, which Task 7 rewrites)

- Line 103: `.background(Color(.systemGroupedBackground))` → `.background(Theme.surface)`. (Line 62, on `EmailVerificationView()`, is deleted in Step 5 instead.)
- Lines 73 and 113: `.foregroundStyle(.secondary)` → `.foregroundStyle(Theme.textSecondary)`.
- `headerSection`: add `.foregroundColor(Theme.textPrimary)` to the title `Text`; the subtitle `.secondary` → `Theme.textSecondary`.
- Lines 167, 194, 233, 242, 245, 283, 309: `.secondary` → `Theme.textSecondary`.
- Line 231: `.gray` → `Theme.textTertiary`.
- Line 270: `[Color(.systemGray4), Color(.systemGray4)]` → `[Theme.textTertiary, Theme.textTertiary]`.
- Line 282/284: `.foregroundColor(.secondary.opacity(0.3))` → `.foregroundColor(Theme.divider)`.

- [ ] **Step 4: RoleSelectionButton.swift**

- Line 55: `.primary` → `Theme.textPrimary`. Line 59: `.secondary` → `Theme.textSecondary`.
- Line 75: `[Color(.systemBackground), Color(.systemBackground)]` → `[Theme.card, Theme.card]`.
- Line 90: `Color(.systemGray4)` → `Theme.pillBorder`.

- [ ] **Step 5: EmailVerificationView.swift**

- Title `Text("Verify Your Email")`: add `.foregroundColor(Theme.textPrimary)`.
- `.secondary` → `Theme.textSecondary` (lines 45, 131); `.primary` → `Theme.textPrimary` (line 153).
- Status colors (lines 63, 66, 72): `isError ? Theme.warning : Theme.success` (and `.opacity(0.1)` on the same).
- After `.padding(.horizontal, 20)` on the root VStack, add `.frame(maxWidth: .infinity, maxHeight: .infinity)` and `.background(Theme.surface)`.
- In `ComprehensiveSignInView.swift:62`, delete the `.background(Color(.systemGroupedBackground))` line on `EmailVerificationView()`. The view now paints its own background.
- `MainAppView.swift` verification toolbar X: `.foregroundStyle(.secondary)` → `.foregroundStyle(Theme.textSecondary)`.

- [ ] **Step 6: ResetPasswordSheet.swift**

- Title `Text(showingSuccess ? …)`: add `.foregroundColor(Theme.textPrimary)`.
- Lines 67, 77, 80, 183, 203: `.secondary` → `Theme.textSecondary`.
- Line 85: `.background(Color(.secondarySystemBackground))` → `.background(Theme.card)` plus `.overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.divider, lineWidth: 1))` after `.cornerRadius(12)`.
- Lines 130, 133: `.red` → `Theme.warning`.
- Line 159: `[Color(.systemGray4), Color(.systemGray4)]` → `[Theme.textTertiary, Theme.textTertiary]`.
- Line 180 (text, not the icon): `.font(.caption)` → `.font(.bodySmall)`, matching the same sentence at line 79.

- [ ] **Step 7: ForceUpdateView.swift and WhatsNewView.swift**

Both: add `.foregroundColor(Theme.textPrimary)` to the `displayMedium` title. Change `.secondary` → `Theme.textSecondary`, and in WhatsNew `.primary` → `Theme.textPrimary`. On the root VStack add:
```swift
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface)
```

- [ ] **Step 8: Build and sweep**

Run the build command. Expected: `** BUILD SUCCEEDED **`.
Then:
```bash
grep -nE "Color\(\.system|systemGroupedBackground|secondarySystemBackground|foregroundColor\(\.(secondary|primary|gray|red|green)\)|foregroundStyle\(\.secondary\)|\.red\b|\.green\b|\.orange\b" PlayerPath/Views/Auth/*.swift PlayerPath/Views/Shared/ModernTextField.swift
```
Expected: hits only inside `authErrorSection` of `ComprehensiveSignInView.swift` (Task 7 removes those).

Manual: walk Welcome → Get Started → sign-up form (type a weak password, then a strong one) → verification screen → X → Sign In → Forgot Password. **Expected:** cream background throughout, no white or gray sheet flash, green/amber states in the forest/amber tones.

- [ ] **Step 9: Commit**

```bash
git add PlayerPath/Theme/Theme.swift PlayerPath/Views/Shared/ModernTextField.swift PlayerPath/Views/Auth PlayerPath/MainAppView.swift
git commit -m "Auth screens: cream surface + Theme text/status colors (finish the palette pass)

Adds Theme.success (alias of chipGreenText). Invalid/recoverable-error
states use Theme.warning per its contract.

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Sign-in UX improvements

**Files:**
- Modify: `PlayerPath/Views/Auth/ComprehensiveSignInView.swift` (`authErrorSection`, password rules condition)
- Modify: `PlayerPath/Views/Auth/EmailVerificationView.swift` (scene-phase polling, send-failed hint)

**Interfaces:**
- Consumes: `Theme.success`/`Theme.warning` (Task 6), `onSwitchToSignIn` (existing), `AuthConstants.ErrorMessages.emailAlreadyInUse`, `authManager.isSignInLocked`, `authManager.verificationEmailSendFailed`.

- [ ] **Step 1: Error card with a specific headline and a recovery action**

First, give the invalid-credential message a constant so the view can match it. In `AuthConstants.swift`, inside `enum ErrorMessages` next to `wrongPassword`, add:

```swift
        static let invalidCredential = "Invalid email or password. Please try again."
```

In `ComprehensiveAuthManager.swift` `friendlyErrorMessage(from:)`, change the `invalidCredential` case to `return AuthConstants.ErrorMessages.invalidCredential`.

Then replace `authErrorSection` in `ComprehensiveSignInView.swift` with:

```swift
    @ViewBuilder
    private var authErrorSection: some View {
        // Show errors from either auth manager or Apple Sign In manager
        let displayError = authManager.errorMessage ?? appleSignInManager.errorMessage
        if let errorMessage = displayError {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.title3).foregroundColor(Theme.warning)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(isSignUpMode ? "Couldn't create your account" : "Couldn't sign you in")
                            .font(.headingSmall).foregroundColor(Theme.textPrimary)
                        Text(errorMessage).font(.bodySmall).foregroundColor(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button {
                        Haptics.light()
                        authManager.clearError()
                        appleSignInManager.errorMessage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill").font(.title3).foregroundColor(Theme.textTertiary)
                    }
                    .accessibilityLabel("Dismiss error")
                }
                if let recovery = errorRecovery {
                    Button {
                        Haptics.light()
                        recovery.perform()
                    } label: {
                        Text(recovery.title).font(.labelLarge).foregroundColor(ppAccent)
                    }
                    .padding(.leading, 36)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12).fill(Theme.warning.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.warning.opacity(0.25), lineWidth: 1))
            )
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    /// One next step for the error on screen. Email enumeration protection makes
    /// "wrong password" and "no such user" indistinguishable (invalidCredential),
    /// so all three credential messages offer a reset. Network, lockout and
    /// generic errors get no action — a reset link would be misleading there.
    private var errorRecovery: (title: String, perform: () -> Void)? {
        let message = authManager.errorMessage
        if isSignUpMode, message == AuthConstants.ErrorMessages.emailAlreadyInUse {
            return ("Sign in instead", {
                authManager.clearError()
                dismiss()
                onSwitchToSignIn?()
            })
        }
        let credentialMessages = [
            AuthConstants.ErrorMessages.invalidCredential,
            AuthConstants.ErrorMessages.wrongPassword,
            AuthConstants.ErrorMessages.userNotFound,
        ]
        if !isSignUpMode, let message, credentialMessages.contains(message) {
            return ("Reset your password", { showingResetPasswordSheet = true })
        }
        return nil
    }
```

- [ ] **Step 2: Show password rules as soon as the field is focused**

In `formFieldsSection`, replace the `if isSignUpMode && !password.isEmpty { … }` block and the `.animation(…, value: password.isEmpty)` line with:

```swift
            if isSignUpMode && (passwordFocused || !password.isEmpty) {
                VStack(alignment: .leading, spacing: 8) {
                    if !password.isEmpty {
                        PasswordStrengthIndicator(password: password)
                    }
                    if !isValidPassword(password) {
                        PasswordRequirementsList(password: password).padding(.top, 4)
                    }
                }
                .padding(.horizontal, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: password.isEmpty)
        .animation(.easeInOut(duration: 0.2), value: passwordFocused)
```

(The closing `}` shown here is the existing one for the `VStack(spacing: 16)`. Don't add an extra brace.)

- [ ] **Step 3: Verification polling only while foregrounded, plus a check on return**

In `EmailVerificationView.swift`, add `@Environment(\.scenePhase) private var scenePhase` under the `ppAccent` environment line.

Make `startPolling()` idempotent by adding `stopPolling()` as its first line.

After `.onDisappear { stopPolling() }`, add:

```swift
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                // Coming back from Mail/Safari is the moment they verified —
                // check now instead of waiting up to 5s for the next tick.
                // Check FIRST, then resume polling, so a timer tick can't run a
                // second checkEmailVerification concurrently (both would flip
                // isHandlingVerification and, on success, load the profile twice).
                Task {
                    let verified = await authManager.checkEmailVerification()
                    if !verified { startPolling() }
                }
            } else {
                stopPolling()
            }
        }
```

- [ ] **Step 4: Surface a failed verification send**

In `EmailVerificationView.body`, directly before `// Status message`, add:

```swift
            if authManager.verificationEmailSendFailed && statusMessage == nil {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(Theme.warning)
                    Text("We couldn't send the email. Tap Resend below.")
                        .font(.bodySmall).foregroundColor(Theme.warning)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.warning.opacity(0.1)))
            }
```

(`resendVerificationEmail()` already resets `verificationEmailSendFailed = false` on success.)

- [ ] **Step 5: Build and verify**

Run the build command. Expected: `** BUILD SUCCEEDED **`. Rerun the Task 6 Step 8 grep. Expected: no output.

Manual:
1. Sign In with a wrong password. **Expected:** "Couldn't sign you in" + "Reset your password" → opens the reset sheet. With networking off (Network Link Conditioner / airplane mode) → error card with NO reset action.
2. Sign up with an existing email. **Expected:** "Couldn't create your account" + "Sign in instead" → Sign In sheet opens.
3. Sign-up form → tap Password. **Expected:** requirement list appears before typing.
4. Verification screen → background the app, verify in a browser, return. **Expected:** it advances within ~1s.

- [ ] **Step 6: Commit**

```bash
git add PlayerPath/AuthConstants.swift PlayerPath/ComprehensiveAuthManager.swift PlayerPath/Views/Auth/ComprehensiveSignInView.swift PlayerPath/Views/Auth/EmailVerificationView.swift
git commit -m "Sign-in: actionable error card, password rules on focus, foreground-only verify polling

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

## Known limits (accepted, not bugs in this plan)

- **Published recruiting page keeps the old name after a rename.** `RecruitingProfileService` bakes `athlete.name` in at publish time (`:211`), and nothing flags a republish. The athlete must republish. A follow-up could show "name changed — republish" in the editor.
- **One pending marker per device.** If parent A signs up (onboarding pending), then parent B signs up on the same phone, B's marker replaces A's, and A's next sign-in skips onboarding (today's behavior). This is rare enough not to warrant a UID set.
- **Invitation notification residue.** A discarded Apple account (Task 2) may leave `notifications/{uid}/items` docs from `backfillInvitationsOnSignup`. They're unreachable.

## After all tasks

- Run `/review` on the branch. Tasks 1–2 touch the auth state machine, which is exactly the playerpath-reviewer's footgun territory.
- Update memory: `project_onboarding_review_2026_09_05.md` (mark the fixed items), `project_edit_athlete_name_todo.md` (option A shipped), and delete the "autoUploadMode nil gap" paragraph.
