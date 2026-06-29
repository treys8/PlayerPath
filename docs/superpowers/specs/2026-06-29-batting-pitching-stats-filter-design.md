# Batting / Pitching Stats Filter — Design

**Date:** 2026-06-29
**Status:** Approved (pending spec review)
**Scope:** `PlayerPath/StatisticsView.swift` (one file, no schema/service changes)

## Problem

On the Stats tab ("The Numbers."), a **two-way** baseball/softball player — one with both
batting (`atBats > 0`) and pitching (`stats.hasPitchingData`) data — gets a single long
vertical scroll: the entire batting suite (hero card, comparison/key stats, batting chart,
detailed stats, play results) stacked **above** the full `PitchingStatsSection`, then
milestones. Reaching pitching means scrolling past everything batting.

Pure hitters and pure pitchers do not have this problem: pitching only renders when
`hasPitchingData`, and a pure pitcher has `atBats == 0`.

## Solution

Add a **segmented Batting / Pitching toggle** that shows **only for two-way players** and
renders one discipline's suite at a time.

### Gating rule

- `hasBatting = stats.atBats > 0`
- `hasPitching = stats.hasPitchingData`
- **Both true** → render the segmented `Picker`, default to **Batting**.
- **Only one true** → no toggle; render that one suite (existing behavior for pure hitters;
  as a bonus, a pure pitcher no longer sees a zero-filled batting hero card — the batting
  suite is skipped).
- Golf path (`isGolf`) is untouched.

### Control

- New enum: `private enum StatMode { case batting, pitching }`
- New state: `@State private var statMode: StatMode = .batting`
- A `Picker("", selection:)` with `.pickerStyle(.segmented)`, pinned as the **first item in
  the `LazyVStack`** (inside the scroll content, not the toolbar — the toolbar already
  carries View Charts / Compare Seasons / season filter / actions, and a segmented control
  does not belong there).

### What each mode renders

| Section | Batting | Pitching |
|---|---|---|
| StatsHeroCard | ✅ | — |
| Career/Season comparison + KeyStatsSection | ✅ | — |
| BattingChartSection | ✅ | — |
| DetailedStatsSection | ✅ | — |
| PlayResultsSection | ✅ | — |
| PitchingStatsSection | — | ✅ |
| MilestonesListSection | ✅ (always) | ✅ (always) |

Milestones stay pinned at the bottom in **both** modes — milestones span both disciplines.

### Persistence

The `statMode` choice **persists across season / Career changes**. It is not reset when
`selectedSeasonFilter` changes.

**Edge case (handled by the gating rule, no extra code):** if the toggle is on Pitching and
the user switches to a season with no pitching data, `hasPitching` becomes false for that
selection, the toggle disappears, and the batting suite renders. `statMode` retains
`.pitching` in state but is ignored while only one discipline exists; it re-applies if they
switch back to a two-way selection.

## Out of scope (left as-is)

- **View Charts** sheet (`StatisticsChartsView`) — already has its own batting+pitching
  layout; does not react to the toggle.
- **Compare Seasons** sheet — unchanged.
- Toolbar buttons — unchanged.
- No new files, no schema bump, no service/sync changes.

## Implementation sketch

In `mainContent`, the baseball branch (currently the
`else if let stats = statistics, stats.atBats > 0 || stats.hasPitchingData` block):

1. Compute `hasBatting` / `hasPitching` from `stats`.
2. If both, emit the segmented `Picker` as the first `LazyVStack` child.
3. Wrap the batting sections (hero, comparison/key, batting chart, detailed, play results) in
   `if !hasPitching || statMode == .batting` (i.e. show batting when it's the only discipline
   or batting is selected).
4. Wrap `PitchingStatsSection` in `if hasPitching && (!hasBatting || statMode == .pitching)`.
5. `MilestonesListSection` stays unconditional at the bottom.

The existing outer condition already guarantees at least one of batting/pitching exists, so
the empty state is unaffected.
