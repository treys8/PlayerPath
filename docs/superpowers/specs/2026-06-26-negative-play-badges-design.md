# Negative-Play Badge Treatment — Design

**Date:** 2026-06-26
**Status:** Approved design, pending implementation
**Scope:** How baseball/softball play-result badges represent *negative* outcomes
(outs, strikeouts, and — for pitchers — walks/hits allowed) across the app.

## Problem

Negative plays render inconsistently and, in two spots, misleadingly:

1. **Feed (`PPOutcomeChip`)** — a strikeout chip is visually identical to a
   non-highlighted single. The feed has only two tiers (accent for HR/highlight,
   neutral for everything else), so outs get no de-emphasis. Worse,
   `pitchingHomeRunAllowed` is currently routed to the **accent** fill — a home
   run hit *off* the pitcher reads as a celebrated highlight.
2. **`PlayResultType.color`** — colors encode the *play type, not the
   beneficiary*. For a pitcher this inverts meaning: a strikeout is alarm-red
   (good outcome, bad color) and hits/HR allowed are green/gold (bad outcome,
   good color).
3. **Dead, drifted abbreviation map** — `PlayResultType.abbreviation`
   (`Models/PlayResultType+Display.swift`) has zero consumers and disagrees with
   the live map `PPOutcomeChip.abbreviation(for:)` on `.strike` (`"S"` vs
   `"STR"`). A future call to `result.abbreviation` silently returns stale text.

## Design

### Unifier: `PlayResultType.valence`

Add one computed property measured from the **recording athlete's** point of
view. Single source of truth that drives the feed treatment and documents the
intent the color map must stay consistent with.

```swift
enum PlayValence { case positive, neutral, negative }

extension PlayResultType {
    var valence: PlayValence { ... }
}
```

| Valence | Cases |
|---|---|
| positive | single, double, triple, homeRun, walk, batterHitByPitch, strike, pitchingStrikeout |
| neutral | ball |
| negative | strikeout, groundOut, flyOut, wildPitch, pitchingWalk, hitByPitch, pitchingSingleAllowed, pitchingDoubleAllowed, pitchingTripleAllowed, pitchingHomeRunAllowed |

**Known limitation (documented, not fixed):** `groundOut`/`flyOut` are shared
enum cases used by both the batter editor (out = negative) and the pitcher
editor (induced out = positive for the pitcher). The clip stores no role flag to
disambiguate, so valence uses the batter framing (`negative`) — which also
matches their existing red color. No regression; just noted.

### A — De-emphasize negatives in the feed (quieter / recede)

In `PPOutcomeChip`, add a third visual tier for `valence == .negative`. The feed
then reads: **hits pop** (accent) → **routine plays neutral** → **outs recede**.

- New styles: `.negativeOnMedia` and `.negativeOnCard`.
  - `.negativeOnMedia`: quieter than `.darkTranslucent` — background
    `.black.opacity(0.35)` (vs 0.55), foreground `.white.opacity(0.75)`.
  - `.negativeOnCard`: foreground `Theme.textTertiary` on
    `Theme.divider.opacity(0.4)`.
- `init(result:overMedia:highlighted:)` routing becomes:
  1. `highlighted || result == .homeRun` → `.accent`
     *(drop `pitchingHomeRunAllowed` from the accent branch — it is negative)*.
  2. else if `result.valence == .negative` → `.negativeOnMedia` / `.negativeOnCard`.
  3. else → `.darkTranslucent` / `.neutralOnCard` (today's neutral).
- `isAccent` semantics unchanged (still true only for `.accent`), so the
  media-tile star de-dup logic in `JournalEntryRow` is unaffected.

Only the feed chip changes. Capture overlay, edit sheet, and stats are not
touched by part A.

### B — Collapse the dead abbreviation map

- Keep the model-level `PlayResultType.abbreviation`, but correct its values to
  match the live map (`.strike` → `"STR"`; all others already agree).
- Point `PPOutcomeChip.abbreviation(for:)` at `result.abbreviation` (or delete
  the static helper and call `result.abbreviation` from `init`).
- Net: one source of truth, **zero** visual change.

### C — Recolor pitching results for the pitcher's POV (full flip)

Edit `PlayResultType.color` pitching cases only. Batting colors unchanged.

| Case | Before | After |
|---|---|---|
| pitchingStrikeout | red | **green** |
| pitchingWalk | cyan | **red** |
| pitchingSingleAllowed | green | **red** |
| pitchingDoubleAllowed | green | **red** |
| pitchingTripleAllowed | green | **red** |
| pitchingHomeRunAllowed | gold | **red** |
| strike | green | green (keep) |
| ball | orange | orange (keep) |
| wildPitch | red | red (keep) |

This reverses the prior "hits-allowed reuse the batting-hit visuals" intent.
`PlayResultType.color` feeds the thumbnail placeholder gradient
(`displayTagColor`), the edit sheet (`PlayResultEditButton`, current-result
header), and the tagging overlay (`PlayResultButton`) — so the pitching
"Hits Allowed" buttons and a HR-allowed clip's placeholder will now read red.
That is the intended effect of the full flip.

No conflict with highlight logic: `PlayResultType.isHighlight` is true only for
batting hits, so no pitching case loses a highlight signal by changing color.

**Intentional carve-out:** `purple` is a deliberate, valence-independent
"special incident" bucket on **both** ends — `batterHitByPitch` (positive
valence: batter reaches base) and `hitByPitch` (negative valence: pitcher hits a
batter). Both keep purple rather than following valence to green/red; both were
outside the approved full-flip set (strikeout / walk / hits-allowed / HR-allowed)
and are unchanged by this work. They still get the correct feed chip via valence
(batterHitByPitch neutral, hitByPitch quiet/recede); only their `.color` stays
purple.

## Affected files

- `PlayerPath/Models/PlayResultType.swift` — add `PlayValence` + `valence`;
  remap pitching `color` cases (C).
- `PlayerPath/Models/PlayResultType+Display.swift` — fix `abbreviation` values (B).
- `PlayerPath/Views/Components/PP/PPOutcomeChip.swift` — new negative styles +
  init routing (A); repoint abbreviation to the model map (B).

No schema, sync, or Firestore surface is touched. No persisted data changes.

## Out of scope (YAGNI)

- Role flag on clips to disambiguate shared out cases — deferred.
- Changing batting colors, walk/HBP colors, or the stats `PlayResultsSection`
  palette.
- Any new color tokens — reuse existing `Theme`/opacity values.

## Verification

No automated tests exist in this project. Verify by:
1. Build succeeds (`xcodebuild ... build`).
2. Manual: a strikeout clip in the Journal feed shows a quiet chip; a
   highlighted hit still shows accent; a HR-allowed clip no longer shows accent.
3. Manual: pitcher editor "Hits Allowed" buttons render red; strikeout renders
   green.
