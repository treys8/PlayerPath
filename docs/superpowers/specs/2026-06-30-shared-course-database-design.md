# Shared Course Database — Design

**Date:** 2026-06-30
**Status:** Approved design, not yet implemented (execute later)
**Sport:** Golf

## Problem

Today a golf "course" is just a free-text string (`Game.opponent` / `Practice.course`). Par/yardage live on per-user `HoleScore` rows under `users/{uid}/...`, and the only reuse is per-athlete carry-forward (`GolfScoreWriter.priorRoundPar` / `priorRoundYardage`), which matches the course by string and only looks at that athlete's own prior rounds. So every user re-enters par/yardage for every course from scratch — a large, repeated ease-of-use cost.

A shared course database lets the first players (or an API seed) establish a course's par/yardage once, and every later player at that course gets it auto-filled.

## Load-bearing decisions (locked)

1. **Data source — Hybrid:** API seed where coverage exists, crowdsourced fill otherwise.
2. **Edit model — Personal override by default:** a normal edit only changes *that user's* app. The canonical shared record is never written directly by a client. Improving the shared record is a separate, deliberate path (consensus, see #4).
3. **Course identity — Searchable picker + GPS assist:** at round creation the user picks a canonical course (GPS floats nearby courses); identity is an explicit course ID, never a fuzzy string match.
4. **Promotion — Consensus auto-promote:** canonical data only appears once seeded from the API OR corroborated by N independent players. No single user can write canonical data; no manual moderation queue.
5. **Tees — Per-tee yardages:** canonical course stores par per hole (tee-independent) + a yardage set per tee box; user picks their tee per round.

### Consciously accepted tradeoff
A rarely-played course with no API coverage stays empty until N players log it. Those early players enter their own data exactly as they do today — no regression; the shared benefit simply activates at critical mass.

## Architecture

### The two-layer resolution model (the core of the feature)

Every par/yardage lookup resolves in this order:

```
personal override  →  canonical course  →  empty (user enters it)
```

- **Canonical layer** — shared, readable by all authenticated users, **never written directly by a client**. New top-level Firestore collection `courses/`, cached in SwiftData for offline reads. Populated only by the API-seed CF or the consensus CF.
- **Personal override layer** — per-user doc `users/{uid}/courseOverrides/{courseId}`. This is "update my app only." It is the **default** target of a normal edit, so a careless or app-only edit can never corrupt the shared record and is trivially reversible.

This single chain is the answer to both founding concerns:
- *"Edited something that didn't need editing"* → the edit lands in the private override layer; canonical is immutable from the client.
- *"Wanted to update my app only"* → that is the default behavior, no special mode.

### Data model

**Canonical course — Firestore `courses/{courseId}` (cached as a SwiftData model):**
- `id`, `name`, `location` (lat/long, for GPS proximity), `holeCount`
- `pars: [Int]` — par per hole (tee-independent)
- `tees: [{ name, color, yardages: [Int] }]` — yardage set per tee box
- `source: "api" | "crowd"`, `version: Int`, created/updated timestamps

**Personal override — `users/{uid}/courseOverrides/{courseId}`:**
- sparse per-hole par overrides + sparse per-(tee, hole) yardage overrides. Stores only fields the user actually changed.

**Round linkage — add to `Game` and `Practice`:**
- `courseID: UUID?` (nil = unlinked / legacy round)
- `teeName: String?`
- Existing `opponent` / `course` strings stay (display + legacy fallback).
- → SwiftData schema bump **V34 → V35**. Bind `Schema(SchemaV35.models)` in `PlayerPathApp.swift` (the bound schema, not the MigrationPlan). Lightweight migration (new optional fields + new cached Course model).

### Course identity — picker + GPS assist

New searchable course picker at round creation:
- Search the `courses/` collection by name.
- GPS floats the 3–4 nearest courses to the top (one-tap common case when logging on-site).
- "Can't find it? Add it" creates a new `crowd`-source course (which then triggers the API-seed CF).
- Sets `courseID` + `teeName` on the round.
- The existing typed `opponent`/`course` flow remains as the fallback for unlinked/legacy rounds.

### Contribution + consensus engine (server-side, integrity-critical)

- When a user enters or scans hole data for a **course-linked** round, the app writes a **candidate** doc: `courses/{courseId}/candidates/{uid}_{tee}` containing that user's par/yardage for the course + tee.
- A **Cloud Function** triggers on candidate writes, tallies agreement per (hole, tee), and when **N independent users** agree on a value, the CF writes that value into canonical `courses/{courseId}` and bumps `version`.
- **N is configurable** via the existing `appConfig` collection. Default **3**.

**Security-rule invariant (highest-risk surface):**
- All authenticated users may **read** `courses/`.
- A user may write only their own `courses/{courseId}/candidates/{uid}_*` doc.
- **No client may write canonical fields on `courses/{courseId}`** — only the Admin SDK (Cloud Functions) can. This mirrors PlayerPath's existing pattern that rules cannot safely aggregate/count, so authoritative enforcement lives in Cloud Functions (coach athlete-limit transactions, sharedFolder coach-add). The `courses/` collection is PlayerPath's **first shared, multi-writer dataset** — every prior collection is siloed under `users/{uid}/` — so this rule is the foundation the whole integrity story rests on.

### API seed (hybrid)

- On creation of a new `crowd` course, a CF attempts to enrich it from an external golf-course API (par + tee yardages).
- If covered → canonical is populated immediately (solves cold-start).
- If not covered → stays empty until consensus fills it.
- **Open research item:** select the external golf-course API. Coverage and licensing for **tee-level** yardage data varies, and munis / foreign courses are often missing. This choice is deferred to Phase 2 and does not block Phase 1.

### Migration & backwards compatibility

- Legacy rounds (no `courseID`) keep working unchanged: today's per-athlete `priorRoundPar` / `priorRoundYardage` carry-forward becomes the fallback used whenever a round is not course-linked.
- No data rewrite of existing rounds.
- Optional later polish: a "link your past rounds to a course" backfill prompt.

## Phasing (each phase ships independently)

### Phase 1 — Foundation + crowdsource loop
- `Course` SwiftData model + `courses/` Firestore collection.
- Security rules: public read, own-candidate write, canonical CF-only.
- Searchable course picker + GPS assist; `courseID`/`teeName` on Game/Practice; schema **V35**.
- Personal override layer + the two-layer read resolution.
- Candidate writes + consensus Cloud Function (N from `appConfig`, default 3).
- **Delivers the win for any course with N+ players.**

### Phase 2 — API seed
- Enrichment CF that fills canonical from the external golf API on course creation.
- Resolves the cold-start gap. Purely additive — no Phase 1 rework.
- Includes the API selection research.

### Phase 3 — Corrections & polish
- Explicit "suggest a correction" UI (distinct from a personal override).
- Canonical version history / audit trail; admin override tool.
- "Link your past rounds" backfill prompt.

## Risks & flags

- **First shared multi-writer dataset.** The CF-only-canonical-write rule is the highest-risk surface; spec the security rules and the CF transaction carefully, and test the rule denies direct client canonical writes.
- **Per-tee data model is the heaviest part of Phase 1.** If Phase 1 proves too large, the natural cut line is shipping single-yardage first and adding the tee dimension in Phase 2. (Current decision keeps per-tee in Phase 1.)
- **API dependency (Phase 2).** Tee-level coverage is the gating unknown; crowdsource (Phase 1) must stand fully on its own so the feature is viable even if no suitable API is found.
- **Consensus cold-start.** Until N players log a non-API course, no auto-fill — by design, but worth surfacing in UX copy so it doesn't read as a bug.

## Out of scope (YAGNI)
- Wiki-style live editing of canonical data.
- Manual moderation queue.
- Course ratings/slope/handicap-differential infrastructure beyond par + yardage (revisit with Strokes Gained v2).
- Cross-sport application (baseball/softball have no analog).
