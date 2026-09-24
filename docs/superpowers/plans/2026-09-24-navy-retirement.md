# Retire `.brandNavy` — Implementation Plan (final palette batch)

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (or subagent-driven-development). Steps use `- [ ]`.

**Goal:** Replace the last 95 `.brandNavy` uses (42 files), then delete the token itself, so the legacy navy can't come back.

**Architecture:** A recolor under the rules batches 4/4b established, plus one new rule for categorical color sets. Views read `@Environment(\.ppAccent)`, which gives the sport accent on athlete screens and terracotta in the coach tree and on sport-neutral surfaces. Static contexts (enums, default arguments, static funcs) use `Theme` tokens directly.

**Tech stack:** SwiftUI. No new APIs.

**Spec:** memory `project_ios26_liquid_glass_chrome` (batch 4b: "Remaining navy is outside the coach suite"). CLAUDE.md: "only tokens with zero call sites get deleted".

## Rules

| # | Meaning | Color |
|---|---|---|
| R1 | Actions, selection, active state, avatars, brand/feature glyphs, progress | `ppAccent` (opacity kept: `navy@x` → `ppAccent.opacity(x)`) |
| R2 | Success / confirmation | `Theme.chipGreenText` |
| R3 | Informational metadata | `Theme.textSecondary` |
| R4 | Navy that only restated a tint (`.tint(.brandNavy)` where the tint is already right) | delete the modifier |
| **R5 (new)** | **Navy is one slot in a multicolor categorical set** (practice types, club categories, score distribution, notification types, error kinds, quality levels, stat-entry rows, Getting Started step icons, metadata badges, upload stat columns) | **`Theme.tileNavy`** (#2D3D52, the palette's own slate). The slot stays distinct from its siblings, which are mostly system colors and out of scope, with no brand saturation. Moving whole categorical sets onto the palette is a separate design pass. |
| **R6 (new)** | Folder types (athlete side) | Mirrors batch 4 D5: games/default = `ppAccent`, lessons = `Theme.chipGreenText` (the system `.green` goes too) |
| **R7 (new)** | Status "SCHEDULED" badge (Game Detail; LIVE is already the accent) | `Theme.textPrimary` (ink): a distinct, calm non-live status that holds white text |

## Global Constraints

- Deployment target **iOS 17.0**. No version-gated APIs.
- Colors: `Theme` + `@Environment(\.ppAccent)` only. Never add `.brandNavy`/`.brandGold`/system `.blue`.
- Recolor only. Other system colors in the same sets (`.purple`, `.green`, `.orange`…), grey fills, fonts and layouts are out of scope. The one exception is R6's lessons green.
- A view struct that newly reads `ppAccent` gets exactly one `@Environment(\.ppAccent) private var ppAccent`, directly under its `struct … {` line. The structs are named per task below.
- The app is light-only (`MainAppView.swift:81`), so fixed tokens are safe.
- **Edit by matching the text**, not by line number. Line numbers are for orientation only.
- No Swift test target. "Test" = a clean build + the task's grep + the sim check.
- **Commit only the files each task names.** `Models/PlayResultAccumulator.swift` and `Views/Games/GameDetailView.swift` carry Trey's uncommitted edits. Task 6 stages only this batch's two GameDetailView lines (method given there). Commit directly to `main`, one commit per task. Never touch version/build numbers.

Build (every task):
```bash
cd /Users/Trey/Desktop/PlayerPath && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PlayerPath.xcodeproj \
  -scheme PlayerPath -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | head -20
```

## Verified facts (repo @ 0d1e267)

| Fact | Source |
|---|---|
| 95 uses in 42 files, plus the definition + one comment in `DesignTokens.swift` (`:80`, `:268`) = 97 grep hits | `grep -rn brandNavy PlayerPath` |
| Already read `ppAccent`: `AthleteProfileRow` (ProfileView), `BulkVideoImportSheet`, `MoveClipSheet`. No other target struct does | struct scan |
| `DashboardView` (athlete) has **no call sites**. It's retired. Its file also holds `DashboardSectionHeader` (used by `CoachDashboardView`) and `AthletePickerLabel` (used only by DashboardView) | grep |
| `MetricTrendChart.accent` defaults to navy, and its only callers (6, all in `GolfSeasonComparisonView`) never pass it, so the golf comparison trend lines are **navy today** | grep |
| `ActivityNotificationRouter.iconColor` and `ErrorView`'s `iconColor` are non-View static/enum contexts | read |
| `LoadingView(tint:)` defaults to navy. Its callers (`MainAppView:72`, `AuthenticatedFlow:31`) sit above any sport injection | grep |
| GameDetailView navy is at HEAD `:240` (SCHEDULED badge) and `:456` (batting-average value). Neither line is inside Trey's uncommitted hunks | `git diff -U0` |
| `ReelCardStyle.backgroundColor` (`DesignTokens.swift:271`) is a fixed `UIColor` #003373 baked into rendered reels. It is **not** the `brandNavy` symbol and stays; only its comment mentions the token | read |

## Review Focus

1. **Golf screens turn green where they were navy:** the scorecard's selected hole, the score chips' selected/par ring, the golf trend + scoring charts, the golf season-comparison trend lines, and the tournament row trophy. Check that a golf round reads coherently green with no terracotta leak.
2. **R5 categorical sets stay distinguishable:** club categories (iron slate vs wood gold vs wedge green vs putter purple), score distribution (par slate vs birdie mint vs bogey orange), practice types. Slate must not read as "disabled".
3. **Profile photo placeholders:** the athlete Profile and the Coach Profile avatar placeholder, upload spinner and edit badge take the right accent (sport for athletes, terracotta for coaches).
4. **Invitation deep link:** the "You're Invited!" and "Invitation Not Found" screens open before any sport context, so the accent there is terracotta.
5. **SCHEDULED badge (R7):** ink with white text next to a terracotta LIVE badge and a grey FINAL, all distinguishable.

---

### Task 1: Categorical slots (R5) + static defaults

**Files (no env reads needed):**
- `PlayerPath/PracticesView.swift:19`: `case .general:        return .brandNavy` → `return Theme.tileNavy`
- `PlayerPath/Models/Club.swift:83`: `case .iron:   return .brandNavy` → `return Theme.tileNavy`
- `PlayerPath/Views/Stats/GolfScoreDistributionSection.swift:68`: `return .brandNavy  // Par` → `return Theme.tileNavy  // Par`
- `PlayerPath/Views/Shared/ActivityNotificationRouter.swift:88`: `case .newVideo:           return .brandNavy` → `return Theme.tileNavy`
- `PlayerPath/Views/Shared/ErrorView.swift:35`: `return .brandNavy` → `return Theme.tileNavy`
- `PlayerPath/Views/Settings/QualityComparisonRow.swift:19` and `QualityDetailCard.swift:18`: `.brandNavy` → `Theme.tileNavy`
- `PlayerPath/Views/Games/ManualStatisticsEntryView.swift` (3×) and `ManualPitchingEntryView.swift` (1×): `color: .brandNavy` → `color: Theme.tileNavy`
- `PlayerPath/Views/Help/GettingStartedView.swift` (7×): `color: .brandNavy` / `iconColor: .brandNavy` → `Theme.tileNavy`
- `PlayerPath/Views/Components/VideoMetadataView.swift:40`: `color: .brandNavy` → `color: Theme.tileNavy`
- `PlayerPath/Views/Components/UploadStatisticsView.swift` StatColumns (the two `color: .brandNavy` at `:94` and `:135`) → `color: Theme.tileNavy`. **Leave** the `:65` ring and the `:206` wifi icon for Task 3.
- `PlayerPath/LoadingView.swift:19`: `tint: Color = .brandNavy,` → `tint: Color = Theme.accent,` (the auth/loading screen, before any sport)

- [ ] **Step 1: Apply the replacements above.** Every one is a `.brandNavy` → `Theme.tileNavy` swap (except LoadingView → `Theme.accent`). The only file with a split is UploadStatisticsView: replace exactly the two `color: .brandNavy` occurrences and nothing else there.

- [ ] **Step 2: Grep + build.**

```bash
cd /Users/Trey/Desktop/PlayerPath && grep -n "brandNavy" PlayerPath/PracticesView.swift PlayerPath/Models/Club.swift PlayerPath/Views/Stats/GolfScoreDistributionSection.swift PlayerPath/Views/Shared/ActivityNotificationRouter.swift PlayerPath/Views/Shared/ErrorView.swift PlayerPath/Views/Settings/QualityComparisonRow.swift PlayerPath/Views/Settings/QualityDetailCard.swift PlayerPath/Views/Games/ManualStatisticsEntryView.swift PlayerPath/Views/Games/ManualPitchingEntryView.swift PlayerPath/Views/Help/GettingStartedView.swift PlayerPath/Views/Components/VideoMetadataView.swift PlayerPath/LoadingView.swift; grep -c "brandNavy" PlayerPath/Views/Components/UploadStatisticsView.swift
```
Expected: no hits, then `2`. Build → `BUILD SUCCEEDED`.

- [ ] **Step 3: Sim check.** Review Focus #2:
  - A golf round's club chips.
  - The Stats score-distribution bar.
  - The Practices list type icons.
  - Settings → Video Quality (Medium is slate).
  - More → Help → Getting Started step icons.

- [ ] **Step 4: Commit.**

```bash
git add PlayerPath/PracticesView.swift PlayerPath/Models/Club.swift PlayerPath/Views/Stats/GolfScoreDistributionSection.swift PlayerPath/Views/Shared/ActivityNotificationRouter.swift PlayerPath/Views/Shared/ErrorView.swift PlayerPath/Views/Settings/QualityComparisonRow.swift PlayerPath/Views/Settings/QualityDetailCard.swift PlayerPath/Views/Games/ManualStatisticsEntryView.swift PlayerPath/Views/Games/ManualPitchingEntryView.swift PlayerPath/Views/Help/GettingStartedView.swift PlayerPath/Views/Components/VideoMetadataView.swift PlayerPath/Views/Components/UploadStatisticsView.swift PlayerPath/LoadingView.swift
git commit -m "Categorical color slots: palette slate replaces navy; loading tint terracotta

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Games, golf scoring, stats

**Env reads to add:** `GamesView`, `TournamentRow`, `GameCreationView`, `GolfScorecardView`, `NumberChip` (`ScoreHoleControls.swift:75`), `GolfStatsSection`, `GolfChartsView`, `MetricTrendChart` (`ComparisonComponents.swift:27`), `StatisticsView`, `PlayResultEditorView`, `ClubPickerEditorView`.

- [ ] **Step 1: Add the env reads** listed above.

- [ ] **Step 2: R1 swaps** (each `.brandNavy`/`Color.brandNavy` → `ppAccent`, opacity kept):
  - `GamesView.swift:380` the swipe "Complete": `.tint(Color.brandNavy)` → `.tint(ppAccent)`
  - `TournamentRow.swift:36` `.foregroundStyle(Color.brandNavy)` → `.foregroundStyle(ppAccent)`
  - `GameCreationView.swift:261, 294` (both `.foregroundColor(.brandNavy)`) → `.foregroundColor(ppAccent)`
  - `GolfScorecardView.swift:206` `? Color.brandNavy.opacity(0.12)` → `? ppAccent.opacity(0.12)`; `:244` `isSelected ? Color.brandNavy : Color.clear` → `isSelected ? ppAccent : Color.clear`
  - `ScoreHoleControls.swift:95` `isSelected ? Color.brandNavy : Color(.secondarySystemBackground)` → `isSelected ? ppAccent : …`; `:100` `Color.brandNavy.opacity(0.4)` → `ppAccent.opacity(0.4)`
  - `GolfStatsSection.swift:371, 376` and `GolfChartsView.swift:215, 222` `.foregroundStyle(Color.brandNavy)` → `.foregroundStyle(ppAccent)`
  - `StatisticsView.swift:430` `.foregroundColor(.brandNavy)` → `.foregroundColor(ppAccent)`; `:444` `.tint(.brandNavy)` → `.tint(ppAccent)`; `:448` `Color.brandNavy.opacity(0.08)` → `ppAccent.opacity(0.08)`
  - `PlayResultEditorView.swift:136` and `ClubPickerEditorView.swift:112` `.background(Color.brandNavy)` → `.background(ppAccent)`

- [ ] **Step 3: MetricTrendChart default.** In `ComparisonComponents.swift`, change `var accent: Color = .brandNavy` to:

```swift
    /// nil = the environment's sport accent (golf comparison → green).
    var accent: Color? = nil
```

Then add, below the new `@Environment(\.ppAccent) private var ppAccent`:

```swift
    private var lineColor: Color { accent ?? ppAccent }
```

Then replace every **other** use of `accent` in `MetricTrendChart`'s body with `lineColor` (grep `accent` inside the struct first). The call sites never pass `accent`, so no caller changes.

- [ ] **Step 4: Grep + build.**

```bash
cd /Users/Trey/Desktop/PlayerPath && grep -n "brandNavy" PlayerPath/GamesView.swift PlayerPath/Views/Games/TournamentRow.swift PlayerPath/Views/Games/GameCreationView.swift PlayerPath/Views/Games/GolfScorecardView.swift PlayerPath/Views/Games/ScoreHoleControls.swift PlayerPath/Views/Stats/GolfStatsSection.swift PlayerPath/Views/Stats/GolfChartsView.swift PlayerPath/Views/Stats/ComparisonComponents.swift PlayerPath/StatisticsView.swift PlayerPath/Views/Components/PlayResultEditorView.swift PlayerPath/Views/Components/ClubPickerEditorView.swift
```
Expected: no output. Build → `BUILD SUCCEEDED`.

- [ ] **Step 5: Sim check.** Review Focus #1:
  - Golf: the scorecard selected hole, score chips, stats charts, the season-compare trend lines and the tournament row are green.
  - Baseball: swipe Complete on a game, the Stats tracking-off banner, and the play-result editor are terracotta.

- [ ] **Step 6: Commit.**

```bash
git add PlayerPath/GamesView.swift PlayerPath/Views/Games/TournamentRow.swift PlayerPath/Views/Games/GameCreationView.swift PlayerPath/Views/Games/GolfScorecardView.swift PlayerPath/Views/Games/ScoreHoleControls.swift PlayerPath/Views/Stats/GolfStatsSection.swift PlayerPath/Views/Stats/GolfChartsView.swift PlayerPath/Views/Stats/ComparisonComponents.swift PlayerPath/StatisticsView.swift PlayerPath/Views/Components/PlayResultEditorView.swift PlayerPath/Views/Components/ClubPickerEditorView.swift
git commit -m "Games, golf scoring, stats: sport accent replaces navy (golf charts now green)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Videos, highlights, folders, search, notifications

**Env reads to add:** `AthleteVideoRow`, `VideoPlayerView`, `FolderRow` (`AthleteFoldersListView.swift:296`), `FilterChip` (`AdvancedSearchView.swift:718`), `NotificationInboxRow` (`NotificationInboxView.swift:105`), `GameLinkerView`, `AnnotationBadgeCluster`, `HighlightReelCard`, `UploadStatisticsView`. (`MoveClipSheet` and `BulkVideoImportSheet` already have it.)

- [ ] **Step 1: Add the env reads** listed above.

- [ ] **Step 2: R1 swaps** (`.brandNavy`/`Color.brandNavy` → `ppAccent`, opacity kept):
  - `AthleteVideoRow` "New Feedback" capsule + highlight fill
  - `VideoPlayerView:701` the retry button
  - `AdvancedSearchView` FilterChip (2)
  - `NotificationInboxView:132` unread dot
  - `GameLinkerView` (3: checkmark, season label, checkmark)
  - `MoveClipSheet:224` checkmark
  - `BulkVideoImportSheet` (the 2 glyphs; `:150` `.tint(.brandNavy)` → `.tint(ppAccent)`)
  - `HighlightReelCard` (the REEL capsule, the reel-name label, and the placeholder gradient `[ppAccent, ppAccent.opacity(0.7)]`)
  - `AnnotationBadgeCluster:91` `Color.brandNavy.opacity(0.65)` → `ppAccent.opacity(0.65)`
  - `UploadStatisticsView:65` ring gradient `[Color.brandNavy, .cyan]` → `[ppAccent, ppAccent.opacity(0.6)]`

- [ ] **Step 3: R3.** `UploadStatisticsView:206` `prefs.allowCellularUploads ? Theme.warning : .brandNavy` → `… : Theme.textSecondary`.

- [ ] **Step 4: R6 folder types.** In `AthleteFoldersListView` `FolderRow.folderIconColor`, replace the switch body with the batch 4 form:

```swift
        switch folder.folderType {
        case "lessons": return Theme.chipGreenText
        default:        return ppAccent   // "games" + any other type
        }
```

- [ ] **Step 5: Grep + build.**

```bash
cd /Users/Trey/Desktop/PlayerPath && grep -n "brandNavy" PlayerPath/AthleteVideoRow.swift PlayerPath/VideoPlayerView.swift PlayerPath/AthleteFoldersListView.swift PlayerPath/Views/Search/AdvancedSearchView.swift PlayerPath/Views/Shared/NotificationInboxView.swift PlayerPath/Views/Components/GameLinkerView.swift PlayerPath/Views/Components/MoveClipSheet.swift PlayerPath/Views/Videos/BulkVideoImportSheet.swift PlayerPath/Views/Highlights/HighlightReelCard.swift PlayerPath/Views/Components/AnnotationBadgeCluster.swift PlayerPath/Views/Components/UploadStatisticsView.swift
```
Expected: no output. Build → `BUILD SUCCEEDED`.

- [ ] **Step 6: Sim check.**
  - Videos: the filter chips in search, a clip's drawing badge, Link to Game checkmarks, Move Clip, and Bulk Import.
  - Highlights: the reel card's REEL pill and name.
  - Notifications: the unread dot.
  - Athlete → Coaches → folders: the game folder is accent and lessons is green.
  - Upload statistics: the ring.
  - Check all of these on a golf athlete (green) and a baseball athlete (terracotta).

- [ ] **Step 7: Commit.**

```bash
git add PlayerPath/AthleteVideoRow.swift PlayerPath/VideoPlayerView.swift PlayerPath/AthleteFoldersListView.swift PlayerPath/Views/Search/AdvancedSearchView.swift PlayerPath/Views/Shared/NotificationInboxView.swift PlayerPath/Views/Components/GameLinkerView.swift PlayerPath/Views/Components/MoveClipSheet.swift PlayerPath/Views/Videos/BulkVideoImportSheet.swift PlayerPath/Views/Highlights/HighlightReelCard.swift PlayerPath/Views/Components/AnnotationBadgeCluster.swift PlayerPath/Views/Components/UploadStatisticsView.swift
git commit -m "Videos, highlights, folders, search, inbox: sport accent replaces navy

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Profile, invitations, help

**Env reads to add:** `ProfileImageView` and `EditableProfileImageView` (`ProfileImageManager.swift:161, 228`), `InvitationDetailView` (`DeepLinkHandler.swift:16`), `AddSportProfileSheet`, `ContactSupportView`, `HelpArticleDetailView` (`HelpArticles.swift:673`). (`AthleteProfileRow` already has it.)

- [ ] **Step 1: Add the env reads** listed above.

- [ ] **Step 2: R1 swaps** (`.brandNavy`/`Color.brandNavy` → `ppAccent`, opacity kept):
  - `ProfileImageManager` (7), including `CircularProgressViewStyle(tint: .brandNavy)` → `CircularProgressViewStyle(tint: ppAccent)`
  - `ProfileView` `AthleteProfileRow` sport icons (2)
  - `DeepLinkHandler` (3)
  - `AddSportProfileSheet` (4, the selection states)
  - `ContactSupportView:35`
  - `HelpArticles:685`

- [ ] **Step 3: Grep + build.**

```bash
cd /Users/Trey/Desktop/PlayerPath && grep -n "brandNavy" PlayerPath/ProfileImageManager.swift PlayerPath/ProfileView.swift PlayerPath/DeepLinkHandler.swift PlayerPath/Views/Components/AddSportProfileSheet.swift PlayerPath/Views/Help/ContactSupportView.swift PlayerPath/Views/Help/HelpArticles.swift
```
Expected: no output. Build → `BUILD SUCCEEDED`.

- [ ] **Step 4: Sim check.** Review Focus #3 and #4:
  - More → Profile: the avatar placeholder and edit badge.
  - More → Profile → Add Sport: the selection state.
  - Help → an article header tile.
  - Contact Support.
  - Coach Profile avatar.

- [ ] **Step 5: Commit.**

```bash
git add PlayerPath/ProfileImageManager.swift PlayerPath/ProfileView.swift PlayerPath/DeepLinkHandler.swift PlayerPath/Views/Components/AddSportProfileSheet.swift PlayerPath/Views/Help/ContactSupportView.swift PlayerPath/Views/Help/HelpArticles.swift
git commit -m "Profile, invitations, help: accent replaces navy

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Retired athlete DashboardView (dead code)

**Files:** `PlayerPath/Views/Dashboard/DashboardView.swift` (14)

It has no call sites, but its file hosts `DashboardSectionHeader` (live, used by the coach dashboard). Deleting the retired view means extracting that struct and chasing the now-dead `Dashboard*Card` files, which is a separate cleanup. This task **recolors in place** so the token can be deleted.

- [ ] **Step 1:** Add `@Environment(\.ppAccent) private var ppAccent` under `struct DashboardView: View {` and `struct AthletePickerLabel: View {`. Replace every `Color.brandNavy` → `ppAccent` and `.brandNavy` → `ppAccent` in the file (opacity kept).

- [ ] **Step 2: Grep + build.** `grep -c brandNavy PlayerPath/Views/Dashboard/DashboardView.swift` → `0`. Build → `BUILD SUCCEEDED`. (There's no sim check: the view is unreachable.)

- [ ] **Step 3: Commit.**

```bash
git add PlayerPath/Views/Dashboard/DashboardView.swift
git commit -m "Retired DashboardView: accent replaces navy (dead code, recolored so the token can go)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: GameDetailView + delete the token + docs

**Files:**
- Modify: `PlayerPath/Views/Games/GameDetailView.swift` (the 2 navy lines only)
- Modify: `PlayerPath/DesignTokens.swift` (delete `brandNavy`, reword the `ReelCardStyle` comment)
- Modify: `CLAUDE.md` (the legacy-palette bullet)
- Modify (memory): `project_ios26_liquid_glass_chrome.md`, `MEMORY.md`

- [ ] **Step 1: GameDetailView, without touching Trey's hunks.** First check `git diff --quiet -- PlayerPath/Views/Games/GameDetailView.swift`.
  - **If it's clean** (Trey committed his edits meanwhile): edit normally (below) and `git add` the file.
  - **If it's dirty:** apply the same two edits to BOTH the working file and the index copy, so only these two lines are staged:

```bash
cd /Users/Trey/Desktop/PlayerPath
F=PlayerPath/Views/Games/GameDetailView.swift
git show :$F > /private/tmp/claude-502/-Users-Trey-Desktop-PlayerPath/282268af-8551-4d44-a704-610aea14cdd9/scratchpad/gdv_index.swift        # index = HEAD for this file
# apply the two replacements (below) to /private/tmp/claude-502/-Users-Trey-Desktop-PlayerPath/282268af-8551-4d44-a704-610aea14cdd9/scratchpad/gdv_index.swift AND to $F, then:
BLOB=$(git hash-object -w /private/tmp/claude-502/-Users-Trey-Desktop-PlayerPath/282268af-8551-4d44-a704-610aea14cdd9/scratchpad/gdv_index.swift)
git update-index --cacheinfo 100644,$BLOB,$F
git diff --cached --stat                   # expect: GameDetailView.swift | 2-4 lines only
```

  The two replacements (R7 + R1). Add the env read if `GameDetailView` lacks one (check both copies):
  - `.background(Color.brandNavy)` (the `case .scheduled:` "SCHEDULED" badge) → `.background(Theme.textPrimary)`
  - `.foregroundColor(.brandNavy)` (the Batting Average value) → `.foregroundColor(ppAccent)`. If adding the env read to the index copy, insert `@Environment(\.ppAccent) private var ppAccent` under `struct GameDetailView: View {` in both copies.

- [ ] **Step 2: Confirm zero uses, then delete the token.**

```bash
cd /Users/Trey/Desktop/PlayerPath && grep -rn "brandNavy" PlayerPath | grep -v DesignTokens.swift
```
Expected: no output. Then, in `DesignTokens.swift`:
  - Delete the `/// LEGACY …` comment, the `/// Primary brand colors …` line and the whole `static let brandNavy = Color(UIColor { … })` block. Keep the `brandGold` block, and move `/// Primary brand colors — derived from the app icon (navy + gold)` above it, reworded to `/// LEGACY gold — do not use in new UI; retired batch by batch.`
  - The `ReelCardStyle` doc comment: change `always the original navy, never the trait-reactive \`Color.brandNavy\`.` → `always the original brand navy (#003373), fixed.`

- [ ] **Step 3: Build.** Expected `BUILD SUCCEEDED`. Then `grep -rn "brandNavy" PlayerPath` → no output.

- [ ] **Step 4: CLAUDE.md.** In the "Legacy, still load-bearing" list, replace the old-palette bullet's opening `Old palette: \`.brandNavy\` (~200 uses as of 2026-09-23 — being retired batch by batch; check new diffs for it) and \`.brandGold\`.` with `Old palette: \`.brandGold\` (~28 uses: highlights family, dashboard, club/shot categories). \`.brandNavy\` was fully retired and deleted 2026-09-24.` Leave the rest of the bullet unchanged.

- [ ] **Step 5: Commit.**

```bash
git add PlayerPath/DesignTokens.swift CLAUDE.md   # GameDetailView is already staged (index-only) or add it if clean
git diff --cached --stat
git commit -m "Retire .brandNavy: last two uses (GameDetail) + delete the token

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
git status --short   # Trey's GameDetailView/PlayResultAccumulator edits must still show as modified
```

- [ ] **Step 6: Run `/review`** on the batch range, fix what's real, and commit the fixes as "Navy retirement review fixes: …".

- [ ] **Step 7: Memory.** Add a "Navy retired" paragraph to `project_ios26_liquid_glass_chrome.md`:
  - the range
  - R5 (categorical slot → `Theme.tileNavy`) and R7
  - the token is deleted
  - `ReelCardStyle`'s fixed navy stays
  - the remaining legacy is `.brandGold` (~28) and the categorical system colors
  - the dead DashboardView (+ Dashboard*Card files) is a cleanup candidate

Update the MEMORY.md hook.
