# Recruiting Profile — Phase 1 Implementation (progress / handoff)

**Branch:** `feature/recruiting-profile-phase1` (off `main`)
**Date:** 2026-06-27
**Status:** Phase 1 code complete, **builds green** for iphonesimulator (no warnings), `sync-field-check` clean. **Not merged, not committed, not device-tested.**

Companion docs: the build plan is [`RECRUITING_PROFILE_PLAN.md`](RECRUITING_PROFILE_PLAN.md); the roadmap framing is [`PRIORITIES.md`](PRIORITIES.md) (#6, the "next needle mover"). This doc records what actually landed on the branch.

---

## Scope shipped (Phase 1 = in-app only)

A Pro-gated, in-app **recruiting profile**: an athlete bio (single JSON blob on `Athlete`) + a sport-branched **editor** and an in-app **preview** that mirrors the eventual public page. Video-first: highlights lead; golf gets a full derived stat band; baseball/softball get opt-in self-entered measurables. **Nothing is published** — no public Firestore collection, no Cloud Function, no web surface. That's Phase 2.

Locked decisions (with the user):
- **Scope:** Phase 1 first, ship and watch fill-in rate (analytics) before building the web page.
- **Baseball/softball:** video-first; opt-in, clearly self-entered measurables (60 / exit / throwing / pitch velo); **no** tracked batting/pitching stat band.
- **Golf:** full stat band, derived live (scoring is the recruiting currency).
- **PII/COPPA:** per-field opt-in toggles (GPA, contact email/phone — default OFF) in the model+editor; the publish-time consent gate is Phase 2.
- **Gating:** Pro (`.proRequired()`).

---

## What was built

### Data model
- **NEW `PlayerPath/Models/RecruitingInfo.swift`** — `nonisolated` `Codable, Equatable` bio blob (flat, all optional/defaulted, `schemaVersion` for forward-compat). Custom `init(from:)` using `decodeIfPresent` so older/newer blobs never throw. Marked `nonisolated` because the module is MainActor-by-default and `JSONDecoder/Encoder` use the conformance from a nonisolated context. Includes display helpers (`locationLine`, `heightFormatted`, `filledFieldCount`) and the **`extension Athlete { var recruiting }`** accessor — decode/encode the blob, set `needsSync = true` only (**not** `version` — that's bumped in `uploadLocalAthletes`).
- **`Athlete.swift`** — new stored `var recruitingProfileJSON: String?`; `toFirestoreData()` converted to a mutable dict + if-let append; best-effort headshot delete in `delete(in:)`.

### Schema (V33)
- **`PlayerPathSchema.swift`** — `enum SchemaV33` (mirrors V32) + appended to `schemas` + a `.lightweight(V32→V33)` stage.
- **`PlayerPathApp.swift`** — both container inits bumped `Schema(SchemaV32.models)` → `V33`.
- ⚠️ The runtime container has **no `migrationPlan:`** by design (all `SchemaV#` enums reference the same live classes → a real plan throws duplicate-checksum). The load-bearing change is **adding the optional property to the live `Athlete` class**; SwiftData does automatic lightweight migration. The `SchemaV33` enum + stage are convention bookkeeping only.

### Sync wiring (all 5 athlete sites — `sync-field-check` clean)
- `Athlete.toFirestoreData()` writes the field (covers `createAthlete`, which sends the full dict).
- `FirestoreManager+EntitySync.updateAthlete` `allowedFields` includes `recruitingProfileJSON` (the silent-drop line).
- `FirestoreModels.FirestoreAthlete` — field + `CodingKeys` case (synthesized `Codable`, the only athlete parser).
- `SyncCoordinator+Athletes.downloadRemoteAthletes` — update branch (compare + set `changed`) and new-athlete creation branch.

### Headshot → Firebase Storage
- **`VideoCloudManager+Photos.swift`** — `uploadRecruitingHeadshot(imageData:athleteId:ownerUID:)` (`putData`, athleteId-keyed path `recruiting_headshots/{uid}/{athleteId}.jpg`, overwrite-in-place) + `deleteRecruitingHeadshot(...)` (idempotent; treats `objectNotFound` as success). `ProfileImageManager` is local-only and could not be reused (a device-local path can't sync via the blob).
- **`storage.rules`** — NEW owner-scoped `recruiting_headshots/{userID}/{fileName}` rule (read/write/delete by owner; image, ≤10MB). **Must be deployed before headshots work on-device.**
- Editor picks via `PhotosPicker`, downscales to ≤1024px JPEG (`UIImage.recruitingHeadshotData`), uploads, stores the **download-URL string** in `RecruitingInfo.headshotCloudURL`.

### Gating
- **`RoleBasedViewModifiers.swift`** — `proRequired()` mirroring `plusRequired()` (uses `TierGateModifier(requiredTier: .pro)`).

### Views — `PlayerPath/Views/Recruiting/` (all new)
- `RecruitingProfileEditorView.swift` — `Form`: headshot, basics (grad-year/height pickers, weight/city/state/HS/club), about, sport-branched section (baseball → `RecruitingBaseballSection`; golf → an auto-stats note), PII section, "Preview Profile" link. Persists + syncs on `onDisappear` only when the blob changed; fires analytics; tracks screen view.
- `RecruitingProfileView.swift` — in-app preview (header + highlight strip + golf band / measurables + contact + bio). Takes `info` (so it can preview unsaved edits) + `athlete` (clips + live golf stats).
- `RecruitingProfileComponents.swift` — `RecruitingHeadshotImage`, `RecruitingHighlightStrip` (reuses `VideoThumbnailView`, ≤8 `isHighlight` clips, read-only in Phase 1), `RecruitingNumberField`, `UIImage.recruitingHeadshotData`.
- `RecruitingGolfStatBand.swift` — derived live from `HandicapEstimator` + `GolfExportData`; **tournament rounds only** for avg/best/rounds (so it agrees with the footer and doesn't show practice scores to recruiters); reuses `CompactStatChip`.
- `RecruitingEditorSections.swift` — `RecruitingBaseballSection`, `RecruitingPIISection`, and the `Binding<String?>.orEmpty()` bridge.

### Integration & analytics
- **`ProfileView.swift`** — gated `NavigationLink` ("Recruiting Profile", `graduationcap.fill`) in `athletesSection` + a `SearchResult` registration.
- **`AnalyticsService.swift`** — `recruiting_profile_created` / `recruiting_profile_edited` events + `trackRecruitingProfileSaved(athleteID:sport:isFirstSave:hasHeadshot:fieldsCompleted:)`. `isFirstSave` captured before assign. Feeds the fill-in-rate metric that gates Phase 2.

---

## Review (project reviewer + self-review)

No blockers. Fixed during review:
1. **Headshot "Remove" leaked the Storage object permanently** (the daily cleanup CF only sweeps `videos`; athlete-delete guards on non-nil URL). → Remove now best-effort-deletes; comments corrected.
2. **Golf band counted practice rounds** in Best/Rounds while claiming "tournament only." → Now tournament-only, consistent with the avg + footer.
3. **`athlete.id` read after `await`** in `uploadHeadshot` (model-access-across-await trap). → Snapshotted before the await.
4. **Locale decimal parsing** — `Double(_)` dropped `,`-locale entries. → Normalize `,`→`.`.
5. Comment accuracy (storage rule vs tokenized download URLs; daily-CF claim).
6. Grad-year Picker could drop a saved out-of-range year. → Options union the saved value.

Accepted as-is (not bugs):
- **Whole-blob last-write-wins** — concurrent cross-field edits on two devices clobber each other (same as `scorecardData`); fine for Phase 1 single-device editing.
- **Opted-out PII is stored** in the owner's *private* athlete doc — not a leak in Phase 1. **Phase 2 publish must filter on the `include*` flags server-side**, not trust the client preview (especially for minors).

---

## Verification status
- ✅ Full `xcodebuild` (iphonesimulator) — **BUILD SUCCEEDED**, no warnings in touched files.
- ✅ `sync-field-check recruitingProfileJSON` — all 8 sites present.
- ⬜ On-device over-the-top **V32→V33 migration test** (a failed migration silently falls back to in-memory and *looks* like data loss).
- ⬜ Smoke test: Pro gating, round-trip persist + relaunch, cross-device sync, preview correctness (PII hidden when off; golf <3 rounds), analytics in DEBUG console.

## Before merge (manual / outward-facing — not yet done)
1. **`firebase deploy --only storage`** — the new `recruiting_headshots/` rule must be live or on-device headshot upload is denied.
2. On-device migration test (above).
3. Smoke test (above).

## Out of scope here — Phase 2 (next branch), decisions pre-made
Public page: top-level `recruitingProfiles/{profileId}` collection (read iff `isPublished`), a `serveRecruitingProfile` `onRequest` CF rendering server-side HTML with **Open Graph tags**, CF-signed highlight + headshot URLs (reuse `getSignedVideoURL`), view-count via `FieldValue.increment` (rate-limited), publish/share service (snapshot golf stats at publish), share UI (`ShareLink`, ≤8-clip curation). **Hosting (decided):** `profiles.playerpath.net` → Firebase Hosting rewrite to the CF (needs DNS access). **Consent gate (decided):** account-owner/parent consent before first publish + the per-field opt-ins; minor contact gated, server-side filtered.

---

*Files touched (12 modified, 6 new): `Models/Athlete.swift`, `Models/RecruitingInfo.swift` (new), `PlayerPathSchema.swift`, `PlayerPathApp.swift`, `FirestoreManager+EntitySync.swift`, `FirestoreModels.swift`, `SyncCoordinator+Athletes.swift`, `VideoCloudManager+Photos.swift`, `RoleBasedViewModifiers.swift`, `ProfileView.swift`, `Services/AnalyticsService.swift`, `storage.rules`, and `Views/Recruiting/{RecruitingProfileEditorView, RecruitingProfileView, RecruitingProfileComponents, RecruitingGolfStatBand, RecruitingEditorSections}.swift` (new).*
