# Stream D — Final Hardening Pass (S4 + A3.1–A3.4)

_Last stream of the golf-bug-fix effort. Grounded in full reads of every touched file. No schema change — pure logic/comment edits. Streams A/B/C logic untouched. Build green on iPhone 17 Pro. Implemented 2026-05-29, uncommitted. No rules deploy._

Judgment calls were surfaced before implementing; the user's decisions are recorded inline.

---

## S4 — playResult/club XOR guard *(IMPLEMENTED)*

**Bug:** the "a clip carries either a `playResult` (baseball/softball) or a `club` (golf), never both" invariant is documented in `VideoClip.swift:27`, `Club.swift:14`, `VideoClip+DisplayTag.swift:7` but enforced nowhere. `isTagged` is an `||` (`VideoClip+DisplayTag.swift:33-35`); `saveClip` sets `club` unconditionally (`ClipPersistenceService.swift:342`) while `playResult` + the stats-mutating `addPlayResult` (`:377`/`:389`) are conditional on `if let playResult`. A future caller passing both would corrupt stats (addPlayResult fires) and mis-display (`displayTagName` prefers `club`). No current caller violates it.

**Single guard point:** `saveClip` is the one choke point all clip creation flows through (recording, import, coach). One `assert` at the top — not scattered.

**Decision (user):** assert at entry only — debug tripwire, zero release cost, documents the contract; fires the moment a future dev adds a both-set caller in a debug build. (Release-safe precedence was rejected: it would silently drop the club and add code for an impossible case.)

**Edit — `ClipPersistenceService.swift`, first statement of `saveClip` body (before the `capturedHoleNumber` capture):**
```swift
// v6.1 S4: enforce the playResult/club XOR at the single clip-creation
// choke point. ... No current caller passes both; this assert is a debug
// tripwire for a future one.
assert(playResult == nil || club == nil,
       "VideoClip XOR violated: a clip cannot carry both a playResult and a club")
```

---

## A3.1 — Reel no-op re-save bumps version/needsSync *(IMPLEMENTED)*

**Bug:** `ScoreHoleSheet.upsertReelIfNeeded` alive-edit branch (`:348-359`) unconditionally rewrote all fields + `version += 1` + `needsSync = true` on every save → re-scoring a hole with an identical clip set/score emitted a redundant Firestore write.

**Fix:** content-diff before mutating; include `isDeletedRemotely` in the diff so a par→birdie undelete always goes through. Demotion branch (`:377`) already self-guards.

**Stream B compatibility (verified against `SyncCoordinator+HighlightReels.swift:111`):** the S1 reconcile guards `(remote.version ?? 0) >= local.version` and assumes version only increases on a real edit. A3.1 makes that assumption *strictly truer* (no bump on no-op); it never decreases or skips a bump on a real change. `date` updating only on real change is fine — it isn't part of S1's `differs` check. No convergence risk.

**Edit — `ScoreHoleSheet.swift`, replace the `if let existing` body inside the birdie path:**
```swift
let differs = existing.clipIDs != clipIDStrings
    || existing.score != score
    || existing.par != par
    || existing.displayName != displayName
    || existing.courseOrOpponent != course
    || existing.isDeletedRemotely
if differs {
    existing.clipIDs = clipIDStrings
    existing.score = score
    existing.par = par
    existing.displayName = displayName
    existing.courseOrOpponent = course
    existing.date = Date()
    existing.isDeletedRemotely = false
    existing.version += 1
    existing.needsSync = true
}
```

---

## A3.2 — Out-of-order hole scoring (`max(scored)+1`) *(JUDGMENT CALL — DEFERRED)*

**Finding:** 4 consistent sites — `LiveHoleTracker.swift:31,48`, `GameDetailView.swift:52-56`, `PracticeDetailView.swift:56-60`, `LiveGameCard.swift:131-134` — derive "next" as `max(scored)+1`, so scoring hole 5 first makes "next" jump to 6, not the lowest unscored hole. Internally consistent; **not a bug**.

**Decision (user): leave as-is.** Changing `LiveHoleTracker.currentHole` to "lowest unscored" would also re-target live clip→hole attribution (it's consumed at `ClipPersistenceService.saveClip` entry), turning a label tweak into a live-play behavior change. Scoring is near-always sequential; not worth the risk.

---

## A3.3 — Stale doc comments *(IMPLEMENTED)*

1. `SyncCoordinator+HoleScores.swift:10-11` — "Practice-round sync is wired up but… lands in PR3" → rewritten to "active (PR3)".
2. `VideoTagEditor.swift:6` — "Pre-populated with baseball-specific suggestions" → rewritten to note it's sport-aware (`isGolf` branch, see `VideoTagEditor+Golf.swift`).
3. *(Bonus, comment-only, no deploy)* `firestore.rules:250-252` carried the same stale "PR3 when practiceType accepts practice_round" note on the practice `holes` block → rewritten to "Active in PR3". Comments don't affect deployed behavior, so no deploy needed; the file now matches reality.

---

## A3.4 — Rules range/type checks *(JUDGMENT CALL — DEFERRED, NO DEPLOY)*

**Deployed state (verified `firestore.rules:224-229, 253-258, 280-285`):** all three golf paths (`games/{g}/holes/{n}`, `practices/{p}/holes/{n}`, `highlightReels/{r}`) are owner-scoped on every verb, no field validation. Payloads confirmed: holes write `holeNumber/par/score/version/isDeleted` (+ optional `putts`); reels add `clipIDs/displayName/courseOrOpponent/athleteID/date`.

**Decision (user): defer/skip.** Owner-scoping already contains the blast radius; range checks add deploy risk and could reject legitimate future writes (par-6 holes, 36-hole events, high stableford scores). Low value. **Nothing deployed by Claude.**

If revisited later, the shape would be generous helpers (e.g. `holeNumber 1–36`, `par 1–10`, `score 1–30`, `putts 0–20`, `clipIDs is list`) gating `create`/`update` only — and the deploy (`firebase deploy --only firestore:rules`) is the user's to run.

---

## Verification

- `xcodebuild -project PlayerPath.xcodeproj -scheme PlayerPath -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build` → **BUILD SUCCEEDED**, no `error:`.
- Manual (recommended): re-save an unchanged birdie hole → reel `version`/`needsSync` unchanged (no redundant write); par→birdie still undeletes + refreshes; birdie→par still soft-deletes.

## Status

S4, A3.1, A3.3 implemented. A3.2 + A3.4 deferred per user. **A1 (dual-enum / central `SportLabels` refactor) is now the only open review item.** Everything uncommitted; no rules deploy.
