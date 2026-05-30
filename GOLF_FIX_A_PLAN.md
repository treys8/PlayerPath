# Stream A — Golf Scoring Total Integrity (C2 + S3)

_Plan grounded in full reads of every touched file. No schema change. Additive computed properties + 6 small edits._

## The bugs

**C2** — `Game.totalScore` is a persisted scalar written in exactly one per-hole place (`ScoreHoleSheet.save`) and **only when all holes are entered** (`if scoreByHole.count == total`). It and the `HoleScore` rows sync in two independent passes. So a 17-of-18 round leaves `totalScore == nil`; Device B pulls the 17-hole grid but the round is **invisible** in `GolfStatsSection` (filters `totalScore != nil`) and shows "Not scored" in `GameRow`. Grid and stats disagree.

**S3** — `EnterScoreSheet.save()` writes `game.totalScore` from a typed number ignoring `holeScores`; `ScoreHoleSheet` writes it from the hole sum. Both reachable from `GameDetailView`. Type "72", then per-hole-score a few holes → the two totals silently disagree.

## Design — derive the total, keep the scalar as a synced mirror

Per-hole rows are the source of truth. The persisted `totalScore` scalar is demoted to **(a)** the value for quick-entry rounds with zero per-hole data, and **(b)** a cross-device fallback shown before the per-hole rows replicate. Read sites derive; the scalar is mirrored on every per-hole save so it never goes stale by more than one sync hop.

```
holeScoreSum  = holeScores empty ? nil : sum(scores)      // derived, live
effectiveTotalScore = holeScoreSum ?? totalScore          // single read API
```

Why this over recomputing in the sync layer: with derived reads, any device renders the correct total from whatever rows it currently holds — no `reconcileHoles` change needed, and no needsSync ping-pong risk. The scalar mirror only has to cover the "rows not arrived yet" window, which it does. (There is no single-hole delete UI today; hole tombstones only occur via `deleteGameDeep`, which removes the whole game — so the stale-scalar-after-delete case is moot.)

Stats inclusion gate moves from `totalScore != nil` to `!isLive` (+ has-score). A live round is in-progress → excluded from averages (preserving intent); an ended/historical round counts. Verified: End Round sets `isComplete=true` (GameDetailView:413-416); EnterScoreSheet sets `isComplete` for non-live (EnterScoreSheet:137); practice rounds already derive live and are untouched.

## Edits

### 1. `Models.swift` (Game) — add derived helpers (after line 108, near the golf fields)
```swift
/// Sum of per-hole scores, or nil when no holes have been scored. The live
/// source of truth for a per-hole-scored round.
var holeScoreSum: Int? {
    let holes = holeScores ?? []
    return holes.isEmpty ? nil : holes.reduce(0) { $0 + $1.score }
}
/// Single read API for a round's total: derived hole sum when scored per hole,
/// else the quick-entry scalar. Use this everywhere instead of `totalScore`.
var effectiveTotalScore: Int? { holeScoreSum ?? totalScore }
```
Update the `totalScore` doc comment to say it's a mirror of the hole sum (for per-hole rounds) / the typed value (quick-entry), and that readers should prefer `effectiveTotalScore`.

### 2. `Views/Games/ScoreHoleSheet.swift` — mirror running sum on EVERY save (replace lines 266-274)
Drop the `let total = g.holes` / `count == total` gate. Build the same dedupe-safe `[holeNumber: score]` map (still folds in the just-upserted row), write the sum unconditionally, dirty only on change:
```swift
if case .game(let g) = parent {
    var scoreByHole: [Int: Int] = [:]
    for h in (g.holeScores ?? []) { scoreByHole[h.holeNumber] = h.score }
    scoreByHole[holeNumber] = score
    let sum = scoreByHole.values.reduce(0, +)
    if g.totalScore != sum { g.totalScore = sum; g.needsSync = true }
}
```

### 3. `Views/Stats/GolfStatsSection.swift` — gate + derive (3 spots)
- `tournamentRounds` filter (line 31): `$0.season?.sport == .golf && !$0.isLive && $0.effectiveTotalScore != nil`
- `tournamentScores` (line 55): `tournamentRounds.compactMap { $0.effectiveTotalScore }`
- chart `LineMark`/`PointMark` (line 157): `if let score = round.effectiveTotalScore, let date = round.date`

### 4. `Views/Games/GameDetailView.swift` — display from derived (line 165)
`if let score = game.effectiveTotalScore {` (and the existing `else` "Enter Score" button now only shows for a truly unscored round). The Edit-Score branch (line 260 `game.totalScore != nil`) → `game.effectiveTotalScore != nil`.

### 5. `Views/Games/GameRow.swift` — display from derived (line 106)
`if let totalScore = game.effectiveTotalScore {`

### 6. `Views/Games/EnterScoreSheet.swift` — lock the typed total when per-hole exists (S3)
When `!(game.holeScores ?? []).isEmpty`: render Total Score as a read-only derived value (`game.effectiveTotalScore`) with caption "Calculated from per-hole scores", and have `save()` skip writing `totalScore` (only persist `holes`/`par`). Keeps par/holes editable; removes the two-writer divergence. Quick-entry (no holes) path unchanged.

## Out of scope (other streams)
- `SyncCoordinator+HoleScores.reconcileHoles` — intentionally NOT modified (see design rationale).
- Reels (S1/S2), export (C1), highlights (A2) — Streams B/C.

## Verification
1. Build green on iPhone 17 Pro simulator.
2. Live golf round, score 3 of 18 holes → GameRow + Score section + (after End Round) GolfStatsSection all show the 3-hole sum; round visible in averages once ended, hidden while live.
3. Quick-entry round (EnterScoreSheet, no holes) → still works, counts after save.
4. Type a total then score holes → EnterScoreSheet shows the derived total read-only; no divergence.
5. Edit an existing hole's score → total updates everywhere.
