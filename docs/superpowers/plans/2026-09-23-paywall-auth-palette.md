# Paywalls + Sign-in: Retire the Legacy Palette — Implementation Plan (Batch 2 of 5)

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (or subagent-driven-development). Steps use `- [ ]`.

**Goal:** Remove every legacy brand color (`.brandNavy`, the blue/green/purple/yellow-orange `LinearGradient` tokens) from the two paywalls and the five sign-in/update screens. Then delete the palette tokens that no longer have any users.

**Architecture:** This follows the precedent already set by `ResetPasswordSheet.swift` and `WelcomeFlow.swift`, the two auth screens that were migrated. Each view reads `@Environment(\.ppAccent) private var ppAccent` and uses it wherever navy was, keeping the same gradient shapes (`[accent, accent.opacity(0.85)]` for buttons, `[accent, accent.opacity(0.7)]` for icons). The coach tier colors are a model property, where the environment can't be read, so they use the static `Theme.accent`.

**Tech stack:** SwiftUI. No new APIs, no OS gating.

**Spec:** the 2026-09-23 audit, batch #2 ("paywall and sign-in navy/gradients; delete the 0-use tokens").

## Global Constraints

- Colors: `@Environment(\.ppAccent)` in views and `Theme.accent` in models. Never add a new `.brandNavy`, `.brandGold`, `LinearGradient.primaryButton`, `.premiumButton`, `.coachButton` or `.premiumAccent`.
- **The app is light-only** (`MainAppView.swift:81` `.preferredColorScheme(.light)`), so a static `Theme` color is always correct.
- **Out of scope** (do not touch):
  - The system surfaces (`systemGroupedBackground`, `secondarySystemBackground`, `systemGray4/5`, `.separator`). They aren't the legacy palette, and switching to cream is a separate call. It's listed in the handoff.
  - The semantic greens (paywall `Save N%`, the athlete paywall's check icons, success messages) and the reds (errors).
  - `.brandGold` anywhere. It has no users in these files; its 34 sites belong to Batch 4 and the Highlights screens.
  - Fonts (`.bodySmall`, `.headingMedium`…).
- No Swift test target. "Test" = clean build + grep assertions + an Xcode Preview check where one exists.
- **Stage only the files each task names.** The working tree has unrelated edits (`PlayResultAccumulator.swift`, `GameDetailView.swift`). Commit directly to `main`, one commit per task. Never touch version/build numbers.

Build (every task):
```bash
cd /Users/Trey/Desktop/PlayerPath && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PlayerPath.xcodeproj \
  -scheme PlayerPath -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | head -20
```

## Decision for Trey (baked in as recommended; flip before execution if you disagree)

**The athlete paywall follows the sport accent.** It's presented from ~18 places. Reading `ppAccent` like every other athlete view makes it golf-green when opened from golf screens (Hole/Club detail, Strokes Gained) and terracotta otherwise.
- The three presenters outside the tab roots (`UserMainFlow`, `RoleBasedViewModifiers`, `ImportStorageFullSheet`) show terracotta even for a golf athlete.
- *Alternative:* pin the paywall to terracotta. The subscription is account-level and covers both sports. That would mean using `Theme.accent` directly plus `.ppAccent(forGolf: false)` on its root.
- Coach paywall and auth screens: always terracotta, because nothing injects a sport there.

## Verified facts (repo @ 707fe6d)

| Fact | Source |
|---|---|
| Migrated pattern: `@Environment(\.ppAccent)`, icon `[ppAccent, ppAccent.opacity(0.8)]`, button `[ppAccent, ppAccent.opacity(0.85)]` + `shadow(ppAccent.opacity(0.3), r8, y4)` | `Views/Auth/ResetPasswordSheet.swift:13,36-54,142-165` |
| Every `brandNavy` in the 5 auth files is a `Color` expression (a fill, gradient stop, foreground or shadow), so a mechanical `Color.brandNavy`/`.brandNavy` → `ppAccent` swap is type-correct at every site | read all 5 files in full |
| Each of the 7 target files declares exactly one top-level View struct holding every site (`ImprovedPaywallView` also has `private struct RoundedCorner` with no colors) | grep `^struct` |
| `CoachSubscriptionTier.color` (`SubscriptionModels.swift:140-147`: free `.secondary`, instructor `.brandNavy`, proInstructor `.brandGold`, academy `.purple`) is used **only** in `CoachPaywallView` | grep `[Tt]ier\)?\.color` |
| After Tasks 1–3, these tokens have **zero** users: `Color.brandPrimary`, `.brandSecondary`, `.premium`, `.premiumBackground`, `LinearGradient.brandNavy`, `.brandGold`, `.primaryButton`, `.coachButton`, `.premiumButton`, `.premiumAccent` (the gradient ones had 4 users total, all in the paywalls) | grep |
| `Color.brandNavy`/`.brandGold` themselves stay (Batch 4 + the rest of the app). `glassBorder/Shine/Dark` stay (the Batch 1 fallback) | grep |
| Xcode Previews exist for `ImprovedPaywallView` (2), `CoachPaywallView` and `RoleSelectionButton`, a quick visual check without signing out | grep `#Preview` |

## Review Focus

1. **Contrast of white text on the accent:** white on terracotta `#C8693E` is about 3.6:1. That passes for the 15–17pt semibold labels here (large-text AA), but the small `Save N%` (11pt bold) on the selected billing pill is borderline. Check it in the preview. It was white-on-navy before (≈12:1).
2. **Disabled/grey states unchanged:** the sign-in CTA stays `systemGray4` when the form is incomplete, and "Keep Free Plan" / "Loading plans" stay grey.
3. **Coach paywall:** every paid tier header now highlights in one accent. Previously navy/gold/purple. The Academy header text (unselected) is accent-colored, so it still reads as the special column.
4. **Golf entry points:** the paywall opened from a golf screen is green end to end (crown, selected column, CTA, links), with no terracotta mixed in.
5. **Token deletion:** if any deleted token still had a hidden user (e.g. inferred-type `.premium`), the build fails. That's the test. Restore only that token and ledger it.

---

### Task 1: Sign-in, verification, update and What's New screens

**Files:**
- Modify: `PlayerPath/Views/Auth/ComprehensiveSignInView.swift` (10 sites)
- Modify: `PlayerPath/Views/Auth/EmailVerificationView.swift` (7 sites)
- Modify: `PlayerPath/Views/Auth/RoleSelectionButton.swift` (4 sites)
- Modify: `PlayerPath/Views/Auth/ForceUpdateView.swift` (4 sites)
- Modify: `PlayerPath/Views/Auth/WhatsNewView.swift` (4 sites)

- [ ] **Step 1: Add the accent environment value** to each struct, one line, placed as follows:
  - `ComprehensiveSignInView.swift`: after `@Environment(\.dismiss) private var dismiss` (line 13)
  - `EmailVerificationView.swift`: after `@EnvironmentObject private var authManager: ComprehensiveAuthManager` (line 11), followed by a blank line
  - `RoleSelectionButton.swift`: after `let action: () -> Void` (line 16), preceded by a blank line
  - `ForceUpdateView.swift`: after `let updateURL: String?` (line 11)
  - `WhatsNewView.swift`: after `let onDismiss: () -> Void` (line 12)

```swift
    @Environment(\.ppAccent) private var ppAccent
```

- [ ] **Step 2: Swap navy for the accent** in those 5 files (every occurrence is a `Color` expression, see Verified facts):

```bash
cd /Users/Trey/Desktop/PlayerPath/PlayerPath/Views/Auth
sed -i '' -e 's/Color\.brandNavy/ppAccent/g' -e 's/\.brandNavy/ppAccent/g' \
  ComprehensiveSignInView.swift EmailVerificationView.swift RoleSelectionButton.swift ForceUpdateView.swift WhatsNewView.swift
```

Resulting examples, which match `ResetPasswordSheet`:
- `LinearGradient(colors: [ppAccent, ppAccent.opacity(0.85)], …)`
- `.foregroundColor(ppAccent)`
- `.shadow(color: ppAccent.opacity(0.3), …)`
- `confirmedAge ? ppAccent : .gray`

- [ ] **Step 3: Assert the auth folder is clean.**
Run: `grep -rn "brandNavy\|brandGold" /Users/Trey/Desktop/PlayerPath/PlayerPath/Views/Auth/`
Expected: no output.
Run: `grep -c "ppAccent" /Users/Trey/Desktop/PlayerPath/PlayerPath/Views/Auth/{ComprehensiveSignInView,EmailVerificationView,RoleSelectionButton,ForceUpdateView,WhatsNewView}.swift`
Expected: every count ≥ 2.

- [ ] **Step 4: Build.** Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
cd /Users/Trey/Desktop/PlayerPath
git add PlayerPath/Views/Auth/ComprehensiveSignInView.swift PlayerPath/Views/Auth/EmailVerificationView.swift PlayerPath/Views/Auth/RoleSelectionButton.swift PlayerPath/Views/Auth/ForceUpdateView.swift PlayerPath/Views/Auth/WhatsNewView.swift
git commit -m "Auth screens: terracotta accent replaces legacy navy (sign-in, verify, role picker, force update, What's New)"
```

---

### Task 2: Athlete paywall

**Files:**
- Modify: `PlayerPath/ImprovedPaywallView.swift` (lines 23, 140-142, 156, 159, 212, 258, 266, 320, 354, 356, 358, 444, 447, 501, 503)

- [ ] **Step 1: Add the environment value** after `@Environment(\.modelContext) private var modelContext` (line 23):
```swift
    @Environment(\.ppAccent) private var ppAccent
```

- [ ] **Step 2: Crown icon.** Replace
```swift
                .foregroundStyle(
                    LinearGradient.premiumAccent
                )
```
with
```swift
                .foregroundStyle(
                    LinearGradient(colors: [ppAccent, ppAccent.opacity(0.7)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
```

- [ ] **Step 3: Purchase CTA.** Replace `.background(LinearGradient.primaryButton)` (line 444) with
```swift
                    .background(LinearGradient(colors: [ppAccent, ppAccent.opacity(0.85)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing))
```

- [ ] **Step 4: Remaining navy (11 sites).** These are the required-tier chip (156/159), the billing pill (212), the Pro athlete/storage numbers (258/266), the selected tier header (320), the selected column tint (354/356/358), the CTA shadow (447) and the Terms/Privacy links (501/503):
```bash
sed -i '' -e 's/Color\.brandNavy/ppAccent/g' -e 's/\.brandNavy/ppAccent/g' /Users/Trey/Desktop/PlayerPath/PlayerPath/ImprovedPaywallView.swift
```

- [ ] **Step 5: Assert.** Run `grep -nE "brandNavy|brandGold|LinearGradient\.(primaryButton|premiumAccent|premiumButton|coachButton)" /Users/Trey/Desktop/PlayerPath/PlayerPath/ImprovedPaywallView.swift`. Expected: no output.

- [ ] **Step 6: Build.** Expected: `BUILD SUCCEEDED`.

- [ ] **Step 7: Preview check (Trey, optional):** open `ImprovedPaywallView.swift` in Xcode → Canvas. Expected: terracotta crown, selected Plus column, CTA and links, and a readable white `Save N%` on the selected Annual pill (Review Focus 1).

- [ ] **Step 8: Commit**

```bash
cd /Users/Trey/Desktop/PlayerPath
git add PlayerPath/ImprovedPaywallView.swift
git commit -m "Athlete paywall: sport accent replaces legacy navy + blue/yellow gradients"
```

---

### Task 3: Coach paywall + coach tier colors

**Files:**
- Modify: `PlayerPath/CoachPaywallView.swift` (lines 12, 113, 155, 314, 358, 415, 470, 472)
- Modify: `PlayerPath/SubscriptionModels.swift:138-147`

- [ ] **Step 1: One accent for every paid coach tier.** In `SubscriptionModels.swift`, replace the `color` doc comment and body:
```swift
    /// Canonical display color for this tier. Free = neutral; every paid tier =
    /// the brand accent (Theme's ONE-accent rule — the old navy/gold/purple split
    /// is retired). Coach UI is always the base (terracotta) accent.
    var color: Color {
        switch self {
        case .free:                                return .secondary
        case .instructor, .proInstructor, .academy: return Theme.accent
        }
    }
```

- [ ] **Step 2: Add the environment value** in `CoachPaywallView.swift` after `@Environment(\.dismiss) private var dismiss` (line 12):
```swift
    @Environment(\.ppAccent) private var ppAccent
```

- [ ] **Step 3: The two CTA gradients.** Replace `.background(LinearGradient.premiumButton)` (Academy, line 358) **and** `.background(LinearGradient.coachButton)` (purchase, line 415) with
```swift
                        .background(LinearGradient(colors: [ppAccent, ppAccent.opacity(0.85)],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing))
```
(Line 415 sits at 20-space indentation, so match it.)

- [ ] **Step 4: Remaining navy (5 sites):** whistle icon gradient (113), billing pill (155), check icon (314), Terms/Privacy links (470/472):
```bash
sed -i '' -e 's/Color\.brandNavy/ppAccent/g' -e 's/\.brandNavy/ppAccent/g' /Users/Trey/Desktop/PlayerPath/PlayerPath/CoachPaywallView.swift
```

- [ ] **Step 5: Assert.** Run `grep -nE "brandNavy|brandGold|\.purple|LinearGradient\.(primaryButton|premiumAccent|premiumButton|coachButton)" /Users/Trey/Desktop/PlayerPath/PlayerPath/CoachPaywallView.swift /Users/Trey/Desktop/PlayerPath/PlayerPath/SubscriptionModels.swift`. Expected: no output.

- [ ] **Step 6: Build.** Expected: `BUILD SUCCEEDED`.

- [ ] **Step 7: Preview check (Trey, optional):** `CoachPaywallView` canvas. Expected: terracotta whistle, selected column header, checks and CTA; Academy CTA terracotta (Review Focus 3).

- [ ] **Step 8: Commit**

```bash
cd /Users/Trey/Desktop/PlayerPath
git add PlayerPath/CoachPaywallView.swift PlayerPath/SubscriptionModels.swift
git commit -m "Coach paywall: one terracotta accent replaces navy/gold/purple tiers and green/purple gradients"
```

---

### Task 4: Delete the dead palette tokens

**Files:**
- Modify: `PlayerPath/DesignTokens.swift:90-96` (Color aliases) and `:152-190` (gradients)

- [ ] **Step 1: Prove zero users** (fresh, after Tasks 1–3):
```bash
cd /Users/Trey/Desktop/PlayerPath/PlayerPath
grep -rnE "\bbrandPrimary\b|\bbrandSecondary\b|\bpremiumBackground\b|\.premium\b|LinearGradient\.(brandNavy|brandGold|primaryButton|coachButton|premiumButton|premiumAccent)|\.(primaryButton|coachButton|premiumButton|premiumAccent)\b" --include='*.swift' . | grep -v DesignTokens.swift
```
Expected: no output. (If a line prints, drop that token from Step 2 and ledger it.)

- [ ] **Step 2: Delete.** In `DesignTokens.swift`, remove these declarations together with their `///` doc comments:
  - in `extension Color`: `brandPrimary`, `brandSecondary` (the "Legacy aliases" block), and `premium`, `premiumBackground` (the "Premium colors" block)
  - in `extension LinearGradient`: `brandNavy`, `brandGold`, `primaryButton`, `coachButton`, `premiumButton`, `premiumAccent`

Keep `glassBorder`, `glassShine` and `glassDark` (the Batch 1 pre-26 fallback). Then add this line above `static let brandNavy` in `extension Color`:
```swift
    /// LEGACY — do not use in new UI (Theme / ppAccent). Still used widely; retired batch by batch.
```

- [ ] **Step 3: Build.** Expected: `BUILD SUCCEEDED`. A failure here means a hidden user; restore only that token and ledger it.

- [ ] **Step 4: Commit**

```bash
cd /Users/Trey/Desktop/PlayerPath
git add PlayerPath/DesignTokens.swift
git commit -m "DesignTokens: delete dead legacy palette tokens (aliases, premium colors, 6 gradients)"
```

---

### Wrap-up

- [ ] Final whole-branch review by one fresh reviewer; fix Critical/Important.
- [ ] Update memory `project_ios26_liquid_glass_chrome.md` (batch 2 shipped) and the CLAUDE.md legacy-palette bullet (the deleted tokens are gone; recount `.brandNavy` with `grep -rn "\.brandNavy" --include='*.swift' PlayerPath | grep -v DesignTokens | wc -l`).
- [ ] Device/preview checklist for Trey: sign-up (role picker, age checkbox, CTA), email verification, the athlete paywall from a golf screen and from a baseball screen, and the coach paywall.
