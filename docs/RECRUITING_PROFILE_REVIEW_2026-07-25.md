# Recruiting Profile — Implementation Review & Fix Plan

**Date:** 2026-07-25 · **Reviewed at:** working tree on `main`, uncommitted, `MARKETING_VERSION 6.4.2` / `CURRENT_PROJECT_VERSION 206`
**Scope:** Phase 1 + Phase 2 (public link) + Phase 3 (analytics/push/share tools) + the uncommitted Reset Link & share-card polish.
**Method:** 7 parallel dimension reviewers (rules/authz, Cloud Function, Swift service, SwiftUI, sync/model, push loop, product) → adversarial refutation pass → completeness critic. 36 findings survived refutation, 7 were refuted, 4 added by the critic.

---

## 0. FIX STATUS — read this first (updated 2026-07-26, client batch)

**37 of 40 findings are DONE, 1 is partial, 2 are left.** (Earlier drafts said "12 left" — that number
double-counted the device-test line and never reconciled: 32 + 1 + 12 = 45 against a 40-finding total.
Recounted item by item below; the real remainder is **P3.7** and **N2**.)

✅ **CLIENT BATCH — 2026-07-26, committed on top of `f9d8308`.** P3.4, P3.3 (warning half), P3.8, P3.9 and
N3, all client-only, no CF redeploy and no schema change. Build gate: **BUILD SUCCEEDED**.
**Version bumped to 6.4.3 / 207** (both Debug and Release) — this tree is ready for a device build.

**§9 execution order steps 1–15 are COMPLETE (2026-07-26): the P3.2 CF deploy, the five cheap P4 fixes, and
the whole CF batch — P2.2, P4.1, P4.2, P4.3, P4.9 — plus new finding N1.**

✅ **CF BATCH DEPLOYED 2026-07-26** (`npm run build` → freshness guard → all functions "Successful update").
Live proof the new segment parser shipped: `/p/{token}/poster` now 404s as **text/plain**, where the old
build treated `poster` as the token and returned an HTML 404 page.

⚠️ **The client half is NOT on any device yet.** `sport` in the subline and `filmDateRange` are written by
`publish()`, so until Trey builds the current tree and REPUBLISHES, a live page shows the new film header,
clip count, runtime, provenance and "Updated ‹Month›" — but **no date range and no sport**. Those two are not
broken; the fields simply aren't on the doc yet.

**Next: device tests.** One publish round-trip is done (page renders, view count ticks); everything else is
untested.

⚠️ **The rules-test gate could NOT be run this session** — `firebase emulators:exec` needs a JVM and this
machine has only the `/usr/bin/java` stub (no JDK). `firestore.rules` was not modified, and the one new
client-written field (`filmDateRange`) passes because `recruitingProfiles` uses `hasAll`, not `hasOnly` —
but the 42/42 suite is unverified since the earlier release. Re-run it wherever Java is available.
Do not re-do anything marked ✅ DONE below; §2's "not yet deployed" table is now obsolete.
(Note: the execution order is §9 — earlier drafts of this doc called it §7.)

| Finding | Status |
|---|---|
| §7.1 `firestore.rules` release (+ **P2.7** folded in) | ✅ **DONE — RELEASED TO PROD.** Reset Link was denied in prod before this. 42/42 rules tests. |
| **P0.1** codec (HEVC/.mov → H.264 `.mp4` rendition) | ✅ **DONE.** Client: new `Services/RecruitingWebRenditionService.swift`. CF: `mimeForPath` + `<source>` + `.vfallback`. |
| **P3.5** portrait hero height cap | ✅ DONE (folded into the same CSS edit). |
| **P1.1** paywall→publish tier race | ✅ DONE (awaited tier sync, `.tierNotSyncedYet`, `pendingError` deferral). |
| **P1.2** cached read resurrects a killed link | ✅ DONE (`getDocument(source: .server)`). |
| **P1.6** offline publish hangs the kill switch | ✅ DONE (`ConnectivityMonitor` guards on publish/unpublish/resetLink). |
| **P1.3** sync clobbers the blob | ✅ DONE (`Athlete.mergedRecruitingBlob` on both sync directions). |
| **P1.4** unknown blob keys dropped on re-encode | ✅ DONE (`unknownKeys` sidecar + hand-written encoder + lenient decoder). |
| **P4.7** `resetLink` doc comment backwards | ✅ DONE. |
| Cloud Functions deploy | ✅ **DEPLOYED**, incl. `athleteId` payload + `pendingByUser` digest grouping (live for the first time). |
| **P1.5** push deep-link self-cancels | ✅ DONE (`pendingMoreDestination` consumed after the athlete-switch resets). |
| **P1.7** notification prefs clobbered across devices | ✅ DONE (new `fetchNotificationPreferences()` → seed locals, back-fill only unset keys, failed read writes nothing). |
| **P1.8** publish races the headshot upload | ✅ DONE (`.disabled(isUploadingHeadshot)` on Share Profile + Preview, `persistIfChanged()` after upload). |
| **P2.1** failed status read reads as never-published | ✅ DONE (`statusLoadFailed` + `statusUnavailableSection` retry row). **Note the row is rendered ABOVE the normal layout, not instead of it** — the doc's original fix text said "instead", but that hides the clip picker, consent and publish button, leaving a never-published athlete offline with nothing to do. The live-state sections are already keyed on non-nil `status`, so they stay hidden by themselves. |
| **P2.5** `selection` not reconciled after publish | ✅ DONE (`selection = result.publishedClipIDs`). |
| **P2.3** unmetered/un-deduped render | ✅ **DONE — DEPLOYED.** Signed-URL memo (`signedUrlCache`, ~1 signBlob/path/hour on a warm instance), `.runWith({maxInstances:20,timeoutSeconds:30})`, per-viewer counter dedup (`alreadyCountedRecently`, sha256 of IP+token+UTC-hour, per-instance LRU). |
| **P2.4** page held by a stalled FCM send | ✅ **DONE — DEPLOYED.** `Promise.race` against `PUSH_SEND_BUDGET_MS` (1500 ms). |
| **P2.6** instant push throttled per profile | ✅ **DONE — DEPLOYED.** Quiet window moved to `users/{uid}.lastRecruitingNotifiedAt` (read in the same transaction); `notifiedViewCount` stays per doc. |
| **P2.9** digest re-arms the instant window | ✅ **DONE — DEPLOYED.** Digest now stamps `lastDigestAt`; `lastNotifiedAt` is retired (inert on old docs) and `lastDigestAt` joined the publish carry-forward list. |
| **P3.6** 1 h signed URLs die in an open tab | ✅ **DONE — DEPLOYED.** `SIGNED_URL_HOURS = 8`; the static `<video>` fallback already shipped with P0.1. |
| **P2.8** digest has no `runWith` (scale-conditional) | 🟡 **PARTIAL — DEPLOYED.** `.runWith({timeoutSeconds:540, memory:'512MB'})` added. **Query paging/batching still not done.** |
| **P3.1** nothing flags a stale published page | ✅ DONE (client-only, no new persistence). Editor status block gained a **"N new highlights aren't on your page yet — Update"** row (`staleHighlightsRow` + `refreshStaleHighlightCount`, recomputed on `.task` / `.onAppear` / return from publish) plus a **"Live since <date>"** line. Also fixed the dead-end it exposed: at the 8-clip cap the picker's unselected rows were disabled with no explanation, so the nudge sent people to a screen that refused them — `RecruitingHighlightPicker` now says "Your page holds 8 clips. Remove one above to add another." |
| **P3.2** growth loop unmeasurable | ✅ **DONE — DEPLOYED 2026-07-26.** (`npm run build` → freshness guard passed → `firebase deploy --only functions`, all functions "Successful update"; compiled `lib/recruitingProfile.js` confirmed to carry `channelViews` ×5 and all three `utm_*` params.) (a) all 3 footer hrefs now use `MARKETING_HREF` with utm params; (b) new `RecruitingShareTools.ShareChannel` + `taggedURL(_:channel:)` stamps `?s=share\|copy\|qr\|mail\|bio` at all 6 share call sites, and the render path buckets it as `channelViews.<s>` behind a **whitelist** (the value becomes a Firestore FIELD PATH — a dot would create nested fields); (c) the digest log now reports new-views-in-window + lifetime views by channel. `channelViews` joined the publish carry-forward list. |
| **P4.10** golf profiles publish baseball measurables | ✅ DONE (`let measurables = isGolf ? [] : info.measurableItems` in `applyBio`). |
| **P4.5** editor view-count row not Pro-gated | ✅ DONE (`if isPro, let status, status.isPublished`). Gates the "Live since" line too — a lapsed page isn't live. |
| **P4.8** `noPublishableClips` wrong copy when files are gone | ✅ DONE (new `RecruitingPublishError.highlightsMissingFromCloud`, thrown only from the post-Storage-probe `kept.isEmpty` guard; the pre-probe guard keeps the "still uploading" copy). |
| **P4.4** golf band reads as verified | ✅ DONE (`RecruitingGolfStats.footnote` now leads with "Scores entered by the athlete in PlayerPath."; single source, so band + page move together). |
| **P4.6** QR has no accessibility label | ✅ DONE (`.accessibilityLabel` + `.accessibilityValue(displayLink)`, **and** the link now always renders under the code — a scanner that won't focus had no fallback). |
| **P2.2** deleted Storage objects render as playable clips | ✅ **DONE — DEPLOYED 2026-07-26.** New `objectMissing()` probes `file.exists()` in parallel with signing (a thrown error is NOT treated as absence — a GCS blip must not blank a healthy page). Three outcomes per highlight (`ok` / `gone` / `failed`) because they need opposite responses: `gone` is permanent and dropped quietly, `failed` is usually the signBlob role and still 500s. All-gone now renders `filmRemovedSection()` — the rest of the profile still serves — instead of "temporarily unavailable, try again shortly", which was the same wrong-copy defect as P4.8. |
| **P4.9** empty UA counts as human; mail scanners inflate | ✅ **DONE — DEPLOYED 2026-07-26.** New `looksLikeBot(req)`: empty UA → bot, plus **`Accept` must contain `text/html`**, which is what catches Defender/Proofpoint/Mimecast fetching with a real Chrome UA. Rationale recorded in-code: over-counting is worse than under-counting here because a phantom view *burns the 24 h quiet window*, silently demoting the real coach's view to that night's digest. ⚠️ **curl no longer counts as a view** — add `-H 'Accept: text/html'` to test the counting path. |
| **P4.1** `og:image` nil without a headshot | ✅ **DONE — DEPLOYED 2026-07-26.** `serveAvatar` → `serveProxiedImage(res, token, kind)` with `kind: 'avatar' \| 'poster'`; new `/p/{token}/poster` route in the same segment parser; `ogImage` falls back to the hero clip's thumbnail. Keyed on `rawHighlights[0]` (what the route re-derives), not the rendered `clips[0]`, so tag and route can't disagree. Still goes through `ownedPath`. |
| **P4.2** renderer drops sport / updatedAt / duration | ✅ **DONE — DEPLOYED 2026-07-26.** `subline(isGolf:)` → **`subline(sport:)`** and now names the sport, so it reaches the page header AND `og:title` (4 call sites updated — note `coachEmailURL` was a 4th site a `subline(` grep misses). Footer renders "Updated \<Month YYYY\>" from `updatedAt` (already written by publish; month granularity + UTC). Per-clip `durationSeconds` now shows in captions — worth the space precisely because grid clips are `preload="none"`, so the browser shows no duration until clicked. |
| **P4.3** film section has no header or provenance | ✅ **DONE — DEPLOYED 2026-07-26.** `<h2>Game Film</h2>` + `8 clips · 3:12 · tagged in PlayerPath · Feb–Jun 2026`. **"tagged", not "recorded & tagged"** — clips can be imported from Photos, so "recorded in PlayerPath" is false for some; the same reasoning as measurables' "self-reported". The footer's old provenance sentence was replaced by "Updated \<Month\> · PlayerPath" so the claim isn't duplicated. Date range is built Swift-side (`RecruitingProfileService.filmDateRange`, new `filmDateRange` doc field) off the same `gameDate ?? practiceDate ?? createdAt` precedence the captions use, so the range can't disagree with the dates under the clips. |
| **P3.4** no minimum-viable-profile bar | ✅ **DONE 2026-07-26.** New `Views/Recruiting/RecruitingReadinessSection.swift` (own file — the publish view was already ~630 lines): a `RecruitingReadinessItem` list + a Section that renders **only while something is unmet**, matching the app's surface-a-problem-and-stay-quiet convention (stale-highlight nudge, status-unavailable row). Publish stays enabled. Header counts "3 of 5". **Golf drops the Position row** rather than showing a box that can never be ticked — golf has no positions, so every golf profile would otherwise read as permanently incomplete (same reasoning as P4.10). No clips row either: `canPublish` already requires a non-empty selection, so it could never be unticked. Rows are computed **once per `load()` into @State**, not in `body` — the items read `athlete.recruiting`, which decodes a JSON blob. A "Fill These In" button calls `dismiss()`, which is safe as a pop because the editor is this screen's ONLY route in. |
| **P3.3** published page can dead-end (warning half) | ✅ **DONE 2026-07-26.** ⚠️ **Placed in the readiness checklist, not the publish footer as the fix text said** — it rides the "Email or phone" row's consequence line ("A coach who scans your QR code has no way to reach you."), which is the same screen and the same moment but sits next to the item it's about instead of stacking a third sentence under the button. Same for P3.4's grad-year line ("Recruiting class is the first thing a coach filters on."). Coverage is equivalent: the section renders whenever either is missing. **The coach/parent reference block is NOT done and was never part of this finding's defect** — the fix text scoped it as a separate feature proposal. |
| **P3.8** unpublish keeps PII + headshot at rest | ✅ **DONE 2026-07-26.** New `deleteDataSection` + `deleteProfileData()`: `deleteProfileDoc` then a best-effort `deleteRecruitingHeadshot`, and it **clears `headshotCloudURL` locally** because the stored download URL 404s once the object is gone (safe to propagate — only `publishConsentAt` and `publishedClipIDs` are nil-protected by `mergedRecruitingBlob`). **Not tier-gated**, same reasoning as unpublish. Needed its own **connectivity guard in the view**, NOT in the service: `deleteProfileDoc` is deliberately unguarded so `Athlete.delete` can ride Firestore's offline queue rather than skip and leave a deleted athlete's page live — but as a foreground action behind `isWorking` it would hang with the kill switch disabled (P1.6's failure). `status` is set to nil **directly instead of via `refreshStatus`**, since a throwing re-read would raise "couldn't check whether this profile is live" over a profile just deleted on purpose. New `recruiting_profile_data_deleted` analytics event rather than reusing unpublish — this is a family withdrawing, not seasonal churn. |
| **P3.9** two-sport athletes break `name · sport` | ✅ **DONE 2026-07-26.** New `Athlete.nameWithSportIfShared` (same `siblings > 1` rule as `PPAthleteSwitcher.rowTitle`) applied at 5 surfaces: the editor header, the Profile-tab row, the More-tab row, `RecruitingShareCard`, and the QR sheet. **Deliberately NOT the mailto subject or the page `<h1>`** — both already carry `subline`, which names the sport since P4.2, so qualifying the name there would print it twice ("Jordan Smith · Golf — Class of 2027 · Golf — Game Film"). That's also why the CF needs no redeploy for this finding. |
| **P3.7, N2, P2.8 (rest)** | ⬜ **NOT STARTED** — the whole remainder. |

**P3.2 notes.** `displayLink` strips the query, so the on-screen URL never shows the marker while every shared
copy carries it. `mail` and `bio` are tagged INSIDE `coachEmailURL`/`bioBlurb` (those builders own their
channel, so a future caller can't forget); `share`/`copy`/`qr` are tagged at their call sites, including the
two email-fallback pasteboard writes. Attribution is **first-touch** — a forwarded link keeps the original
marker, which is the intended reading. **Deliberately did NOT add client-side share analytics events:**
`ShareLink` is a system component with no completion callback, so `share` — likely the biggest channel —
cannot be instrumented client-side, and a funnel that systematically undercounts its largest entry is worse
than none. Server-side `channelViews` covers all five channels uniformly instead.

**P3.1 judgement calls worth knowing:** the count stays **silent when `publishedClipIDs` is nil** (a profile
published before curation was persisted has unknown page contents — claiming staleness there would be a
guess; the next publish heals it). And the date reads **"Live since"**, not "last updated", because
`publishedAt` is carried forward from the FIRST publish (`RecruitingProfileService`), so freshness wording
would tell someone who republished yesterday that their page is months old. A true last-updated line would
need a new `updatedAt` field on the doc — deliberately not added, since the fix was scoped "no new
persistence". Golf-stat staleness is still unsurfaced (snapshots aren't diffable client-side).

✅ **FUNCTIONS DEPLOYED 2026-07-25** (`npm run build` → freshness guard passed → `firebase deploy --only
functions`, all functions "Successful update"). Verified live: `recruitingViewDigest` now reports **512 MB**
(was the 256 MB default), proving the new `runWith` config shipped, and a bot-UA request to a nonexistent
token on `https://profiles.playerpath.net` returns **404 + the styled "Profile unavailable" page**. Rules were
NOT touched by this batch.

### Self-review of the 2026-07-26 batch — 2 defects found in the fixes themselves

Both were caught reviewing the batch AFTER it deployed, and both are now fixed and redeployed.

| # | Defect I introduced | Fix |
|---|---|---|
| **S1** | **N1's rendition delete was a third SERIAL round-trip** inside `dailyStorageCleanup`'s purge loop — which iterates up to 500 documents against the **60 s default timeout** (the file has no `runWith` anywhere), and whose sections 2 and 3 (pending deletions, expired invitations) run only if section 1 returns. Worse, the rendition 404s for every clip that was never published, i.e. almost all of them, and a 404 costs a full round-trip. I made a plausible pre-existing timeout meaningfully more likely, and the failure mode is silent: the other two cleanup jobs simply never run. | Master + rendition now delete **concurrently** via `Promise.allSettled` (`purgedCount` and the 404-vs-real-error logging preserved per target), and `dailyStorageCleanup` gained `.runWith({ timeoutSeconds: 540 })`. Memory left at 256 MB — the constraint is round-trips, not heap. |
| **S2** | `clockDuration` received `durationSeconds` guarded only by `typeof === 'number' && > 0`. That field is client-written inside `highlights[]`, which **rules cannot type-check**, and Firestore stores NaN/Infinity as legitimate doubles — so `Infinity` would have rendered as `Infinity:NaN:NaN` in a caption on a public page. Self-inflicted only (an athlete's own doc), but free to close. | Added `Number.isFinite`. |

**Checked and found correct** (worth not re-deriving): `missingStoragePaths` marks a path missing **only** on a genuine `objectNotFound` — a transient network error yields `isGone = false`. So P4.8's new `highlightsMissingFromCloud` copy ("no longer in your cloud backup") cannot fire on a connectivity blip, which would have been the same wrong-copy defect P4.8 exists to fix. Also verified: the JS rendition base-name derivation matches Swift's `NSString.deletingPathExtension` for multi-dot and extensionless names.

### Self-review of client batch #2 — 4 defects found in the fixes themselves

Same pattern as the S1/S2 pass: reviewing the batch after writing it. All four are fixed, build re-verified.

| # | Defect I introduced | Fix |
|---|---|---|
| **S3** | **P3.8's headshot clear was resurrected on the way out.** `RecruitingProfileEditorView` holds `working: RecruitingInfo` snapshotted in `init`, and its `.onDisappear` → `persistIfChanged` writes that snapshot back. My delete path set `headshotCloudURL = nil` from the *pushed* publish screen — so returning to the editor and leaving re-wrote the stale URL, pointing at a Storage object I had just deleted. **Not an edge case: the publish screen's only exit is back to the editor, so it fired every time.** Consequences compounded — a broken headshot in the editor with a live "Remove" button, and the next publish stamping a dead `headshotPath` onto the public page (`headshotPath()` keys purely on `headshotCloudURL != nil`). This is the footgun `persistIfChanged`'s own comment warns about — *"Any new field written by a pushed screen needs a line here"* — and I walked straight into it. | Re-seed `working.headshotCloudURL` from the saved blob in the editor's existing `.onChange(of: showingPublish)` return handler. **Deliberately NOT a line in `persistIfChanged`'s carry-forward block**: that block is "saved wins if non-nil" and this is a deliberate nil-CLEAR, which that rule would discard — and it's the same reason the editor's own Remove button can't use that mechanism. Safe unconditionally because `persistIfChanged` runs immediately before the push, so the two agree on every field the publish screen didn't change. |
| **S4** | **The checklist went stale after "Fill These In"** — the one flow it exists to serve. `readiness` was computed only in `load()`, and `.task` runs once per view identity, so a field filled in on the editor and returned from would still read as missing. **The editor had already logged this exact trap** for `staleHighlightCount` ("`.task` runs once per view identity…"), which is what made it findable. | Extracted `refreshReadiness()` (with the `isDeleted`/`modelContext` liveness guard) and called it from `.onAppear` as well as `load()`. |
| **S5** | The checklist reported **"Headshot ✓" immediately after deleting the headshot** — computed at load, never recomputed by the delete path. | `refreshReadiness()` after the blob write. |
| **S6** | `deleteProfileData` had **no `seededAthleteID` witness**, unlike `publish()`. If the view was re-rendered with a different athlete while pushed, the on-screen link and view count still belonged to the loaded athlete while `athlete.id` pointed at the new one — so the tap would delete a profile other than the one displayed. Irreversible. | Added the same guard `publish()` uses. ⚠️ **`unpublish()` and `resetLink()` still lack it** — pre-existing, not touched by this batch, and `resetLink` is irreversible too. Logged below as a follow-up rather than silently changed. |

**Also checked and found correct** (worth not re-deriving): **no Cloud Function writes `updatedAt`** — the view path increments `viewCount`/`dailyViews`/`channelViews` and stamps `lastViewedAt`, and the digest writes `notifiedViewCount`/`lastDigestAt`/prunes, but none touch `updatedAt`. So N3's "updated ‹date›" is a genuine content-freshness signal, not a view counter. The CF's own `updatedLabel` doc comment reaches the same conclusion independently. **Note the deliberate divergence:** the page renders `updatedAt` at **month granularity in UTC** (a coach shouldn't be invited to ask "why does it say yesterday"), while the in-app row renders the **full date in local time** (matching the existing "Live since" line and `DateFormatter.mediumDate`). At a month boundary the page can say "Updated June" while the app says "updated Jul 1" — the same UTC-vs-local tension already accepted for `filmDateRange`. Don't "fix" one to match the other.

**New follow-up (not from the original 40):**
- **`unpublish()` and `resetLink()` lack the `seededAthleteID` witness** that `publish()` and now `deleteProfileData()` carry. Both read `athlete.id` fresh, so on a re-rendered view they act on an athlete other than the one whose link and counts are on screen. `resetLink` is irreversible. ~15 min, client-only.

### New findings — added 2026-07-26, after the original 37

| # | Finding | Status |
|---|---|---|
| **N1** | **A deleted clip keeps playing on the published page.** `dailyStorageCleanup` purged the master by exact name (`athlete_videos/{uid}/{fileName}`) and **nothing anywhere deleted the P0.1 web rendition** at `athlete_videos/{uid}/recruiting/{base}.mp4` — not the client, not the cron. Since a published doc's `videoStoragePath` now points at the *rendition*, P2.2's existence probe would have found it happily present: the athlete deletes a clip, and a college coach can still play it from the public link, forever. Also a silent storage leak (renditions never counted against `cloudStorageUsedBytes`). | ✅ **FIXED — DEPLOYED 2026-07-26.** `dailyStorageCleanup` now deletes the rendition alongside the master. P2.2's probe then drops the tile on the next render. **Residual, NOT fixed:** the ~30-day soft-delete window, during which the deleted clip still plays. Closing that needs a client-side decision — remove the highlight from `recruitingProfiles` at delete time (the "cheaper complement" P2.2's own fix text suggested). |
| **N2** | **The share token is a 36-char UUID** (`claimShareToken` → `UUID().uuidString`), so links read `profiles.playerpath.net/p/1D695788-DEE7-4298-9966-EE8…`. Not a security issue — freshly random, 122 bits, and deliberately *not* the athlete UUID, so nothing is enumerable. It is a product cost, and it lands on exactly the channels this feature bets on: the success sheet truncates it, it can't be read aloud at a showcase, it can't be typed from the QR screen's fallback text, and it eats a third of an Instagram bio. | ⬜ **NOT STARTED.** Fix: a short random slug (~10 base32 chars ≈ 50 bits; the claim loop already retries on collision). **`TOKEN_RE` is UUID-strict and must keep accepting UUIDs** or every already-shared link dies. Interacts with §8.1.9's "re-key profiles by shareToken" option. |
| **N3** | The doc's P3.1 note says a true last-updated line "would need a new `updatedAt` field". **That field already exists** — publish has always written it (`RecruitingProfileService`), which is why P4.2 could render it server-side with no schema work. The in-app editor could show "Updated \<date\>" instead of / alongside "Live since" by adding it to `RecruitingPublishStatus`. | ✅ **DONE 2026-07-26.** `RecruitingPublishStatus` gained `updatedAt`, parsed in `fetchStatus`; the editor's clock row now reads **"Live since Feb 3, 2026 · updated Jul 26, 2026"** via a new `liveSinceText(publishedAt:updatedAt:)`. **Both dates, not one** — `publishedAt` alone tells someone who republished this morning their page is months old, and `updatedAt` alone loses how long the link has been in circulation. The updated half is **suppressed on the same calendar day** so a fresh first publish doesn't read "live since today · updated today", and both use the full date because a bare "Jul 26" repeats P4.2's year-ambiguity defect. `resetLink`'s local status reconstruction stamps `updatedAt: Date()` to mirror the server write — otherwise the row would show a date older than an action just taken. Note `updatedAt` also moves on **unpublish**, so it means "when the page last changed", including going dark. |

### Scoreboard: 37 done + 1 partial, 2 left

Recount by group (40 findings = 37 original + N1–N3): **P0** 1/1 · **P1** 8/8 · **P2** 8/9 (P2.8 partial) ·
**P3** 8/9 (P3.7 left) · **P4** 10/10 · **N** 2/3 (N2 left).

**LEFT TO DO, in the order I'd take it:**

| # | Item | Cost | Needs CF redeploy |
|---|---|---|---|
| ~~0~~ | ~~Deploy P3.2's CF half~~ | ✅ **DONE 2026-07-26** | — |
| 1 | **Device tests — 1 of ~14 run.** Full list at the end of §9. **Now unblocked: the tree builds at 6.4.3 / 207 and carries the whole client half** | — | — |
| ~~2–6~~ | ~~P4.10 · P4.5 · P4.8 · P4.4 · P4.6~~ | ✅ **DONE 2026-07-26** (build clean) | — |
| ~~7–9~~ | ~~P2.2 · P4.1 · P4.2+P4.3~~ + **P4.9** and new **N1** | ✅ **DONE + DEPLOYED 2026-07-26** | ✅ |
| ~~10, 11, 13, 14~~ | ~~P3.4 · P3.8 · P3.9 · P3.3 (warning half)~~ + **N3** | ✅ **DONE 2026-07-26** (client batch, build clean) | — |
| 2 | **P3.7** consent taken once forever — later PII opt-ins publish with no re-prompt (COPPA-adjacent). Needs a new `publishedContactKinds` blob field, so it also needs P1.4's unknown-key sidecar (already shipped) | ~1 h | — |
| 3 | **N2** share token is a 36-char UUID — unreadable on the QR/bio/verbal channels the feature bets on. `TOKEN_RE` must keep accepting UUIDs or live links die | ~1.5 h | ✅ |
| 4 | **P2.8 (rest)** digest query paging/batching — scale-conditional, but a killed pass loses that night's deltas permanently | ~1.5 h | ✅ |

Ordering logic: device tests first — they can invalidate anything below, and nothing left is urgent. Then P3.7
(the only remaining item with a compliance edge), then the two that need a CF redeploy, grouped into **one**
deploy if they land together. P2.8's paging is last because nothing is broken today.

**Also deferred, deliberately (not open findings):**
- **P3.3's coach/parent reference block** — `coachName`/`coachRole`/`coachEmail`/`includeCoachContact` rendered as a second contact group. The recruiting-normal, minor-safe reply channel. Scoped as a separate feature proposal from the start; needs a blob field AND a CF render change.
- **N1's residual** — the ~30-day soft-delete window still serves a deleted clip publicly. Closing it means removing the highlight from `recruitingProfiles` at clip-delete time.

**Carry these forward:**
- ✅ **Client work is COMMITTED** — `f9d8308` carried the earlier batch; this batch sits on top of it. (Trey also commits outside these sessions, so still `git status` fresh.)
- ✅ **Version/build bumped to 6.4.3 / 207** (both Debug and Release), so a device build is ready to go.
- 🚨 **`firebase deploy --only functions` does NOT compile TypeScript.** It uploads `lib/` as-is while reporting success. **Always `cd firebase/functions && npm run build` first.** A predeploy guard (`firebase/functions/check-build-fresh.sh`) now blocks a stale deploy. This was the root cause of §2's deployment drift.
- P1.5 is fixed, so the deployed `athleteId` push payload now deep-links correctly — but that path is **only reachable on a multi-athlete account** and is still device-untested.
- Blob serialization has a **35-assertion scratch harness** — the repo has no test target, so re-run it if `RecruitingInfo` changes.

---

## How to use this document in a fresh session

> Read **§0** first — its scoreboard is the live source of what is done and what is left. Then this file top
> to bottom. Every
> finding carries a `file:line`
> anchor, a concrete failure scenario, and a specific fix. **§6 Do-not-re-raise** lists decisions that were
> already argued and settled — do not "fix" anything in that list. Findings marked ✅ were re-verified
> against source during the review session; unmarked ones came from the reviewer pass and should be
> confirmed against the code before you change anything.
>
> ⚠️ Line numbers in the findings below were captured on 2026-07-25 and have **drifted** in the files
> already fixed (`RecruitingProfileService.swift`, `RecruitingPublishView.swift`, `recruitingProfile.ts`,
> `RecruitingInfo.swift`, `SyncCoordinator+Athletes.swift`, `firestore.rules`). Anchor by symbol name.

Related context: `docs/RECRUITING_PROFILE_PLAN.md`, `docs/RECRUITING_PROFILE_PHASE1.md`,
`docs/RECRUITING_PROFILE_PHASE2.md`, `docs/superpowers/specs/2026-07-16-recruiting-profile-phase2-design.md`.

---

## 1. Verification gates (run at review time)

| Gate | Command | Result |
|---|---|---|
| iOS build | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PlayerPath.xcodeproj -scheme PlayerPath -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build` | ✅ **BUILD SUCCEEDED** |
| Functions typecheck | `cd firebase/functions && npx tsc --noEmit -p tsconfig.json` | ✅ clean |
| Firestore rules tests | `cd firebase/rules-tests && export JAVA_HOME="$(echo ~/.local/jdk/*/Contents/Home)" && npm test` | ✅ **37/37 pass** |
| New file target membership | `RecruitingShareCard.swift` | ✅ no pbxproj entry needed — project uses `PBXFileSystemSynchronizedRootGroup` |
| `syncNotificationPreferences` call sites | `grep -rn syncNotificationPreferences --include="*.swift" .` | ✅ one call site, updated for the 3rd param |

**Assessment.** The architecture holds up. The security layer in particular survived adversarial reading —
`ownedPath()`, the `recruitingTokens` atomic claim, the per-render tier re-check, `esc()` coverage, and the
`resource == null` read guard were all attacked and all held. Five of the seven refuted findings were in
that layer. **What is wrong is at the edges: the codec, the money, and the kill switch.**

---

## 2. Deployment state — ⚠️ OBSOLETE, kept for the root-cause analysis

> **This section is historical.** Rules and functions have both been deployed (see §0). The root cause of
> the drift documented here was found on 2026-07-26: `firebase deploy --only functions` **does not compile
> TypeScript** — `package.json` `main` is `lib/index.js` and the CLI uploads that directory as-is, so every
> green deploy was re-shipping stale JS. A predeploy guard now blocks it.

| Artifact | Built but NOT live | Consequence until deployed |
|---|---|---|
| `firestore.rules:1129-1136` | shareToken-rotation exception (`\|\| (hasProTier() && ownsShareToken(...))`) | ✅ **Reset Link is denied in prod today.** Deployed rules still require `request.resource.data.shareToken == resource.data.shareToken`. **Requires a rules RELEASE.** |
| `firebase/functions/src/recruitingProfile.ts:596` | `athleteId: doc.id` in the instant-push payload | Push taps carry no athlete id → deep-link always lands on the More root. **Requires CF REDEPLOY.** |
| `firebase/functions/src/recruitingProfile.ts:637-766` | per-account digest grouping + single-athlete deep-link | Multi-athlete Pro parents still get one digest push per kid. **Requires CF REDEPLOY.** |
| `firebase/rules-tests/recruitingProfiles.test.mjs` (+53L) | new token/rotation cases | Now passing locally (37/37); not a deploy artifact. |

✅ **Drift evidence:** `firebase/functions/lib/recruitingProfile.js` (mtime 12:18) predates
`src/recruitingProfile.ts` (16:42) and contains **no** `pendingByUser` — the digest owner-grouping rewrite
has never been compiled, therefore never deployed.

> **Hard release-ordering gate:** release `firestore.rules` **before** the app build ships. The rules change
> only *widens* `allow update`, so it is backward-compatible with the build currently on the App Store.
> Ship the app first and every Reset Link tap fails with a raw permissions error **and** leaves behind a
> permanently-undeletable orphan `recruitingTokens` claim.

---

## 3. P0 — The published film will not play for a meaningful share of recruiters

### P0.1 Published clips are HEVC-in-QuickTime, served as `video/quicktime` ✅
**`firebase/functions/src/recruitingProfile.ts:224` (and `:234` for grid cells)**

The entire chain was traced and verified in source:

| Step | Code | Result |
|---|---|---|
| Record | `PlayerPath/VideoRecordingSettings.swift:105`, `:239` | default format is `.hevc`; `:379` returns `"mov"` |
| Upload | `PlayerPath/Services/UploadQueueManager.swift:1052` → `PlayerPath/Services/VideoCompressionService.swift:27-49` | **unconditional** re-encode, prefers `AVAssetExportPresetHEVC1920x1080`, `session.outputFileType = .mov` |
| Store | `PlayerPath/VideoCloudManager.swift:146` | `metadata.contentType = "video/quicktime"` |
| Serve | `recruitingProfile.ts:224` | bare `<video src>` — **no** `<source type>`, **no** child fallback content, and CSP `default-src 'none'` (`:108`) forbids any JS to detect the failure |

**Failure scenario.** A D2 coach opens the emailed link on a Windows 11 laptop.
*Firefox (any OS):* `video/quicktime` is not in its supported media types (`video/mp4`, `video/webm`,
`video/ogg`), so it never attempts a decode — renders "No video with supported format and MIME type found."
*Chrome/Edge on Windows:* the container is sniffed, but the HEVC track needs an OS decoder (Microsoft's
paid HEVC Video Extensions, absent on most machines) — the element fires `error` and shows a black box.
Nothing on the page explains it. Meanwhile the athlete receives a "Your recruiting profile was viewed"
push and concludes the share worked.

**Why this is P0.** The failure is silent on *both* ends. The athlete previews it working on their iPhone;
a coach who gets a black box does not email to say so. The one thing this feature exists to do fails
invisibly for the exact audience it targets.

**Fix.** Publish a **web-safe rendition**, not the coaching-quality master. On publish (or on upload when a
clip is flagged `isHighlight`), export H.264 Main + AAC with `outputFileType = .mp4` and
`shouldOptimizeForNetworkUse = true` to `athlete_videos/{uid}/recruiting/{base}.mp4`, upload with
`contentType = "video/mp4"`, and point `highlightPayload["videoStoragePath"]`
(`RecruitingProfileService.swift:410`) at that object. `ownedPath()`'s
`athlete_videos/{ownerUID}/` prefix allowlist (`recruitingProfile.ts:140`) already covers the new path — no
CF security change needed.

**Interim mitigation (< 1 hour, ship alongside):** emit `<source src="…" type="video/mp4">` inside the
`<video>` element plus visible fallback text (`Trouble playing? Open this link on a phone.`). No JS, no CSP
change. **Changing only the stored `contentType` is insufficient** — Firefox and decoder-less Chrome fail on
the HEVC *track*, so a real transcode is required.

**Verification:** open a published link in Firefox on macOS (fails today) and after the fix.

---

## 4. P1 — Must fix before this ships

### P1.1 Paywall-resumed publish races the server-side tier sync ✅
**`PlayerPath/Views/Recruiting/RecruitingPublishView.swift:149`**

`ImprovedPaywallView(...) { Task { await publish() } }` resumes immediately off StoreKit's *local* tier. But
`firestore.rules:25-28 hasProTier()` reads `users/{uid}.subscriptionTier`, which clients cannot write and
which only the `syncSubscriptionTier` CF sets — after an AppTransaction fetch, entitlement JWS,
`getIDToken()`, and a URLSession round trip.

**Failure.** Free user picks 4 clips → Publish → buys Pro Monthly. `publish()` finishes its Storage probes,
`getDocument`, and `claimShareToken` in a few hundred ms, then `setData` hits
`allow create … && hasProTier()` (`firestore.rules:1099`) while the server still reads `free` →
`PERMISSION_DENIED` → `RecruitingPublishView.swift:462-466` renders *"Couldn't publish your profile. Check
your connection and try again."* Worse: that alert is bound with
`.alert(…, isPresented: .constant(errorMessage != nil))` (`:121`) and raised while the paywall sheet is
still dismissing — the same condition the file's own `pendingSuccess` workaround (`:44-48`, `:451-455`)
exists to dodge on the *success* path, with no equivalent on the error path. **The customer may see nothing
at all** and simply have no page. Each retry mints another permanently-undeletable `recruitingTokens` claim
(`RecruitingProfileService.swift:280-296` + `firestore.rules:1053`).

**Fix.** In `RecruitingPublishView.publish()`, before calling the service:
```swift
try? await authManager.syncSubscriptionTierToFirestoreAndWait()
```
✅ The symbol exists at `PlayerPath/ComprehensiveAuthManager+Tier.swift:138`, and
`PlayerPath/SharedFolderManager.swift:454` already uses this exact call in this exact position for the
identical race. Additionally: add `RecruitingPublishError.tierNotSyncedYet`, map a Firestore
`permissionDenied` code onto it in `RecruitingProfileService.publish()` so a rules denial never surfaces as
connection copy, and route the error alert through the same `pendingSuccess`-style deferral so a dismissing
sheet cannot eat it.

### P1.2 `publish()` reads the profile doc from cache — a killed share link can be resurrected ✅
**`PlayerPath/Services/RecruitingProfileService.swift:161`** (branch `:173`, write `:214`)

`let existing = try await docRef.getDocument()` uses the default source, and ✅ `PersistentCacheSettings` is
installed at `PlayerPath/AppDelegate.swift:52`, so an unreachable backend returns the **local cached copy**.
Every server-owned field in the full-overwrite payload is then copied from a possibly stale snapshot —
including `shareToken`.

**Failure.** iPhone + wifi-only iPad on one account. Parent taps Reset Link on the iPhone (T1 → T2); the UI
promises *"the current one stops working permanently… This can't be undone"*
(`RecruitingPublishView.swift:333`). Days later, iPad off-network, parent edits the bio and taps "Update
Published Profile". The cached read still holds T1 → `:214` writes `shareToken: T1` back. The rules update
branch sees `request.shareToken(T1) != resource.shareToken(T2)`, falls through to
`ownsShareToken(T1, athleteID)`, which **passes** because the T1 claim doc is deliberately undeletable
(`firestore.rules:1053`) — the write is admitted on reconnect and `/p/T1` goes live again at the exact URL
the family paid a Pro action to kill. The same stale read also rolls `viewCount` / `dailyViews` /
`notifiedViewCount` / `lastViewedAt` backwards (which re-arms the instant push).

> ✅ **The carry-forward list itself is complete.** `:187-204` covers every field the CF writes
> (`recruitingProfile.ts:571-584`, `:725-729`). The defect is the *source of the read*, not the list.

**Fix.** Change `:161` to `try await docRef.getDocument(source: .server)`, **or** keep `.default` and add
`guard !existing.metadata.isFromCache else { throw RecruitingPublishError.offlineSnapshot }` before `:172`
with copy *"You need a connection to update your published profile."* The codebase already uses both idioms
(`SharedFolderManager.swift:345`, `FirestoreManager+Invitations.swift:746`) — this is a deviation from its
own convention.

### P1.3 Cross-device blob sync erases `publishedClipIDs` + `publishConsentAt` ✅
**`PlayerPath/SyncCoordinator+Athletes.swift:218-219`** (upload-before-download at `:19-21`)

`recruitingProfileJSON` syncs as one opaque last-write-wins string:
```swift
if local.recruitingProfileJSON != remoteData.recruitingProfileJSON {
    local.recruitingProfileJSON = remoteData.recruitingProfileJSON; changed = true
}
```
`RecruitingProfileEditorView.persistIfChanged` guards the in-process version of this clobber (`:348-351` —
*"Any new field written by a pushed screen needs a line here"*); the **sync path has no equivalent**.

**Failure.** Device A (offline) has a dirty bio edit; device B curates 8 clips and publishes, writing
`publishedClipIDs` + `publishConsentAt` (`RecruitingPublishView.swift:437-445`). A reconnects →
`uploadLocalAthletes` runs *first* (`:19-21`) and pushes A's blob with both keys nil, replacing the server
copy. Next time anyone opens Share Profile, `load()` computes `curated` as empty and falls back to
`defaultSelection` = newest-8 (`RecruitingPublishView.swift:360-373`). One tap on "Update Published Profile"
(e.g. to refresh stats) silently replaces the coach-facing page's hero clip and ordering. The consent toggle
also reappears and is re-stamped.

**Fix.** In `uploadLocalAthletes`, before serializing a dirty athlete whose blob changed, decode the remote
blob and re-apply `publishConsentAt ?? local` and `publishedClipIDs ?? local` (monotonic union — neither is
ever legitimately cleared by the bio editor); do the mirror-image merge at `:218` instead of the straight
string assignment. **Structurally better:** move `publishedClipIDs` / `publishConsentAt` out of the bio blob
onto the `recruitingProfiles` doc, whose publish path is their only real owner.

### P1.4 `RecruitingInfo` drops unknown blob keys on re-encode (same root cause) ✅
**`PlayerPath/Models/RecruitingInfo.swift:290`**

`init(from:)` is hand-written and tolerant (`:103-132`) but the **encoder is synthesized**, and the
`Athlete.recruiting` setter re-encodes the whole struct. The blob has shipped in three shapes (`38e52c0`:
neither publish key; `dc597dd`, the build live in prod: `publishConsentAt` only; HEAD: both). A device still
on the App Store build that edits any field it *does* model drops `publishedClipIDs` permanently, producing
the identical curation reset.

**Fix (do with P1.3 as one data-integrity change).** Either add an unknown-key sidecar
(`private var unknownKeys: [String: JSONValue]` populated in `init(from:)`, spliced back in a hand-written
`encode(to:)`), or in the `recruiting` setter decode the current `recruitingProfileJSON` to a dictionary and
merge new-over-old.

### P1.5 The recruiting push deep-link cancels itself ✅
**`PlayerPath/Views/Navigation/MainTabView.swift:374`** (clobbered by `:156-164`)

The observer sets `selectedAthlete = athlete` then `navigateToMore(.recruiting)` in one synchronous
NotificationCenter callback. SwiftUI coalesces both writes, then runs `.onChange(of: selectedAthlete.id)` —
which executes `morePath = NavigationPath()` **last**, discarding the pushed destination.

**Failure.** Two athlete rows (a dual-sport person is two rows by definition). Selected row is golf; a coach
opens the baseball page → push `{type:'recruiting_view', athleteId:<baseball UUID>}` → tap → the user lands
on the bare More tab root instead of that athlete's Recruiting editor. The `athleteId` payload, the
observer, and the `.recruiting` MoreDestination all do nothing in exactly the case the payload was added
for. **Unreproducible on a single-athlete account.**

**Fix.** Add `@State private var pendingMoreDestination: MoreDestination?`. In the observer, when the
resolved athlete differs from `selectedAthlete`, set `selectedAthlete` and `pendingMoreDestination` with
**no** path write; at the end of the `.onChange(of: selectedAthlete.id)` handler (after the resets) consume
it with `navigateToMore(d)`. Keep the direct call for the same-athlete case. Precedent for the hazard:
`UserMainFlow.swift:363-379` defers a post-athlete-switch navigation 250 ms for the same reason.
**Also needs the CF redeploy** to ship the `athleteId` key at all.

### P1.6 Offline publish leaves the screen spinning with Unpublish and Reset Link disabled
**`PlayerPath/Views/Recruiting/RecruitingPublishView.swift:417-418`**

Firestore write completion fires only on backend commit, so `docRef.setData`
(`RecruitingProfileService.swift:214`) and `claimShareToken`'s `setData` (`:284`) never resume while
offline. `isWorking` is cleared only by the `defer` the suspended task never reaches. There is no
connectivity precondition anywhere in `Views/Recruiting` or `RecruitingProfileService` (grep for
`ConnectivityMonitor|isConnected` returns nothing), unlike `VideoCloudManager+Photos.swift:133/280`, and no
timeout.

**Failure.** Athlete opens Share Profile on wifi (status cached), enters a dead zone, taps "Update Published
Profile". Publish spins forever; Unpublish (`:297`) and Reset Link (`:326`) are both `.disabled(isWorking)`;
`canPublish` (`:77`) stays false. No error, no cancel, **and the kill switch is unreachable** until they back
out of the screen.

**Fix.** Guard the entry of `publish()`, `unpublish()` and `resetLink()` with
`guard ConnectivityMonitor.shared.isConnected else { throw RecruitingPublishError.offline }` (matching
`VideoCloudManager`'s convention). **Same guard closes P1.2's cached-read hole — do them in one edit.**

### P1.7 Opening Notification Settings on a second device silently re-enables Profile View Alerts ✅
**`PlayerPath/Views/Profile/NotificationSettingsView.swift:277`** (writer at `:297-303` →
`FirestoreManager+UserProfile.swift:109-122`)

`.task` fires `syncActivityPushPreferences()` unconditionally on every appearance and
`setData(merge: true)`s all three device-local `@AppStorage` toggles (all defaulting `true`) over the
account-level `users/{uid}.notificationPreferences`. ✅ Grep confirms **nothing anywhere reads that map
back** — the only Swift reference to `notificationPreferences` is the writer.

**Failure.** Athlete turns "Profile View Alerts" OFF on iPhone → `push.ts:49` suppresses instant + digest. A
week later they open Settings → Notifications on the iPad (`notif_recruitingViews` never written there) →
`.task` writes `recruitingViews: true` back. Pushes resume on both devices while the iPhone's toggle still
displays OFF, and its local `willPresent` check (`PushNotificationService.swift:787-793`) keeps suppressing
foreground banners — so the phone shows off, drops foreground alerts, and rings for backgrounded ones.
Coach Activity is silently re-enabled the same way.

> **Scoping note:** `git diff` shows the `.task` call and the clobber pattern are **pre-existing shipped
> behavior**; the recruiting change only added a third parameter to an already-clobbering function. It is in
> Must-Fix because the recruiting toggle is the one users will actually opt out of.

**Fix.** In `.task`, read `users/{uid}.notificationPreferences` once and seed the three `@AppStorage` values
from any keys present, then call `syncNotificationPreferences` only from the three `.onChange` handlers. If
the legacy backfill must stay, gate it behind a `notif_prefsBackfilled` `UserDefaults` flag.

### P1.8 Publishing while the first headshot upload is in flight ships a page with no headshot ✅
**`PlayerPath/Views/Recruiting/RecruitingProfileEditorView.swift:94`**

✅ `isUploadingHeadshot` is referenced only at `:201` (PhotosPicker `.disabled`) and `:203` (Remove) — **not**
the "Share Profile" row (`:93-99`) or Preview (`:83-90`). `working.headshotCloudURL` is written only after
the upload returns (`:308`), so `persistIfChanged` saves nil, `headshotPath` returns nil
(`RecruitingProfileService.swift:403-406`), and the key is omitted from the doc.

**Failure.** First headshot, slow cellular (the window is wide — `item.loadTransferable` at `:292` may need
an iCloud Photos download before the downscale starts). Athlete taps Share Profile → Publish before the
upload lands. Live page renders the person-placeholder and `og:image` is nil
(`recruitingProfile.ts:492`), degrading the link unfurl to `twitter:card = summary`. Seconds later the
editor shows the headshot, so the athlete believes it is live. Nothing ever contradicts this. (A
*replacement* headshot is safe — the path is deterministic and overwritten in place.)

**Fix.** Add `.disabled(isUploadingHeadshot)` to the Share Profile button and the Preview row, and call
`persistIfChanged()` at the end of `uploadHeadshot` so a later publish always sees the URL.

---

## 5. P2 — Should fix soon

### P2.1 A failed first status read renders a live profile as "never published", with no error
**`RecruitingPublishView.swift:385-393`** — `refreshStatus` assigns only on success and its catch only calls
`handle(error, showAlert: false)`. On the initial `.task { await load() }` there is no previous value, so
`status` stays nil — indistinguishable from `fetchStatus`'s legitimate nil-for-no-doc
(`RecruitingProfileService.swift:356-361`). `isLoading` is cleared unconditionally by the defer at `:350`.

**Failure (load-bearing case is an *online* device):** one transient `getDocument` failure — Firestore
`unavailable`, or permission-denied on a stale/refreshing ID token — and the athlete sees a screen with no
live link, no view counts, **no Unpublish and no Reset Link**, while the page is live and being served.
Recovery is the undiscoverable pull-to-refresh at `:114`. The function's own doc comment (`:376-384`) says
this outcome must never happen.

**Fix.** Add `@State private var statusLoadFailed = false`, set in `refreshStatus`'s catch and cleared on
success; when `status == nil && statusLoadFailed`, render a retry row ("Couldn't check whether this profile
is live. Retry.") instead of the never-published layout.

### P2.2 Deleted Storage objects still render as playable clips — `signPath` cannot detect them
**`recruitingProfile.ts:155-169`** (guard that can never fire: `:480`)

`getSignedUrl` only computes a signature — it performs no `exists()`/`getMetadata()` — so `signPath`'s
documented degrade-to-one-absent-tile behavior never happens, and nothing in the codebase removes a
highlight from a published profile when its clip is deleted (the only `recruitingProfiles` writers are
publish/unpublish/resetLink/deleteProfileDoc).

**Failure.** Athlete publishes 8 highlights, then deletes 3 of those clips. The page keeps signing the dead
paths successfully; a college coach sees 8 tiles and 3 fail on play with a GCS `NoSuchKey` XML error. No
server log, no "Temporarily unavailable", and the athlete is never told their film is broken. Publish-time
`missingStoragePaths` (`RecruitingProfileService.swift:243`) closes this only at publish time — the risk
window is entirely post-publish.

> Related: the comment at `RecruitingProfileService.swift:413-414` ("The CF drops the poster if the object
> isn't there") is factually wrong for the same reason — but a 404 poster degrades to the same black box the
> CSS already shows, so that half is cosmetic.

**Fix.** In `signPath`, add `const [ok] = await file.exists()` and return null when false (≤17 extra GCS
calls per render — see P2.3 about memoizing). That also restores the intended meaning of the
`clips.length === 0 → 500` guard. Cheaper complement: clear the matching highlight from `recruitingProfiles`
in the clip-delete path.

### P2.3 Public render is unmetered and un-deduped — counts are inflatable, cost is unbounded
**`recruitingProfile.ts:548`** (amplification at `:465-473`, `:489`)

`Cache-Control: no-store` (`:419`) means every reload reaches the function. The counter transaction is gated
on nothing but `req.method === 'GET' && !BOT_UA.test(ua)` — a caller-controlled header — and unconditionally
increments `viewCount` and `dailyViews.<utcDay>` on a single doc (`:571-577`). No App Check (the file's own
comment at `:81` concedes it), no rate limit in `firebase.json`, no `runWith({maxInstances})` on `:416`, no
per-viewer dedup.

**Failure.** Anyone holding a forwarded token — including the athlete reloading in Safari — increments the
counter once per request. `curl` in a loop inflates "Profile Activity" totals and the digest body into
fiction. Each render also costs 1 collection query + 1 users read + 1 read-write transaction + up to **17
IAM signBlob calls** (8 videos + 8 posters + headshot), so a scripted loop is a direct cost/quota amplifier
with no instance ceiling. No data is exposed and no user is locked out; the harm is metric integrity plus
unbounded spend.

**Fix (cheapest first).** (1) Memoize signed URLs in a module-level `Map<storagePath, {url, expires}>` with a
TTL just under `SIGNED_URL_HOURS` — a warm instance then makes ~1 signBlob call per path per hour instead of
17 per request. (2) Add `.runWith({ maxInstances: 20, timeoutSeconds: 30 })` to the `onRequest` declaration
at `:416`. (3) Dedupe the counter by `hash(clientIP + token + UTC hour)` in a module-level LRU.

### P2.4 Page HTML is withheld until an FCM send that can outlive the function timeout
**`recruitingProfile.ts:591-600`** (html built at `:534`, sent at `:606`)

`admin.messaging()` uses a 15 s per-request timeout with 4 retries on `ECONNRESET`/`ETIMEDOUT`, and there is
no `runWith` anywhere in `firebase/functions/src` — so the default 60 s HTTPS timeout applies.

**Failure.** During an FCM/APNs stall that produces `ETIMEDOUT` (not a fast 503), a request where the
transaction returned `isQuiet === true` — at most one per profile per 24 h — holds a fully-rendered page for
up to ~82 s. The coach gets a platform 504 on a perfectly healthy profile. *(Normal-case push latency on
first-view-per-24h is an accepted decision — see §6.)*

**Fix.** Bound the send: `await Promise.race([sendPushNotification(...), new Promise(r => setTimeout(r, 1500))])`,
and add `.runWith({ timeoutSeconds: 30 })` at `:416`.

### P2.5 `selection` is never reconciled after publish, so `atCap` locks out replacements
**`RecruitingPublishView.swift:443`** — `publish()` persists `result.publishedClipIDs` to the model but
leaves `@State selection` at the full pre-publish set. `RecruitingHighlightPicker.atCap` (`:39`) keys off
`selection.count`, the header (`:50`) renders from it, and `:109` disables unselected rows.

**Failure.** 8 selected, 2 objects reclaimed → page goes live with 6 and the sheet says "2 clips couldn't be
included" without naming them. The picker then reads "On your profile (8 of 8)", all 8 rows still show
checkmarks, and every other row is disabled — so they cannot add replacements without blindly deselecting
clips that may be the good ones. Self-heals on leaving and re-entering the screen.

**Fix.** After `info.publishedClipIDs = result.publishedClipIDs` at `:443`, also assign
`selection = Set(result.publishedClipIDs)`.

### P2.6 Instant view push is throttled per profile — a multi-athlete account gets N pushes at once
**`recruitingProfile.ts:569`** (stamp at `:562-587`) — the quiet window lives on
`recruitingProfiles/{athleteId}.lastNotifiedAt`, so the throttle is per athlete. The digest was deliberately
rewritten to send one push per **account** for exactly this reason (comment at `:632-635`); the instant path
was not.

**Failure.** Pro parent with 3 published kids emails all three links to one program; the coach opens all
three tabs in a minute; each doc independently clears its own 24 h window → three "Your recruiting profile
was viewed" pushes inside 60 seconds.

**Fix.** Move the instant-push quiet stamp to the account — read/write
`users/{ownerUID}.lastRecruitingNotifiedAt` and gate `isQuiet` on that, keeping the per-doc
`notifiedViewCount` watermark for the digest delta. **Requires CF redeploy.**

### P2.7 `recruitingTokens` create rule has no `hasOnly()`, no type/size bound, docs undeletable forever ✅
**`firestore.rules:1049-1053`** — create requires only `isAuthenticated()` +
`hasAll(['userId','athleteId'])` + `userId == uid`, and `allow update, delete: if false`. Contrast the
project's own convention two blocks up (`pendingDeletions`, ~`:1020`, which uses `hasOnly` + a value regex).

**Failure.** A signed-in free account scripts
`setDoc(doc(db,'recruitingTokens', uuid()), {userId: myUid, athleteId: 'x', junk: <900KB>})` in a loop.
Every write succeeds and **nothing can ever delete them** — the only reclaim path is
`cleanupUserDataOnDelete`, which fires on Auth account deletion. Permanent doc-count and storage growth in a
collection designed for one ~100-byte doc per profile. No privilege is gained (every use of a claim goes
through `ownsShareToken` + `hasProTier`), so this is hardening, not an exploit.

**Fix.**
```
allow create: if isAuthenticated() && hasProTier()
              && request.resource.data.keys().hasOnly(['userId','athleteId','createdAt'])
              && request.resource.data.userId == request.auth.uid
              && request.resource.data.athleteId is string
              && request.resource.data.athleteId.size() < 64;
```
> ⚠️ The allowlist **must** include `createdAt`, which `claimShareToken` writes
> (`RecruitingProfileService.swift:284-288`) — omitting it breaks every publish.

Adding `hasProTier()` is safe (both callers already require Pro). Add rules tests for free-tier denied /
extra-key denied / non-string athleteId denied — the current 6 token cases assert none of this.
**Requires rules release.**

### P2.8 `recruitingViewDigest` has no `runWith` and processes every doc serially inside the 60 s default
**`recruitingProfile.ts:637-649`** — unbounded `.get()` (no limit, no cursor), serial `await ref.update()`
per doc (`:704`, `:725-729`) plus a serial FCM send per owner (`:747`), on a v1 scheduled function with
default 60 s / 256 MB and retries off.

**Failure (scale-conditional — nothing is broken today).** At roughly 800-1000 in-window profiles the
instance is killed mid-pass-2. Nobody gets a digest that night, and there is no retry. Worse, the deltas are
**permanently lost**: run N at 01:00 on day D covers `lastViewedAt > D-1 00:00`; run N+1 covers only
`> D 00:00`, so anything viewed before that midnight falls out of the window forever.

**Fix.** Add `.runWith({ timeoutSeconds: 540, memory: '512MB' })`, page the query with `.limit(500)` +
`startAfter` cursor (the shape `dailyStorageCleanup` already uses), and replace the serial updates with
chunked `db.batch()` (500/batch) plus a bounded-concurrency `Promise.all` for the sends.
**Requires CF redeploy.**

### P2.9 Daily digest resets the instant-push quiet window ✅ (logic verified)
**`recruitingProfile.ts:728`** — the digest stamps `lastNotifiedAt = serverTimestamp()` on every profile it
digests, and the render path's gate is `Date.now() - lastNotifiedAt > 24h` (`:569`). Any profile with at
least one view **per day** is re-armed nightly at 01:00 UTC and can never satisfy the test again — so the
real-time "someone just opened your page" push becomes unreachable on exactly the profiles that are working.
(It does re-arm after any viewless day, since `lastViewedAt` then falls outside the 25 h window at `:648`.)

This reads as a defensible "at most one recruiting push per 24 h" cap, but it cuts against the stated intent
at `:550-553` ("A showcase weekend must feel alive").

**Fix.** Give the digest its own `lastDigestAt` field and drop `lastNotifiedAt` from its update — idempotency
already comes from `notifiedViewCount` (`:682-690`, `:727`), so there is no repeat risk. Caps the athlete at
two pushes/day. **Requires CF redeploy** — and if `lastDigestAt` is added, **it must join the publish
carry-forward loop at `RecruitingProfileService.swift:198`.**

---

## 6. P3 — Product gaps ("what are we missing")

### P3.1 Nothing tells an athlete their published page has gone stale — *highest value per hour*
**`RecruitingProfileEditorView.swift:100`** — `highlights` and `golfStats` are publish-time snapshots
(`RecruitingProfileService.swift:186`, `:207-209`) and the picker cannot self-heal: `load()` seeds
`selection` from persisted `publishedClipIDs` and only falls back to newest-8 when that set is empty
(`RecruitingPublishView.swift:360-372`), so new highlights stay unselected forever. `status.publishedAt` is
fetched (`RecruitingProfileService.swift:368`) and **never displayed**. The only mention of republishing is
the footer at `RecruitingPublishView.swift:284`, visible only to someone already on the publish screen.

**Failure.** Publish in February with 3 clips and a 6.2 handicap; flag 17 new highlights and drop to 2.8 by
June; the same link still serves February. The best version of the profile never reaches a recruiter.

**Fix (~1 h, client-only, no new persistence, no CF work).** In the editor's status row (`:100-108`), compute
the count of `isPublishableHighlight` clips (`RecruitingHighlightPicker.swift:175`) not in
`publishedClipIDs`; when > 0, render a tappable row *"N new highlights aren't on your page yet — Update"*
that pushes `RecruitingPublishView`.

### P3.2 The growth loop is unmeasurable
**`recruitingProfile.ts:531`** (+ `:310`, `:327`), **`RecruitingShareCard.swift:97`**

`docs/PRIORITIES.md:21` states the launch signal: *"Ship that, get five real athletes to share their link,
watch for click-throughs."* The only outbound link is a bare `https://playerpath.net` with no query params,
under `Referrer-Policy: no-referrer` (`:105`) — every click is untagged direct traffic. Separately,
ShareLink / Copy / QR / mailto / bio blurb all emit the identical URL (`RecruitingShareCard.swift:97, 109,
112, 126`; `RecruitingShareTools.swift:33`), the server records only anonymous `viewCount` + `dailyViews`,
the digest logs only `snap.size` (`:764`), and there are exactly five client-side recruiting analytics
events — none of them a view or a share (`AnalyticsService.swift:551-556`).

**Fix (~1.5 h).** (a) Tag all three footer hrefs
`?utm_source=recruiting&utm_medium=profile&utm_campaign=share_page`. (b) Append a channel marker per share
verb (`?s=qr|mail|copy|share|bio`) and bucket it server-side as `channelViews.<s>` alongside `dailyViews`
(whitelist the 5 values). (c) Log view totals in the digest's `console.log`.

> Token parsing reads `req.path` (`:433`), which excludes the query string, so `TOKEN_RE` is unaffected.
> **Do not remove `no-referrer`** — the share token is in the URL.
> ⚠️ **`channelViews` must be added to the carry-forward loop at `RecruitingProfileService.swift:198` or
> every republish erases it.** Requires CF redeploy.

### P3.3 The published page can dead-end — no contact channel, no coach reference
**`recruitingProfile.ts:203-204`** — `contactSection` returns `''` on an empty array; `data.contact` is
written only when `visibleContactItems` is non-empty (`RecruitingProfileService.swift:439-442`); all three
gates default false (`RecruitingInfo.swift:63, 65, 67`); the body ends at `contactSection` → `<footer>`
(`:530-531`) and CSP `form-action 'none'` (`:113`) rules out any form. Meanwhile the app's own outreach copy
asserts otherwise: `RecruitingShareTools.swift:32` hard-codes *"My game film, measurables, and contact info
are here:"* into the coach email body.

Reply paths exist for ShareLink and mailto (the coach can reply in-thread). The genuine dead end is **QR at a
showcase, the Instagram/X bio blurb, and forwarded links**.

**Fix.** The defect is the absent publish-time warning — in `RecruitingPublishView`'s publish-section footer,
when `athlete.recruiting.visibleContactItems.isEmpty`, say *"Coaches scanning your QR code will have no way
to reach you."* (warn, don't block). **Feature proposal, separate:** a coach/parent reference block
(`coachName`, `coachRole`, `coachEmail`, `includeCoachContact`) rendered as a second contact group — the
recruiting-normal, minor-safe channel.

### P3.4 Publish has no minimum-viable-profile bar; `filledFieldCount` is computed and never shown
**`RecruitingPublishView.swift:76-78`** — `canPublish` is
`!selection.isEmpty && !isWorking && (!needsConsent || consentAcknowledged)` — nothing else.
`RecruitingInfo.filledFieldCount` (`RecruitingInfo.swift:250`) has exactly one consumer: an analytics
parameter (`RecruitingProfileEditorView.swift:362`).

**Failure.** Publish 30 seconds after discovering the feature with nothing filled in → the page is
`<h1>Jordan Smith</h1>` plus four videos. No grad year, no position, no school, no headshot → `ogImage` null
(`:492`) → `twitter:card` = summary (`:298`) → og:description falls back to *"Jordan Smith — recruiting
profile"* (`:513-515`). The link unfurls in a coach's inbox as a plain text row and the coach cannot
determine the recruiting class — **the first thing they filter on**.

**Fix (~2 h, client-only, non-blocking per house convention).** Add a "Profile readiness" Section above the
publish button — checkmarks for grad year, position/sport, high school, headshot, one contact channel —
driven by `filledFieldCount` plus explicit nil checks, and change the publish footer to *"Coaches filter by
grad year first — yours is blank."* when `info.gradYear == nil`. Keep Publish enabled.

### P3.5 Portrait hero clip renders ~1300px tall — no height cap on `<video>`
**`recruitingProfile.ts:259`, `:261`** — `.hero video` and `.cell video` are `width:100%` with no
`max-height` or `aspect-ratio`.

**Failure.** Athlete records a highlight holding the phone upright (`CameraViewModel.swift:507/541` sets the
connection orientation from the device, so the clip is 1080x1920) and picks it first, making it the hero. A
coach on a 1440x900 laptop gets a hero `<video>` rendered 728 × 1294 CSS px — playback controls and caption
sit ~400px below the fold, so the coach lands on a full screen of black with no visible play button, and
every other section is pushed two screens down. In the grid, `minmax(220px,1fr)` produces 220×391 cells, so a
mixed set is a ragged grid. **The athlete cannot see any of this** — `RecruitingProfileComponents.swift:121`
previews through fixed `CGSize(width: 200, height: 112)` landscape thumbnails.

**Fix (one CSS edit).**
```css
.hero video{width:100%;max-height:min(70vh,560px);object-fit:contain;background:#000;display:block}
.cell video{width:100%;aspect-ratio:16/9;object-fit:contain;background:#000;display:block}
```

### P3.6 1-hour signed URLs die in an open tab with no recovery affordance
**`recruitingProfile.ts:51`** — `SIGNED_URL_HOURS = 1`, non-hero clips are `preload="none"` (`:234`) so their
URLs are first requested only on click, and the page has no JS (CSP `default-src 'none'`) and no error copy.

**Failure.** A coach opens the link at 9:05am while triaging inbox, watches the hero, leaves the tab. At
10:40am they click the third grid clip; the signed URL is fetched for the first time right then, GCS returns
403 `ExpiredToken`, the `<video>` fires `error` and renders as a black box with a crossed-out play control.
Nothing explains it. A refresh would fix it (the page is `no-store`), but the coach has no way to know.

**Fix.** Raise `SIGNED_URL_HOURS` to 6–12. The marginal exposure is small — the page is already `no-store`,
the share token in the URL is the real gate. Independently, add static fallback content inside each `<video>`
element (no JS, no CSP change) saying the clip may need a page refresh.

### P3.7 Consent is taken once forever — later PII opt-ins publish with no re-prompt
**`RecruitingPublishView.swift:71`** (gate at `:93`, stamp at `:436-438`) — `needsConsent` is
`publishConsentAt == nil` and the stamp is carried forward permanently
(`RecruitingProfileEditorView.swift:350`). A republish that newly makes a minor's phone number or GPA public
shows no re-confirmation and no change summary. (Each field does have its own explicit opt-in that's
disabled while empty — `RecruitingEditorSections.swift:88, 104, 111, 118-123` — and the first-publish copy is
written as blanket consent, so this is a gap in granularity rather than an absence of consent.)

**Fix (~3 h).** Persist `publishedContactKinds: [String]?` in the blob (same carry-forward pattern and
`persistIfChanged` line as `publishedClipIDs` — and see P1.4, it needs the unknown-key fix or old builds drop
it). When `visibleContactItems` contains a kind not in that set, re-show the consent section with specific
copy: *"This update makes Jordan's phone number public."*

### P3.8 Unpublish keeps PII and the headshot at rest; no per-profile delete action
**`RecruitingProfileService.swift:340-345`** — unpublish sets only `isPublished:false` + `updatedAt`, leaving
`contact`, `gpa`, `name`, `physicalLine`, `schoolLine`, `headshotPath` in the doc and the JPEG in Storage.
`deleteProfileDoc` (`:393`) exists but its only callers are whole-athlete deletion (`Athlete.swift:196`,
`AthleteManagementView.swift:82`).

> **Not a GDPR gap.** Exposure after unpublish is owner-only (`loadPublishedProfile` returns null unless
> `isPublished === true`, `recruitingProfile.ts:360`), and account/athlete deletion already purges everything
> on both client (`FirestoreManager+UserProfile.swift:589-618`) and server (`index.ts:1297-1314`).

The gap is **granularity**: "delete our recruiting data" currently means "delete the athlete and lose four
seasons of film."

**Fix (~1.5 h, both service calls exist).** Add a destructive "Delete Profile Data" row beneath Unpublish
calling `deleteProfileDoc(athleteId:)` + `VideoCloudManager.deleteRecruitingHeadshot(...)`, with a
confirmation naming what goes. The `recruitingTokens` claim correctly stays (undeletable by design) — the
dead token then matches nothing.

### P3.9 Two-sport athletes: recruiting surfaces break the app's own `name · sport` convention
**`RecruitingProfileEditorView.swift:193`** — a dual-sport person is two rows with the **same name**
(`AddSportProfileSheet.swift:34`, `SportProfileSplitService.swift:138`), each with its own blob, headshot,
consent stamp, `recruitingProfiles/{id}` doc and share link. Every recruiting surface is name-only: the
editor header (`:193`), the More-tab row, the ProfileView row, `RecruitingShareCard.swift:80`, the mailto
subject (`RecruitingShareTools.swift:21-24`), and the CF `<h1>` (`recruitingProfile.ts:521`). The app already
disambiguates everywhere else — `PPAthleteSwitcher.swift:101-106` renders `"\(name) · \(sport.displayName)"`
when siblings > 1, and `ProfileView.swift:878-882` uses a sport `titleOverride` inside a person group.

**Fix.** Reuse the `siblings > 1` row-title rule in the editor header, both Recruiting rows, and the share
card — e.g. `Text(athlete.name + (hasSiblings ? " · \(athlete.sportType.displayName)" : ""))`. The
`\.ppAccent` tint change alone is not a label.

---

## 7. P4 — Polish

| # | Finding | Anchor | Fix |
|---|---|---|---|
| P4.1 | `og:image` is nil with no headshot → `twitter:card` degrades to `summary`, a grey text row on the feature's highest-leverage impression | `recruitingProfile.ts:489-492`, `:298` | Generalize `serveAvatar` into `serveProxiedImage(res, token, kind)` with `kind: 'avatar' \| 'poster'` (poster = `highlights[0].thumbnailStoragePath`, already going through `ownedPath`), route `/p/{token}/poster` in the same segment parser (`:433-436`), set `ogImage = headshot ? …/avatar : (heroPoster ? …/poster : null)`. Keep the null branch — the thumbnail path is derived by convention and may not exist. Landscape poster also unfurls better than a circular headshot crop. **CF redeploy.** ~45 min |
| P4.2 | Renderer drops `sport`, `updatedAt`, `durationSeconds` — all already in the doc. Baseball vs. softball is indistinguishable; clip captions carry month/day but **no year** (`RecruitingProfileService.swift:498-500`) so "this spring" vs. "three seasons ago" is unreadable | `recruitingProfile.ts:518-532`; written at `RecruitingProfileService.swift:184`, `:188`, `:420` | Include sport in `RecruitingInfo.subline(isGolf:)` (`RecruitingInfo.swift:144`) so it also reaches og:title; render "Updated \<Month YYYY\>" from `data.updatedAt` in the footer; surface `durationSeconds` in captions. ~45 min |
| P4.3 | Film section has no header, count, runtime or provenance line; the one claim competitors can't make ("recorded and tagged in PlayerPath") sits 300 lines later in 13px grey footer type | `recruitingProfile.ts:219-242`, `:531` | Merge with P4.2 into one edit: `<h2>Game Film</h2><p class="note">8 clips · 3:12 · recorded and tagged in PlayerPath, Feb–Jun 2026</p>`. The date range must be built Swift-side in `publish()` (the CF only receives pre-formatted labels). |
| P4.4 | Golf stat band reads as verified; measurables say "self-reported" and golf doesn't | `RecruitingGolfStats.swift:65` vs `recruitingProfile.ts:528` | One string — `RecruitingGolfStats.footnote` is the single source read by `golfPayload` (`RecruitingProfileService.swift:448`), so it propagates to both the in-app band and the page: `"Scores entered by the athlete in PlayerPath. Scoring (avg / best / rounds) from tournament rounds only."` |
| P4.5 | Editor's view-count row is not Pro-gated, contradicting the publish screen. Premise is real server-side: `recruitingProfile.ts:369` returns null for a non-Pro owner, so a lapsed page is dark while `isPublished` stays true | `RecruitingProfileEditorView.swift:100` vs `RecruitingPublishView.swift:87-89` | `if isPro, let status, status.isPublished { … }` |
| P4.6 | QR image has no accessibility label and no on-screen link text. `Views/Recruiting/` contains **zero** accessibility annotations, against 195 uses of `accessibilityLabel` elsewhere | `RecruitingQRCodeView.swift:28-39`, `:44` | `.accessibilityLabel("QR code for \(athleteName)'s recruiting profile")` + `.accessibilityValue(RecruitingShareTools.displayLink(url))`, or always render `displayLink(url)` under the code as the success sheet does |
| P4.7 | `resetLink()` carries `unpublish()`'s doc comment, which claims it is **not** tier-gated — documents a security invariant backwards. A maintainer acting on it would remove the `isPro` gate on `resetLinkSection` and produce orphan claims plus raw permissions errors. `func unpublish` (`:340`) has no docs at all | `RecruitingProfileService.swift:300-321` ✅ | Split the block: "Takes the public page down / not tier-gated / takes plain values" moves above `unpublish` at `:340`; keep only the Reset Link paragraphs above `resetLink` and add "Pro-only — unlike unpublish." |
| P4.8 | `noPublishableClips` tells the athlete to wait on Wi-Fi when the files are gone for good. Same error thrown for "not uploaded yet" (`:135-137`, copy correct) and "every Storage object came back objectNotFound" (`:149-151`, copy wrong) | `RecruitingProfileService.swift:150`, message at `:65` | Add `case highlightsMissingFromCloud` ("These clips are no longer in your cloud backup. Pick different clips, or re-upload them from the Videos tab.") and throw it at `:150` |
| P4.9 | `BOT_UA` counts an empty User-Agent as a human view. Enterprise mail-security scanners (Defender Safe Links, Proofpoint, Mimecast) also fetch with ordinary desktop Chrome UAs — and `coachEmailURL` puts the bare URL in a mailto body addressed to a college coach | `recruitingProfile.ts:75`, `:547-548` | Treat empty/missing UA as a bot; dedupe by `hash(IP + UA)` (same mechanism as P2.3). Stronger: move counting to a same-origin 1×1 beacon (`/p/{token}/px.gif`) — CSP already allows `img-src 'self'` and headless scanners rarely fetch subresources |
| P4.10 | Golf profiles publish baseball measurables the in-app preview hides — `applyBio` computes `isGolf` but writes `measurables` unconditionally; the CF renders the card for any sport. Contradicts the "preview and page can't disagree" invariant | `RecruitingProfileService.swift:435` vs `RecruitingProfileView.swift:36-40` and `recruitingProfile.ts:528` | `let measurables = isGolf ? [] : info.measurableItems`. (Fixing it preview-side would be wrong — it would start showing golf athletes a baseball card.) |

---

## 8. Do NOT re-raise

### 8.1 Deliberate decisions (argued and settled — see `docs/RECRUITING_PROFILE_PHASE2.md`)
1. Publish is a full `setData` overwrite, **not** merge (a merge leaves toggled-off PII in the doc). The
   consequence is the carry-forward list; a **missing** field in that list is a real bug, the pattern is not.
2. PII is filtered client-side; server-side filtering is impractical for a client-direct publish. Residual
   risk is owner-only.
3. `VideoClip` has no persisted `storagePath`; paths are re-derived by convention.
4. `RecruitingPublishView` / the editor are **not** `.proRequired()` — that modifier replaces the whole
   screen and would paywall the unpublish kill switch.
5. Golf stat scope asymmetry (scoring = tournament rounds only; GIR/FIR/putts/scrambling = all rounds).
6. QR code is black-on-white deliberately. Normal-case push latency on the first-view-per-24h render is
   accepted (freeze-safety forbids post-send work; "no stamp, no push" forbids push-before-write).
7. There is **no** per-recipient revocation model (recruiters never authenticate). Unpublish and Reset Link
   are the only remedies; a "shared with" list was explicitly rejected.
8. `recruitingTokens` claims are never client-deletable — releasing one while a published profile still
   points at it would let an attacker re-claim a live link.
9. **Known-open, documented:** "profile-doc squatting" — `recruitingProfiles/{athleteId}` is keyed by athlete
   UUID and rules cannot verify athlete ownership, so a connected coach with Pro could pre-create the doc and
   block the real owner. DoS-only. Fixes both need a decision: an `athleteOwners/{uuid}→uid` index +
   backfill, **or** re-keying profiles by shareToken.

### 8.2 Refuted during this review (checked and found not to be defects)
| Claim | Why refuted |
|---|---|
| `recruitingTokens` read rule dereferences `resource.data` with no null guard | Rule text is as quoted, but **nothing reads this collection** — the only client touch is a `setData` |
| `ownedPath()` has zero test coverage | Code is correct as written and all three callers feed it; harm is conditioned on a hypothetical future widening |
| `storage.rules` has no automated coverage | Same reasoning — `storage.rules:134-146` correctly scopes `recruiting_headshots/{userID}/{fileName}` today |
| Lowercased share token passes `TOKEN_RE` but the equality query never matches | Both branches produce the same 404 + `unavailablePage()`; no behavioral difference |
| Share-row tiles truncate / icons ignore Dynamic Type | Style opinion against the codebase's own convention (`lineLimit(1)` + `minimumScaleFactor`) |
| Athlete-UUID reconcile orphans a live public page | The two reassign sites are real but the scenario requires state that does not occur |
| "Where to see me play" schedule block is missing | Net-new feature proposal; nothing in code, copy, or docs promises it |

---

## 9. Execution order

> ✅ **Steps 1–4 are COMPLETE (see §0). Start at step 5, P1.5.** Step 6's CF redeploy has also happened, but
> carried only P0.1 + P3.5 + what was already written — **P2.3, P2.4, P2.6 and P2.9 are still unwritten** and
> will need another deploy. Run `cd firebase/functions && npm run build` first; the CLI does not compile
> TypeScript, and a predeploy guard will now block you if you forget.

1. ~~**Release `firestore.rules`**~~ ✅ DONE — unblocks Reset Link in prod. Fold in **P2.7**'s `hasOnly` + Pro gate
   (remember `createdAt` in the allowlist). Run the emulator suite first:
   `cd firebase/rules-tests && export JAVA_HOME="$(echo ~/.local/jdk/*/Contents/Home)" && npm test`
2. **P0.1 codec fix** — nothing else in this document matters if the film does not play. Ship the
   `<source type>` + fallback-text mitigation in the same change.
3. **P1.1 + P1.2 + P1.6 as one edit** — awaited tier sync, `isFromCache`/`source: .server`, and the
   connectivity guard. These are the three that touch money and the kill switch.
4. **P1.3 + P1.4 as one edit** — the blob merge and the unknown-key sidecar are one data-integrity change.
5. **P1.5, P1.7, P1.8, then P2.1 / P2.5** — client-only, no backend coupling.
6. **CF redeploy** carrying P1.5's `athleteId` payload, the already-written per-account digest, P2.3's
   memoization + `maxInstances`, P2.4's timeout race, P2.9's `lastDigestAt`, P3.5's CSS cap, P3.6's TTL.
7. ~~**P3.1** (stale-profile nudge)~~ ✅ DONE.
8. ~~**P3.2** (growth loop measurable)~~ ✅ code complete — **its CF deploy is still pending.**
9. Everything else in §6 / §7 — **see §0's scoreboard for the ordered remaining list**, which supersedes this
   step list.

### Verification checklist after each stage
```bash
# iOS
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project PlayerPath.xcodeproj -scheme PlayerPath -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Functions
cd firebase/functions && npx tsc --noEmit -p tsconfig.json

# Rules
cd firebase/rules-tests && export JAVA_HOME="$(echo ~/.local/jdk/*/Contents/Home)" && npm test
```
Bump `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION` in both Debug and Release build configs before any
device build (currently 6.4.2 / 206).

### Device tests still outstanding
- **P0.1:** open a published link in **Firefox** and on a **Windows** machine — before and after the fix.
- **P1.5:** requires **two athlete profiles** — unreproducible on a single-athlete account. Tap a recruiting
  push while a DIFFERENT athlete is selected and confirm you land on that athlete's Recruiting editor, not the
  More root.
- **P1.7:** turn Profile View Alerts OFF on device A, open Settings → Notifications on device B, confirm B
  shows OFF and Firestore still reads `recruitingViews: false`. Also open the screen in airplane mode and
  confirm no write happens (a failed read must not back-fill).
- **P1.8:** pick a headshot on slow cellular and confirm Share Profile + Preview are held until it lands.
- **P2.6:** two published athletes on one account, open both links within a minute → exactly **one** push.
- **P2.3:** reload a published link several times in a browser → `viewCount` moves once per hour, not per load.
- Reset Link end-to-end: old URL → "Profile unavailable", new URL serves, QR shows the new link.
- Free-tier surface: no share verbs / bio / Activity / Reset; **Unpublish still reachable**.
- Unpublish → page goes to "Profile unavailable".
- Over-the-top **V34→V35 migration** (install over existing data, not fresh — a migration failure looks like
  data loss because the container falls back to in-memory).
- Headshot upload + cross-device sync; first-view instant push; next-day digest; republish preserves
  `dailyViews`; QR scan; mailto prefill.

> ⚠️ Plain `curl` is **not** in the CF's `BOT_UA` regex, so every curl check inflates `viewCount`. Test with a
> bot UA or a real browser.
