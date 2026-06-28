# Practices, Seasons & Photos — Feature Gap Backlog

**Created:** 2026-06-28 · **Last reviewed:** 2026-06-28 (verified against current `main`)

Source: feature-gap audit of the three areas we'd spent the least time on. The **basics in all three are solid** — create / edit / delete / sync / filter all work, golf + baseball both handled, photos are first-class in the Journal. The gaps below are about **depth that drives engagement/retention** and ties into the two strategic bets (coach loop + recruiting profile), not missing fundamentals.

Re-verify statuses against code before acting — they drift as work lands outside tracked sessions. Cross-refs: `docs/PRIORITIES.md` (canonical roadmap), `docs/RECRUITING_PROFILE_PLAN.md`.

### Status legend
- ☐ Not started · ◐ In progress · ☑ Done
- **P1** = highest leverage · **P2** = worth doing · **P3** = nice-to-have / cheap polish
- 🐛 = correctness bug (tracked separately at the bottom, not a feature)

---

## Top 3 bets (do these first)

Ranked by leverage, not by area. Each is a design conversation first (schema impact, coach-loop ties, UI) before code.

1. **☑ P1 — Practice focus / drill layer.** Shipped — multi-select, sport-aware focus on create + detail. → [Practices #1](#practices)
2. **☐ P1 — Goals (season + practice).** Not in this batch — still the strongest unbuilt retention hook. → [Seasons #1](#seasons) / [Practices #2](#practices)
3. **◐ P1 — Hero/favorite photos + per-athlete headshot + season recap.** Favorite photos + quota shipped; per-athlete headshot UI and season recap still open. → [Photos #1–2](#photos) / [Seasons #2](#seasons)

---

## Practices

Today a practice is a **dated bucket of clips** — no "what am I working on" layer, which is the point of practicing.

- ☑ **P1 — Drill / focus layer.** **Shipped.** SchemaV33 `Practice.drillTypes` (comma-joined rawValues) + shared `DrillType`/`GolfDrillType` extracted to `Models/DrillType.swift` + `PracticeFocusPicker` (multi-select, sport-aware) in `AddPracticeView` and `PracticeDetailView`. Fully synced. Coach drill-*assignment* surface remains deferred (the field is forward-compatible).
- ☐ **P1 — Practice goals / focus areas.** No goal or focus field today. See unified Goals item under Seasons — should span both.
- ☐ **P2 — Practice-level summaries & trends.** Clip play-results roll into athlete totals, but there's no "this practice: 25 swings, 3 Ks" view and no across-practice trend. Practices are invisible in stats.
- ☐ **P2 — Baseball practice highlights/milestones.** Only golf practice-round birdies auto-reel today. A baseball cage session produces nothing to share or celebrate; practices never fire milestones.
- ☐ **P3 — Templates / recurring practices.** None. "Schedule Practice…" in the UI is a misnomer (just opens the date picker). No clone/duplicate, no recurring.
- ☐ **P3 — Practice-as-entity coach sharing.** Clips are shareable to coaches; the practice session itself is not (no session-level coach feedback, no coach drill assignment targeting a practice).
- ☐ **P3 — Duration / session metadata.** `date` + `liveStartDate` exist but no `liveEndDate`/duration, no intensity/effort.
- ◐ **P3 — Golf scorecard scan for practices.** `selectedTee` + `scorecardData` fields exist and sync (SchemaV32) but there's **no capture/review UI** ("wired for sync parity, no practice scan entry point this phase"). Tracked under scorecard-scan Phase 2.

## Seasons

Solid lifecycle (create → activate → archive → delete → compare) but **no payoff at the end and no structure**.

- ☐ **P1 — Season goals / targets.** Confirmed: only a freeform `notes` field ("goals, achievements, etc.") on `Season` — no structured target. A goal ("hit .300", "break 80", "handicap to 10") with progress is a strong motivation/retention hook and a natural Journal/Home element. Unify with the practice goals item → one **Goals** feature.
- ◐ **P1 — Season recap / year-in-review.** **Next up (Phase 5, not yet built).** Plan: new `SeasonRecapView` reusing `GenerateReelView`/`ReelStitchCoordinator`/`ReelExportControls` + `Milestone` + `season.seasonStatistics`; recap card free, reel build stays Plus-gated; surfaced in `SeasonDetailView` + at season-end. Half-built today: the season reel only stitches already-starred clips.
- ☑ **P2 — Season types / categories.** **Shipped.** SchemaV33 `Season.seasonType` + `Season.SeasonType` enum; optional picker in `CreateSeasonView` (folded into name suggestions) + type badge on `SeasonRow`; recruiting-profile doc note added. `SeasonFilterMenu` type-filter deferred (shared across 5 screens).
- ☐ **P3 — Auto-roll / next-season creation.** No clone or "start next season" flow; manual creation each time.
- ☐ **P3 — Bulk season actions.** No "move all games from Season A → B"; archive/activate don't re-notify linked content.

## Photos

First-class in the Journal, but **second-class compared to video**.

- ☑ **P1 — Favorite / hero photo.** **Shipped.** SchemaV33 `Photo.isHighlight` (mirrors `VideoClip.isHighlight`, fully synced incl. the re-tag merge branch); star toggle in `PhotoDetailView` + thumbnail badge + context-menu toggle + "Favorites" filter in `PhotosView`. "Game cover = first highlighted photo" deferred.
- ◐ **P1 — Per-athlete headshot.** **Field shipped** (SchemaV33 `Athlete.headshotPhotoId` → a `Photo`, fully synced, reuses the photo pipeline). **UI still open (Phase 7):** set-as-headshot action + display in `PPProfilePill`/`PPAthleteSwitcher`/`AthleteCard` with initials/account-photo fallback.
- ☑ **P2 — Photo storage quota surfacing.** **Shipped.** "Cloud Storage" section in `StorageSettingsView`: used vs plan limit (`SubscriptionGate.effectiveAthleteTier.storageLimitGB`), color-coded bar, near-limit warning.
- ☐ **P3 — Photo editing / markup.** No crop / rotate / draw / filters.
- ☐ **P3 — Albums / collections.** No user-created albums beyond event tagging; no smart albums.
- ☐ **P3 — Photo coach sharing / feedback.** Videos share to coach folders; photos don't. (Lower priority — coach value is instruction, photos less central.)

---

## Correctness issues (bugs — not features)

Separate track. Most are already logged in session notes; listed so they don't get lost. Verify scope before fixing.

- 🐛 ☑ **Season stats stale on late-add** — investigated: `recalculateAthleteStatistics` already re-aggregates *all* seasons (archived included) on every stat edit, so this is largely self-healing. Added a manual **"Recalculate Stats"** backstop in `SeasonDetailView` for the residual window.
- 🐛 ☑ **Open-ended season catch-all** — `Season.season(containing:)` now bounds an active season at end-of-today and skips inactive seasons with no `endDate` (no more `distantFuture` catch-all). Fixed.
- 🐛 ☑ **`seasonStatistics` lost on season delete** — `SeasonService.deleteSeason` now deletes the stats object before the season (local-only delete no longer orphans it). Fixed.
- 🐛 ☑ **Multi-device photo re-tag relink** — added a metadata-merge branch in `SyncCoordinator+Photos` (mirrors the re-home clean-wins rule using existing `Photo.version`-free LWW) so a re-tag/caption/favorite on device A relinks on a clean device B. Fixed.

---

## Changelog

- **2026-06-28** — Doc created from the practices/seasons/photos feature-gap audit.
- **2026-06-28 (impl)** — Shipped in the `main` working tree, **build green at each step, NOT yet committed/pushed**: all 4 correctness bugs; **SchemaV33** (`Practice.drillTypes`, `Season.seasonType`, `Photo.isHighlight`, `Athlete.headshotPhotoId`) with full sync-site wiring verified for all 4 fields; practice drill/focus UI; season types UI; photo favorites UI; cloud-quota surfacing. **Remaining:** season recap (Phase 5) + per-athlete headshot UI (Phase 7). **Manual gates pending before release:** over-the-top V32→V33 migration test on real data; two-device sync round-trip per new field; build-number bump (`./increment_build_number.sh`) before archive.
