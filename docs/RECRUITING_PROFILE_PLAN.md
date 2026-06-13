# Recruiting Profile — Implementation Plan (V29 refresh)

> Refreshed 2026-06-12 against schema **V29**, golf-as-first-class, and the V2
> coach-pays pricing pivot. Supersedes the V15-era plan captured in memory
> `project_recruiting_profile.md` (all its file:line citations were stale).

## What this feature is

An athlete-owned **recruiting profile**: a **video-first showcase** — headshot +
bio + contact + a curated set of in-game highlight clips — shared to college
coaches as a **public web link**. Stats are a *secondary, sport-weighted band*,
not the headline (see §3).

**The real wedge is the video pipeline, not stat credibility.** PlayerPath
already holds the athlete's in-game film, tagged by play result and flagged
`isHighlight`. Assembling a clean, shareable recruiting video page is therefore
nearly free — the clips already exist and are already curated. That is what a
stat/recruiting service (NCSA $500+/yr, FieldLevel) and a generic upload tool
can't cheaply match: *your best game film, already shot and tagged, one link
away.* Lean on the already-shipped highlight/reel infrastructure
(`project_highlights_export_reels`) rather than rebuilding clip handling.

> **Why not lead with stats?** College baseball/softball coaches heavily
> discount high-school / self-logged batting and pitching stats — competition
> isn't standardized and the numbers aren't verifiable, so game-by-game tracking
> doesn't make a parent-tagged .450 credible. They recruit on **video** +
> **showcase-verified measurables**. Golf is the exception (§3): scoring is
> objective and *is* the recruiting currency, so the golf stat band carries real
> weight. Plan accordingly — don't sell tracked stats as the moat.

Scope line (held from the competitive readout): PlayerPath helps an athlete
**present** themselves. It does **not** become the coach-matching / outreach
layer — "recruiting future = export to FieldLevel-style platforms, not build a
marketplace."

## The sharing model (the decision that drives everything)

**Share = a public, unguessable web link. NOT the coach folder-invite flow.**

The existing `sharedFolders` + `CoachInvitation` system is built for the
**private instructor** relationship (account holder, lesson loop, telestration,
costs a coach seat). College recruiters will never make an account, never accept
an invite, and get blasted the same link across 30+ schools. Reusing folders
here would be dead on arrival.

**PDF export is cut from v1.** The link is always-current, plays video inline,
tracks views, and previews richly in iMessage/email via Open Graph tags. A PDF
is a strictly-worse, instantly-stale copy. (Possible later add for in-person
showcases; not launch-critical.)

### Three layers

1. **Athlete bio (manual attributes)** — lives on the `Athlete` model, syncs to
   the user's own devices via the existing athlete sync chain. Edited in-app.
2. **Publish** — snapshots bio + *current derived stats* + chosen clip IDs into a
   new top-level `recruitingProfiles/` Firestore doc with a share token.
3. **Public web page** — a Cloud Function renders server-side HTML at a stable
   URL; college coaches open it in a browser, no app, no login.

Derived stats (batting average, est. handicap, scoring average, GIR%) are
**computed at publish time and snapshotted** — never stored on `Athlete`. Keeps
the model lean and avoids a second stale copy of stats.

---

## Phase 1 — Bio model + editor + in-app preview (~3–4 days)

### 1A. Store bio as a single JSON blob, not 20 columns

The original plan added ~13 individual `Athlete` columns. **Don't.** The athlete
sync chain is a hand-wired per-field whitelist + explicit download mapping (the
exact shape that produced the `holeNumber` data-loss bug). Threading ~20
recruiting fields through it multiplies that footgun 20×.

Instead add **one** optional field carrying a Codable struct:

```swift
// Athlete.swift — new stored property (Optional → lightweight migration)
var recruitingProfileJSON: String?   // JSON-encoded RecruitingInfo, nil until set
```

```swift
// New file: PlayerPath/Models/RecruitingInfo.swift  (~80 lines)
struct RecruitingInfo: Codable, Equatable {
    // Shared (all sports)
    var gradYear: Int?
    var heightInches: Int?
    var weightPounds: Int?
    var highSchool: String?
    var hometown: String?          // "Austin, TX"
    var gpa: Double?
    var headshotCloudURL: String?
    var contactEmail: String?      // opt-in
    var contactPhone: String?      // opt-in
    var achievements: String?      // free text: awards, rankings, honors

    // Baseball / softball
    var primaryPosition: String?   // "SS"  (softball adds DP/FLEX — free string)
    var secondaryPositions: String?// "2B,OF"
    var batsThrows: String?        // "R/R"
    var sixtyYardDash: Double?     // seconds
    var exitVeloMph: Double?       // manual — app can't measure
    var throwingVeloMph: Double?   // manual
    var pitchVeloMph: Double?      // manual (pitchers)

    // Golf
    var driverSwingSpeedMph: Double?  // manual
    var driverCarryYards: Int?        // manual
    // (handicap / scoring avg / GIR are DERIVED at publish, not stored here)
}
```

In-app: `athlete.recruiting` computed accessor that decodes/encodes the blob and
sets `needsSync = true` on write. One field, last-write-wins on the whole bio —
correct, since one user edits it as a unit.

### 1B. Schema V30 (documentation marker)

Schema enums here are documentation only — the real container schema is
`Schema(SchemaV29.models)` in `PlayerPathApp.swift` and the live `@Model`
classes carry the fields (see memory `feedback_swiftdata_unversioned_container`).
Steps:

1. Add the property to the live `Athlete` class (1A).
2. `PlayerPathSchema.swift` — add `enum SchemaV30` mirroring V29's
   `SchemaV1.models + [HoleScore, HighlightReel, GolfTournament]` body, with a
   header comment describing the `Athlete.recruitingProfileJSON` addition.
3. Append `SchemaV30.self` to `PlayerPathMigrationPlan.schemas` (line 544) and
   `.lightweight(fromVersion: SchemaV29.self, toVersion: SchemaV30.self)` to
   `stages` (after line 577).
4. `PlayerPathApp.swift:52,59` — bump `Schema(SchemaV29.models)` →
   `Schema(SchemaV30.models)` (both the primary and fallback container inits).

All additive + optional → lightweight migration, no data loss. Do an
over-the-top update test (memory `project_swiftdata_migration_inmemory_footgun`:
a failed migration silently falls back to in-memory and *looks* like total data
loss).

### 1C. Wire the one synced field (run /sync-field-check after)

Exactly 4 sites, 5 branches — the same chain that drops fields silently if you
miss one:

1. `Athlete.toFirestoreData()` (`Athlete.swift:238`) — add
   `"recruitingProfileJSON": recruitingProfileJSON ?? NSNull()`.
2. `FirestoreManager+EntitySync.updateAthlete` whitelist
   (`FirestoreManager+EntitySync.swift:58`) — add `"recruitingProfileJSON"` to
   the `allowedFields` set. **This is the line that silently drops the field if
   missed.**
3. `FirestoreModels.FirestoreAthlete` (`FirestoreModels.swift:393`) — add
   `let recruitingProfileJSON: String?` + a `CodingKeys` case.
4. `SyncCoordinator+Athletes.downloadRemoteAthletes` — both branches:
   - update branch (~`:214`): `if local.recruitingProfileJSON != remoteData.recruitingProfileJSON { local.recruitingProfileJSON = remoteData.recruitingProfileJSON; changed = true }`
   - new-athlete branch (~`:239`): `newAthlete.recruitingProfileJSON = remoteData.recruitingProfileJSON`

### 1D. Editor + in-app preview (sport-branched)

- `RecruitingProfileEditorView.swift` (~180 lines) — form bound to
  `RecruitingInfo`. **Branches on `athlete.sport`**: baseball/softball shows
  position / bats-throws / 60 / velos; golf shows driver speed / carry +
  achievements. Shared section (grad year, height/weight, school, hometown, GPA,
  headshot via `PhotosPicker`, contact opt-ins) always shown. Lift name/number
  validation patterns from `AddAthleteView`.
- `RecruitingProfileView.swift` (~200 lines) — the in-app preview that mirrors
  what the web page will show: headshot header, bio chips, a **sport-branched
  stat card** (see §3), highlight-clip strip, and the Publish/Share button.
- Integration: a `NavigationLink` in `ProfileView` athlete section, gated
  `.proRequired()`; add to the searchable items array for discoverability.

---

## Phase 2 — Publish + public web profile (~6–8 days)

> ⚠️ Greenfield backend. There is currently **one** `onRequest` function
> (`appStoreServerNotifications`, `index.ts:3295`) and **no `firebase.json`
> hosting block**. `playerpath.net/invitation/...` in the emails are links to
> the external marketing site, *not* a served Cloud Function. So page-serving is
> net-new. The **signed-URL** pattern, however, already exists
> (`index.ts:2736`, `shared_folders/...getSignedUrl`) and is reusable.

### 2A. New collection `recruitingProfiles/{profileId}`

```
recruitingProfiles/{profileId}
  ├── athleteFirestoreId, userId
  ├── shareToken            // UUID, unguessable, STABLE forever
  ├── isPublished: Bool
  ├── sport: "baseball|softball|golf"
  ├── name, gradYear, heightInches, weightPounds, highSchool, hometown
  ├── gpa?, headshotURL?, contactEmail?, contactPhone?, achievements?
  ├── bio: { position, secondaryPositions, batsThrows, sixtyYardDash,
  │          exitVeloMph, throwingVeloMph, pitchVeloMph,           // baseball/softball
  │          driverSwingSpeedMph, driverCarryYards }                // golf
  ├── stats: { ...sport-branched snapshot... }   // see §3 — denormalized at publish
  ├── seasonStats: [ ...per-season rows... ]
  ├── highlightVideoIds: [String]   // ≤ 8, from athlete's isHighlight clips
  ├── viewCount, lastViewedAt, createdAt, updatedAt
```

Top-level (not under `users/`) because it must be readable by **unauthenticated**
college coaches. Rule: `allow read: if resource.data.isPublished == true;` plus
owner read/write. Unpublish → page returns "Profile unavailable", token never
rotates (a coach's bookmark stays valid).

### 2B. `RecruitingProfileService.swift` (~160 lines)

`publish(athlete:season?:highlightVideoIds:contact:) -> shareToken`:
- Computes the **stat snapshot at publish time** (§3), sport-branched.
- Writes/updates the `recruitingProfiles/` doc; generates `shareToken =
  UUID().uuidString` on first publish.
- `unpublish()`, `refreshStats()` (re-snapshot), `fetchViewCount()`.

### 2C. `serveRecruitingProfile` Cloud Function (~250 lines, new onRequest)

Looks up by `shareToken` where `isPublished == true`; signs highlight-video URLs
(reuse `index.ts:2736` pattern, 1-hour expiry) and the headshot; increments
`viewCount`; renders a template-literal HTML page (no framework) with:
- **Open Graph tags** — this is the magic. `og:title` =
  `Jordan R. · Class of 2027 · SS` and `og:description` carries the headline
  stat line, so the link unfurls beautifully in iMessage/email/X.
- **Video grid first** (inline `<video controls>` players), then bio, then the
  sport-weighted stat band (§3), then contact block. Footer: "Game film recorded
  & tagged in PlayerPath" — lean on the film, not a stat-credibility claim.

### 2D. Hosting / domain — **open decision for Trey (DNS-level)**

No hosting exists. Options, pick one:
- **Firebase Hosting rewrite** — add a `hosting` block to `firebase.json` with
  `/p/** → serveRecruitingProfile`, deploy `--only hosting,functions`. Needs a
  domain/subdomain pointed at Firebase Hosting.
- **Subdomain** — e.g. `profiles.playerpath.net` CNAME'd to Firebase Hosting,
  keeping the marketing site on the apex untouched. **Recommended** — cleanest
  separation, link reads as official.
- **Function URL directly** — ugly URL, no custom domain; fine for a private
  beta only.

This is the one thing I can't resolve from the codebase — it depends on how
`playerpath.net` DNS is managed.

### 2E. Share UI

- `RecruitingProfilePublishView.swift` (~120 lines): publish toggle, the live
  URL, a native `ShareLink`, view count ("Viewed 12 times"), per-field privacy
  opt-ins (GPA, contact email, contact phone).
- `RecruitingHighlightPicker.swift` (~100 lines): toggle/reorder from clips where
  `isHighlight == true`, cap 8 (controls page load + egress cost).

---

## 3. Video-first; stats are a sport-weighted secondary band

Every profile **leads with the highlight clips**. The stat treatment then
branches on `athlete.sport`, because recruiting value differs sharply by sport.

### Baseball / softball — DE-EMPHASIZE stats
Coaches discount self-logged HS batting/pitching stats (above). So **do not lead
with a tracked-stat band**, and don't build the `AthleteStatistics` snapshot for
v1. Instead:
- Profile = headshot + bio + contact + **clips** (the whole point).
- Optional **measurables row** the athlete opts into, clearly self-entered: 60
  time, exit velo, throwing velo, pitch velo (the `RecruitingInfo` manual fields).
  These are what a coach scans as a first filter — but they're bio, not a moat.
- *Optional, off by default:* a compact single season stat line for context only.
  Skippable for v1. If shown, source from `AthleteStatistics`
  (`totalGames, atBats, hits, homeRuns, runs, rbis` + computed
  `battingAverage/ops`). Treat as "nice to have," not the headline.

### Golf — full scoring band (this is the recruiting currency)
Golf scoring is objective and *is* what college coaches recruit on, so the golf
stat band carries real weight and is worth the full treatment. All sources
already shipped in V29:
- `HandicapEstimator.estimatedIndex(for:season:) -> Double?` → **Est. handicap**
- `GolfExportSummary` (`GolfExportData.swift:45`): `totalRounds, bestScore,
  tournamentAverage` → **scoring average, best round, rounds played**
- `GolfAdvancedStats` (`GolfExportData.swift:74`): `girPct, firPct,
  scramblingPct, puttsPerRound, par3/4/5Avg` → detailed grid (hidden when
  `hasDetailed == false`)
- `GolfExportData.tournamentRounds(for:season:)` → recent scored rounds

Lead stat line: `+2.4 Hcp · 74.1 Avg · 68 Best`. Reuse `GolfExportData` /
`HandicapEstimator` directly so the profile never disagrees with the in-app Stats
screen. **Snapshot tournament rounds specifically** — practice-round scores carry
no recruiting credibility, mirror the existing `tournamentRounds` filter.

---

## 4. Pricing fit, privacy, effort

**Gating:** Pro-only (`.proRequired()`). Strategically this is the **headline
athlete-Pro hook after the V2 pivot** — V2 makes coach-sharing free and
re-anchors athlete tiers on storage + highlights + multi-athlete, removing other
Pro reasons. Recruiting becomes a primary reason a high-school family pays Pro.
So: build it *after* V2 ships, as the next athlete-Pro feature.

**Privacy / COPPA (it's high-school minors):**
- Per-field opt-in for GPA, contact email, contact phone — default off.
- Account owner (often a parent) controls publishing.
- Unguessable token; no PII in the URL; unpublish hides immediately.
- No age gate exists in the app today — COPPA applies under 13; gate or
  age-confirm before publish.

**Effort (PDF cut; baseball stat snapshot cut → video-first):**

| Phase | Est. | Notes |
|---|---|---|
| 1 — blob model + V30 + sync wiring + editor + in-app preview | 3–4 days | sport-branched UI; baseball = video + measurables only |
| 2 — publish service + collection + rules + hosting + CF + share UI | 6–8 days | greenfield page-serving; signed-URL pattern reused; golf stat snapshot only |
| **Total** | **9–12 days** | + DNS/hosting decision (2D) |

**Open decisions before building:**
1. Hosting/domain (§2D) — needs DNS access. **(only true blocker)**
2. Baseball/softball stat band — recommend **video + optional self-entered
   measurables, no tracked-stat band** for v1 (coaches discount it). Confirm, or
   include the optional context season line.
3. Manual measurables — include exit velo / 60 / pitch velo / driver speed as
   opt-in bio fields? Recommend yes (it's the first-filter row coaches scan), but
   label them as athlete-entered, not "tracked."
4. One profile per athlete row (Pro = up to 5) — confirm multi-athlete UX.

**Build order:** ship V2 first (device-tested) → Phase 1 → validate fill-in rate
via `recruiting_profile_created` analytics → Phase 2.
