# Golf Feature — Senior Engineering Review

_Reviewed 2026-05-29. Scope: the v6.0/v6.1 golf addition (multi-sport athletes, club tagging, tournaments, per-hole scoring, auto-highlight reels, live golf practices, course pre-fill) plus the uncommitted coach-side club surfacing. Findings were verified against current source, not just the design memos — several "critical" first-pass flags turned out to be false alarms and are listed as such so they don't get re-raised._

## Verdict

The golf **data + sync + rules layer is genuinely well-engineered** — clean schema versioning, correct lightweight migrations, a real concurrency fix for clip→hole attribution, idempotent reel upserts, connectivity-gated destructive reconciliation, and complete/owner-scoped security rules. That part was thought through.

The **sport abstraction and the "long tail" features were thrown in carefully rather than designed**: golf was patched onto a baseball schema per-call-site instead of behind an abstraction. The result is one real user-facing data bug (golf stat export), one real cross-device consistency bug (`Game.totalScore`), a reachable highlight-stripping bug, a handful of edit/delete edge cases in the new reel/score code, and accumulating maintainability debt (dual sport enum, no central label vendor, `activeSport` recomputed in ~11 files).

Net: **ship-able, but with a few fixes that should land before golf gets marketed**, plus a cleanup pass that pays for itself the moment a third sport or a serious golf-stats feature is attempted.

---

## ✅ What's done right (don't touch)

- **Schema V21→V26 are all lightweight, additive migrations**; current container registers `SchemaV26.models`. New `@Model`s (`HoleScore`, `HighlightReel`) + optional fields only.
- **Clip→hole attribution race fix is real and correct.** `ClipPersistenceService.saveClip` captures `LiveHoleTracker.shared.currentHole(...)` at function entry, before the multi-second copy/verify/thumbnail awaits, with a comment explaining the score-tap-between-yields hazard.
- **Current hole is derived (`max(scoredHole)+1`), never persisted** — avoids pointer/row drift. Gated on `isLive` + sport for clip attribution; detail screens intentionally derive inline so past rounds stay scorable.
- **Reel upsert is idempotent** on `(holeNumber, gameID|practiceID)` via a flat `FetchDescriptor<HighlightReel>` + manual filter (sidesteps SwiftData `#Predicate` optional-UUID equality). Demote→soft-delete and re-promote→undelete+refresh both handled.
- **Firestore rules are complete and safe.** All three golf paths (`games/{g}/holes/{n}`, `practices/{p}/holes/{n}`, `highlightReels/{r}`) are owner-scoped on every verb; the `seasons.sport` lock correctly allows first-set and blocks later mutation without blocking a legitimate golf write; coaches read golf clips' `club`/`holeNumber` via the existing whole-doc `videos` read rule.
- **The dual VideoClip parser hazard was honored.** Both `club` and `holeNumber` are present in *both* `FirestoreVideoMetadata` (Codable) and `VideoCloudManager.VideoClipMetadata` (manual), on read and write.
- **Coach-side club surfacing diff (uncommitted) is complete and safe to commit.** Closes the read-render gap *and* silently fixes a missing share-time write of `club`; no force-unwraps, untagged clips render cleanly, `Club(rawValue:)` falls back safely.

### False alarms (verified NOT bugs — do not re-flag)
- ~~Golf clips leaking into batting stats / auto-highlight on save~~ — both `addPlayResult` and `shouldAutoHighlight` live inside `if let playResult`, and the golf UI passes `playResult: nil`. Cannot fire for golf during recording. (Note: the *retroactive* rescan path is a separate, real issue — see A2.)
- ~~`FirestorePractice.isLive` decode failure on pre-V26 docs~~ — it's optional, so it decodes to `nil` (Codable doesn't throw on a missing optional), and the consumer explicitly guards `nil`.
- ~~Season sport syncs golf as baseball~~ — `SyncCoordinator+Seasons` uses `SportType(rawValue:) ?? .baseball`; golf round-trips correctly.

---

## 🔴 Critical — fix before promoting golf

### C1. Golf statistics export emits an all-zero **baseball** sheet
`StatisticsExportService` **and** `CSVExportService`/`PDFReportGenerator` both hardcode baseball columns (At Bats, Hits, AVG, OBP, SLG, OPS, 1B/2B/3B/HR…) with **zero** sport branching. A golf athlete who exports (a Plus/Pro feature; data that can reach college coaches) gets a document showing `At Bats: 0 … AVG: .000` and no score/round data. The golf stat fields already exist (`GolfStatsSection`, `HoleScore`).
- **Fix:** branch both stacks on `athlete.sport`/`season.sport`; emit golf columns (date, course, score, score-to-par, putts; GIR/fairways when added) + a golf `ReportType`/icon. Minimum bar: gate baseball export so a golf athlete can't generate a meaningless all-zero sheet.

### C2. `Game.totalScore` is never derived from per-hole `HoleScore`s → cross-device blank/stale rounds
`totalScore` is a standalone scalar written in one place (`ScoreHoleSheet.save`) and **only when all holes are entered on the entering device**. It and the `HoleScore` rows sync in two independent passes, so:
- Device A scores 17 of 18 holes → `totalScore` stays `nil`; Device B pulls the 17-hole grid but the round is **invisible** in `GolfStatsSection`/Dashboard (both filter `totalScore != nil`). B can't repair without re-saving the final hole.
- A remote hole tombstone (`reconcileHoles`) deletes a local `HoleScore` but never recomputes `totalScore`, leaving the scalar one hole too high.
- **Fix:** make the total a derived value (sum of non-deleted `holeScores`) at read time, or recompute-and-redirty it in the hole-sync pass / on any hole add/edit/delete. Practice rounds already derive live — mirror that.

---

## 🟠 Should-fix — correctness edge cases in the new reel/score code

### S1. HighlightReel field edits don't propagate cross-device
`syncHighlightReels` only *inserts* remote reels that don't exist locally (skip-if-`firestoreId`-exists). Unlike `reconcileHoles`, no `version`/`updatedAt` comparison — a reel whose `clipIDs`/score were corrected on Device A never updates Device B. Only create + soft-delete cross over; edits diverge silently. **Fix:** add the same version-based reconcile the hole-score path uses.

### S2. Reels go stale/orphaned when their clips are deleted
`VideoClip.delete()` does file/cloud/thumbnail cleanup but never touches `HighlightReel.clipIDs` (denormalized UUID strings). Delete every clip on a birdie hole → empty reel card the user can't remove; only cleaned if they re-save that hole's score. Players degrade gracefully (skip missing clips). **Fix:** on clip delete, drop its id from referencing reels and soft-delete any reel left empty.

### S3. Two un-reconciled total-score entry paths
`EnterScoreSheet.save()` writes `game.totalScore` from a typed number and ignores `holeScores`; `ScoreHoleSheet` writes it from the hole sum. Both reachable from `GameDetailView`. A user can type "72", then per-hole-score a few holes, and the totals silently disagree until all 18 are entered. **Fix:** once any `HoleScore` exists, make `EnterScoreSheet` read-only / drive everything off the derived total from C2.

### S4. Latent: `playResult`/`club` XOR is convention-only
The "either playResult or club, never both" invariant is documented in three files but **enforced nowhere** — `isTagged` is an `||`, and `saveClip` sets `club` unconditionally while `playResult` is conditional. No current caller violates it, but a future path passing both would corrupt stats *and* mis-display. **Fix:** cheap guard — `assert(playResult == nil || club == nil)` and/or short-circuit stats when `club != nil`.

---

## 🟡 Improvements — architecture / maintainability

### A1. The sport abstraction is the weakest part of the feature
- **Dual enum:** `Athlete.Sport` (lowercase raw values) and `Season.SportType` (capitalized) are bridged by stringly-typed `.capitalized`/`.lowercased` round-trips with `?? .baseball` fallbacks (~30 sites). Single-word golf survives, but a future multi-word sport whose two spellings aren't pure case-variants silently relabels athletes as baseball. **Fix:** one enum (or a shared raw token) with an exhaustive `switch` mapping so a missing case is a *compile error*, not a silent default.
- **No central label vendor:** `isGolf ? "Tournament" : "Game"` is duplicated across ~25 sites in ~20 files, and "is this golf?" is re-implemented many ways. `Game+Sport.swift` is the only centralization and vends only the opponent prefix. **Fix:** a `SportConfig`/`SportLabels` struct that vends event noun(s), section titles, icons, notification copy; route every site (and the next sport) through it.
- **`activeSport` recomputed in ~11 files** as a copy-pasted computed var; only `StatisticsView` reconciles it against `selectedSeasonFilter`. Other season-filtered screens (Games, Photos, Videos, Dashboard) can show golf rows under baseball chrome when filter and active sport disagree. **Fix:** one resolver that accounts for the optional season filter, used everywhere.

### A2. Reachable bug: "rescan library" strips golf highlights
`AutoHighlightSettings.scanLibrary(for:context:)` (AutoHighlightSettings.swift:93) is **wired to a button** in `AutoHighlightSettingsView` (line 49 → 85) — not dead code. At line 99 it runs `if clip.isHighlight { clip.isHighlight = false; clip.needsSync = true }` for every clip with no `playResult`. Golf clips always have `playResult == nil`, so a rescan **silently clears every manual golf highlight** and dirties them for sync, propagating the loss cross-device. Golf is "manual highlights only," so the key question is whether this settings screen is presented to golf athletes at all — **verify that gating**. **Fix:** sport-guard `scanLibrary` to skip golf, and/or hide the auto-highlight settings entry for golf athletes. (Quick fix; bundle with S1–S3.)

### A3. Minor
- Reel re-save bumps `version`/`needsSync` every time even when the clip set is unchanged → redundant Firestore writes.
- Out-of-order/gap hole scoring: both `LiveHoleTracker` and inline `nextHoleNumber` use `max(scored)+1`, so scoring hole 5 first jumps "next" to 6, not 1. Consistent but doesn't find the lowest unscored hole.
- Optional rules hardening: `holeNumber`/`par`/`score` range + type checks on the golf subcollections (defense-in-depth; owner-scoping already contains blast radius).
- Stale doc comments: `SyncCoordinator+HoleScores` header still calls the practice-round path "lands in PR3" (it's active now); `VideoTagEditor` header still says "baseball-specific suggestions" (now sport-aware).

---

## Suggested fix order
1. **C1 golf export** and **C2 totalScore derivation** — user-facing / data integrity, before any golf marketing push.
2. **S1–S3 + A2** reel/score/highlight edge cases — schedule into the next golf PR (A2 is quick).
3. **A1** sport abstraction cleanup — do this *before* attempting real golf stats (GIR/fairways/handicap) or a 3rd sport; highest-leverage refactor.
4. **S4 / A3** — opportunistic / hardening.
