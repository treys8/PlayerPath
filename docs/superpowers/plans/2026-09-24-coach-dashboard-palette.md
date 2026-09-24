# Coach Dashboard Palette — Implementation Plan (Batch 4 of 5)

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (or subagent-driven-development). Steps use `- [ ]`.

**Goal:** Retire the legacy navy/gold/system-blue on the coach's home surfaces (the tab root's tint, the Dashboard, its shared components, the Invitations sheet) and on the live-session athlete picker, moving them to the Calm Keepsake tokens.

**Architecture:** A pure recolor, with no layout or behavior changes. `CoachTabView` swaps `.tint(.brandNavy)` for `.ppAccent(forGolf: false)`, the same injector the athlete `MainTabView` uses, so the whole coach tree gets the base terracotta explicitly and `ppIsGolf` stays false. Views then read `@Environment(\.ppAccent)`. The one exception is the camera overlay, which uses `Theme.accent` directly because it's coach-only.

**Tech stack:** SwiftUI. There are no new APIs, and iOS 17 through 26 behave identically.

**Spec:** the 2026-09-23 palette/glass audit, batch #4 (`docs/superpowers/plans/2026-09-23-capture-overlays-glass.md`, "The 5-batch breakdown": "Coach dashboard navy (`CoachDashboardView`, `CoachDashboardComponents`, `CoachInvitationsView`, `CoachTabView` `.tint(.brandNavy)`)"). It also picks up `SessionAthletePickerOverlay` navy, deferred to this batch by batch 1 (memory `project_ios26_liquid_glass_chrome`).

## Design calls (baked in; flag any you want changed before execution)

| # | Where | Was | Becomes | Why |
|---|---|---|---|---|
| D1 | Dashboard section-header icons (5×) | `.brandGold` | `ppAccent` | A one-for-one swap of the decorative color. The icons are 14pt glyphs beside the heading. |
| D2 | `CoachSummaryCard` icons (Overview + This Month) | `.brandGold` | `Theme.textSecondary` | Up to 6 cards on screen. Accent on every one would make the accent mean nothing ("pay attention here" is its job). |
| D3 | Quick Actions: New Session / Review Clips / Invite Athlete | navy, navy, navy@0.7 | all solid `ppAccent` | Resume Session is already `ppAccent`. Terracotta @0.7 under white text drops to ~2.8:1, so the muted secondary tile doesn't carry over. The glyph + title tell the two tiles apart. |
| D4 | Accepted / "Connected" invitation states | navy | `Theme.chipGreenText` / `Theme.chipGreenBg` | Success status is not the accent. This matches Pending = `Theme.warning`, and the chip pair is already the app's "Seen" receipt. |
| D5 | Folder-type icon: games / default / lessons | navy / navy / system `.green` | `ppAccent` / `ppAccent` / `Theme.chipGreenText` | Keeps the two types visually distinct without the bright system green or the golf green (coach UI never takes golf green). |
| D6 | Folder-row permission glyphs (upload, comment) | navy | `Theme.textSecondary` | Informational metadata sitting beside the grey video count, not a call to action. |
| D7 | Upcoming Sessions header icon + count pill | system `.blue` | `ppAccent` | A stray system blue on the same dashboard. |

## Global Constraints

- Deployment target stays **iOS 17.0**. This batch adds no version-gated API.
- Colors: `Theme` + `@Environment(\.ppAccent)` only. Never add `.brandNavy`, `.brandGold` or a system `.blue`/`.green`. Coach UI is always the **base** terracotta, never golf green.
- Recolor only. Don't touch the grey `Color(.secondarySystemBackground)` card fills, the fonts (`.headingLarge` etc.) or the layouts. They're out of scope.
- `DashboardSectionHeader` and `QuickActionButton` (`Views/Dashboard/`) are **not** edited. Only the colors the coach dashboard passes into them change. The athlete DashboardView is retired dead code.
- No Swift test target. "Test" = a clean build + the grep in each task + the stated simulator check (a signed-in coach account).
- **Commit only the files each task names.** The working tree has unrelated edits (`Models/PlayResultAccumulator.swift`, `Views/Games/GameDetailView.swift`) that must NOT be staged. Commit directly to `main`, one commit per task. Never touch version/build numbers.

Build (every task):
```bash
cd /Users/Trey/Desktop/PlayerPath && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PlayerPath.xcodeproj \
  -scheme PlayerPath -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | head -20
```

## Verified facts (repo @ ac1ceb7, after batch 3)

| Fact | Source |
|---|---|
| `CoachTabView.body` applies `.tint(.brandNavy)` to `tabViewContent` (`:44`). Nothing else in the coach tree injects `ppAccent`/`.tint` except local ProgressView/white tints and `CoachDowngradeSelectionView:163` (out of scope) | grep `Views/Coach`, `Coach*.swift` |
| `MainAppView.swift:80` sets `.tint(Theme.accent)` app-wide; `ppAccent`'s default is `Theme.accent`, `ppIsGolf`'s default is false | `MainAppView.swift`, `Theme/AccentEnvironment.swift` |
| `ppAccent(forGolf:)` injects `ppAccent`, `ppAccentLight`, `ppIsGolf` and `.tint` | `AccentEnvironment.swift:63-70` |
| `CoachDashboardView` already reads `@Environment(\.ppAccent)` (`:53`) and uses it for the live header and Resume Session | read |
| Legacy sites in `CoachDashboardView`: `.blue` 504/513/516; `.brandGold` 556/605/717/745/806/1089; `.brandNavy` 574/584/593/641/643/776/780/812 | grep |
| `CoachSummaryCard` (private, `:1078+`) has no `ppAccent`; its gold icon is `:1089` | read |
| `QuickActionButton(color:)` fills a gradient `[color, color@0.8]` under white text and adds a `color@0.3` shadow | `Views/Dashboard/QuickActionButton.swift` |
| `CoachDashboardComponents` navy: 40/42 (AthleteSection avatar), 107/109 (folder icon), 135/140 (permission glyphs), 196/203 (empty-state glyph), 237 (empty-state button), 284/298 (pending banner). `.green` at 108. None of its structs read `ppAccent` | grep/read |
| `CoachInvitationsView` navy: 279 (InvitationRow icon), 368 (Accept button), 405/421 (AcceptedInvitationRow), 501 (SentInvitationRow folder label), 535 (accepted status icon), 566/567 (Connected badge). No struct reads `ppAccent` | grep/read |
| `SessionAthletePickerOverlay` navy: 45/61/65 (selected avatar fill, capsule fill, capsule stroke) on a dark glass panel. It's presented only from the coach recorder (`DirectCameraRecorderView.coachTaggingView`) | read, grep |
| `Theme.chipGreenBg` = `#DCE7DD`, `Theme.chipGreenText` = `#3B5044`, `Theme.textSecondary` = `#8A7F6F`, `Theme.accentLight` = `#F0997B` | `Theme/Theme.swift` |
| Counts at start: `.brandNavy` 196 (31 in scope), `.brandGold` 34 (6 in scope). Expected after: **165** / **28** | grep |

## Review Focus

1. **Tab-wide tint side effects:** once the coach tab is tinted terracotta, every system control inherits it: the tab bar's selected item, nav bar buttons, toggles, segmented pickers, `Link`s, swipe actions, context-menu confirmations. Walk all 3 tabs + Profile → Settings and confirm nothing is illegible or reads as destructive. Destructive buttons must stay red (`role: .destructive`).
2. **Mixed palette inside the coach tab:** ~63 `.brandNavy` uses remain in 21 other coach files (NoteCardView, CoachFolderComponents, StartSessionSheet, InviteAthleteSheet, CoachProfileView, …). Navy next to terracotta on the same screen is expected until the follow-up batch. Record any screen where it looks broken rather than merely mixed.
3. **White on terracotta contrast:** the Quick Action titles (`.headingSmall`), the empty-state Invite button and the Accept button put white text on terracotta. That's the same ~3.8:1 open question as batch 2 (`Theme.accentStrong`). Don't solve it here; just note whether any of them look worse than the paywall buttons.
4. **Live-session picker over a bright frame:** a terracotta selected avatar + capsule on dark glass. The selected state must be obvious at a glance, and the white initial must be readable on the filled circle.
5. **Dark mode:** `Theme.chipGreenText` (`#3B5044`) is a fixed light-scheme color. Check the Accepted/Connected rows in dark mode. If they're too dark to read, raise it (and the same risk applies to D5's lessons icon).

---

### Task 1: Coach tab root tint

**Files:**
- Modify: `PlayerPath/Views/Coach/CoachTabView.swift:44`

**Produces:** an explicit base-accent environment (`ppAccent` = `Theme.accent`, `ppIsGolf` = false, `.tint` = terracotta) for the whole coach tree. Tasks 2–4 read `ppAccent` from it.

- [ ] **Step 1: Swap the tint.** Replace line 44:

```swift
        .tint(.brandNavy)
```
with:
```swift
        // Coach UI is always the base (terracotta) accent — same injector as the
        // athlete MainTabView, pinned to non-golf.
        .ppAccent(forGolf: false)
```

- [ ] **Step 2: Build + grep.**

```bash
cd /Users/Trey/Desktop/PlayerPath && grep -n "brandNavy" PlayerPath/Views/Coach/CoachTabView.swift
```
Expected: no output. Build → `BUILD SUCCEEDED`.

- [ ] **Step 3: Sim check.** Signed in as a coach: the selected tab item is terracotta on all 3 tabs, and the nav bar buttons (Dashboard toolbar, Athletes, Profile → Settings) are terracotta. Walk through Review Focus #1.

- [ ] **Step 4: Commit.**

```bash
git add PlayerPath/Views/Coach/CoachTabView.swift
git commit -m "Coach tab: base terracotta accent replaces navy tint

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Coach Dashboard

**Files:**
- Modify: `PlayerPath/CoachDashboardView.swift:504, 513, 516, 556, 574, 584, 593, 605, 641, 643, 717, 745, 776, 780, 806, 812, 1089`

**Interfaces:** consumes the `ppAccent` environment (Task 1). The view already declares `@Environment(\.ppAccent) private var ppAccent` at `:53`.

- [ ] **Step 1: Upcoming Sessions (D7).** Lines 504 and 513: `.foregroundColor(.blue)` → `.foregroundColor(ppAccent)`. Line 516: `.background(Capsule().fill(Color.blue.opacity(0.12)))` → `.background(Capsule().fill(ppAccent.opacity(0.12)))`.

- [ ] **Step 2: Section headers (D1).** In all 5 `DashboardSectionHeader(...)` calls (lines 556, 605, 717, 745, 806), change `color: .brandGold` → `color: ppAccent`.

- [ ] **Step 3: Quick Actions (D3).** Lines 574 and 584: `color: .brandNavy` → `color: ppAccent`. Line 593: `color: .brandNavy.opacity(0.7)` → `color: ppAccent`.

- [ ] **Step 4: Recent athlete avatar.** Line 641: `.foregroundColor(.brandNavy)` → `.foregroundColor(ppAccent)`. Line 643: `.background(Color.brandNavy.opacity(0.1))` → `.background(ppAccent.opacity(0.1))`.

- [ ] **Step 5: Getting Started steps.** Line 776: `.fill(Color.brandNavy.opacity(0.1))` → `.fill(ppAccent.opacity(0.1))`. Line 780: `.foregroundColor(.brandNavy)` → `.foregroundColor(ppAccent)`.

- [ ] **Step 6: "View all".** Line 812: `.foregroundColor(.brandNavy)` → `.foregroundColor(ppAccent)`.

- [ ] **Step 7: Summary card icons (D2).** Line 1089 (inside `private struct CoachSummaryCard`): `.foregroundColor(.brandGold)` → `.foregroundColor(Theme.textSecondary)`.

- [ ] **Step 8: Grep + build.**

```bash
cd /Users/Trey/Desktop/PlayerPath && grep -nE "brandNavy|brandGold|\.blue\b|Color\.blue" PlayerPath/CoachDashboardView.swift
```
Expected: no output. Build → `BUILD SUCCEEDED`.

- [ ] **Step 9: Sim check.** Coach Dashboard with ≥1 athlete: section icons and Quick Action tiles are terracotta; Overview/This Month card icons are warm grey; Recent Athletes avatars are terracotta-tinted; "View all" is terracotta. On a coach with no athletes: the Getting Started circles are terracotta. With a scheduled session: the Upcoming Sessions icon + count pill are terracotta.

- [ ] **Step 10: Commit.**

```bash
git add PlayerPath/CoachDashboardView.swift
git commit -m "Coach Dashboard: terracotta accent replaces navy/gold/blue; summary icons go neutral

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Coach dashboard components

**Files:**
- Modify: `PlayerPath/Views/Coach/CoachDashboardComponents.swift` (structs at `:21`, `:92`, `:175`, `:272`; color lines 40, 42, 107-109, 135, 140, 196, 203, 237, 284, 298)

**Interfaces:** consumes the `ppAccent` environment (Task 1).

- [ ] **Step 1: Add the environment read** to the four structs that need it. Insert `@Environment(\.ppAccent) private var ppAccent` as a new line directly under each struct declaration:
  - `struct AthleteSection: View {` (`:21`)
  - `struct CoachFolderRowView: View {` (`:92`)
  - `struct CoachEmptyStateView: View {` (`:175`)
  - `struct PendingInvitationsBanner: View {` (`:272`)

(Line numbers below are from before this insert, so apply the recolors first, or match on the text.)

- [ ] **Step 2: AthleteSection avatar.** `.foregroundColor(.brandNavy)` (`:40`) → `.foregroundColor(ppAccent)`; `.background(Color.brandNavy.opacity(0.1))` (`:42`) → `.background(ppAccent.opacity(0.1))`.

- [ ] **Step 3: Folder icon color (D5).** Replace `folderIconColor` (`:105-111`) with:

```swift
    private var folderIconColor: Color {
        switch folder.folderType {
        case "lessons": return Theme.chipGreenText
        default:        return ppAccent   // "games" + any other type
        }
    }
```

- [ ] **Step 4: Permission glyphs (D6).** Both `.foregroundColor(.brandNavy)` at `:135` and `:140` → `.foregroundColor(Theme.textSecondary)`.

- [ ] **Step 5: Empty state.** `:196` `.fill(Color.brandNavy.opacity(0.1))` → `.fill(ppAccent.opacity(0.1))`. `:203` `colors: [.brandNavy, .brandNavy.opacity(0.6)],` → `colors: [ppAccent, ppAccent.opacity(0.6)],`. `:237` `.background(Color.brandNavy)` → `.background(ppAccent)`.

- [ ] **Step 6: Pending banner.** `:284` `.foregroundColor(.brandNavy)` → `.foregroundColor(ppAccent)`. `:298` `colors: [Color.brandNavy.opacity(0.1), Color.brandNavy.opacity(0.05)],` → `colors: [ppAccent.opacity(0.1), ppAccent.opacity(0.05)],`.

- [ ] **Step 7: Grep + build.**

```bash
cd /Users/Trey/Desktop/PlayerPath && grep -nE "brandNavy|return \.green" PlayerPath/Views/Coach/CoachDashboardComponents.swift
```
Expected: no output. Build → `BUILD SUCCEEDED`.

- [ ] **Step 8: Sim check.** Coach → Athletes tab: athlete avatars are terracotta-tinted; game folders show a terracotta glyph and lessons folders a dark forest-green one; the upload/comment glyphs are warm grey. With a pending invitation, the banner has a faint terracotta wash. A coach with zero athletes sees the terracotta empty state and a terracotta "Invite an Athlete" button.

- [ ] **Step 9: Commit.**

```bash
git add PlayerPath/Views/Coach/CoachDashboardComponents.swift
git commit -m "Coach dashboard components: terracotta accent replaces navy; lessons folder muted green

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Coach Invitations sheet

**Files:**
- Modify: `PlayerPath/CoachInvitationsView.swift` (structs at `:263`, `:458`; color lines 279, 368, 405, 421, 501, 535, 566, 567)

**Interfaces:** consumes the `ppAccent` environment (Task 1). The sheet is presented from inside the coach tree (`CoachProfileView:365` and the dashboard), so it inherits the injected accent.

- [ ] **Step 1: Add the environment read** directly under `struct InvitationRow: View {` (`:263`) and `struct SentInvitationRow: View {` (`:458`):

```swift
    @Environment(\.ppAccent) private var ppAccent
```

- [ ] **Step 2: Incoming invitation row.** `:279` `.foregroundColor(.brandNavy)` → `.foregroundColor(ppAccent)`. `:368` `.background(Color.brandNavy)` → `.background(ppAccent)`.

- [ ] **Step 3: Accepted row (D4).** `:405` and `:421` `.foregroundColor(.brandNavy)` → `.foregroundColor(Theme.chipGreenText)`.

- [ ] **Step 4: Sent row.** `:501` (folder label) `.foregroundColor(.brandNavy)` → `.foregroundColor(ppAccent)`. `:535` (accepted status icon, D4) `.foregroundColor(.brandNavy)` → `.foregroundColor(Theme.chipGreenText)`. `:566` `.background(Color.brandNavy.opacity(0.15))` → `.background(Theme.chipGreenBg)`. `:567` `.foregroundColor(.brandNavy)` → `.foregroundColor(Theme.chipGreenText)`.

- [ ] **Step 5: Grep + build.**

```bash
cd /Users/Trey/Desktop/PlayerPath && grep -n "brandNavy" PlayerPath/CoachInvitationsView.swift
```
Expected: no output. Build → `BUILD SUCCEEDED`.

- [ ] **Step 6: Sim check.** Coach → Invitations: an incoming invite has a terracotta icon and a terracotta Accept button (the at-limit variant stays amber); accepted rows show a green check + "Accepted"; on the Sent tab, pending stays amber, "Connected" is a green chip and the folder label is terracotta. Repeat in dark mode (Review Focus #5).

- [ ] **Step 7: Commit.**

```bash
git add PlayerPath/CoachInvitationsView.swift
git commit -m "Coach Invitations: terracotta actions, green success states replace navy

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Live-session athlete picker + wrap-up

**Files:**
- Modify: `PlayerPath/Views/Coach/SessionAthletePickerOverlay.swift:45, 61, 65`
- Modify (memory, not the repo): `project_ios26_liquid_glass_chrome.md`, `MEMORY.md`

- [ ] **Step 1: Recolor the selected state.** It's coach-only on a dark glass panel, so it uses the tokens directly:
  - `:45` `.fill(isSelected(athlete.id) ? Color.brandNavy : Color.white.opacity(0.2))` → `.fill(isSelected(athlete.id) ? Theme.accent : Color.white.opacity(0.2))`
  - `:61` `.fill(isSelected(athlete.id) ? Color.brandNavy.opacity(0.3) : Color.white.opacity(0.15))` → `.fill(isSelected(athlete.id) ? Theme.accent.opacity(0.3) : Color.white.opacity(0.15))`
  - `:65` `.strokeBorder(isSelected(athlete.id) ? Color.brandNavy : Color.clear, lineWidth: 2)` → `.strokeBorder(isSelected(athlete.id) ? Theme.accentLight : Color.clear, lineWidth: 2)` (the dark-surface variant, so the ring reads on dark glass)

- [ ] **Step 2: Grep (whole batch) + build.**

```bash
cd /Users/Trey/Desktop/PlayerPath && grep -c "brandNavy" PlayerPath/Views/Coach/SessionAthletePickerOverlay.swift; grep -rn "brandNavy" PlayerPath | wc -l; grep -rn "brandGold" PlayerPath | wc -l
```
Expected: `0`, `165`, `28`. Build → `BUILD SUCCEEDED`.

- [ ] **Step 3: Device check (camera required, so the sim can't reach it).** Coach live session → record a clip → the picker shows the last-used athlete with a terracotta avatar + a light-terracotta ring; tapping another athlete saves once.

- [ ] **Step 4: Commit.**

```bash
git add PlayerPath/Views/Coach/SessionAthletePickerOverlay.swift
git commit -m "Session athlete picker: terracotta selected state replaces navy

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 5: Run `/review`** on the batch range, fix what's real, and commit the fixes as "Batch 4 review fixes: …".

- [ ] **Step 6: Update memory.** Add a "Coach dashboard palette (batch 4 of 5)" paragraph to `project_ios26_liquid_glass_chrome.md`: the commit range, `CoachTabView` now injects `.ppAccent(forGolf: false)`, the D1–D7 rules (success = chipGreen, informational = textSecondary, stats icons neutral), the counts (165 navy / 28 gold), the ~63 coach navy uses left in 21 files (the follow-up batch), and which sim/device checks are pending. Update the MEMORY.md hook to "batches 1–4/5 done".
