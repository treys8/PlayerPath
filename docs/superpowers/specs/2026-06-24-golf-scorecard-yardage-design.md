# Per-Hole Yardage & Derived Drive Distance (with Optional Scorecard Scan)

A junior golfer with a rangefinder + a scoring parent get a per-hole yardage property (like par), and PlayerPath derives **Est. Driving Distance** = hole yardage − approach yards-to-pin — no GPS, no course database, no device import.

---

## 1. Context & problem

**Persona:** a competitive **junior golfer who carries a laser rangefinder**, scored and filmed by an **engaged parent** mid-round. The rangefinder gives accurate **yards-to-pin before each approach** (the existing optional `Shot.distanceBefore`), but it **cannot measure how far a shot traveled** — you can't laser the pin from the tee, and the ball is gone before you'd range it.

**The derivation that unlocks the headline stat:**

```
drive distance  =  hole yardage  −  approach yards-to-pin
                   (HoleScore.yardage)   (Shot.distanceBefore on the regulation approach)
```

So the missing ingredient is **hole yardage**. The category gets this from a GPS course database (Arccos/Shot Scope/18Birdies) — which PlayerPath deliberately does **not** have. Our two no-database sources are: (a) the player **types the number off the tee marker / printed scorecard**, and (b optionally) a **scorecard photo** read by OCR. The chain is: **scorecard photo → per-hole yardage → derived drive distance → stats/export.**

This makes hole yardage a first-class **hole property, like par**, stored on `HoleScore`. Drive distance is **derived, never stored**, consistent with how FIR/GIR/score are already computed-on-read from shots in this codebase.

---

## 2. Goals / Non-goals

**Goals**
- `HoleScore.yardage: Int?` as a synced hole property, entered via a wheel chip next to Par, carried across rounds at the same course (like `priorRoundPar`).
- Derived, compute-on-read **Est. Driving Distance** (par ≥ 4 holes with a recorded approach), shown per-hole and as avg/longest in the round summary.
- (Phase 2+) Capture a **scorecard photo** and OCR par + yardage into a mandatory human **confirm grid**.

**Non-goals (explicit)**
- **No GPS / shot tracking.** Distance is derived from typed/scanned yardage minus a ranged approach, never from coordinates.
- **No course database.** Yardage comes from the player/scorecard, not a mapped course DB.
- **No device/watch import.** Garmin/Arccos/Shot Scope data is a walled garden (no public per-user API); we do not ingest it.
- **No OCR auto-commit.** OCR only ever *proposes*; nothing reaches `HoleScore` without human confirm.
- **No dogleg correction.** Card yardage is routed distance; the stat is labeled **"Est."** and not corrected.

---

## 3. Primary user flow (setup → per-hole → summary)

**Setup (per round)**
1. Parent creates the round in `GameCreationView.swift` (course = `Game.opponent`, holes 9/18, par).
2. *(Phase 2)* Optional **"Scan scorecard"** (`doc.viewfinder`) → `VNDocumentCameraViewController` → deskewed image saved via the existing Photo pipeline → OCR → **confirm grid** (tee picker + editable par/yardage per hole) → Apply writes `HoleScore.yardage` + `par` for every hole.
3. *(MVP)* No scan: yardage is entered per-hole during scoring, seeded from the prior round at the same course.

**Per-hole (during play)**
4. Parent scores hole-by-hole. A **yardage chip** sits next to the **Par** chip in both `ShotByShotContent` and `QuickScoreContent`, opening the existing `YardagePickerSheet` wheel → writes `HoleScore.yardage`. Prefilled from the prior round (or scan) if available.
5. In shot-by-shot mode, the kid lasers the pin before the approach; parent taps it into the existing per-shot `Shot.distanceBefore` wheel. **These two numbers are everything the drive derivation needs.**

**Summary (post-round)**
6. Per hole: `driveDistance = HoleScore.yardage − regulationApproach.distanceBefore` (par ≥ 4 only, nil on every edge case → em-dash).
7. Round: **Avg / Longest Est. Driving Distance**, shown in the round summary and stats screens; em-dash when no hole is derivable.

---

## 4. Data model & migration

### 4.1 Fields shipping in SchemaV31

| Field | Type | File | MVP? |
|---|---|---|---|
| `HoleScore.yardage` | `Int? = nil` | `PlayerPath/Models/HoleScore.swift` | **Yes** |
| `Photo.isScorecardPhoto` | `Bool = false` | `PlayerPath/Models/Photo.swift` | Phase 2 (scan) |

**Reviewer-driven cuts (do NOT ship in V31):**
- **`HoleScore.teeBox` — CUT.** Both reviews flagged this as wrong altitude: a round is played from **one** tee, so a per-hole copy is 18 redundant, divergence-prone values and a *second* full sync-wiring pass. The tee is a round-level concern.
- **`Game.selectedTee` / `Practice.selectedTee` — DEFER to Phase 2** (only needed once scan/OCR ships, to collapse `yardageByTee` to one column). Not in the MVP field set.
- **Scorecard image = reuse `Photo`** (attached via existing `Game.photos`/`Practice.photos`), distinguished by the one `isScorecardPhoto` flag. No `scorecardImagePath`, no dedicated 1:1 relationship — those re-implement upload/quota/deletion from scratch.

### 4.2 SchemaV31 migration steps

In `PlayerPath/PlayerPathSchema.swift`:
1. Add `enum SchemaV31: VersionedSchema` after `SchemaV30` (version `31,0,0`), listing the same model classes (`SchemaV1.models + [HoleScore.self, HighlightReel.self, GolfTournament.self, Shot.self]` — `Photo` already rides in `SchemaV1.models`).
2. Append `SchemaV31.self` to `PlayerPathMigrationPlan.schemas` and a `.lightweight(fromVersion: SchemaV30.self, toVersion: SchemaV31.self)` stage. **(Documentation only — see below.)**

**THE LOAD-BEARING EDIT** — `PlayerPath/PlayerPathApp.swift`: change `Schema(SchemaV30.models)` → `Schema(SchemaV31.models)` at **BOTH line 52 AND line 59** (verified: the container binds the *unversioned* schema; `PlayerPathMigrationPlan` is deliberately dead code — passing it crashes on duplicate checksums). Miss line 59 and a migration failure silently falls back to an **in-memory store on the old schema** (looks like total data loss that "fixes itself" next launch).

**Migration safety (reviewers: Important):** all additions are nil/false-defaulted columns → guaranteed lightweight; existing rows read back `yardage = nil`, `isScorecardPhoto = false`. The in-memory `catch` branch (L57–63) builds `isStoredInMemoryOnly: true` on the *same* models and swallows non-lightweight mistakes **silently**. Mitigations: (a) test V30→V31 on a store seeded with **real V30 data** (scored holes + photos) before merge, confirming fields read back and no rows vanish; (b) add launch-time telemetry/assertion that fires when the in-memory branch is taken, so the silent fallback becomes a loud TestFlight signal instead of a "my rounds vanished" review.

### 4.3 SYNC WIRING CHECKLIST — exhaustive (every file:function)

> Run the `sync-field-check` skill against `HoleScore.yardage` (and `Photo.isScorecardPhoto` if shipping scan) after wiring. A missed site = silent data loss (the holeNumber bug class).

#### A. `HoleScore.yardage` — mirror `penalties` exactly (8 sites). **Reviewer verdict: GO as written.**

| # | File : function | Edit | Mirrors |
|---|---|---|---|
| 1 | `Models/HoleScore.swift` : class body | add `var yardage: Int? = nil` | `penalties` (L29) |
| 2 | `Models/HoleScore.swift` : `init` | add `yardage: Int? = nil` param (at END) + `self.yardage = yardage` | `penalties` |
| 3 | `Models/HoleScore.swift` : `toFirestoreData()` (L96) | add `if let yardage { data["yardage"] = yardage }` after the penalties block | `penalties` |
| 4 | `FirestoreModels.swift` : `struct FirestoreHoleScore` (L712) | add `let yardage: Int?` — synthesized decoder (no custom `init(from:)`) decodes missing key → nil | `penalties` (L722) |
| 5 | `FirestoreManager+HoleScores.swift` : `updateGameHoleScore` | add `"yardage"` to `allowedFields` (L31) **AND** to the `FieldValue.delete()` loop (L36–37) so clearing deletes remotely | `penalties` |
| 6 | `FirestoreManager+HoleScores.swift` : `updatePracticeHoleScore` | same two edits (L93, L98–99) | `penalties` |
| 7 | `SyncCoordinator+HoleScores.swift` : `reconcileHoles` UPDATE branch | add `local.yardage = remote.yardage` | `penalties` |
| 8 | `SyncCoordinator+HoleScores.swift` : `reconcileHoles` INSERT branch | add `yardage: remote.yardage` to the `HoleScore(...)` initializer | `penalties` |

*No change needed* (verified generic): upload writers (`syncHoleScores` call `toFirestoreData()`), dirty flag (UI sets `hole.needsSync = true` on yardage edit, same as par/putts), version/`updatedAt` (bumped generically in reconcile), `createGameHoleScore`/`createPracticeHoleScore` (write the full dict unfiltered).

#### B. `Photo.isScorecardPhoto` — Phase 2 only. **Reviewer verdict: NO-GO as originally designed; the Photo path differs structurally from HoleScore. These corrected sites are mandatory:**

| # | File : function | Edit | Why (reviewer, Critical) |
|---|---|---|---|
| B1 | `Models/Photo.swift` : class body | add `var isScorecardPhoto: Bool = false` | new flag |
| B2 | `Models/Photo.swift` : `toFirestoreData(ownerUID:)` (L40) | add `data["isScorecardPhoto"] = isScorecardPhoto` (CREATE path) | first upload |
| B3 | `Models/Photo.swift` : `updatableFirestoreData()` (L59) | add it here **too** — Photo has **TWO** write methods; flag set/cleared after first upload rides THIS path | silent loss if missed |
| B4 | `FirestoreManager+EntitySync.swift` : `updatePhoto` (L652) | add `"isScorecardPhoto"` to `allowedFields` (L655 — currently `["caption","gameId","practiceId","seasonId"]`); unknown keys are filtered out before write | **the literal holeNumber bug** |
| B5 | `FirestoreModels.swift` : `struct FirestorePhoto` (L808) | add `var isScorecardPhoto: Bool = false` (**defaulted/optional — NEVER bare non-optional**) | a bare non-optional Bool throws on every legacy doc → entire photo row dropped on next sync |
| B6 | `SyncCoordinator+Photos.swift` : INSERT branch (~L162) | set `newPhoto.isScorecardPhoto = remotePhoto.isScorecardPhoto` by hand (no generic copy exists) | manual reconcile |
| B7 | `SyncCoordinator+Photos.swift` : RE-HOME branch | set the flag in the re-home branch too | re-homed scorecard else loses flag |

**Photo caveats (reviewer):** `FirestorePhoto` has **no `version` field** → no version-based LWW; a two-device flag race resolves last-write-to-Firestore with no guard (tolerable for one advisory flag — do **not** claim LWW parity). Setting the flag must set `photo.needsSync = true`. Make the scorecard getter **deterministic** (e.g. `photos.filter { $0.isScorecardPhoto }.min(by: createdAt)`) so a two-device double-flag is cosmetic, not nondeterministic.

### 4.4 Firestore document shape

Hole doc at `users/{uid}/games|practices/{id}/holes/{N}` gains one additive field:
```jsonc
{ "...": "...", "penalties": 0,
  "yardage": 412,        // NEW — omitted when nil; FieldValue.delete() on clear
  "version": 3, "isDeleted": false }
```
Scorecard photo: a normal Photo doc gaining `"isScorecardPhoto": true`. No new hole-doc field for the image.

### 4.5 Par-3 single-source rule (no double-storage)

`HoleScore.yardage` is authoritative for **hole length**; `Shot.distanceBefore` is authoritative for **a shot's yards-to-target**. They coincide on a par-3 tee shot but are two different facts on independent sync lanes — **no reconciliation between them.** Rules: (1) drive derivation reads hole length only from `HoleScore.yardage`; (2) any par-3 pre-fill of `distanceBefore` is **one-way (hole → shot), never back**; bind them to **separate `@State`** — do not reuse one binding. The derivation guards `par >= 4` before touching the approach, so par-3 never subtracts.

---

## 5. Scorecard capture & OCR pipeline *(Phase 2+)*

### 5.1 Capture — VisionKit
New thin `ScorecardScannerView.swift` (`UIViewControllerRepresentable` over `VNDocumentCameraViewController`), modeled on `PhotoCamera/PhotoCameraView.swift`. Takes page 0 only (deskewed, perspective-corrected). No new Info.plist key (`NSCameraUsageDescription` already present). The `UIImage` rides the **existing** path verbatim: `PhotoPersistenceService.savePhoto(image:context:athlete:game:practice:season:)` → set `isScorecardPhoto = true` → `SyncCoordinator+Photos.syncPhotos()` → `VideoCloudManager+Photos.uploadPhoto`. OCR reads the **local** `resolvedFilePath` immediately — never waits for upload, so it works offline.

### 5.2 Engine — recommended + fallback
- **Primary: on-device Vision** (`VNRecognizeTextRequest(.accurate)` over the deskewed page; native table detection on iOS 26, manual bbox row/column grouping on iOS 17/18). Offline, free, private, ~1s. The hard part is column/row grouping — the mandatory confirm grid absorbs residual error.
- **Fallback: Firebase Cloud Function → Claude vision** (`claude-opus-4-8`, structured output via `output_config.format` JSON schema, base64 image block) returning the same contract. **Reviewers: do NOT build this until on-device is proven to fail real cards** — it adds server cost, a consent disclosure, Plus-gating, and a quota counter. Offered only as opt-in "Try smart scan" on low confidence; never auto-commits. If built, gate behind `SubscriptionGate.effectiveAthleteTier` (Plus) + a monthly scan quota.

Both engines emit an identical transient `ScorecardExtraction` struct (`holes: [{holeNumber, par?, yardageByTee:[tee:yards]}]`, `detectedTees`, `subtotals` for cross-check only, `engine`, `overallConfidence`). It is **not** a SwiftData model. OUT/IN/TOTAL columns parse into `subtotals` for validation **only** — never emitted as holes 19–21.

### 5.3 Tee selection
After extraction, if `detectedTees.count > 1`, a one-tap picker (each tee labeled with its total yardage, e.g. "Blue — 6,412 yds") collapses `yardageByTee` to a single column. Persist once on the round as `Game.selectedTee` / `Practice.selectedTee` (Phase-2 field; wire its own sync sites). **Reviewers: drop the median-yardage default and prior-round inference heuristics** — let the user pick from a card they're looking at.

### 5.4 Confirm contract (mandatory, non-bypassable)
```
extract() → ScorecardExtraction (proposal)
  → ScorecardConfirmGrid (REQUIRED — no auto-commit, no "trust" shortcut)
  → on Confirm → write par into HoleScore.par; write selected-tee yardage into HoleScore.yardage
```
Low-confidence cells (`<0.6`, or par∉3…6 / yardage∉60…700) render amber and focus first. Partial reads representable (`par == nil` / missing tee key); the user fills gaps — we never invent values. `overallConfidence < 0.4` (or <60% holes read, or gross subtotal mismatch) → "Couldn't read clearly" with **Retake / Try smart scan / Enter manually**. "Enter manually" drops into the **same** empty confirm grid — scan simply seeded nothing.

---

## 6. UI: confirm grid + yardage chip + chevrons + entry points

### 6.1 Per-hole yardage chip (MVP)
- **`ShotByShotContent.swift` `slimHeader`:** add a yardage chip immediately after the Par chip — a `Button` opening `YardagePickerSheet` (a **wheel**, not a Menu — range 1–700 is unusable as a menu), styled with `.golfControlChip()`. New `@State holeYardage: Int?`, loaded from `existing.yardage`, persisted on change with `hole.needsSync = true`. Separate `@State` boolean from the per-shot approach picker. Seed the wheel center by par (par 3→165, par 4→400, par 5→530).
- **`QuickScoreContent.swift`:** put the same chip on the **PAR label row** (sibling hole property). Quick mode has no shots → yardage is stored/displayed but **no drive derivation**.
- Reuses `YardagePickerSheet.swift` and `golfControlChip` — one yardage idiom across the app. This chip is **distinct** from the per-shot `Shot.distanceBefore` wheel (which stays inside the shooting card, unchanged); copy must read them as different controls.

### 6.2 Confirm grid (`ScorecardConfirmGrid.swift`, new — Phase 2)
A `ScrollView` + `LazyVStack` (not `Form`, so cells host `golfControlChip` pills): tee selector on top → header `Hole | Par | Yardage` → editable rows (par cell = Menu picker 3…6; yardage cell = `YardagePickerSheet` driven by an `editingRow` index) → read-only OUT/IN/TOTAL → toolbar `Cancel` / `Looks good, apply`. Low-confidence cells flagged with `exclamationmark.triangle.fill` in `Theme.warning` + a grid banner "N holes need a quick check" (advisory; never blocks Apply). It is an **input** grid — does not touch the read-only `GolfScorecardView`.

**Apply (bulk write):** loop `GolfScoreWriter.upsertHole(input, in: roundRef, context:)` per hole, then `mirrorTotalScore`. **Never clobber a real score:** if `score > 0`, update **par + yardage only**, keep the score (mirror the `scoreManuallySet` precedent). During **creation** the round may not exist yet → grid returns its `[par, yardage]` array to `GameCreationView` to write after the Game is inserted on Save; during **detail** write immediately. `Haptics.success()` on apply.

### 6.3 Entry points (Phase 2)
- **Primary — `GameCreationView.swift`:** "Scan scorecard" (`doc.viewfinder`) section between the Round and Tournament sections. Footer: "Capture the printed scorecard to fill in par and yardage for every hole."
- **Secondary — `GameDetailView.swift`:** one `Button` in `primaryActionMenu` (~L486) next to "Scorecard"/"Enter Score".
- **Not** in the per-hole sheet (scan is a whole-round bulk action).

### 6.4 Disclosure chevrons (locked decision — ship as a SEPARATE cosmetic PR)
Add a trailing `chevron.down` to the `GolfControlChip` modifier (`ShotByShotContent.swift` ~L706) with an opt-out `showsChevron: Bool = true`, so tappable chips (Par/lie/penalty/yardage/tee) read as "opens a picker." Promote `GolfControlChip` + `golfControlChip(_:)` to a shared location (needed by QuickScoreContent + the confirm grid). **Reviewer: keep this out of the yardage MVP** — it touches every existing chip's visuals; ship it as its own small additive PR.

**Copy/a11y:** sentence-case, action-first. Chip unset = "Add yardage", set = "420 yds" (monospaced digits). Each chip: `.accessibilityLabel` (property name), `.accessibilityValue` (value or "Not set"), `.accessibilityHint("Opens a picker")`. Confirm rows: `.accessibilityElement(children: .combine)` → "Hole 7, par 4, 420 yards, low confidence, please check". Never color alone — warning tint always pairs with the glyph + text.

---

## 7. Prefill, drive-distance derivation & stats/export

### 7.1 `priorRoundYardage` prefill
Add to `Services/GolfScoreWriter.swift` next to `priorRoundPar` (after ~L215), **byte-for-byte identical** except the terminal keypath `.par` → `.yardage`. Course-keyed the same way (games off `Game.opponent`, practices off `Practice.course`, golf-sport filtered, most-recent prior round). **Critical difference:** par's terminal fallback is the constant `4`; **yardage has no sensible constant → the chain ends at `nil`** (empty field), so yardage is never inferred into a default that could pollute the to-par/effectivePar invariant. **No "previous hole" fallback** (each hole has a distinct yardage). Seed call sites: `QuickScoreContent` and `ShotByShotContent` (`existing.yardage` → `priorRoundYardage` → nil).

### 7.2 Drive-distance derivation — **COMPUTE-ON-READ, never stored**
Storing `driveDistance` would add a fourth synced field reconciled against two moving inputs — exactly the divergence this codebase avoids by deriving FIR/GIR/score. Add a pure helper to `Services/ShotStats.swift`:

```swift
static func driveDistance(for hole: HoleScore) -> Int? {
    guard hole.par >= 4, let holeYardage = hole.yardage else { return nil }
    let live = (hole.shots ?? []).filter { !$0.isDeletedRemotely && !$0.isPutt }
                                 .sorted { $0.shotNumber < $1.shotNumber }
    guard live.contains(where: { $0.lie == .tee }) else { return nil }
    guard let approach = regulationApproach(in: live, par: hole.par),  // verified L150
          let toPin = approach.distanceBefore else { return nil }
    let drive = holeYardage - toPin
    return drive > 0 ? drive : nil   // guard mis-entry / wrong tee
}
```

The "approach" is `regulationApproach(in:par:)` (the validated par-2 regulation stroke), **not** a naive "second shot" — which makes all edge cases fall out: par 3 → nil (`par >= 4` guard); penalty/rehit off the tee → nil (the stroke-walk pushes `playedAt > target`); no approach number → nil; drivable par 4 reached off the tee → nil; `holeYardage − toPin ≤ 0` → nil. **Reviewer-verified correct against the real `regulationApproach` walk.**

**Display (all read the helper, no storage):** `ShotLogRow.swift` tee-shot row only → secondary "→ N yd drive" caption (the tee row has no `distanceBefore` of its own); `HoleDetailView.swift` → a "Drive" summary line when non-nil; round summary → avg/longest.

### 7.3 Stats & export — **MVP keeps it minimal**
- **MVP, in-app, free:** **Avg** and **Longest** Est. Driving Distance in `Views/Stats/GolfStatsSection.swift` (mirror the `shotPatterns` computed-var + `hasData` gate). Per-hole and round-summary display. The *number* is free in-app (like GIR/FIR/putts).
- **DEFER (reviewers: stat-padding on a sparse, estimated base):** GIR-by-distance buckets, `avgApproachDistance`, per-round CSV driving columns. Do not build until the core estimate proves valuable.
- **When export ships (fast-follow):** career-level `Avg Drive` / `Longest Drive` / `Avg Approach` in `StatisticsExportService.swift` CSV summary + PDF detail (each `if let`-guarded), reusing the existing **Plus** export gate — no new gate primitive. Per-round CSV columns require threading fields through `GolfExportData.GolfRoundRow`; do that last.

**"Est." labeling is load-bearing and must thread ALL the way through** (in-app + export). Card yardage is routed (dogleg) distance, so derived drive **systematically over-reads** on doglegs. An inflated "Longest Drive: 410 yds" exported to a recruiter is a credibility problem — the stat is **"Est. Driving Distance"** everywhere it appears.

---

## 8. Phasing / MVP

**OCR is Phase 2, not Phase 1. Both reviewers agree, strongly.** The headline value (drive distance) comes from `HoleScore.yardage` + `Shot.distanceBefore`, **not** OCR — OCR only saves typing 9–18 numbers the parent already comfortably types. The confirm grid is mandatory regardless, so Phase-2 OCR is purely additive (it pre-fills cells the grid already renders). And the irreversible part (schema + sync) must be decoupled from the flaky part (OCR accuracy across lighting/iOS versions).

**Phase 1 (MVP — ship alone, prove value):**
- `HoleScore.yardage` only, fully sync-wired (8 sites, §4.3-A), schema bumped to SchemaV31, validated with `sync-field-check`. **No `teeBox`, no `selectedTee`, no `Photo.isScorecardPhoto`, no camera, no OCR, no confirm grid, no Cloud Function, no tee-box flow, no new gating.**
- Yardage chip in `ShotByShotContent` + `QuickScoreContent`, reusing `YardagePickerSheet` + `golfControlChip`, seeded by `priorRoundYardage`.
- Derived **Est. Driving Distance** in `ShotStats` (compute-on-read), shown per-hole + avg/longest in round summary. In-app, free.
- Chevron/`GolfControlChip` promotion = **separate cosmetic PR**.

**Phase 2 (scan + confirm grid):** `Photo.isScorecardPhoto` (corrected 7-site Photo wiring, §4.3-B), `ScorecardScannerView` (VisionKit), `ScorecardConfirmGrid`, `Game.selectedTee`/`Practice.selectedTee`, on-device Vision OCR pre-fill (free), entry points. Export columns ride the existing Plus gate.

**Phase 3 (only if on-device OCR proves insufficient on real cards):** Cloud Function → Claude vision fallback (Plus + quota + consent string), auto-tee detection.

---

## 9. Edge cases

| Case | Handling |
|---|---|
| **Par 3** | `driveDistance` returns nil (`par >= 4` guard); the tee shot *is* the approach. Hole yardage still displays. Excluded from avg/longest. |
| **Dogleg** | Card yardage is routed, not straight-line → derived drive over-reads. **Not corrected.** Labeled **"Est. Driving Distance"** everywhere (in-app + export). |
| **No approach number entered** | `approach.distanceBefore == nil` → nil → em-dash (not 0); hole silently excluded from avg, like GIR/FIR. |
| **Penalty / rehit off the tee** | `regulationApproach` walks `penaltyStrokes`; a consumed regulation stroke → nil. No bogus drive attributed to a reload. (Reviewer-verified.) |
| **Drivable par 4 reached off tee** | No regulation approach → nil. |
| **Quick-score round (no shots)** | Yardage stores & displays; **no drive derivation** (no `distanceBefore`). Documented expectation. |
| **9-hole front/back** | Confirm grid lets the parent pick which nine; OUT/IN/TOTAL columns parsed for cross-check only, never as holes. Derivation iterates only the round's actual holes. |
| **Multiple tee boxes** | Round-level `selectedTee` (Phase 2) picked once; confirm grid shows that column. **No per-hole tee, no heuristics.** |
| **Re-scan / overwrite scored round** | Confirm grid pre-loads current par/yardage; Apply overwrites **par + yardage only**, never score/putts/penalties; `needsSync = true` on changed holes. |
| **Replace scorecard photo** | **DELETE** the prior `isScorecardPhoto` Photo via `Photo.delete(in:)` (cloud + pending-deletion + quota decrement) — **not** just clear the bool (reviewer: clearing orphans the blob against quota forever). Then attach the new one. |
| **Deleting the scorecard image** | Uses existing Photo deletion path; **must NOT cascade to `HoleScore.yardage`** — yardage is denormalized onto holes and survives. The image is the source, not the store. |
| **Offline capture** | Capture + local persist + on-device OCR all work offline; upload defers to the next `syncPhotos()` sweep. If quota-exceeded the photo silently fails to upload but OCR already ran locally → round unaffected. |
| **Sync conflict on yardage** | LWW via `version`/`updatedAt` in `reconcileHoles`, tombstones gated on `ConnectivityMonitor.isConnected` (consistent with every other HoleScore field). |
| **Two-device scorecard flag race** | No `version` on `FirestorePhoto` → unguarded; make the getter deterministic (`min(by: createdAt)`) so a double-flag is cosmetic. |
| **Dual-sport athlete** | All yardage/scan UI gates on `season.sport == .golf` / `athlete.sportType == .golf`; baseball never shows these controls. HoleScore is golf-only already. |

---

## 10. Open decisions for the human

1. **MVP scope — yardage-only, or yardage + scan?** *Recommend:* **yardage-only MVP** (one synced field), scan deferred to Phase 2. Both reviewers strongly favor this. → *Confirm or expand.*
2. **OCR in Phase 1?** *Recommend:* **No** — Phase 2, on-device Vision first; Cloud-LLM only as a Phase-3 fallback if on-device fails real cards. → *Confirm.*
3. **Drive-distance stat name.** *Recommend:* **"Est. Driving Distance"** (honest about dogleg over-read), threaded through in-app **and** export. → *Confirm.*
4. **`teeBox` storage.** *Recommend:* **No `HoleScore.teeBox`** (per-hole = redundant). A single `Game.selectedTee`/`Practice.selectedTee` **only when scan ships** (Phase 2); nothing tee-related in V31. → *Confirm.*
5. **Cloud-LLM OCR ever?** Accept sending scorecard images server-side (consistent with existing media uploads) as a Phase-3 fallback with per-scan cost + a consent string? *Recommend:* build only if on-device proves insufficient. → *Decide.*
6. **Phase-2 OCR pre-fill: free or Plus?** *Recommend:* **free** (convenience over already-free manual entry; gating adds entitlement complexity for little revenue). → *Confirm.*
7. **9-hole front/back mapping.** *Recommend:* **always ask** in the confirm grid (simpler, robust) rather than auto-detect. → *Confirm.*
8. **Approach-distance / bucket stats.** *Recommend:* **defer** `avgApproachDistance` + GIR-by-distance buckets + per-round CSV columns; ship only avg/longest first. → *Confirm.*

---

## 11. Verification plan

**No automated test targets exist in this project.** Verification is build + manual on-device.

**Build**
```bash
xcodebuild -project PlayerPath.xcodeproj -scheme PlayerPath -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

**Schema migration (do this BEFORE merge — irreversible):**
- [ ] Seed a store on **real V30 data** (golf rounds with scored holes + photos), upgrade to V31, confirm `yardage` reads back, `isScorecardPhoto = false` on legacy photos, and **no rows vanish**.
- [ ] Confirm `Schema(SchemaV31.models)` changed at **both** `PlayerPathApp.swift:52 and :59`.
- [ ] Confirm the in-memory fallback telemetry/assertion fires when forced (so silent fallback is loud).

**Sync wiring (run `sync-field-check` on `HoleScore.yardage`, and on `Photo.isScorecardPhoto` if scan ships):**
- [ ] Enter yardage on device A → appears on device B (round-trip).
- [ ] Clear yardage on A → `FieldValue.delete()` removes it on B (not a stale value).
- [ ] **(Phase 2)** Set `isScorecardPhoto` *after* first upload → rides `updatableFirestoreData()` + passes the `updatePhoto` allowlist → flag present on B.
- [ ] **(Phase 2)** A pre-existing/legacy photo doc (no `isScorecardPhoto` key) still decodes and does **not** vanish from the device on next sync.

**Per-hole entry**
- [ ] Yardage chip appears next to Par in both `ShotByShotContent` and `QuickScoreContent`; wheel opens, saves, persists across app relaunch.
- [ ] Prefill: a second round at the same course pre-fills yardage from the prior round; first-ever round shows the empty "Add yardage" affordance (no `4`-style default).
- [ ] Chip is hidden for baseball seasons (sport gating).

**Drive derivation**
- [ ] Par 4/5 with hole yardage + ranged approach → correct "→ N yd drive" on the tee row.
- [ ] Par 3 → no drive. Penalty off the tee → no drive. No approach number → em-dash. Quick-score round → yardage shows, no drive.
- [ ] Round summary avg/longest counts only derivable holes; em-dash when none.
- [ ] Stat labeled **"Est. Driving Distance"** in-app (and in export when it ships).

**Phase 2 (scan), when built**
- [ ] VisionKit deskewed capture → Photo persists with `isScorecardPhoto = true`; OCR runs offline against the local file.
- [ ] Confirm grid is non-bypassable; low-confidence cells flagged amber; "Enter manually" opens an empty grid; Apply writes all holes via `upsertHole` without clobbering existing scores.
- [ ] Re-scan overwrites par/yardage only; replacing the scorecard **deletes** the old Photo (no orphan); deleting the image does **not** clear `HoleScore.yardage`.

---

**Key files:** `PlayerPath/Models/HoleScore.swift`, `PlayerPath/Models/Photo.swift`, `PlayerPath/FirestoreModels.swift` (L712 `FirestoreHoleScore`, L808 `FirestorePhoto`), `PlayerPath/FirestoreManager+HoleScores.swift`, `PlayerPath/FirestoreManager+EntitySync.swift` (L655 `updatePhoto` allowlist), `PlayerPath/SyncCoordinator+HoleScores.swift`, `PlayerPath/SyncCoordinator+Photos.swift`, `PlayerPath/PlayerPathSchema.swift`, `PlayerPath/PlayerPathApp.swift` (L52 & L59), `PlayerPath/Services/ShotStats.swift`, `PlayerPath/Services/GolfScoreWriter.swift`, `PlayerPath/Views/Games/ShotByShotContent.swift`, `PlayerPath/Views/Games/QuickScoreContent.swift`, `PlayerPath/Views/Games/YardagePickerSheet.swift`, `PlayerPath/Views/Stats/GolfStatsSection.swift`. New (Phase 2): `ScorecardScannerView.swift`, `ScorecardConfirmGrid.swift`.