# Journal Mode / Track Statistics Toggle — Session Summary

**Date:** 2026-04-17 through 2026-04-19
**Status:** Implemented, builds clean, ready for simulator QA. Not yet committed.

## Feature

Per-athlete toggle that disables play-result tagging at record time and suppresses new stat accumulation. Existing tagged clips and stats remain intact. Intended for users who want to use the app as a pure video journal.

## Key Product Decisions

- **Naming:** "Track Statistics" (positive framing), not "Journal Mode." Stored as `Athlete.trackStatsEnabled: Bool = true`.
- **Per-athlete, not account-wide.** Multi-athlete accounts can mix modes.
- **Default ON.** Existing athletes keep current behavior after migration.
- **AddAthleteView toggle shown for second+ athletes only.** First-athlete onboarding stays clean to preserve the stats pitch.
- **No TipKit tip** — three visible UI surfaces cover discoverability (Profile nav link, swipe action, Stats banner).
- **No Firestore deployment needed** — rules have no field allowlist on athletes, no Cloud Function touches athlete fields, old docs decode missing field as nil and default to true.

## Files Modified

### Data layer
- `PlayerPath/Models/Athlete.swift` — added `trackStatsEnabled: Bool = true` + `toFirestoreData()` entry
- `PlayerPath/PlayerPathSchema.swift` — SchemaV16 log entry + migration stage
- `PlayerPath/PlayerPathApp.swift` — `SchemaV15.models` → `SchemaV16.models` (both occurrences)
- `PlayerPath/FirestoreModels.swift` — `trackStatsEnabled: Bool?` added to `FirestoreAthlete`
- `PlayerPath/FirestoreManager+EntitySync.swift` — added to `updateAthlete` allowlist
- `PlayerPath/SyncCoordinator+Athletes.swift` — decode in update branch + create-new-from-remote branch
  - Drive-by fix: also propagated `primaryRole` in the create-new branch (was pre-existing bug where new devices lost role)

### Recording
- `PlayerPath/DirectCameraRecorderView.swift` — new branch in `playResultPhaseView` before practice branch. When `athlete?.trackStatsEnabled == false`, shows a "Saving..." overlay and auto-saves with `playResult: nil`. Reuses existing `didAutoSave` flag (coach auto-save pattern). Accessibility label added.

### Settings UI
- `PlayerPath/Views/Athletes/EditAthleteView.swift` — **new file**. Form with Track Statistics toggle. No internal NavigationStack (callers supply). Uses `.onDisappear` for sync trigger (covers Done, back arrow, swipe-dismiss uniformly). Done button just calls `dismiss()`.

### Navigation / Entry Points
- `PlayerPath/ProfileView.swift`:
  - `AthleteProfileRow`: info button (44x44 tap target), "Stats off" orange badge in caption when tracking off, leading swipe action "Settings"
  - `athletesSection`: new "Athlete Settings" NavigationLink between Manage Athletes and Manage Seasons — pushes EditAthleteView for selected athlete, grayed-with-hint when none selected
- `PlayerPath/Views/Athletes/AddAthleteView.swift` — `trackStats` @State (default true), Toggle section between name field and Create button, only rendered when `!isFirstAthlete`. Applied during save.
- `PlayerPath/StatisticsView.swift` — "Stat tracking is off for [Name]" banner at top of contentView, with "Turn On" button that presents EditAthleteView. Sheet attached at stable parent (not banner) to survive banner unmounting when toggling ON inside the sheet. Manual-entry toolbar options hidden when tracking off.

## Discoverability Surfaces

| Entry | Taps | Context |
|---|---|---|
| Profile → Athlete Settings | 2 | Primary labeled path |
| Profile/Manage Athletes → swipe athlete row | 1 swipe + 1 tap | Power shortcut |
| Profile/Manage Athletes → ⓘ on row | 2 | Visible affordance in row |
| Stats tab → banner "Turn On" | 1 tap | Re-enable path |
| AddAthleteView toggle | creation-time | Second+ athletes only |

## Verified Clean

- Builds succeed (xcodebuild -project PlayerPath.xcodeproj -scheme PlayerPath -sdk iphonesimulator)
- Schema migration is lightweight (default value = true)
- Role param is dead code when playResult == nil (`ClipPersistenceService.swift:361-362`) — no coercion needed for `.both`
- GameRow stat badge auto-hides for journal-mode athletes (`atBats > 0` guard, pre-existing)
- Firestore `updateAthlete` allowlist updated — field won't be silently stripped
- `FirestoreAthlete.trackStatsEnabled: Bool?` decodes missing field as nil → defaults to true (backward compat with existing docs)
- Sheet lifecycle stable (sheet on parent, not on conditionally-rendered banner)
- `.onDisappear` single source of truth for sync trigger — works for all exit paths
- Info button has 44x44 tap target (HIG compliance)
- AddAthleteView toggle spacing symmetric (no extra top padding)
- Trimmer-skip path (short clips) covered — both paths land in `.tagging` phase

## Verified Safe (Not Changed)

- Coach recording flow — unaffected (different branch)
- BulkVideoImportSheet — no tagging step there
- PlayResultEditorView — still available for manual post-hoc tagging
- Highlights — auto-highlights just empty in journal mode (consistent behavior)
- Practices — still use PracticeVideoSaveView

## Known Follow-Ups (Out of Scope)

- `WeeklySummaryScheduler.scheduleAll(for: user)` may schedule confusing "0 hits this week" notifications for journal-mode athletes. Worth a check in a follow-up PR.
- If `firestore.rules` ever adds a field-level allowlist to athletes, remember to include `trackStatsEnabled`.

## What's Left

- Simulator QA (build clean, but haven't run the app)
- Git commit (currently uncommitted — see `git status` on main branch)
- Version bump via `./increment_build_number.sh` when ready to ship

## Context for New Session

- App: PlayerPath (iOS baseball/softball tracking, SwiftUI + SwiftData + Firebase)
- Bundle ID: RZR.DT3
- v5.0 was first App Store release (~2026-03-30)
- User instructions (via memory): keep files small and focused, spend time thinking upfront, plans need deep research not shallow sketches, tooltips use TipKit not custom overlays
- Local-first architecture with `SyncCoordinator` handling SwiftData ↔ Firestore sync via `needsSync` dirty flags
