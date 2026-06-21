# Unified Golf Hole Scoring — Quick + Shot-by-Shot in One Sheet

**Date:** 2026-06-21
**Status:** Approved design, ready for implementation plan
**Area:** Golf scoring (SwiftUI, SchemaV30 — no schema change)

## Problem

Tapping **"Score Hole N"** opens the quick hole-at-a-time sheet (`ScoreHoleSheet`:
par / score / putts / fairway / GIR / penalties). The fully-built shot-by-shot
engine (`ShotEntryView`, `ShotRollup`, `Shot` model, sync) is only reachable when
the round's `tracksShotByShot` flag was flipped on — at round creation or via a
mid-round toggle the user has to discover. Result: the natural scoring action
never surfaces shot-by-shot, and on the **Dashboard live card the shot-by-shot
view is unreachable entirely** (`DashboardView.swift:345/347` presents
`ScoreHoleSheet` on both branches).

For golf, shot-level stats are the product's strongest differentiator ("the
statistics are more valuable than the video"). The entry point must make
shot-by-shot a first-class, per-hole choice — not a hidden round-level gate.

## Goals

1. Tapping "Score Hole" opens **one unified sheet** with a `Quick | Shot-by-shot`
   switch; the user picks per hole.
2. The choice is **sticky** (remembered for the round, and across rounds) so a
   shot-tracker never re-picks, without any round-creation decision.
3. **Redesign the shot-by-shot card** (Direction B — approved in visual
   brainstorming): a whole-hole timeline of tap-to-edit shots, 1–2 taps per shot,
   inline distance entry (no modal popup), slim header, cleaner hierarchy.
4. Preserve every existing invariant: `ShotRollup` → `GolfScoreWriter` stays the
   single derivation path; the two-writer guard, soft-delete filter, and sync
   parity are untouched. **No schema change.**

## Non-Goals

- No Strokes Gained / dispersion / cross-round trends (still deferred Plus v2;
  `distanceBefore` continues to be captured for it).
- No change to the `Shot` model, `FirestoreShot`, `SyncCoordinator+Shots`,
  `ShotRollup`, `ShotStats`, `ShotLieChain`, or `ShotClubRecommender` logic.
- No change to Quick mode's captured fields or its `GolfScoreWriter` save path.

## Current State (verified)

**Routing (the gate to remove):**
- `GameDetailView.swift:474-483` — `.sheet(item: $scoreHoleTarget)`:
  `if game.tracksShotByShot || holeHasShots(target.holeNumber) { ShotEntryView } else { ScoreHoleSheet }`
- `PracticeDetailView.swift:316-323` — identical pattern for `practice`.
- `DashboardView.swift:342-348` — `.sheet(item: $liveScoreTarget)` presents
  `ScoreHoleSheet` on **both** game/practice branches (shot-by-shot unreachable).
- `HoleScoreGrid` re-tap calls the parent's `onTap`, which sets
  `scoreHoleTarget` in the detail views — so it's covered by the detail-view
  sheet change; no direct edit to `HoleScoreGrid`.

**Toggles (to remove):**
- `GameCreationView.swift:185-186` `Toggle("Track Shots")` + `@State golfTracksShots`
  (line 50) + passes `tracksShotByShot: golfTracksShots` (line 431).
- `AddPracticeView.swift:95-96` `Toggle("Track Shots")` + `@State trackShots`
  (line 33) + sets `practice.tracksShotByShot` (line 215).
- `GameDetailView.swift:281-283` `Toggle("Track Shots", isOn: shotTrackingBinding)`
  + `shotTrackingBinding` (≈lines 54-58).
- `PracticeDetailView.swift` `shotTrackingBinding` (≈lines 58-60) + its toggle UI.

**Persistence:** `Game.tracksShotByShot` / `Practice.tracksShotByShot`
(`Models.swift:127`, `Models.swift:362`) and their Firestore round-trip stay as
they are — the field is reused, not removed.

**Two-writer invariant (honor):** a hole that already has live shots
(`GolfRoundRef.hasShots(onHole:)`, `HoleDetailView.swift:85`) is owned by
`ShotRollup` and is read-only in `GolfScorecardView`. `ShotEntryView`'s
`hadPriorScore` guard prevents a partial shot log from clobbering a pre-existing
quick score.

## Design

### 1. `HoleScoringSheet` — the unified wrapper

New file `Views/Games/HoleScoringSheet.swift`. Owns the `NavigationStack`, the
`Quick | Shot-by-shot` segmented switch (just under the title), a **mode-aware
toolbar**, and the presentation detents. Constructed with the same XOR-parent
pattern as the existing sheets:

```
HoleScoringSheet(game: Game, holeNumber: Int)
HoleScoringSheet(practice: Practice, holeNumber: Int)
```

It renders one of two **content** subviews (each stripped of its own
NavigationStack/toolbar):
- **Quick** → `QuickScoreContent` (extracted from today's `ScoreHoleSheet`).
- **Shot-by-shot** → `ShotByShotContent` (the rebuilt Direction-B card).

**Mode-aware toolbar:**
- Quick: `Cancel` / `Save` (explicit save, exactly as `ScoreHoleSheet` today).
- Shot-by-shot: `Done` (each shot already persists live via `GolfScoreWriter`).

**Detents:** allow `[.medium, .large]`, default `.large` so the shot timeline has
room; Quick still works at either.

### 2. Which mode opens

On appear, pick the initial mode (`@State mode: ScoringMode`):

1. Hole **has live shots** → `.shotByShot`, **locked** (Quick segment disabled).
   It's `ShotRollup`-owned.
2. Hole has an existing `HoleScore` with `score > 0` and **no shots** → `.quick`
   (you're editing what's already there).
3. New hole → the round's remembered default: `round.tracksShotByShot ? .shotByShot : .quick`.

### 3. Sticky default replaces both toggles

- A new global preference `GolfPrefs.preferredShotByShot` (`@AppStorage`, sits
  beside the existing `GolfPrefs.trackDetailedStats`).
- When the user flips the in-sheet segment, write **both** `round.tracksShotByShot`
  (so the rest of this round defaults to it) **and** `GolfPrefs.preferredShotByShot`
  (so future rounds inherit it). Persist the round flag with
  `ErrorHandlerService.shared.saveContext` + `needsSync`/`version` bump, mirroring
  the current mid-round toggle's write.
- At round creation, seed `tracksShotByShot` from `GolfPrefs.preferredShotByShot`
  instead of a visible toggle:
  - `GameCreationView`: drop the toggle UI + `golfTracksShots` state; set
    `GolfRoundDetails.tracksShotByShot = GolfPrefs.preferredShotByShot` (read at
    submit). `GameService.createGame` is unchanged.
  - `AddPracticeView`: drop the toggle UI + `trackShots` state; set
    `practice.tracksShotByShot = (practiceType == .practiceRound) && GolfPrefs.preferredShotByShot`.
- Remove the mid-round `Toggle("Track Shots")` rows + `shotTrackingBinding` from
  `GameDetailView` and `PracticeDetailView` — the sheet is the control now.

The two-writer guard is unaffected: a hole that has shots still locks to
shot-by-shot regardless of the flag (`hasShots(onHole:)` and the `hadPriorScore`
guard remain the source of truth — the flag is only the *default mode* hint).

### 4. `ShotByShotContent` — Direction B redesign

Rebuild `ShotEntryView`'s body as `ShotByShotContent` (same state, same
`commit`/`persist`/`deleteLast`/`beginEdit` logic, same `ShotRollup` derivation —
**only the layout changes**):

- **Slim header (one line):** `Hole N · [Par n ▾] · {yardage}y` on the left
  (Par is a tappable chip → menu, as today), compact running score on the right
  (`derivedInput.score` colored `.parRelative`). Replaces the chunky tinted
  `headerCard`. Yardage shown only if known; omit otherwise.
- **Timeline:** each logged shot is a compact `ShotLogRow` (new small file
  `Views/Games/ShotLogRow.swift`): `① · {club} · {lie} → {outcome} · {distance}`.
  Tap a row → it becomes the active/editable card in place (drives the existing
  `beginEdit`). Swipe / explicit control to delete **any** shot (today's
  `deleteLast` only removes the last): apply the same soft-delete-if-synced rule,
  then **renumber the remaining live shots' `shotNumber`** (sort field) and bump
  their `needsSync`/`version` so the reorder syncs and `ShotRollup` re-derives
  correctly. Replaces the small `progressDots`.
- **Active card (bottom of the timeline):** from-lie chip (auto-chained, tap to
  correct) · **inline distance** — tapping the distance pill reveals an inline
  `numberPad` field (replaces the `.alert` keypad in `ShotEntryView` lines
  131-144) · compact penalty control · `ShotClubGrid` (recommended highlighted) ·
  context-aware `ShotResultButtons`.
- **Advance:** tapping a result `commit`s the shot and opens the next card with
  the auto-chained lie (existing `ShotLieChain.nextLie`). Ball reaches the green →
  the active card becomes the **putts stepper** (seeded 2). `Holed` → completion
  card. Unchanged engine: `ShotRollup.deriveInput` → `GolfScoreWriter.upsertHole`
  / `mirrorTotalScore` / `upsertReelIfNeeded`.
- Keep the `!$0.isDeletedRemotely` soft-delete filter everywhere shots are read
  (already present in load/derive).

### 5. Quick mode unchanged

`QuickScoreContent` is today's `ScoreHoleSheet` body verbatim (par segmented,
score chips, optional putts behind the toggle, detailed FIR/GIR/penalties behind
`GolfPrefs.trackDetailedStats`) and its `save()`. Only the surrounding
NavigationStack/toolbar move up to `HoleScoringSheet`.

### 6. Refactor shape (small, focused files)

| File | Change |
|---|---|
| `Views/Games/HoleScoringSheet.swift` | **New** — wrapper: mode state/switch, mode-aware toolbar, detents, parent XOR init |
| `Views/Games/ScoreHoleSheet.swift` | Extract body → `QuickScoreContent` (no NavigationStack/toolbar); `save()` exposed to wrapper. Keep file small |
| `Views/Games/ShotEntryView.swift` | Rebuild body → `ShotByShotContent` (Direction-B layout); inline distance; same state/persist logic |
| `Views/Games/ShotLogRow.swift` | **New** — one logged-shot timeline row (tap-to-edit, delete) |
| `Views/Games/GameDetailView.swift` | Present `HoleScoringSheet`; remove if/else routing, `Toggle("Track Shots")`, `shotTrackingBinding` |
| `Views/Practices/PracticeDetailView.swift` | Same as GameDetailView |
| `Views/Dashboard/DashboardView.swift` | Present `HoleScoringSheet` on both `liveScoreTarget` branches |
| `Views/Games/GameCreationView.swift` | Drop toggle + `golfTracksShots`; seed `tracksShotByShot` from `GolfPrefs.preferredShotByShot` |
| `Views/Practices/AddPracticeView.swift` | Drop toggle + `trackShots`; seed from `GolfPrefs.preferredShotByShot` |
| `GolfPrefs` (where `trackDetailedStats` lives) | Add `preferredShotByShot` key |

## Edge Cases

- **Switch Quick→Shot-by-shot on a hole with a saved quick score:** opens in
  Quick (rule 2); switching is allowed; `hadPriorScore` guard holds the saved
  score until the hole is fully re-logged (`isComplete`).
- **Switch attempt on a hole with shots:** Quick segment disabled (rule 1) — no
  path to two-write a shot-derived hole.
- **Uncommitted quick draft, then switch to shot-by-shot:** the quick draft is
  unsaved state; switching discards it (shot mode writes live). Acceptable — no
  data was committed.
- **Mode flip writes the round flag:** must bump `needsSync`/`version` +
  `saveContext` so the changed default syncs (parity with the removed mid-round
  toggle).
- **Dashboard live card:** now reaches shot-by-shot for the first time — verify
  the live "Score Hole X" CTA opens the unified sheet and derives correctly.

## Testing / Device Checklist

1. New golf round (no creation toggle): first Score Hole opens in the
   `GolfPrefs.preferredShotByShot` default; switching the segment sticks for the
   next hole and the next round.
2. Shot-by-shot: log a par-4 (drive → approach with inline distance → green →
   2 putts); derived score / FIR / GIR / putts land on the scorecard + totals +
   birdie reel; Firestore docs at `.../holes/{n}/shots/{uuid}`.
3. Tap a logged timeline row → edit in place → save; delete a synced shot →
   soft-delete tombstone reconciles on a 2nd device.
4. Quick mode unchanged: par/score/putts/FIR/GIR/penalties save as before.
5. Hole with shots → Quick segment disabled. Hole with a prior quick score →
   opens Quick, can upgrade to shot-by-shot without clobbering.
6. Dashboard live card "Score Hole X" → unified sheet, shot-by-shot reachable.
7. `tracksShotByShot` still round-trips through Firestore (game + practice).
8. Build: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild
   -project PlayerPath.xcodeproj -scheme PlayerPath -sdk iphonesimulator
   -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build` (use
   `clean build` if a stale @Model macro cache trips a false "does not conform").

## Out of Scope

Strokes Gained / dispersion / cross-round trend stats (Plus v2), any `Shot`
schema or sync changes, and changes to Quick mode's captured fields.
