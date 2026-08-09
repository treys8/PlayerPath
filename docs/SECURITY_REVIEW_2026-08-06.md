# PlayerPath Security Review & Minors-Data Assessment — 2026-08-06
Method: 14 parallel audit agents across Firestore rules, Storage rules, Cloud Functions, the public
recruiting endpoint, the iOS client, logging/analytics, and privacy/minors compliance; every finding
then adversarially re-verified against source. 41 agents total. The top 8 findings were additionally
confirmed by hand against the code before this document was written.

---

## ✅ Remediation batch 1 — 2026-08-06 — **SERVER DEPLOYED**, client build 215 pending release

**Deployed to `playerpath-159b2` on 2026-08-06:** `firestore:indexes` (purely additive — verified
nothing would be deleted first), `firestore:rules` (released), and all **38 Cloud Functions**
(zero failures). Post-deploy smoke test: `serveRecruitingProfile` returns 404 for an unknown token
with `x-robots-tag: noindex`, `cache-control: no-store`, `referrer-policy: no-referrer` and the full
CSP intact.

Because the server half of the under-13 gate is the *retroactive* one, **already-published profiles
with no grad year stopped serving contact details the moment the functions deployed** — that
protection is live now and does not wait on the app release.

Client build 215 (the `contactPublishingBlocked` gate, editor/readiness copy, `canPublish` grad-year
requirement, and the `cfManagedKeys` strip) still needs to ship through TestFlight/App Store.

## ✅ Remediation batch 2 — 2026-08-08 — **SERVER DEPLOYED**, client half in build 216

Findings **#4** (account deletion never swept `shared_folders/**` Storage) and **#6** (deleting a
child's athlete profile left the coach folder fully live) are fixed. `cleanupUserDataOnDelete` and
`onSharedFolderDeleted` deployed to `playerpath-159b2`; both now run at 512MB.

| Finding | Fix |
|---|---|
| #4 | `cleanupUserDataOnDelete` step 2 sweeps `shared_folders/{id}/` **before** deleting the folder doc (doc-last, so a timeout leaves findable docs rather than unfindable bytes), with a per-folder try/catch so one bad prefix can't strand the rest. `onSharedFolderDeleted` sweeps the same prefix on **any** folder-doc delete, placed above the no-coaches early return — deleting the doc is now sufficient by construction, so no future delete path has to remember Storage. |
| #6 | `performDeleteAthlete` queries the athlete's folders and runs the full `SharedFolderManager.deleteFolder` path (ends coach sessions → revocation tombstone per coach → videos/Storage → folder doc), in the same privacy-critical band as the recruiting-profile delete. |

**Raised while implementing, not in the original findings:**

- `deleteSharedFolder`'s `while true` video loop **could spin forever** — a page where every Storage
  delete fails deletes nothing, so the next iteration refetches the same 400 docs indefinitely,
  re-issuing 400 reads and N Storage calls each time. Now bounded on no-progress plus a 50-page cap.
  Bailing early is safe *because* #4 landed first: the server sweeps the prefix regardless.
- `cleanupUserDataOnDelete` had **no `runWith`** — 60s/256MB for fourteen sequential steps, and #4
  added per-folder Storage sweeps on top. A timeout there is a half-finished account deletion that
  nothing re-triggers, since the Auth user is already gone. Raised to 540s/512MB.

**Traps avoided (each would have made the fix silently useless or actively harmful):**

- `fetchSharedFolders(forAthlete:)` keys on `ownerAthleteID`, which is the **account UID** — using it
  for #6 would have deleted the *siblings'* folders on a family account. The new
  `sharedFolderIDs(forAthleteUUID:)` keys strictly on `athleteUUID` and must never fall back.
- It returns raw document IDs, not decoded `SharedFolder` values: the sibling fetchers drop
  undecodable docs with a warning, and in a deletion path a silently skipped folder is the bug.
- Offline athlete deletion self-heals — Storage deletes fail with no offline queue, but the
  folder-doc delete is durably queued, and when it lands the server trigger sweeps.

### Self-review pass on batch 2 — one defect that would have made #6 a no-op

**The cascade query was denied by security rules.** `sharedFolderIDs(forAthleteUUID:)` filtered only
on `athleteUUID`, but the `sharedFolders` read rule requires owner-or-coach — and Firestore evaluates
list rules against a query's **potential** result set, not the documents actually returned. So the
query threw `permission-denied` every time, the fire-and-forget catch logged it, and the deleted
child's folders stayed live. The fix reads as a loosening but is the opposite: adding
`ownerAthleteID == <auth uid>` is what makes the query *legal*, and it's served by the composite
index already deployed for the Cloud Function. Three regression tests in `sharedFolders.test.mjs`
pin the behaviour (athleteUUID-only denied, both-filters allowed, stranger denied).

Caught before build 216 shipped, so no user was ever affected — but nothing in the type system or
the build would have flagged it, and in a fire-and-forget path it fails **silently**.

Also fixed during the same pass: the first version of that fix read `user.firebaseAuthUid` *inside*
the detached Task, i.e. touching a SwiftData model after `athlete.delete(in:)` — the documented
across-await trap. It is now captured with the other values before the local delete, and
deliberately without the `?? uuidString` fallback, which is a value no folder carries and the rules
deny anyway.

Verified clean during review: no flow deletes a `sharedFolders` doc expecting its bytes to survive
(all three delete sites are genuine teardown; `CoachFolderArchiveManager` is UserDefaults-only, so
"archiving" never touches Firestore).

**Written but NOT run:** `firebase/functions/scripts/reconcile-shared-folder-orphans.js` clears
objects already stranded in GCS (dry-run default; aborts if Firestore returns implausibly few
folders, since a bad read would otherwise make everything look orphaned). Needs
`GOOGLE_APPLICATION_CREDENTIALS`.

**Still open from the original 20:** #5 permanent `downloadURL()` tokens, #13 Analytics PII, and the
consent/age-gate/privacy-policy track. Note #4 and #6 reduce but do **not** eliminate the exposure
while #5 stands: bytes are now deleted, but any token URL captured before deletion stopped working
only because the object is gone — a coach who downloaded the file still has it.

---

## ✅ Remediation batch 3 — 2026-08-08 — #5 and #13 FIXED (client in build 217)

`getPersonalPhotoSignedURL` deployed to `playerpath-159b2` (verified: returns `UNAUTHENTICATED`
without a token). Everything else is client-side and ships in **build 217**.

**#13 — Analytics PII, complete.** All five leaks closed in `AnalyticsService.swift`:
`feedback_text` (verbatim cancellation text) deleted along with its parameter, so the call site can't
pass it; `opponent` → `has_opponent: Bool`; `error_description` deleted (domain/code/context kept,
and the full error still reaches Crashlytics); `user_id` deleted from all four GDPR events.

The `setAnalyticsCollectionEnabled(true)` fix is sharper than the finding described. Firebase
**persists** that flag across launches, so forcing it in the singleton initializer silently
re-enabled collection for an opted-out user on *every* cold start — and because `MainAppView.task`
is what applies the real preference, they were collected for the whole window in between. The call
is now gone entirely: Firebase restores the persisted value, so an opt-out holds from process start.

**#5 — permanent token URLs.** Three parts:

- **Export leak closed.** `DataExportView` no longer writes `photo.cloudURL`; it writes
  `isCloudBacked: Bool`. `filePath` already identified each record.
- **Shared-folder minting stopped.** `uploadVideo`/`uploadThumbnail` return the Storage **path**;
  the dead, misnamed `getSecureDownloadURL` is deleted. `markVideoCompleted(storageURL:)` renamed to
  `storagePath:`. A path is **not a capability** — fetching it still goes through storage.rules —
  unlike the token URL, which Firebase serves with no auth and without consulting rules at all.
  `firebaseStorageURL` is still **written** (never omitted) because it is non-optional in
  `FirestoreVideoMetadata` and omitting it would make every shared clip silently vanish from the
  coach's list and both review queues.
- **Photo signed path built.** New `getPersonalPhotoSignedURL` (owner derived from the verified
  token, never the body — the Admin SDK bypasses storage.rules, so a body-supplied uid would be a
  bucket-wide read oracle) + `SecureURLManager.getPersonalPhotoURL`, wired into all three photo
  consumers signed-first with `cloudURL` as fallback.

**Hardened during self-review:** `RemoteThumbnailView`'s non-secure fallback now requires an
absolute http(s) URL. With minting stopped, `thumbnail.standardURL` can hold a *path*, and
`URL(string:)` builds a relative URL from that which fails confusingly. All three shared-folder call
sites pass `folderID` + `videoFileName` and take the secure branch, so this is belt-and-braces.

**Still to run, deliberately not automated:**
`firebase/functions/scripts/rotate-shared-folder-tokens.js` — rotates
`firebaseStorageDownloadTokens` on every `shared_folders/` object, killing every URL already in
circulation. **This is the step that actually retires the revoked coach's links.** Dry-run default.
Safe now, because nothing reads those URLs.

**Deferred by design (#5 follow-up):** rotating `athlete_photos/` tokens and dropping the `cloudURL`
fallback. Must wait until the signed photo path is proven on device in build 217 — rotating first
would break every photo in the app.

---

### Second pass over #4/#5/#6/#13 — 2026-08-08 — two findings that enlarge #5 and #13

**#4 and #6 audited clean this pass.** The `shared_folders/{folderID}/` prefix does cover thumbnails
(they live at `.../thumbnails/...`, confirmed against every Storage path the client builds), so the
sweep is complete for its scope. The coach's copies are folder-scoped `videos` docs
(`sharedCoachVideoIDs`), so deleting the folder deletes them. And the cascade is genuinely reachable
— every preceding call in that Task is `await retryAsync { }`, which swallows rather than throws, so
nothing can skip it.

**🔴 #5 is roughly 3× larger than the original finding says.** The audit named two
`downloadURL()` sites in `VideoCloudManager+SharedFolders.swift`. There are **seven**, and the others
cover the athlete's *personal* media:

| Site | Mints a permanent token URL for |
|---|---|
| `VideoCloudManager.swift:178` | personal athlete videos |
| `VideoCloudManager+Photos.swift:36`, `:85` | photos (two paths) |
| `VideoCloudManager+Metadata.swift:463` | thumbnails |
| `VideoCloudManager+SharedFolders.swift:51`, `:117`, `:160` | shared-folder video / thumbnail / (dead code) |

Personal media is a weaker exposure than shared-folder media — no revoked coach holds the URL — but
it is the same defect, and it has one consequence the original review missed entirely:

**🔴 "Export My Data" ships live, unauthenticated, permanent URLs to a child's photos.**
`DataExportView.swift:400` writes `"cloudURL": photo.cloudURL` into the export, and `photo.cloudURL`
is exactly the `downloadURL()` token string minted at upload (`SyncCoordinator+Photos.swift:85-89`).
The export is a file the parent is invited to save and share; anyone they forward it to can fetch
that child's photos forever, with no account and no way to revoke short of rotating the object's
token. The original review flagged the export as *incomplete*; it is also *leaking*. Whatever fixes
#5 must cover this, and dropping the field is a cheap interim mitigation.

**🔴 #13: `user_id` is sent as an event PARAMETER, on the privacy events specifically.**
Beyond the three known PII parameters, `AnalyticsService` uploads the raw Firebase Auth UID as an
event parameter on four events (`trackDataExportRequested`, `trackAccountDeletionRequested`,
`trackAccountDeletionCompleted` — lines 413/425/431). Google's Analytics ToS prohibits uploading
persistent identifiers as event parameters, and this is on top of the `setUserID` linkage. The irony
is the aggravating factor: the events that carry it are the ones a family fires while *exercising a
privacy right* — requesting their data, or deleting the account.

---

### 🔴 Discovered during deploy: `dailyStorageCleanup` §1 and §4 have never run in production

Listing the live indexes confirmed the suspicion in the plan: there is **no composite index** for
either `videos: isDeleted == + deletedAt <=` (§1) or `videos: uploadStatus in + createdAt <=` (§4).
Both are equality-plus-range and require one, so both sections have been throwing
`FAILED_PRECONDITION` into their outer `catch` since they shipped. Consequences:

- Orphaned shared-folder uploads have **never** been reaped, and soft-deleted data has never been purged.
- The §4 hardening in this batch is currently repairing dead code (harmless, and correct for when it wakes up).
- **Adding those two indexes would activate a destructive cron that has never executed against
  production data.** Deliberately NOT done in this deploy. §4 is now safe to activate (path
  validation + claimant check); §1 has not been reviewed at all. Treat enabling them as its own
  change, with §1 reviewed first.

---

### Original batch-1 record

The coach-sharing authz cluster and the under-13 fail-open are **fixed in the working tree**.
Verified: `firebase/functions` tsc clean, `xcodebuild` BUILD SUCCEEDED, rules suite 68/68 — and,
critically, the 5 new rules tests were run against the **pre-fix** rules and all 5 failed, so they
prove the defect rather than merely describing current behaviour.

| # | Finding | Fix |
|---|---------|-----|
| 1 | Invitation accept joins any folder | `index.ts` — folder-ownership guard (throws), owner-scoped reuse query, permissions shape normalization, `athleteID` operand guard, `athleteUUID` length caps, ownership-miss instrumentation. New `athleteUUID+ownerAthleteID` composite index. |
| 2 | `dailyStorageCleanup` §4 arbitrary delete | `index.ts` — inline component validation (skip + log + converge), plus a **claimant check** that also fixes a pre-existing data-loss bug where a retried upload's stale `failed` doc deleted the live clip 24h later. |
| 3 | `isCoachLeavingFolder()` missing subset check | `firestore.rules` — subset check on `sharedWithCoachIDs` **and** `permissions`. |
| 8 | `sharedFolderID` mutable on personal clips | `firestore.rules` — unconditional `get(...,null)` comparison. |
| 18 | Coach could delete own revocation | `firestore.rules` — athlete-side delete only. |
| 10 | `coachTierSource` client-writable | `firestore.rules` create+update freeze, `cfManagedKeys` in Swift, and `normalizeTierSource()` in `index.ts` failing closed on unrecognized values (repairs already-poisoned docs). `coach_academy` is now excluded from both auto-downgrade branches, since it has no StoreKit product and must never be revoked by one. |

### Self-review pass — three defects found in the fixes above, all corrected

1. **The §4 claimant check was defeatable by the attacker it guarded against.** Fetching 20 docs and
   filtering in code meant planting 20+ pending/failed docs for a victim's path pushed their real
   `completed` doc out of the window. Now a server-side `uploadStatus == 'completed'` filter (window
   irrelevant), with the bounded scan kept only as a legacy safety net.
2. **The athlete-only revocation delete broke client account deletion for coaches.** `FirestoreManager+UserProfile.swift`
   step 6 looped over both `athleteID` and `coachID`; the coach axis now always throws, recording a
   spurious failure. Dropped that axis — `cleanupUserDataOnDelete` step 9 already sweeps both with
   the Admin SDK.
3. **Failing `coachTierSource` closed could have silently downgraded a hand-granted Academy comp**
   if an admin had typed a marker like `'manual'` in the console. Academy is now excluded from both
   write-down branches, and the normalizer logs loudly when it reinterprets a value.

Also hardened: `isCoachLeavingFolder()`'s permissions check uses `.get('permissions', {})`, because a
bare read of a missing field errors — and an errored rule denies, which would have bricked the coach
downgrade self-shed on any folder lacking a permissions map. Two regression tests cover the real
client write shape and the legacy no-permissions folder.
| 7 | Under-13 gate failed open on nil grad year | New `RecruitingInfo.contactPublishingBlocked` (nil **or** under-13), server `contactSection` mirror (retroactive for already-published profiles), distinct editor/readiness copy, and `canPublish` now requires a grad year. Unpublish deliberately left ungated. |

**Still required before this is real:**
1. Run the pre-deploy audit queries in the plan (they need production Admin SDK access — they check
   for live invitations naming a folder their sender doesn't own, and for `sharedFolders` rows where
   `athleteUUID` and `ownerAthleteID` disagree).
2. Confirm whether `dailyStorageCleanup` §1/§4 have their required `videos` composite indexes in the
   console. `firestore.indexes.json` declares neither, and both queries are equality-plus-range — if
   they were never created by hand, those sections have been throwing `FAILED_PRECONDITION` since
   they shipped and fix #2 is repairing dead code.
3. Deploy in order: `firestore:indexes` → `firestore:rules` → `functions` (via `npx firebase-tools`
   on Node 20), then ship build 215.

**Not in this batch** (unchanged, still open): #4 account-deletion `shared_folders/**` Storage sweep,
#5 permanent `downloadURL()` tokens, #6 athlete-delete cascade, #13 Analytics PII, and the whole
consent/age-gate/privacy-policy track.

---

## 🔎 Independent adversarial review of the remediation — 2026-08-08 — **SERVER DEPLOYED**

A second reviewer re-verified all three batches against source with no access to the authors'
reasoning, and was told to treat this document as unverified claims. Everything below was
confirmed by running something — `tsc`, `xcodebuild`, the rules emulator, or the scripts
themselves — not by reading.

**Eight defects in the fixes.**

**Deployed to `playerpath-159b2` on 2026-08-08:** `firestore:rules` (compiled clean, released)
and all **39 Cloud Functions** (zero failures). `firestore:indexes` deliberately NOT deployed —
nothing in it changed, and the `dailyStorageCleanup` §1/§4 indexes stay absent on purpose because
adding them activates a destructive cron that has never run against production data.

Post-deploy smoke test: `serveRecruitingProfile` returns 404 for an unknown token with
`cache-control: no-store`, `referrer-policy: no-referrer`,
`x-robots-tag: noindex, nofollow, noimageindex` and the CSP intact; all five signing callables
(`getSignedVideoURL`, `getSignedThumbnailURL`, `getBatchSignedVideoURLs`,
`getPersonalPhotoSignedURL`, `getPersonalVideoSignedURL`) return `401 UNAUTHENTICATED` without a
token.

**Client half is NOT shipped** — items 1 and 2 below are the P0 crash fix and both live only in
build 217. Nothing deployed here depends on them.

| # | Where | What was wrong |
|---|---|---|
| 1 | `VideoCloudManager+Photos.swift:252` | **P0, would have shipped in 217.** The new signed-photo path called `Storage.reference(forURL:)` on a GCS signed URL. That API **`fatalError`s** on any URL that is not `…/v0/b/<bucket>/o/<obj>` — an uncatchable abort, so the `do/catch … fall through to the legacy token URL` in all three consumers could never run. It would have crashed on every photo whose local file was missing: fresh install, restored device, second device, cache eviction — i.e. exactly the case the code was added for. Now a plain `URLSession` download (the pattern `CoachVideoCacheService` already used), with an HTTP-status check so a 403 body is never written over the photo. |
| 2 | `VideoCloudManager.swift:239` | Same root cause, pre-existing and never noticed: `try storage.reference(for:)` **throws** on a signed URL, so `getPersonalVideoURL` → `downloadVideo` has never worked. Personal-video cloud re-download and `RecruitingWebRenditionService`'s source fetch both silently failed. This is load-bearing for #5's endgame — the `cloudURL` tokens can only be dropped once the signed path works. Now branches on `isFirebaseStorageURL()`. |
| 3 | `index.ts` `normalizeTierSource` | **Deployed and live.** The self-review spotted the fail-closed hazard and fixed it only on the coach axis (`coach_academy` exclusion). `athleteTierSource` has **never** been client-writable — it was in both rules lists long before this work — so collapsing an unrecognized value there has zero security benefit and one effect: it silently revokes a hand-granted athlete comp, then stamps `'storekit'` so the doc looks like a lapsed purchase. Split into `normalizeCoachTierSource` (fails closed) and `readAthleteTierSource` (preserves). |
| 4 | `index.ts:3055/3142/3199` | The #5 remediation hands the whole guarantee to the signing CFs — and all three still accepted a client `expirationHours` clamped only at **720** and authorized on bare array membership with **no `coach_access_revocations` check**. A coach anticipating removal could mint 30-day URLs over the entire folder; token rotation does nothing about those. `MAX_EXPIRATION_HOURS` is now 24 and the triplicated access block is one `assertFolderMediaAccess()` that consults the deny-list. |
| 5 | `firestore.rules:277` | **Deployed and live.** `coachAthleteCount` was introducible while absent, and the "Raised and dismissed" entry below is **wrong**: `index.ts:2538/:2886` read `coachAthleteCount ?? recompute`, so the cached counter *is* the seat-limit operand. Seeding `-1000` bought unlimited connections to minors on a free seat. Added to the `hasAny` deny list. |
| 6 | `index.ts` §4 Query B | The `limit(20)` legacy net was defeatable by the attacker Query A's server-side filter was added to stop — not by authoring a field-absent doc, but by **evicting** the victim's from the window with 20 planted pending docs. Now cursor-paged, and hitting the cap counts as claimed. |
| 7 | `firestore.rules` `isCoachLeavingFolder()` | The subset check forbids additions but permits removing *any* key, so a departing coach could strip a co-coach's `permissions` (silently disabling them while they stay a member), and `sharedWithCoachNames` had no constraint at all — the relabelling finding 3 itself described. Both maps now use `.diff().affectedKeys().hasOnly([uid])`, which covers additions, removals and value changes. |
| 8 | both `scripts/*.js` | **Verified by running them: neither could execute.** `admin.initializeApp()` with only `GOOGLE_APPLICATION_CREDENTIALS` leaves `storageBucket` undefined and throws at module load, so both usage lines were wrong — and the banner printed `(from credentials)`, never naming the project it was about to delete from. New `scripts/_preflight.js`: refuses to run with any emulator var set, requires credentials whose `project_id` matches, initializes explicitly, prints the real project/bucket/service account. |

**Also closed while in there** (both were in the original 20, both left open, both one line):
finding 16 — `canComment` is now enforced server-side via a legacy-tolerant
`hasPermissionOrLegacy()`, so "Add Comments: off" stops meaning UI-only; finding 20 —
`coachSessions.coachID` is frozen on update.

**Changed behaviour worth knowing about:**

- `MAX_EXPIRATION_HOURS` 720 → **24**, and the Swift thumbnail default 168 → 24 to match.
  Free, because `SecureURLManager`'s cache is in-memory and re-signs every cold launch.
- `rotate-shared-folder-tokens.js` now **removes** the token rather than writing a fresh UUID.
  Rotating swapped one permanent public link for another that merely happened to be unknown,
  and any current member could re-learn it via `getDownloadURL()`. Removal also makes success
  verifiable: a clean re-run must report `Carrying a token: 0`.
- `CoachVideoItem.firebaseStorageURL` deleted. Zero readers, but a decoded URL-named `String`
  that now holds a *path* was one autocomplete away from an `AVPlayer(url:)`.

**Verified sound, so it is not re-litigated later:** nothing reads `firebaseStorageURL` as a
URL (5 hits total, none in `functions/src`); all three `RemoteThumbnailView` call sites take
the secure branch at HEAD as well as in the working tree; `Photo.fileName` really does equal
the Storage object name on every path, with the uid always `Auth.currentUser.uid`; the
athlete-delete cascade is both permitted *and* correctly scoped (proved with a two-child
family-account test, plus a case-sensitivity pin on Swift's uppercase `uuidString`); the
self-shed write shapes all still pass, including the legacy no-`permissions` folder; only
three code paths delete a folder doc and all are genuine teardown; and the under-13 gate
fails closed on every route — `visibleContactItems` is the only publish path,
`contactSection` the only server render path, and the readiness row `canPublish` reads is
added unconditionally, so its `?? true` default is unreachable.

**Verification:** `tsc` clean · `xcodebuild` BUILD SUCCEEDED · rules suite **100/100**
(73 pre-existing + 27 new in `firebase/rules-tests/adversarial-review.test.mjs`, which pins
the shipped-client write shapes against the deployed rules as well as each hole above) ·
both maintenance scripts confirmed to abort on missing credentials, on a wrong-project
service account even with `--apply`, and on a stray `FIRESTORE_EMULATOR_HOST`.

**Still open, deliberately:** finding 9 (storage-quota bypasses), finding 11
(`personGroupID` seat collapse — instrumented, not enforced), finding 12 (invitation email
abuse), finding 15 (on-device wipe gaps), finding 19 (sandbox StoreKit), the
`dailyStorageCleanup` §1/§4 indexes, and the whole consent/age-gate track.

### Run this before trusting any of it

`scripts/audit-security-preconditions.js` (new, read-only, no `--apply`) runs the two
production queries this document listed as required and that were never run, plus two more:
non-canonical tier-source markers (§1 — flags in red any coach comp that the deployed
normalizer **will** revoke on its next sync), implausible `coachAthleteCount` values (§2),
pending invitations naming a folder their sender does not own (§3 — these now hard-throw on
accept), and folders missing `ownerAthleteID` (§4). Exits non-zero if it finds anything.

---

## Bottom line

PlayerPath's security posture is better than most solo-built consumer apps I've reviewed: Firestore rules are field-frozen and thoughtfully commented, StoreKit receipts are cryptographically verified server-side, the public recruiting page has a real CSP/noindex/prefix-pinning defense stack, and there are no committed secrets. The real problems cluster in one place — the coach-sharing seam — where three independent defects let a current or former coach reach, retain, or destroy a minor's video after the family revoked them. On minors' data specifically: the technical protections around the public page are genuinely good, but the app has no age gate, no verifiable parental consent, and its one age signal (grad year) is optional and fails open, so a young child's contact details can publish with no gate firing. Fix the four coach-sharing findings first; the compliance work is a separate, slower track.

## Are we set up to handle minors' information?

Partly — you are further along than most, but not where a product built around video of children needs to be. What's genuinely right: the recruiting page withholds email/phone/GPA for implied-under-13 athletes on BOTH the client and the server (so old app builds and already-published profiles are covered retroactively), the page is noindex/nofollow/noimageindex with a real CSP and 3-hour signed media URLs, publishing is per-field opt-in defaulting to off behind a guardian attestation that re-arms whenever a republish newly exposes something, and account deletion does take the public page down. The single biggest gap is that all of that hangs on one optional, self-reported field. `gradYearImpliesUnder13` (PlayerPath/Models/RecruitingInfo.swift:359) is `guard let gradYear else { return false }` — unknown means "not a child" — and the server mirror at recruitingProfile.ts:460 does the same, so a parent who leaves the Grad Year picker on "—" publishes a 10-year-old's phone number and email with zero gate firing on either side, while your own readiness checklist actively prompts them to add one. Behind that sits the deeper issue: there is no date of birth anywhere in the app and no verifiable parental consent — a checkbox at signup is what you have, and COPPA does not accept a checkbox for publicly disclosing a child's photograph and video. Separately, the runtime side leaks: a coach removed by a family can still hold working media links, a deleted athlete's coach folder stays fully live, and account deletion never removes the `shared_folders/**` bytes at all. Engineering guidance only — not legal advice; before you ship the consent changes, spend a few hours with a privacy attorney who has done COPPA work, because the "general-audience, parent-operated" vs "child-directed" classification decision drives everything else and is worth getting right once.

## Top 3 actions

1. Validate the invitation-accept Cloud Functions before they touch any folder. In firebase/functions/src/index.ts: (a) at line ~2432, require `legacyFolderSnap.data().ownerAthleteID === inv.athleteID` before joining the folder, and clamp `inv.permissions` to server-defined defaults instead of trusting the invitation; (b) at line ~2476 and ~2554, assert `athleteOwners/{athleteUUID}.userId` equals the invitation's athlete-side account before calling reuseOrCreateSharedFolders, and stop preferring the client-body athleteUUID over the invitation's; (c) inside reuseOrCreateSharedFolders (line 4182), add `.where('ownerAthleteID','==',params.ownerAthleteID)` to the reuse query. This is the one path that lets a removed coach silently re-grant themselves read+delete on a minor's whole library.

2. Close the two Firestore-rules holes that make the CF fix load-bearing. In firestore.rules: add `&& request.resource.data.sharedWithCoachIDs.removeAll(resource.data.sharedWithCoachIDs).size() == 0` inside isCoachLeavingFolder() (line ~166) so cardinality plus subset really means 'only the caller left'; and replace lines 512-513 with `request.resource.data.get('sharedFolderID', null) == resource.data.get('sharedFolderID', null)` so an uploader can never add a sharedFolderID to a personal clip — that single change also kills the dailyStorageCleanup cross-tenant delete primitive at its source.

3. Make revocation and deletion actually reach the bytes. Three changes: in firebase/functions/src/index.ts cleanupUserDataOnDelete step 2, call `bucket.deleteFiles({ prefix: `shared_folders/${folderDoc.id}/` })` before recursiveDelete-ing the folder doc (today those files survive account deletion forever); in PlayerPath/Views/Profile/AthleteManagementView.swift performDeleteAthlete, write coach_access_revocations docs and delete the athlete's shared folders before the local delete; and stop calling `downloadURL()` in PlayerPath/VideoCloudManager+SharedFolders.swift:51 and :117 — store the Storage path and let SecureURLManager mint expiring URLs, then sweep `firebaseStorageDownloadTokens` off existing shared_folders objects with an Admin SDK job.

---

## Ranked security findings

### 1. [CRITICAL] Invitation-accept Cloud Functions trust unvalidated invitation fields, joining a coach to ANY athlete's folders and erasing the revocation record

**Where:** `firebase/functions/src/index.ts:2432 and :2476 and :4182`  
**Confidence:** confirmed — traced end to end, no mitigation at any layer  
**Effort:** half day including a rules-emulator test for each variant

**What:** Two sibling defects in the same callable. (a) The legacy branch resolves `db.collection('sharedFolders').doc(inv.folderID)` and arrayUnions the accepting coach into it with the invitation-supplied `permissions` map — never checking that the folder's ownerAthleteID matches the inviting athlete. (b) reuseOrCreateSharedFolders finds folders with a bare `where('athleteUUID','==',athleteUUID)` and no ownerAthleteID filter. Both then `transaction.delete(coach_access_revocations/<folderID>_<coachID>)`, which is precisely the doc canAccessFolder() consults to keep a removed coach out. firestore.rules:977-1004 constrains none of folderID, athleteUUID, or permissions on invitation create. This is the one path CLAUDE.md declares safe — the CF itself is the bypass.

**Exploit:** A coach who was removed from a 13-year-old's folder knows both the folderID and the athleteUUID (both are in the video docs and folder doc they legitimately read). They create a second account, self-invite from it with `folderID: <victim folder>` and `permissions: {canUpload:true, canComment:true, canDelete:true}`, and call acceptAthleteToCoachInvitation. The CF joins them to the victim's folder with self-granted delete rights and deletes the revocation doc. getSignedVideoURL (index.ts:2900) then authorizes on bare sharedWithCoachIDs membership and never consults revocations — so they stream and can delete the minor's entire shared library, silently, with the family's revocation permanently erased.

**Fix:** In index.ts inside the acceptAthleteToCoachInvitation transaction, after reading legacyFolderSnap, require `legacyFolderSnap.data()?.ownerAthleteID === inv.athleteID` and throw permission-denied otherwise (and do NOT delete the revocation doc on that path). Replace `const permissions = inv.permissions || {...}` with a server-defined constant. At line 2476 and 2554, read `athleteOwners/{athleteUUID}` (the index already exists, written Admin-SDK-only by athleteOwnership.ts) and require `.userId === invData.athleteID` / `=== context.auth.uid` respectively; stop preferring the client body's athleteUUID over the invitation's. In reuseOrCreateSharedFolders (line 4182) add `.where('ownerAthleteID','==',params.ownerAthleteID)` to the reuse query. Also add `isCoachRevokedFromFolder` equivalent checks to the three signing CFs.

### 2. [HIGH] dailyStorageCleanup deletes shared_folders objects from an attacker-controlled folderID + fileName — irreversible destruction of a minor's game film

**Where:** `firebase/functions/src/index.ts:4596-4604`  
**Confidence:** code confirmed verbatim; exploit chain plausible and the write primitive is separately confirmed (finding 8)  
**Effort:** 1 hour for the CF guard, plus finding 8's one-line rules change

**What:** Section 4 selects videos docs with uploadStatus pending/failed older than 24h and does `bucket.file(`shared_folders/${data.sharedFolderID}/${data.fileName}`).delete()` with the Admin SDK — no ownership check, no folder-membership check, no filename sanitization. The sibling pendingDeletions branch 90 lines above explicitly prefix-validates and comments that Admin-SDK delete bypasses Storage rules so 'this is the only authorization boundary here'. Section 4 has no boundary. storage.rules:53 deliberately restricts shared-folder deletes to the folder OWNER; this cron hands that capability to anyone who can write a videos doc.

**Exploit:** A coach (current, or removed — they retain the folderID and fileName values from docs they legitimately read) creates their own personal videos doc with `fileName` set to the victim's file, `uploadStatus:'pending'`, `createdAt` 25h ago and no sharedFolderID (allowed by the personal-video create branch), then PATCHes in `sharedFolderID: <victim folder>` (allowed because firestore.rules:512 only freezes the field if it was already present). The next nightly run deletes the victim's bytes from GCS. One doc per clip wipes the child's entire shared library; the Firestore doc survives so the athlete sees an intact entry until playback fails.

**Fix:** In index.ts section 4, load `sharedFolders/{folderID}` and confirm the doc's uploadedBy is the folder owner or a current member before deleting; reject any fileName containing '/' or '..' by routing it through the existing sanitizeFileName (index.ts:96). Independently apply the rules fix in finding 8, which removes the write primitive entirely.

### 3. [HIGH] isCoachLeavingFolder() omits the subset check its sibling branch has, letting a folder coach replace the membership array with arbitrary UIDs

**Where:** `firestore.rules:166-178`  
**Confidence:** confirmed — I re-read firestore.rules:161-178 directly  
**Effort:** 30 min + test

**What:** The comment says 'Exactly one coach removed, none added', but the rule only checks cardinality (`new.size() == old.size() - 1`) plus 'caller not in the new array'. It never checks the new array is a SUBSET of the old. The owner-update branch at line 462-465 does exactly that check (`.removeAll(...).size() == 0`); this branch, OR'd in as a peer at line 466, does not. `permissions` is in the hasOnly allowlist with no constraint, so the same write grants the injected UID full canUpload/canComment/canDelete. Multi-coach folders are the norm — reuseOrCreateSharedFolders arrayUnions each new coach into the athlete's existing games/lessons folder.

**Exploit:** Coach A, legitimately in athlete X's Lessons folder alongside coach B, writes `{sharedWithCoachIDs: ['C'], 'permissions.C': {canUpload:true,canComment:true,canDelete:true}, updatedAt: ...}` where C is a throwaway account A controls (role:'coach' is freely self-assignable at users-create). Every clause passes. Coach B is silently ejected with no revocation record and no notification; account C — which the family never invited — gains read and delete on the minor's clips. Because coach_access_revocations is keyed <folderID>_<coachID>, when the family later revokes A, C carries no revocation doc and keeps access indefinitely. A also controls sharedWithCoachNames in the same write, so C can be labelled with the ejected coach's name in the member list.

**Fix:** Add `&& request.resource.data.sharedWithCoachIDs.removeAll(resource.data.sharedWithCoachIDs).size() == 0` inside isCoachLeavingFolder(), and constrain the permissions/sharedWithCoachNames maps to removals only: `&& request.resource.data.permissions.keys().removeAll(resource.data.permissions.keys()).size() == 0`. Add a rules-unit test for the swap case [A,B] -> [C]; firebase/rules-tests currently covers only recruiting.

### 4. [HIGH] Account deletion never removes shared_folders/** Storage objects — a deleted minor's video survives forever with permanent public download tokens

**Where:** `firebase/functions/src/index.ts:1334-1346 (step 13) and :1205-1224 (step 2)`  
**Confidence:** confirmed — every deletion path traced, no backstop exists  
**Effort:** 1 hour + a backfill script run

**What:** shared_folders/{folderID}/{fileName} and .../thumbnails/* are live prefixes holding a SEPARATE copy of every clip an athlete shared to a coach. Step 2 recursiveDeletes the video docs and folder doc with zero Storage calls; step 13's only Storage sweep covers athlete_videos/, athlete_photos/ and recruiting_headshots/. The client mirror (FirestoreManager+UserProfile.swift:628-643) is the same. dailyStorageCleanup can't reach them either — the docs were hard-deleted so they never match isDeleted. The normal folder-delete path DOES delete Storage (FirestoreManager+SharedFolders.swift:285-300), proving the omission is accidental.

**Exploit:** A parent deletes the family account to get their 12-year-old's videos off the internet; the app reports success and PrivacyPolicyView.swift:120 promises removal within 30 days. Every clip ever shared to a coach still exists in GCS, permanently, with a non-expiring Firebase download token minted at upload — and once the Firestore docs are gone there is no query left that can even locate the surviving objects. This is 100% of affected accounts, not an edge case.

**Fix:** In cleanupUserDataOnDelete step 2, before `recursiveDelete(folderDoc.ref)`, add `await step('storage shared folder', () => bucket.deleteFiles({ prefix: `shared_folders/${folderDoc.id}/` }))`. Add the same to onSharedFolderDeleted (index.ts:414) as a backstop for every other delete route. Run a one-shot Admin-SDK reconcile listing the shared_folders/ prefix against live sharedFolders doc IDs to clean up what's already orphaned.

### 5. [MEDIUM] Shared-folder media is finalized with getDownloadURL(), attaching a permanent unauthenticated bearer token that revocation cannot touch

**Where:** `PlayerPath/VideoCloudManager+SharedFolders.swift:51 and :117, persisted at PlayerPath/FirestoreManager+VideoMetadata.swift:136 and :146`  
**Confidence:** confirmed — same defect reported independently by three surfaces  
**Effort:** half day including the backfill

**What:** Every shared-folder video and thumbnail upload calls downloadURL(), which permanently attaches firebaseStorageDownloadTokens to the object and returns a URL Firebase serves with no auth and without evaluating storage.rules. That string is written to videos/{id}.firebaseStorageURL / .thumbnailURL and read by every folder coach. Nothing in the client or in firebase/functions/src ever rotates the token — removal only arrayRemoves the coach and writes a revocation doc. So the whole signed-URL architecture (SecureURLManager -> getSignedVideoURL, 24h expiry + membership + tier re-check) is bypassable forever by anyone who captured the stored URL while authorized. Thumbnails additionally carry `public, max-age=31536000`. The recruiting feature already does this correctly (stores paths, never URLs).

**Exploit:** An instructor with legitimate access to a 13-year-old's folder reads the video docs (their own app caches them) and saves the firebaseStorageURL strings. The family removes them; the app shows them gone and Firestore denies every read. They still open those URLs signed out, in any browser, forever, and can paste them into a message or a forum where the recipient needs no PlayerPath account. Thumbnails are worse — the client fetches those token URLs automatically in normal use, so images of the minor land in ordinary caches without any deliberate act.

**Fix:** Delete the downloadURL() calls at VideoCloudManager+SharedFolders.swift:51 and :117 (and getSecureDownloadURL at :157, which has the same problem); store the deterministic path `shared_folders/{folderID}/{fileName}` in the video doc and route every reader through the existing getSignedVideoURL/getSignedThumbnailURL CFs. Backfill: an Admin-SDK job that setMetadata's firebaseStorageDownloadTokens to a new value on every object under shared_folders/ (which revokes all previously issued token URLs) and blanks the URL fields on existing docs. Also drop the thumbnail cacheControl from a year to something short.

### 6. [MEDIUM] Deleting a child's athlete profile leaves their shared coach folder, video docs and Storage files fully live and accessible

**Where:** `PlayerPath/Views/Profile/AthleteManagementView.swift:14-138 (performDeleteAthlete)`  
**Confidence:** confirmed — every deletion path and server trigger checked  
**Effort:** half day

**What:** performDeleteAthlete tombstones games, practices, seasons, tournaments, holes, reels, the athlete doc, coach records and the recruiting profile — but never touches the top-level sharedFolders doc carrying that athlete's athleteUUID, never deletes the videos/* docs pointing at it, never writes a coach_access_revocations doc, and never deletes shared_folders/{fid}/** in Storage. canAccessFolder() has no dependency on the athlete profile existing, so nothing degrades. No Firestore trigger covers it either (enforceAthleteLimit is onCreate-only; claimAthleteOwnership returns early on delete). Account deletion DOES cascade folders, which shows the per-athlete omission is accidental.

**Exploit:** A parent with two children on one account decides the private instructor for Child A is someone they no longer trust, and deletes Child A's profile in Settings. Locally everything disappears and the confirm text says 'delete the athlete and related data'. The coach's app is completely unaffected — the folder still lists them, every video doc is still readable, the Storage objects are untouched. They keep watching, downloading and re-sharing the deleted minor's film indefinitely, and the parent now has NO in-app entry point to revoke, because both AthleteFoldersListView and CoachesView require a live Athlete row.

**Fix:** In performDeleteAthlete, before the local hard-delete, query `sharedFolders where athleteUUID == athleteID` and in the async block: write coach_access_revocations/<folderID>_<coachID> for every coach on each folder, then call the existing FirestoreManager.deleteSharedFolder(folderID:) which already handles subcollections, Storage object and thumbnail. Add the affected coach names to the delete confirmation alert. Same gap exists at the single-clip level — VideoClip.delete (Models/VideoClip.swift:277) never reads sharedCoachVideoIDs, so deleting one clip leaves its coach copy live too.

### 7. [MEDIUM] Under-13 contact suppression fails open when gradYear is unset — a child's phone and email publish as live tel:/mailto: links

**Where:** `PlayerPath/Models/RecruitingInfo.swift:359 and firebase/functions/src/recruitingProfile.ts:460`  
**Confidence:** confirmed on both client and server  
**Effort:** 2 hours across client + CF, plus a CF deploy

**What:** The entire COPPA control for the public page keys on an OPTIONAL, self-reported grad year, and both enforcement points treat missing as 'not under 13': the client `guard let gradYear else { return false }` and the server `typeof gradYear === 'number' && ...`. Publish omits the key when nil (RecruitingProfileService.swift:657), the picker offers '—', and publish has no minimum bar. There is no DOB anywhere in the app, so there is no fallback signal. Worse, the readiness checklist actively prompts for contact info in exactly this state — RecruitingReadinessSection.swift:67 gates the 'Email or phone' row on `!info.gradYearImpliesUnder13`, which is true when the value is nil.

**Exploit:** A parent of a 10-year-old fills in the profile, leaves Grad Year on '—' because it's optional, and follows the app's own checklist prompt to add a phone number. Both include toggles are enabled (they only disable when under13 is true), consent succeeds, and the page renders `<a href="tel:+1555...">` next to the child's face, city, school and film on an anonymous URL. No gate fires on either side, and the editor footer that would have told them about the protection stays silent.

**Fix:** Three coordinated changes: (1) in RecruitingInfo.swift, return [] from visibleContactItems and false from hasPublicReplyChannel when `gradYear == nil`; (2) in recruitingProfile.ts change contactSection to `if (typeof gradYear !== 'number' || impliesUnder13(gradYear)) return '';` so the server fails closed for the already-published corpus; (3) in RecruitingReadinessSection.swift, drop the contact row when `info.gradYear == nil` and add a row prompting for grad year instead. Longer term, require grad year before the first publish — it's the only age signal the product has.

### 8. [MEDIUM] videos update rule lets an uploader ADD sharedFolderID to a personal clip, injecting docs into any folder whose ID they know

**Where:** `firestore.rules:512-513`  
**Confidence:** confirmed — I re-read firestore.rules:509-513 directly  
**Effort:** 15 min

**What:** Both sharedFolderID guards are predicated on `'sharedFolderID' in resource.data` — the field being on the EXISTING doc. A personal video is created without it (line 496 explicitly allows that), so both clauses short-circuit true and the uploader can write an arbitrary sharedFolderID by update. The create rule carefully requires hasPermission(folderID,'upload') && canAccessFolder(folderID); the update rule never re-applies that for the no-folder-to-folder transition. The shipped client never performs this write, so it is pure unused capability.

**Exploit:** A coach removed from an athlete's folder still knows the folderID. canAccessFolder() now blocks their reads, but this update path still lets them push new attacker-authored clips and text into the (often minor) athlete's folder feed — fetchVideos(forFolder:) is a bare whereField query with no uploader-membership filter, so the row renders for the athlete and every other coach. This is also the write primitive that feeds finding 2's destructive cron delete.

**Fix:** Replace firestore.rules:512-513 with a single unconditional guard on the incoming doc: `&& request.resource.data.get('sharedFolderID', null) == resource.data.get('sharedFolderID', null)`. This preserves every shipped client write path since sharedFolderID is only ever set at create.

### 9. [MEDIUM] Server-side storage quota has three independent bypasses; any free account can park unbounded bytes at your expense

**Where:** `firebase/functions/src/index.ts:3122 (shared_folders exempt), :3133 (recruiting/thumbnails exempt), :3157 (client-written fileSize)`  
**Confidence:** confirmed — three independent gaps, each traced to the enforcing code  
**Effort:** half day

**What:** enforceStorageQuota is the only server-side enforcement of the 2GB/25GB/100GB caps. (a) It returns immediately for anything not under athlete_videos/ or athlete_photos/, so shared_folders/ bytes are never counted or deleted — and firestore.rules lets any authenticated user create unlimited folder docs while storage.rules allows 500MB objects with no count cap. (b) Line 3133 blanket-exempts athlete_videos/{uid}/recruiting/ and /thumbnails/, which the client fully controls via the recursive {allPaths=**} wildcard. (c) The video half of the total is summed from the client-written `videos.fileSize` field, which the uploader-update rule never freezes. Nothing sweeps orphan objects with no Firestore doc.

**Exploit:** A free-tier user takes their own ID token and PUTs 500MB video/mp4 objects to shared_folders/<their folder>/ or athlete_videos/<uid>/recruiting/ in a loop — nothing counts them, nothing caps the count, nothing deletes them. Or, simpler: PATCH `fileSize: 0` onto their own videos docs and the quota computes ~0 forever, which also resets the client gate on every device. Terabytes overnight, billed to you, permanently.

**Fix:** In index.ts enforceStorageQuota: extend the handler to shared_folders/ (resolve ownerAthleteID from the folder doc and charge the owner), remove the blanket recruiting/thumbnails early-return in favor of counting-but-not-deleting derived files, and stop trusting videos.fileSize — write the trusted `object.size` back onto the doc from this trigger and sum that. Add the same pre-upload cloudStorageUsedBytes check to SharedFolderManager.uploadVideo (SharedFolderManager.swift:563) that the personal path already has. Add `.runWith({ timeoutSeconds: 300, memory: '512MB' })` while you're in there.

### 10. [MEDIUM] coachTierSource is client-writable, making a refunded or cancelled coach subscription permanent

**Where:** `firestore.rules:257-259 (deny list) and :227-230 (create-forbid list)`  
**Confidence:** confirmed  
**Effort:** 15 min

**What:** The users update rule freezes role, subscriptionTier, coachSubscriptionTier, coachAthleteCount, coachAthleteLimit, athleteTierSource, downgradeUnresolved and coachDowngradeGraceStartedAt — but coachTierSource appears in NEITHER list and is not named anywhere in firestore.rules. That single field is the sole discriminator the server uses to decide whether a coach tier is a revocable StoreKit purchase or a permanent admin comp. Both downgrade paths gate on it: index.ts:3623 (the ASSN refund/expiry handler) and index.ts:3431 (syncSubscriptionTier's write-down). The athlete axis is correctly protected, which shows this is an oversight.

**Exploit:** A coach buys coach.proinstructor.monthly, then PATCHes their own user doc with `{coachTierSource: 'manual'}` (every clause of the update rule passes), keeps the app closed, and requests a refund from Apple. The genuine REFUND notification arrives, the handler sees source != 'storekit', logs 'admin comp' and writes nothing. Every future sync also refuses to write down. They keep 30 paid athlete seats permanently for $0. Note: syncSubscriptionTier repairs the field while the subscription is still active (index.ts:3429), so this needs the app closed until the terminal event lands — a timing window, not a blocker, and the post-event state is absorbing.

**Fix:** Add 'coachTierSource' to the affectedKeys().hasAny([...]) deny list at firestore.rules:258 and to the create-forbid list at :227. Add "coachTierSource" to cfManagedKeys in PlayerPath/FirestoreManager+UserProfile.swift:74. Defense in depth: in index.ts treat any value other than a recognized enum as 'storekit' (fail closed) rather than as a comp.

### 11. [MEDIUM] Coach seat count dedups on personGroupID, a field the athlete's client writes with no validation

**Where:** `firebase/functions/src/index.ts:3801 (computeCoachConnectionKeys)`  
**Confidence:** plausible — code quoted accurately from the seat-counting helper; not independently exploit-tested  
**Effort:** 2 hours including verifying the dual-sport Person Card case still dedups correctly

**What:** The authoritative seat count keys each connection on `personGroupID || athleteUUID`, so all folders/invitations sharing a personGroupID collapse to ONE key regardless of which ACCOUNT owns them — the account axis is discarded once a group ID is present. That key is client-authored: firestore.rules:280 opens users/{uid}/athletes to the owner with zero field validation, and the sharedFolders create rule doesn't constrain personGroupID either. resolveAthletePersonGroupID re-reads the athlete doc but that doc is exactly the unvalidated one, and it falls back to the client value. The athlete-tier path guards this class (enforceAthleteLimit caps a group at 3 and blocks duplicate sports) but only within one user's own subcollection — a group ID spanning accounts is never observed.

**Exploit:** A coach on the free tier wants 30 students without paying $19.99/mo. Each student sets `personGroupID` to one shared constant on their own athlete doc (permitted by rules), then invites the coach normally. Every accept stamps that constant onto the created folder, computeCoachConnectionKeys returns a set of size 1, coachAthleteCount stays 1, and auditCoachDowngrades recomputes the same 1. 30 minors served on a free seat indefinitely. Secondary damage: personMatchesKeys also matches on personGroupID, so one athlete's revocation can delete another athlete's accepted invitation.

**Fix:** In computeCoachConnectionKeys, key on `ownerAthleteID + ':' + (personGroupID || athleteUUID)` so a group can never span accounts. Additionally, in enforceAthleteLimit or claimAthleteOwnership, reject a personGroupID already claimed by a different uid.

### 12. [MEDIUM] Any authenticated user can send mail from noreply@playerpath.net to an arbitrary address with attacker-chosen text, plus a spoofed in-app push

**Where:** `firebase/functions/src/index.ts:1439-1447 (invitations) and :2037-2043 (revocations)`  
**Confidence:** confirmed  
**Effort:** half day

**What:** sendInvitationEmail fires on any invitations create and takes the recipient from client-written coachEmail and the subject text from client-written athleteName. firestore.rules:977-1004 requires only isAuthenticated(), athleteID == auth.uid, pending status, an expiry window and a lowercase email — no email_verified, no format check, no length or content bound. The sibling onInvitationCreated resolves that arbitrary address to a real UID and writes an invitation_received notification + FCM push with the attacker's text. sendCoachAccessRevokedEmail is the same shape with folderName landing in the Subject line, and only resolves coachEmail server-side when the client OMITS it. Only limit is 10/hour per uid on free unlimited accounts.

**Exploit:** Attacker signs up with a throwaway unverified email and writes invitations docs with `coachEmail: parent@victim.com` and `athleteName: 'PlayerPath Account Security'`. The victim gets DKIM/SPF-aligned mail from your real domain with the attacker's string in the subject, and — if they have an account — a push on their lock screen. Ten per hour per account, unlimited accounts. HTML bodies ARE escaped so this is plain-text phishing inside your branding, not markup injection. The realistic damage is domain-reputation abuse getting your Resend account suspended (killing every real invitation email) plus a harassment channel aimed at families.

**Fix:** In firestore.rules add `request.auth.token.email_verified == true` to the athlete_to_coach create branch, a `keys().hasOnly([...])` allowlist, `size()` caps on athleteName/folderName/message, and an address regex on coachEmail. In index.ts, render athleteName/folderName from server state (the sender's users/{uid}.displayName and the real sharedFolders doc) rather than the invitation fields, always resolve revocation coachEmail from users/{coachID}.email (ignore the client value), and add a per-recipient cooldown keyed on sha256(email) alongside the per-sender one.

### 13. [MEDIUM] Analytics collects identity-linked children's telemetry by default, including verbatim user free text

**Where:** `PlayerPath/Services/AnalyticsService.swift:28, :53, :217, :355, :443`  
**Confidence:** confirmed  
**Effort:** 2 hours

**What:** Line 28 unconditionally calls `Analytics.setAnalyticsCollectionEnabled(true)` in the singleton initializer — overriding IS_ANALYTICS_ENABLED=false in the plist, and it persists. UserPreferences defaults enableAnalytics to true, so this is opt-OUT. Collection is identity-linked via setUserID(firebaseAuthUid) on both Analytics and Crashlytics. Payloads include athlete_id, video_id, `opponent` (a user-typed team name), `feedback_text` verbatim up to 100 chars from the win-back sheet, and `error_description` (raw Firebase error strings that embed Storage object paths). Google's Analytics ToS prohibits uploading PII as event parameters. The project links FirebaseAnalytics rather than FirebaseAnalyticsWithoutAdIdSupport, and nothing sets child-directed or ad-personalization signals — a hard blocker if you ever want a Kids Category listing.

**Exploit:** Not attacker-driven. A parent whose subscription lapses types 'my daughter Emma is done for the season, email me at jane@gmail.com' into the win-back box; that string uploads to Google Analytics joined to the app-instance ID, IDFV, coarse geo and the Auth UID, with no user-facing deletion path. Separately, an 11-year-old on the family device generates telemetry from first launch with no consent surface — a straightforward GDPR Art. 6/Art. 8 and AADC 'high privacy by default' complaint in the EU/UK.

**Fix:** In AnalyticsService.swift: delete the free-text parameter at line 357 (keep the existing `has_free_text: Bool`, which is the actual product metric); drop `opponent` at line 217 in favor of a boolean; drop `error_description` at line 443 and keep error_domain/error_code/context (keep Crashlytics.record, it's useful); make line 28 read the stored preference rather than forcing true. Stop building AppError cases from raw nsError.localizedDescription (AppError.swift:266, :278). Switch the SPM product to FirebaseAnalyticsWithoutAdIdSupport.

### 14. [LOW] A signed video URL — a bearer capability to a minor's clip — is logged with privacy: .public

**Where:** `PlayerPath/SecureURLManager.swift:83-84`  
**Confidence:** confirmed  
**Effort:** 5 min

**What:** callCloudFunction, the single helper behind getSignedVideoURL and getSignedThumbnailURL, stringifies the ENTIRE CF response body and logs it with an explicit `privacy: .public` marker, defeating OSLog redaction. On the success path that body contains the full GCS signed URL, valid 24h for videos and 168h for thumbnails. Every other sensitive value in this same file is correctly marked .private, so it's an outlier. It ships in Release (no #if DEBUG). Mitigating: it's log.debug, which is memory-only and absent from a default sysdiagnose.

**Exploit:** Someone with the device plugged into a Mac — a repair shop, an ex-partner, a club-managed device with a logging profile — opens Console.app with debug messages on. Every signed URL scrolls past in cleartext while the athlete browses. They copy one, paste it into any browser on any machine, and download the minor's video; it keeps working for up to 24h even after the coach's access is revoked.

**Fix:** Reduce line 84 to `log.debug("[\(functionName)] HTTP \(httpResponse.statusCode)")`. If you need the body for debugging, wrap it in #if DEBUG and remove the `, privacy: .public`.

### 15. [LOW] Sign-out and account deletion leave minors' media on the device in four stores the wipe never touches

**Where:** `PlayerPath/SyncCoordinator.swift:413-449 (clearLocalData) and PlayerPath/ComprehensiveAuthManager+Profile.swift:466`  
**Confidence:** confirmed  
**Effort:** 2 hours

**What:** clearLocalData is the only on-disk wipe, used by BOTH sign-out and account deletion, and it removes exactly Documents/Clips and Documents/Photos plus 14 SwiftData model types. Untouched: Documents/Thumbnails (now full 1920x1080 JPEGs of the child, so recognizable images not previews), Documents/ProfileImages (headshots), Caches/coach_videos (full-resolution clips of OTHER families' minors on a coach device — the whole-cache clearCache() at CoachVideoCacheService.swift:81 exists but has zero callers), Caches/shared_thumbnails, and five live schema types (HoleScore, Shot, GolfTournament, HighlightReel, UserPreferences — golf scores, shot rows, and tournament names/dates/course locations, which live in Application Support and DO flow into device backups). Firestore.clearPersistence() is never called anywhere. Separately, deleteAccount skips 12 teardown calls that sign-out performs, most visibly cancelAllPendingNotifications — so scheduled reminders naming the deleted account's opponents keep firing on the lock screen days later.

**Exploit:** A parent uses Delete My Account to honor an erasure request for their child. The app says 'Account deletion successful'. 1080p stills of the child, their headshot, the full golf tournament schedule with course locations, and the departing user's Firestore SQLite cache (athlete names, invitation emails, coach notes) all remain and flow into the next backup. Three days later the device shows 'Your game vs Riverside Lions starts in 30 minutes'. Not reachable through the app UI — this needs backup extraction or filesystem access — but the erasure the app reports is incomplete on the device where it was requested.

**Fix:** Extend the SyncCoordinator.swift:437 loop to ["Clips", "Photos", "Thumbnails", "ProfileImages"]; add CoachVideoCacheService.shared.clearCache() and removal of Caches/shared_thumbnails and the stitched-reel dir into clearLocalData so every caller gets them; add `try context.delete(model:)` for Shot, HoleScore, GolfTournament, HighlightReel, UserPreferences (Shot before HoleScore, HoleScore before Game) and ideally derive the list from SchemaV37.models. Factor clearLocalSignedInState()'s teardown into a shared tearDownLocalSession() and call it from deleteAccount() instead of the hand-rolled subset.

### 16. [LOW] Coach 'Add Comments' permission is enforced client-side only

**Where:** `firestore.rules:628-634`  
**Confidence:** plausible — rules quoted accurately, not independently exploit-tested  
**Effort:** 15 min

**What:** The videos/{id}/comments create rule checks only canAccessFolder(). It never calls hasPermission(folderID, 'comment'), even though that helper exists and every sibling capability uses it — video create requires 'upload' (line 498), video delete requires 'delete' (612), annotation create requires 'comment' (668). Comments are the odd one out. canComment is a real athlete-controlled setting rendered as a toggle in InviteCoachSheet.swift:127 and displayed back as a badge in AthleteFoldersListView.swift:771.

**Exploit:** A parent connects an outside instructor to their 13-year-old's folder with 'Add Comments' turned OFF, intending view-only. The coach POSTs directly to videos/{clipID}/comments with their own uid as authorId. It's accepted, delivered to the child through the comment thread and the onNewComment push, and the parent's UI still shows the Comment badge as disabled. The same coach IS correctly blocked from telestration, which makes the inconsistency invisible.

**Fix:** Add `&& hasPermission(getVideoData(videoID).sharedFolderID, "comment")` to the shared-folder branch of the comments create rule (firestore.rules:631-633), mirroring the annotations rule at line 668. Keep the uploader branch unconditional.

### 17. [LOW] Signed URLs can be minted for 30 days and a revoked coach can still obtain them

**Where:** `firebase/functions/src/index.ts:43 (MAX_EXPIRATION_HOURS = 720) and :2887, :2943, :3000`  
**Confidence:** confirmed  
**Effort:** 30 min

**What:** getSignedVideoURL, getSignedThumbnailURL and getBatchSignedVideoURLs take expirationHours straight from the caller and clamp only at 720. The shipped client asks for 24/168, but these are plain HTTPS endpoints the app calls with a raw Bearer token, so any value is reachable. None of the three consults coach_access_revocations — they authorize on bare sharedWithCoachIDs membership. An issued signed URL cannot be revoked.

**Exploit:** A coach anticipating removal (a dispute, or a downgrade that will shed the athlete) scripts getBatchSignedVideoURLs with expirationHours: 720 over the folder's file list, 50 per call. The family removes them that afternoon; they keep streaming every video of the minor for 30 days from any device. This is insider retention rather than a bypass — they could download the files today — but the 30-day window and the missing revocation check are both free to fix.

**Fix:** Lower MAX_EXPIRATION_HOURS to 24 (recruitingProfile.ts already uses 3) and ignore the client-supplied expirationHours entirely for these three endpoints rather than clamping it. Add an `exists(coach_access_revocations/<folderID>_<uid>)` check before signing.

### 18. [LOW] A revoked coach can delete their own coach_access_revocations record

**Where:** `firestore.rules:851-854`  
**Confidence:** confirmed  
**Effort:** 10 min

**What:** `allow delete: if isAuthenticated() && (resource.data.athleteID == request.auth.uid || resource.data.coachID == request.auth.uid)` — the subject of a deny-list entry controls the entry. isCoachRevokedFromFolder() is a bare exists() on that doc, so deleting it clears the backstop canAccessFolder() consults. No CF recreates it.

**Exploit:** Not standalone-exploitable, because canAccessFolder also requires array membership and the athlete's removal batch does both atomically. But it is the second half of a working chain with finding 3 (or finding 1): once a colluding/throwaway coach account re-inserts the revoked UID into sharedWithCoachIDs, that coach deletes their own revocation doc and full access is restored with the family's explicit revocation permanently erased and no server record it happened.

**Fix:** Restrict to the athlete side: `allow delete: if isAuthenticated() && resource.data.athleteID == request.auth.uid;` — or set `allow delete: if false` and let the CFs (index.ts:2446/4224) be the sole deleter, which is where every legitimate re-accept already handles it.

### 19. [LOW] Sandbox-signed StoreKit transactions grant production entitlements

**Where:** `firebase/functions/src/index.ts:3357-3372`  
**Confidence:** confirmed  
**Effort:** 30 min

**What:** syncSubscriptionTier accepts an AppTransaction verified under EITHER the production or sandbox verifier and hands the same verifier to resolveTransactionTiers. Sandbox purchases are free and cryptographically genuine, so a sandbox transaction for pro.annual verifies cleanly and writes to the same production Firestore. tx.environment and appTransaction.receiptType are never inspected. Your own comment at index.ts:3341-3351 names this exact hazard and closes it only on the no-receipt branch.

**Exploit:** Someone on your TestFlight (or a dev-provisioned build — the AppTransaction is signed over bundleId AND appAppleId, so a self-signed build cannot produce one) makes free sandbox 'purchases' of pro.annual and coach.proinstructor.monthly and gets a real production Pro + 30-seat coach tier for $0, renewable indefinitely. Gated behind TestFlight membership today; escalate this if you ever open a public TestFlight link.

**Fix:** In index.ts, only fall back to verifiers.sandbox when `process.env.FUNCTIONS_EMULATOR` is set or the uid is in a testers allow-list, mirroring the guard already at line 3345. At minimum persist the resolved environment on the user doc and have getCoachAthleteLimit/SubscriptionGateService treat sandbox-sourced tiers as non-entitling.

### 20. [LOW] coachSessions update does not freeze coachID — a session doc can be reassigned to another coach

**Where:** `firestore.rules:951-952`  
**Confidence:** confirmed  
**Effort:** 10 min

**What:** `allow update: if isAuthenticated() && resource.data.coachID == request.auth.uid` checks only the PRE-image, so the post-image coachID is unconstrained. Every other ownership-keyed collection freezes its owner field (videos:511, photos:424, drillCards:908, comments:641). CoachSessionManager selects purely on `whereField("coachID", isEqualTo:)` with a live listener, so a reassigned doc lands on the victim's dashboard.

**Exploit:** Coach A creates a session, then updates it setting coachID to a victim coach's UID with attacker-chosen title/athleteNames/notes and status 'live'. The victim's dashboard shows an attacker-authored active session attributed to their own account. No data flows to the attacker (they lose read access the moment coachID flips), so this is content injection, not disclosure.

**Fix:** Add `&& request.resource.data.coachID == resource.data.coachID` to firestore.rules:952.

---

## Minors / privacy compliance gaps

### [P1 — start the legal conversation now; the engineering follows the classification decision] COPPA (16 CFR 312.5)

**Gap:** No verifiable parental consent for collecting and publicly disclosing children's photographs and video. The only age control in signup is a self-attestation checkbox (ComprehensiveSignInView.swift:231, gating canSubmitForm at :424), and no date of birth is collected anywhere in the app. COPPA treats a child's photograph, video containing their image, email and phone as personal information, and a checkbox is explicitly insufficient for public disclosure of it.

**Risk:** You cannot produce a consent record for the highest-consequence category of collection. Note two things in your favor that the audit initially missed: a consent artifact DOES exist for publishing (publishConsentAt, RecruitingInfo.swift:77, written at RecruitingPublishView.swift:714), and the signup checkbox is a hard gate, not decorative. The exposure is the quality of the consent, not its total absence.

**Fix:** Decide the classification first with counsel: general-audience-parent-operated vs child-directed. If the former, make the account holder a parent by design — a neutral age screen collecting birth year at signup (not a checkbox), hard-block under-18 self-signup, and store attestation + timestamp on the user doc. If under-13 athletes may exist, add a real VPC flow (parent email + charge authorization or ID via a safe-harbor vendor like PRIVO/kidSAFE) before any publish. Either way, extend the existing under-13 branch to hard-block publish rather than only withholding the contact card.

### [P0 — 2 hours of work, deploy the CF the same day] COPPA / AADC

**Gap:** The under-13 gate fails open when grad year is unset, on both the client (RecruitingInfo.swift:359) and the server (recruitingProfile.ts:460). Grad year is optional, omitted from the published doc when nil, and the readiness checklist actively prompts for contact info in exactly that state.

**Risk:** A 10-year-old's live tel: and mailto: links can publish on an anonymous page next to their face, city and school with no gate firing anywhere. This is the single biggest gap in the minors story and it is purely technical — no legal ambiguity.

**Fix:** Return [] from visibleContactItems when gradYear == nil; change contactSection in recruitingProfile.ts to `if (typeof gradYear !== 'number' || impliesUnder13(gradYear)) return '';` so the already-published corpus is covered; drop the 'Email or phone' readiness row when gradYear is nil. Then require grad year before the first publish.

### [P2 — copy change, but do it in the same release as the consent work so the story is consistent] COPPA / GDPR Art. 8 / FTC §5

**Gap:** Three mutually contradictory age standards for the same account: signup says 18+ or parent/guardian (ComprehensiveSignInView.swift:231), Terms say 13+ or parental consent (TermsOfServiceView.swift:51), publish gate says 'parent or guardian, or I'm 13 or older' (RecruitingPublishView.swift:318).

**Risk:** Undermines any argument that you have a coherent age policy. The publish branch is the substantive one: a self-identified 13-year-old can authorize public disclosure of their own likeness, which is invalid in DE/NL/IE/FR where the digital-consent age is 15-16. A 13-17-year-old also cannot form a binding subscription contract in most US states, yet the same account buys StoreKit subscriptions.

**Fix:** Pick one standard — for a youth-athlete product the defensible one is 18+ account holder who is the parent/guardian — and make all three strings match. Remove the 'or I'm 13 or older' branch from RecruitingPublishView.swift:318 and the 13+ option from TermsOfServiceView.swift:51.

### [P2] GDPR Art. 6 + ePrivacy / UK & CA AADC / App Store 5.1.4

**Gap:** Firebase Analytics and Crashlytics collect identity-linked telemetry from first launch with no consent surface, opt-OUT by default, including athlete_id, video_id, user-typed opponent names and verbatim feedback text. Line 28 of AnalyticsService.swift explicitly overrides IS_ANALYTICS_ENABLED=false in the plist, and no child-directed or ad-personalization signal is set anywhere.

**Risk:** In the EU/UK this is children's telemetry collected with no lawful basis and weakest-defensible defaults, which is a straightforward ICO/DPA complaint. It also permanently blocks a Kids Category listing, and passing verbatim free text and athlete identifiers as event parameters violates Google's own Analytics ToS (remedy: deletion of your property's data).

**Fix:** Stop sending free text and identifiers (delete AnalyticsService.swift:357's feedback_text, :217's opponent, :443's error_description); make line 28 read the stored preference rather than forcing true; switch the SPM product to FirebaseAnalyticsWithoutAdIdSupport. If you ever target the EU seriously, add a first-run consent choice rather than an opt-out buried in settings.

### [P2] FTC §5 deception / GDPR Art. 13-14 & 28

**Gap:** The privacy policy is materially incomplete: it never mentions the public recruiting profile (the app's most consequential data flow) or its view analytics, omits Resend as an email processor and Crashlytics as an SDK, and a stale privacy-policy.txt at the repo root is three months behind with a different contact address (playerpath@proton.me vs support@playerpath.net).

**Risk:** An inaccurate privacy policy is an independent FTC violation regardless of COPPA. The divergent contact address means a parent's rights request can land in an unmonitored inbox and blow past the GDPR 1-month / CCPA 45-day deadlines. Note the audit's claim that the children's-privacy sentence describes a nonexistent control was wrong — you do implement parental attestation and under-13 suppression — so this is a completeness gap, not a false statement.

**Fix:** Add a 'Public Recruiting Profile' section naming every field that can become public, that the page is link-accessible and noindex'd, that view counts are recorded, and how to take it down. Add Resend and Crashlytics to Third-Party Services. Delete privacy-policy.txt or regenerate it from the same source as PrivacyPolicyView.swift, and verify the App Store Connect URL points at the current version.

### [P3] App Store 5.1.1 / privacy nutrition label accuracy

**Gap:** PrivacyInfo.xcprivacy omits phone number (unambiguously collected and published via RecruitingInfo.contactPhone), and GPA/high school/city-state have no declaration either.

**Risk:** A reviewer or researcher opens a live recruiting page showing a phone number and compares it to a label declaring none. For a product whose subjects are minors, an inaccurate contact-info label is the least defensible variety. Lower than it sounds because the manifest feeds Xcode's privacy report while the store label is entered by hand in ASC — but both should match reality.

**Fix:** Add NSPrivacyCollectedDataTypePhoneNumber (Linked, AppFunctionality) and NSPrivacyCollectedDataTypeOtherDataTypes for GPA/school to PrivacyInfo.xcprivacy, and re-sync the App Store Connect privacy answers.

### [P3] COPPA §312.6 / GDPR Arts. 15 & 20

**Gap:** Parental review and portability are incomplete. 'Export My Data' claims 'a complete copy' (DataExportView.swift:41) but produces metadata-only JSON that omits all media by design, the entire golf domain (no GolfTournament/HoleScore/Shot), highlight reels, the recruiting profile blob, clip notes/tags, and every coach-authored comment/annotation/drill card about the child. AccountDeletionView recommends this export as step 1 before irreversible deletion. There is also no documented process for a parent who is NOT the account holder to review or demand deletion.

**Risk:** A parent follows your own prompt — export, then delete — and loses everything the export skipped. A rights request from a non-account-holding parent (separated co-parent, or the 13-year-old who signed up themselves) has no fulfilment path at all.

**Fix:** Add the missing metadata domains to gatherAllData (golf, reels, recruitingProfileJSON, clip notes/tags, received coach feedback) — that's the cheap win. Add a bulk 'Save all videos to Photos' action, and change the line 41 copy to state precisely what is and isn't included. Publish a written parental-rights procedure in the privacy policy: the email path, what identity evidence you require, your response SLA, and that a parent may refuse further collection.

### [P3 — roadmap, not a defect] COPPA §312.10 / GDPR storage limitation

**Gap:** No retention limit on a child's media. dailyStorageCleanup is the only scheduled purge and it only ages out already-soft-deleted data. There is no dormant-account sweep, no per-clip TTL, and no graduation age-out for a recruiting profile. The policy says 'as long as your account is active'.

**Risk:** A family stops using the app in 2026 without deleting; in 2034 the now-adult subject's childhood video, name, school and possibly a live public page are all still there. Standard posture for an active account, but weak for a service whose subjects are children.

**Fix:** Add a scheduled retention CF: flag accounts with no activity for N months, email a one-tap keep-alive, purge after a grace period via the same path as cleanupUserDataOnDelete. Separately, auto-unpublish recruiting profiles some interval past the athlete's gradYear — the closedAt/410 design is already sketched in your recruiting docs.

---

## Confirmed working — do not re-solve

- StoreKit receipt verification is done properly — appStoreServerNotifications uses Apple's official SignedDataVerifier with real root CAs, OCSP on, bundleId RZR.DT3 and appAppleId pinned, 401 on failure. A forged webhook cannot grant or revoke a tier. Don't re-solve this.

- Tier fields are correctly frozen client-side: role, subscriptionTier, coachSubscriptionTier, coachAthleteLimit, athleteTierSource, downgradeUnresolved are all immutable in firestore.rules, and users-create forces free/coach_free. Academy tier has no client write path at all. The one exception is coachTierSource (see ranked findings).

- The sharedFolders OWNER update branch (firestore.rules:462-465) genuinely is removals-only — the subset check there is correct. The bug is in the OR'd coach-leaving branch, not this one.

- The public recruiting page is well hardened for an anonymous endpoint: ownedPath() re-derives every client-authored Storage path against the immutable doc userId before Admin-SDK signing (so it is not a bucket-wide oracle), esc() at every HTML interpolation, real CSP with default-src 'none', X-Robots-Tag noindex/nofollow/noimageindex plus a meta tag, Referrer-Policy no-referrer, GET/HEAD only, identical 404 copy for missing vs unpublished (no existence oracle), and ~50-bit CSPRNG share tokens with atomic create-only claim.

- Under-13 contact/GPA suppression is enforced server-side at render time (recruitingProfile.ts contactSection), not just in the client — so an old app build or an already-published profile is still covered. That is the right architecture; it just needs the nil-gradYear case closed.

- Storage path traversal is closed everywhere it matters: sanitizeFileName on the signed-URL callables, owner-prefix validation on pendingDeletions, per-UID prefix scoping in storage.rules with a `if false` catch-all.

- No committed secrets anywhere in tracked files or git history — firebase/functions/.env with RESEND_KEY was never committed. GoogleService-Info.plist is expected and is not a credential.

- Apple Sign In is correctly nonced (SecRandomCopyBytes, SHA256, 5-minute expiry, cleared on every exit path) — replay is closed. Email verification is enforced server-side in both the rules and both accept CFs, so the 'sign up as victim@x.com and claim their invite' takeover does not work.

- All 35 print() sites compile out of Release via the DebugPrint.swift shadow, and OSLog PII is consistently marked privacy: .private. Crashlytics carries no custom keys or breadcrumbs. One outlier (SecureURLManager.swift:84) is in the ranked findings.

- Account deletion is thorough on the Firestore side — recursiveDelete over the whole user tree including golf holes/shots, plus collectionGroup sweeps for coach comments/annotations/drill cards, recruitingProfiles, recruitingTokens and athleteOwners. The public page really does go down. The gap is Storage objects under shared_folders/, not the documents.

- coach_access_revocations create is properly hardened — the deterministic doc ID is pinned to the body, and the coach branch pins athleteID to the folder's real owner, so you cannot forge a deny record against someone else's folder.

- No advertising SDK, no IDFA/AdSupport access, no ATT prompt anywhere. NSPrivacyTracking=false is accurate.

---

## Raised and dismissed (with reasons)

- GoogleService-Info.plist being committed with an API_KEY — this is not a secret. It's a project identifier shipped inside every copy of your binary; access is gated by security rules and Auth tokens. The only follow-up is a console check that the key is restricted to bundle ID RZR.DT3 and the APIs you use. No code change.

- Storage rules validating only client-declared Content-Type — Storage rules cannot inspect bytes at all, so the suggested 'fix' isn't implementable in that layer, and the recruiting headshot rule offered as precedent doesn't validate bytes either. The real residual (free hosting, permanent tokens) is already captured in findings 5 and 9. Dropped to info.

- No NSFileProtection class on media directories — this is the iOS default (CompleteUntilFirstUserAuthentication) that essentially every media app ships with, and raising it to .complete would break your background upload and download pipeline. It's a genuine tradeoff, not a free fix, and the attack needs physical possession plus a current forensic exploit chain.

- Sign-in error messages distinguishing 'no account' from 'wrong password' — Firebase's Email Enumeration Protection is on by default for projects since Sept 2023 and collapses both into invalidCredential, so the branch may never fire. Even if it does, your signup path returns 'An account with this email already exists' anyway, which answers the same question. Worth collapsing the strings when you're nearby; not a finding.

- cleanupUserDataOnDelete timing out and leaving a public recruiting page live — refuted. loadPublishedProfile (recruitingProfile.ts:809) returns null when the owner's users/{uid} doc is missing, and step 1 of the purge deletes that doc first, so the page goes dark immediately. The real residual is orphaned Storage bytes (finding 4), not a live page. Still worth adding `.runWith({ timeoutSeconds: 540, memory: '512MB' })` as a one-liner.

- auditCoachDowngrades having no resume cursor — real design gap but entirely latent until you have roughly 100+ connected coaches, and active coaches' counts are re-trued on every accept/revoke anyway. Add a cursor when you're near that scale, not now.

- syncSubscriptionTier's unbounded transactionTokens array — junk strings fail fast in JWS decode before any X.509 work, so the per-element cost is a parse-and-throw, not crypto; and the batch-write concern isn't reachable because only genuinely Apple-signed transactions make it into the batch. A cheap `if (transactionTokens.length > 25) throw` is still worth adding.

- enforceStorageQuota's unbounded bucket listing DoS — reaching it requires an attacker to upload ~10^5-10^6 objects to poison their OWN trigger, billing you the whole way, to win free storage on one account. Fix it opportunistically with `{ autoPaginate: false, maxResults: 5000 }` while you're in that function for finding 9.

- ASSN webhook lacking ordering/supersession checks — real but not attacker-driven, and the client re-syncs on foreground so the window closes at the user's next app open. Log it as robustness.

- Recruiting page view-count spoofing via X-Forwarded-For — analytics integrity only, and the push is throttled to one per account per 24h regardless, so it can't be turned into notification spam. A determined attacker with an IPv6 /64 defeats a correct implementation too.

- /p/** having no rate limit — availability-only on a public marketing surface, no data or authz consequence, and maxInstances:20 is your deliberate spend ceiling. The alternative (unbounded scale-out on an anonymous uncached route) is the billing risk you already chose against.

- /p/{token}/poster streaming arbitrary owner-namespace objects — storage.rules caps those at 500MB and nosniff+CSP defuse content-type confusion. The page already hands out a 3-hour signed URL to the same object with better throughput and no concurrency cap, so this route is a strictly worse amplifier than what's already public.

- The 3-hour signed-URL window after unpublish — this is documented, deliberately chosen (down from 8h), and inherent to signed URLs. The page itself is no-store and goes down immediately. Only worth revisiting if you build the closedAt/410 design, though dropping the avatar/poster max-age=300 to no-store is a cheap improvement.

- coachAthleteCount being introducible when the field is absent — no demonstrated exploit: the accept CFs gate on an authoritative recompute, not the counter, and the field is written by the CF the moment any connection exists. Add it to the deny list for parity while you're fixing coachTierSource (finding 10).

- enforceAthleteLimit's `!=` inequality skipping field-less docs — real (and your own code documents the identical hazard for the storage query at index.ts:3151), but exploiting it needs a two-step REST loop and only buys extra athlete profiles on a free tier. Fix it when convenient by switching to an equality-free fetch with an in-code filter.

- The privacy policy's children's-privacy sentence 'describing a control that doesn't exist' — this sub-claim was wrong. You do enforce a parental attestation as a hard signup gate, re-ask at publish, record publishConsentAt, and suppress under-13 contact data on both client and server. The policy problem is completeness (missing recruiting section, missing Resend/Crashlytics), not a false statement.

- The recruiting page publishing a 12-year-old's name, face, city, school and film — this is a documented, consented product decision (RecruitingInfo.swift:352-354 says so explicitly), behind an affirmative guardian toggle with clear disclosure copy, on a noindex page. It belongs in a policy risk-acceptance conversation, not a security defect list. The actionable piece is the fail-open case in finding 7.

- A deleted athlete's public page staying live because the takedown is fire-and-forget — largely refuted: deleteProfileDoc is a plain Firestore SDK write and persistent local caching is enabled, so an offline delete is durably queued and commits on reconnect, surviving app relaunch. The narrow residual is app deletion before the queue flushes.

- Cloud Function logs writing email addresses (index.ts:247, :1146) — only two sites, account-holder addresses you already have, and reading them requires an existing GCP role. Swap in the resolved UID next time you touch those lines.

---

_Engineering guidance, not legal advice. The COPPA classification decision (general-audience-parent-operated vs child-directed) should be made with counsel._
