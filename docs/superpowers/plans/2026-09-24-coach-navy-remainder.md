# Coach Navy Remainder — Implementation Plan (Batch 4b)

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (or subagent-driven-development). Steps use `- [ ]`.

**Goal:** Retire the last 63 `.brandNavy` uses in the coach suite (21 files). Batch 4 turned the coach tab's tint terracotta, so these are the screens that now show navy next to terracotta.

**Architecture:** A pure recolor, following the rules batch 4 set. Views read `@Environment(\.ppAccent)`, which resolves to base terracotta inside the coach tree (`CoachTabView` injects `.ppAccent(forGolf: false)`) and to the sport accent in athlete-side screens (`Views/Coaches/`). Navy that only duplicated the tint on toolbar glyphs, `Link`s and `.tint(...)` is **deleted**, so the control inherits the system/tint default instead.

**Tech stack:** SwiftUI. No new APIs.

**Spec:** memory `project_ios26_liquid_glass_chrome`, batch 4 entry ("~63 coach navy uses remain in 21 files … = batch 4b"). The batch 4 rules come from `docs/superpowers/plans/2026-09-24-coach-dashboard-palette.md` (D1–D7).

## Rules (batch 4's, restated) + the new calls this batch needs

| # | Meaning | Color |
|---|---|---|
| R1 | Actions, selection, active state, avatars, primary buttons, decorative feature glyphs | `ppAccent` (opacity variants kept, e.g. `navy@0.1` → `ppAccent.opacity(0.1)`) |
| R2 | Success / confirmation (✓ refreshed, ✓ video selected, Upload Complete) | `Theme.chipGreenText` |
| R3 | Informational metadata glyphs (stat-pill icons, unknown-club fallback) | `Theme.textSecondary` |
| R4 | Navy that only restated the tint (toolbar glyphs, `Link`s, `.tint(.brandNavy)`) | **delete the modifier** |
| **E1 (new)** | **Author color:** coach-authored note/marker vs athlete-authored | coach = `ppAccent`; athlete = `Theme.textSecondary`. Notes already used `.secondary` for athletes. The annotation markers flip the athlete marker from accent to grey so the two surfaces agree. |
| **E2 (new)** | **Review queues:** "My Drafts" vs "Needs Your Review" (distinct accents, filled button under white text) | My Drafts = `Theme.textPrimary` (warm ink); Needs Review keeps `Theme.accent`. The accent at a lower opacity fails white-text contrast, and ink keeps the two queues distinct. |
| **E3 (new)** | Coach video-card tag chips | `Theme.cueBg` / `Theme.cueText`, the existing quick-cue chip pair |

## Global Constraints

- Deployment target **iOS 17.0**. There are no version-gated APIs in this batch.
- Colors: `Theme` + `@Environment(\.ppAccent)` only. Never add `.brandNavy`/`.brandGold`/system `.blue`.
- Recolor only. The grey `systemGray*`/`secondarySystemBackground` fills, fonts and layouts are out of scope.
- A struct that newly reads `ppAccent` gets exactly one `@Environment(\.ppAccent) private var ppAccent` line, directly under its `struct … {` declaration. Nested enums (`UploadField`, `GamesFolderFilter`, `Field`) are not structs. The property goes on the enclosing view.
- The app forces light mode (`MainAppView.swift:81`), so fixed light tokens are safe.
- No Swift test target. "Test" = a clean build + the grep in each task + the stated simulator check.
- **Commit only the files each task names.** The working tree has unrelated edits (`Models/PlayResultAccumulator.swift`, `Views/Games/GameDetailView.swift`) that must NOT be staged. Commit directly to `main`, one commit per task. Never touch version/build numbers.
- **Edit by matching the text**, not by line number. Line numbers are given for orientation only, and they shift after the env inserts.

Build (every task):
```bash
cd /Users/Trey/Desktop/PlayerPath && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PlayerPath.xcodeproj \
  -scheme PlayerPath -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | head -20
```

## Verified facts (repo @ bc33acc)

| Fact | Source |
|---|---|
| 63 navy uses in 21 files. None of the 21 files read `ppAccent` except `AnnotationPlaybackViews.swift` (`AnnotationMarkersOverlay:45`) | grep |
| Athlete-side hosts: `CoachDetailView` (from `CoachesView:110`), `ShareToCoachFolderView` (from 5 athlete clip rows/cards). Everything else is presented inside the coach tree | grep |
| `AthleteCoachVideosView` has **no call sites** (dead). It gets recolored for the count; deleting it is out of scope | grep |
| `ClipQueueStyle.accent` fills the "Review Clips" button under white text (`ReviewQueueCard.swift:90-91`) and tints the header, badge, gradient and stroke | read |
| `InlineSpeedControl`'s selected rate = a navy capsule under white text (`:37-43`) | read |
| Toolbar glyph navy: `CoachAthletesTab.swift:65, 84, 99` and `CoachFolderDetailView.swift:166` (the refresh `ToolbarItem`). On iOS 26 toolbar glyphs render plain inside glass (the batch 1 athlete precedent) | read |
| `.tint(.brandNavy)` on `.borderedProminent`: `CoachVideoUploadView.swift:142`, `CoachDowngradeSelectionView.swift:163`. With the modifier deleted they inherit the tab tint or MainAppView's `Theme.accent` (the downgrade sheet is attached outside the coach env, where the value is the same) | read |
| Counts at start: `.brandNavy` **160** (incl. the `DesignTokens` definition). Expected after: **97** | grep |

## Review Focus

1. **Coach vs athlete authorship (E1):** on a clip with both coach and athlete notes/markers, the coach's must read as the highlighted voice (terracotta) and the athlete's as secondary (grey), both in the notes list and on the timeline markers. A grey athlete marker must still be visible on the scrubber track.
2. **Toolbar glyphs after the delete (R4):** the Athletes tab's invitations / record / more glyphs and the folder's refresh glyph must stay visible and tappable, on iOS 26 (plain in glass) and pre-26 (the tint color).
3. **My Drafts ink button (E2):** the "Review Clips" button, header and badge on the My Drafts card read as a deliberate secondary queue, not as disabled or as an error.
4. **Athlete-side sport color:** a golf athlete's Coach Detail (folder icons, avatar) and Share to Coach Folder checkmark are green. A baseball athlete's are terracotta.
5. **Session start sheet:** Start Session stays grey while no athlete is picked and turns terracotta once one is picked. The selected checkmarks are terracotta.

---

### Task 1: Review surface (notes, markers, filmstrip, speed, drill cards, tag editor)

**Files:**
- Modify: `PlayerPath/Views/Coach/Review/NoteCardView.swift` (`:25, 30, 38, 39, 59, 62`)
- Modify: `PlayerPath/Views/Coach/Telestration/AnnotationPlaybackViews.swift:52`
- Modify: `PlayerPath/Views/Coach/FilmstripScrubber/FilmstripScrubberView.swift` (`:98, 132, 138`)
- Modify: `PlayerPath/Views/Coach/InlineSpeedControl.swift:39`
- Modify: `PlayerPath/Views/Coach/DrillCardSummaryView.swift:24`
- Modify: `PlayerPath/Views/Coach/Review/DrillCardTabView.swift` (`:41-42`)
- Modify: `PlayerPath/Views/Coach/VideoTagEditor.swift` (`:48, 83, 155, 156, 160`)

- [ ] **Step 1: Environment reads.** Add `@Environment(\.ppAccent) private var ppAccent` under the declarations of `struct NoteCardView`, `struct FilmstripScrubberView`, `struct InlineSpeedControl`, `struct DrillCardSummaryView`, `struct DrillCardTabView`, `struct VideoTagEditor` and `struct TagChip` (`VideoTagEditor.swift:143`).

- [ ] **Step 2: NoteCardView (E1 + R1).** Replace every `.brandNavy` → `ppAccent` and every `Color.brandNavy` → `ppAccent` in the file: the coach icon + name (`isCoachComment ? ppAccent : .secondary`), the COACH badge (`ppAccent.opacity(0.2)` bg / `ppAccent` text), and the "Tap to view drawing" glyph + text.

- [ ] **Step 3: Annotation markers (E1).** `AnnotationPlaybackViews.swift:52`:
  `let color: Color = annotation.isCoachComment ? Color.brandNavy : ppAccent`
  → `let color: Color = annotation.isCoachComment ? ppAccent : Theme.textSecondary`

- [ ] **Step 4: Filmstrip, speed, drill cards (R1).**
  - `FilmstripScrubberView`: `.fill(Color.brandNavy)` → `.fill(ppAccent)`; `isActive ? Color.brandNavy : .clear` → `isActive ? ppAccent : .clear`; `isActive ? .brandNavy : .secondary` → `isActive ? ppAccent : .secondary`
  - `InlineSpeedControl`: `? Color.brandNavy` → `? ppAccent`
  - `DrillCardSummaryView`: `.foregroundColor(.brandNavy)` → `.foregroundColor(ppAccent)`
  - `DrillCardTabView`: `.background(Color.brandNavy.opacity(0.1))` → `.background(ppAccent.opacity(0.1))`; `.foregroundColor(.brandNavy)` → `.foregroundColor(ppAccent)`

- [ ] **Step 5: VideoTagEditor + TagChip (R1).** The checkmark and "plus.circle.fill": `.foregroundColor(.brandNavy)` → `.foregroundColor(ppAccent)`. TagChip: `isSelected ? Color.brandNavy.opacity(0.2)` → `isSelected ? ppAccent.opacity(0.2)`; `isSelected ? .brandNavy : .primary` → `isSelected ? ppAccent : .primary`; `isSelected ? Color.brandNavy : Color.clear` → `isSelected ? ppAccent : Color.clear`.

- [ ] **Step 6: Grep + build.**

```bash
cd /Users/Trey/Desktop/PlayerPath && grep -n "brandNavy" PlayerPath/Views/Coach/Review/NoteCardView.swift PlayerPath/Views/Coach/Telestration/AnnotationPlaybackViews.swift PlayerPath/Views/Coach/FilmstripScrubber/FilmstripScrubberView.swift PlayerPath/Views/Coach/InlineSpeedControl.swift PlayerPath/Views/Coach/DrillCardSummaryView.swift PlayerPath/Views/Coach/Review/DrillCardTabView.swift PlayerPath/Views/Coach/VideoTagEditor.swift; grep -c "Environment(\\\\.ppAccent)" PlayerPath/Views/Coach/VideoTagEditor.swift
```
Expected: no navy hits, then `2`. Build → `BUILD SUCCEEDED`.

- [ ] **Step 7: Sim check.** As a coach, open a clip in a folder:
  - The filmstrip's active frame and markers are terracotta.
  - The selected speed chip is terracotta with white text.
  - In the Notes tab, coach notes show a terracotta name + COACH badge. Athlete notes are grey.
  - Tag editor: selected chips are terracotta.
  - The drill-card tab's add button is terracotta.
  - Review Focus #1.

- [ ] **Step 8: Commit.**

```bash
git add PlayerPath/Views/Coach/Review/NoteCardView.swift PlayerPath/Views/Coach/Telestration/AnnotationPlaybackViews.swift PlayerPath/Views/Coach/FilmstripScrubber/FilmstripScrubberView.swift PlayerPath/Views/Coach/InlineSpeedControl.swift PlayerPath/Views/Coach/DrillCardSummaryView.swift PlayerPath/Views/Coach/Review/DrillCardTabView.swift PlayerPath/Views/Coach/VideoTagEditor.swift
git commit -m "Coach review surface: accent replaces navy; coach-authored = accent, athlete = secondary

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Coach folders, upload, review queues

**Files:**
- Modify: `PlayerPath/CoachFolderComponents.swift` (`:28, 165, 383-384, 396, 425`)
- Modify: `PlayerPath/CoachFolderDetailView.swift` (`:166, 465`)
- Modify: `PlayerPath/CoachVideoUploadView.swift` (`:57, 142, 256`)
- Modify: `PlayerPath/Views/Coach/ReviewQueueCard.swift:19`

- [ ] **Step 1: Environment reads.** Add `@Environment(\.ppAccent) private var ppAccent` under `struct AllVideosTabView: View {` and `struct CoachVideoCard: View {` (`CoachFolderComponents.swift`) and under `struct CoachFolderDetailView: View {`.

- [ ] **Step 2: CoachFolderComponents.**
  - `FolderInfoHeader` "Updated" ✓ (R2): `.foregroundColor(.brandNavy)` → `.foregroundColor(Theme.chipGreenText)`
  - `AllVideosTabView` "Load More Videos" (R1): `.foregroundColor(.brandNavy)` → `.foregroundColor(ppAccent)`
  - `CoachVideoCard` tag chips (E3): `.background(Color.brandNavy.opacity(0.1))` → `.background(Theme.cueBg)`; `.foregroundColor(.brandNavy)` → `.foregroundColor(Theme.cueText)`
  - `CoachVideoCard` club fallback (R3): `?? .brandNavy` → `?? Theme.textSecondary`
  - `CoachVideoCard` highlight ring (R1): `.stroke(Color.brandNavy.opacity(isHighlighted ? 0.9 : 0), lineWidth: 3)` → `.stroke(ppAccent.opacity(isHighlighted ? 0.9 : 0), lineWidth: 3)`

- [ ] **Step 3: CoachFolderDetailView.**
  - Refresh toolbar glyph (R4): delete the line `.foregroundColor(.brandNavy)` under `Image(systemName: "arrow.clockwise")`.
  - The selection circle (R1): `selectedClipIDs.contains(clip.id) ? .brandNavy : .white` → `selectedClipIDs.contains(clip.id) ? ppAccent : .white`.

- [ ] **Step 4: CoachVideoUploadView.**
  - Both `checkmark.circle.fill` `.foregroundColor(.brandNavy)` ("Video selected", "Upload Complete!") (R2) → `.foregroundColor(Theme.chipGreenText)`.
  - Delete the line `.tint(Color.brandNavy)` after `.buttonStyle(.borderedProminent)` (R4).

- [ ] **Step 5: ReviewQueueCard (E2).** `case .myDrafts: return .brandNavy` → `case .myDrafts: return Theme.textPrimary`.

- [ ] **Step 6: Grep + build.**

```bash
cd /Users/Trey/Desktop/PlayerPath && grep -n "brandNavy" PlayerPath/CoachFolderComponents.swift PlayerPath/CoachFolderDetailView.swift PlayerPath/CoachVideoUploadView.swift PlayerPath/Views/Coach/ReviewQueueCard.swift
```
Expected: no output. Build → `BUILD SUCCEEDED`.

- [ ] **Step 7: Sim check.**
  - Coach Dashboard: the My Drafts card is warm ink and Needs Your Review is terracotta (Review Focus #3).
  - A folder: the "Updated" check is green, tag chips are cream/olive, the refresh glyph is visible, and batch-select checkmarks are terracotta.
  - Coach Upload: the ✓ is green and the Upload button is terracotta.

- [ ] **Step 8: Commit.**

```bash
git add PlayerPath/CoachFolderComponents.swift PlayerPath/CoachFolderDetailView.swift PlayerPath/CoachVideoUploadView.swift PlayerPath/Views/Coach/ReviewQueueCard.swift
git commit -m "Coach folders + upload + queues: navy retired (accent, success green, cue chips, ink drafts)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Coach athletes, sessions, invites, profile

**Files:**
- Modify: `PlayerPath/Views/Coach/CoachAthletesTab.swift` (`:65, 84, 99`)
- Modify: `PlayerPath/Views/Coach/CoachMultiAthleteView.swift` (`:46, 91, 93, 127`)
- Modify: `PlayerPath/Views/Coach/StartSessionSheet.swift` (`:107, 111, 123, 173, 208`)
- Modify: `PlayerPath/Views/Coach/InviteAthleteSheet.swift` (`:69, 74, 164, 171, 206`)
- Modify: `PlayerPath/Views/Coach/PendingSentInvitationsBanner.swift` (`:29, 48`)
- Modify: `PlayerPath/CoachProfileView.swift` (`:39, 44, 62, 110, 194`)
- Modify: `PlayerPath/Views/Coach/CoachDowngradeSelectionView.swift:163`
- Modify: `PlayerPath/Views/Coach/AthleteCoachVideosView.swift:101`

- [ ] **Step 1: Environment reads.** Add `@Environment(\.ppAccent) private var ppAccent` under the declarations of `struct CoachMultiAthleteView`, `private struct AthleteComparisonRow`, `struct StartSessionSheet`, `struct InviteAthleteSheet`, `struct PendingSentInvitationsBanner`, `struct CoachProfileView` and `struct AthleteCoachVideosView`.

- [ ] **Step 2: Deletes (R4).**
  - `CoachAthletesTab.swift`: delete all three `.foregroundColor(.brandNavy)` lines (under `envelope.badge`, `record.circle` and `ToolbarSymbol.more`).
  - `CoachDowngradeSelectionView.swift`: delete the line `.tint(.brandNavy)`.

- [ ] **Step 3: CoachMultiAthleteView.**
  - The empty glyph: `.foregroundColor(.brandNavy.opacity(0.4))` → `.foregroundColor(ppAccent.opacity(0.4))`.
  - `AthleteComparisonRow` avatar: `.foregroundColor(.brandNavy)` → `.foregroundColor(ppAccent)`; `.background(Color.brandNavy.opacity(0.1))` → `.background(ppAccent.opacity(0.1))`.
  - `StatPill` icon (R3): `.foregroundColor(.brandNavy)` → `.foregroundColor(Theme.textSecondary)`.

- [ ] **Step 4: StartSessionSheet (R1).** `Color.brandNavy.opacity(0.1)` → `ppAccent.opacity(0.1)`; both `.foregroundColor(.brandNavy)` → `.foregroundColor(ppAccent)`; `selectedAthleteIDs.isEmpty ? Color.gray : Color.brandNavy` → `selectedAthleteIDs.isEmpty ? Color.gray : ppAccent`; `.background(Color.brandNavy)` → `.background(ppAccent)`.

- [ ] **Step 5: InviteAthleteSheet (R1).** `Color.brandNavy.opacity(0.1)` → `ppAccent.opacity(0.1)` (both: the header circle and the info box); both `.foregroundColor(.brandNavy)` → `.foregroundColor(ppAccent)`; `canSend ? Color.brandNavy : Color.gray` → `canSend ? ppAccent : Color.gray`.

- [ ] **Step 6: PendingSentInvitationsBanner (R1).** `.foregroundColor(.brandNavy)` → `.foregroundColor(ppAccent)`; `.background(Color.brandNavy.opacity(0.06))` → `.background(ppAccent.opacity(0.06))`.

- [ ] **Step 7: CoachProfileView (R1).** `Color.brandNavy.opacity(0.1)` → `ppAccent.opacity(0.1)`; all three `.foregroundColor(.brandNavy)` (the avatar initial, the "Coach Account" seal, the "Upgrade/Manage Plan" label) → `.foregroundColor(ppAccent)`; `.background(Color.brandNavy)` (the pending-count capsule) → `.background(ppAccent)`.

- [ ] **Step 8: AthleteCoachVideosView (R1; dead code, recolored for the count).** `.foregroundColor(.brandNavy)` → `.foregroundColor(ppAccent)`.

- [ ] **Step 9: Grep + build.**

```bash
cd /Users/Trey/Desktop/PlayerPath && grep -n "brandNavy" PlayerPath/Views/Coach/CoachAthletesTab.swift PlayerPath/Views/Coach/CoachMultiAthleteView.swift PlayerPath/Views/Coach/StartSessionSheet.swift PlayerPath/Views/Coach/InviteAthleteSheet.swift PlayerPath/Views/Coach/PendingSentInvitationsBanner.swift PlayerPath/CoachProfileView.swift PlayerPath/Views/Coach/CoachDowngradeSelectionView.swift PlayerPath/Views/Coach/AthleteCoachVideosView.swift
```
Expected: no output. Build → `BUILD SUCCEEDED`.

- [ ] **Step 10: Sim check.**
  - Athletes tab: the toolbar glyphs are visible (Review Focus #2).
  - Compare Athletes: the avatars are terracotta and the stat icons grey.
  - Start Session: Review Focus #5.
  - Invite Athlete: the header, info box and Send are terracotta.
  - Profile: the avatar, "Coach Account" seal, Upgrade Plan and pending-count capsule are terracotta.

- [ ] **Step 11: Commit.**

```bash
git add PlayerPath/Views/Coach/CoachAthletesTab.swift PlayerPath/Views/Coach/CoachMultiAthleteView.swift PlayerPath/Views/Coach/StartSessionSheet.swift PlayerPath/Views/Coach/InviteAthleteSheet.swift PlayerPath/Views/Coach/PendingSentInvitationsBanner.swift PlayerPath/CoachProfileView.swift PlayerPath/Views/Coach/CoachDowngradeSelectionView.swift PlayerPath/Views/Coach/AthleteCoachVideosView.swift
git commit -m "Coach athletes, sessions, invites, profile: accent replaces navy; toolbar/tint navy removed

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Athlete-side coach screens + wrap-up

**Files:**
- Modify: `PlayerPath/Views/Coaches/CoachDetailView.swift` (`:29, 103, 119, 135, 148`)
- Modify: `PlayerPath/Views/Coaches/ShareToCoachFolderView.swift:138`
- Modify (memory, not the repo): `project_ios26_liquid_glass_chrome.md`, `MEMORY.md`

- [ ] **Step 1: Environment reads.** Add `@Environment(\.ppAccent) private var ppAccent` under `struct CoachDetailView: View {` and `struct ShareToCoachFolderView: View {`. These are athlete screens, so this resolves to the sport accent.

- [ ] **Step 2: CoachDetailView.** The avatar glyph and both `folder.fill` icons: `.foregroundColor(.brandNavy)` → `.foregroundColor(ppAccent)` (R1). The two `Link` lines (phone, email): delete `.foregroundColor(.brandNavy)` so the Link takes the tint (R4).

- [ ] **Step 3: ShareToCoachFolderView.** The selected-folder checkmark: `.foregroundColor(.brandNavy)` → `.foregroundColor(ppAccent)`.

- [ ] **Step 4: Grep (whole batch) + build.**

```bash
cd /Users/Trey/Desktop/PlayerPath && grep -n "brandNavy" PlayerPath/Views/Coaches/CoachDetailView.swift PlayerPath/Views/Coaches/ShareToCoachFolderView.swift; grep -rn "brandNavy" PlayerPath | wc -l
```
Expected: no file hits, then **97**. Build → `BUILD SUCCEEDED`.

- [ ] **Step 5: Sim check.** Review Focus #4: as a golf athlete, More → Coaches → a coach, and the icons are green with green links; share a clip to a coach folder, and the checkmark is green. Repeat with a baseball athlete for terracotta.

- [ ] **Step 6: Commit.**

```bash
git add PlayerPath/Views/Coaches/CoachDetailView.swift PlayerPath/Views/Coaches/ShareToCoachFolderView.swift
git commit -m "Athlete coach screens: sport accent replaces navy

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 7: Run `/review`** on the batch range, fix what's real, and commit the fixes as "Batch 4b review fixes: …".

- [ ] **Step 8: Update memory.** Add a "Coach navy remainder (batch 4b)" paragraph to `project_ios26_liquid_glass_chrome.md`:
  - the commit range
  - the rules R1–R4 + E1–E3, including the author color: coach = accent, athlete = secondary
  - the count (97). The remaining navy is outside the coach suite: the retired `DashboardView` (14), GettingStarted, ProfileImageManager, stats/golf views, and so on.
  - that `AthleteCoachVideosView` is dead code
  - which sim checks are pending

Update the MEMORY.md hook.
