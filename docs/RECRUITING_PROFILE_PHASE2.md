# Recruiting Profile — Phase 2 (public share link)

Design spec: `docs/superpowers/specs/2026-07-16-recruiting-profile-phase2-design.md`.
Phase 1 (in-app editor/preview): `docs/RECRUITING_PROFILE_PHASE1.md`.

## What shipped

An athlete curates ≤8 already-uploaded highlight clips and publishes. They get an
unguessable URL — `https://profiles.playerpath.net/p/{shareToken}` — that any
college coach opens in a browser with no account, no app, no login. Unpublishing
kills the page immediately; the token never rotates, so a coach's bookmark
survives a republish.

## Shape

```
iOS (RecruitingProfileService.publish)
   ├─> recruitingTokens/{shareToken}      create-only atomic claim (uniqueness)
   │     userId, athleteId
   └─> recruitingProfiles/{athleteId}     owner-only in firestore.rules
        ├─ shareToken (stable, claimed), isPublished
        ├─ display strings + Storage PATHS (never URLs)
        └─ golfStats snapshot (golf only)
                │
Firebase Hosting  /p/**  ──rewrite──> serveRecruitingProfile (Admin SDK)
                │                       ├─ /p/{token}         the page
                │                       ├─ /p/{token}/avatar  headshot proxy
                │                       ├─ re-checks owner tier is Pro (both)
                │                       ├─ ownedPath() → signs paths, 1h expiry
                │                       ├─ renders HTML + OG tags, noindex
                └─────────────────────> └─ increments viewCount (bots skipped)
```

**No public Firestore read exists.** The Cloud Function reads with the Admin SDK
(bypassing rules), which is why the collection stays owner-only while the page
stays anonymous. Don't add a public read rule to "simplify" this.

## Invariants (don't regress these)

- **The storage paths in the doc are UNTRUSTED input.** Rules validate `userId`,
  `shareToken`, `isPublished`, `name`, `sport`, and the highlight count — they do
  **not** validate the paths inside `highlights[]` (a rule can't iterate a list).
  The CF signs with the Admin SDK, which bypasses `storage.rules`. So signing a
  path unchecked turns the page into a signed-URL oracle for the entire bucket:
  publish `headshotPath: "athlete_videos/<victim>/x.mov"`, open your own page,
  read back a working link to someone else's private video. `ownedPath()` in
  `recruitingProfile.ts` re-derives every path against the doc's `userId` (which
  rules pin immutable) and is the real defense; the `matches()` check on
  `headshotPath` in `firestore.rules` is defense in depth for the one path a rule
  *can* see. **Never pass a stored path to `signPath()` without `ownedPath()`.**
- **Tier is re-checked at render.** Rules gate writes only and cannot expire an
  at-rest doc, so "publish on Pro, then cancel" would otherwise leave the page up
  forever — bypassing the entire Pro hook. `serveRecruitingProfile` reads the
  owner's `subscriptionTier` on every render and serves "unavailable" for
  non-Pro. That's what actually enforces the paywall; the rules only stop the
  write.

- **Unpublish is never tier-gated — and neither is the ROUTE to it.**
  `firestore.rules` allows an update at any tier as long as it results in
  `isPublished == false`, and `RecruitingPublishView` is deliberately NOT wrapped
  in `.proRequired()` (that modifier replaces the whole screen and would lock a
  lapsed-Pro family out of their own kill switch). Only the publish action checks
  Pro, on tap.

  **This was broken from the day it shipped and nothing caught it.**
  `RecruitingProfileEditorView` is the only way to reach the publish screen, and
  it carried `.proRequired()` at both `ProfileView` entry points — so the instant
  Pro lapsed the family hit a paywall and could never pull their kid's page down,
  while the rules, the Cloud Function, and the "lapsed owner CAN unpublish" rules
  test all stayed green. An invariant enforced at every layer except the
  navigation is not enforced. The editor is now un-gated (any tier can fill a
  profile in — a better funnel anyway) with an inline upsell card, and the publish
  button opens the paywall on tap instead of sitting disabled.
- **Publish is a full `setData`, not a merge.** A merge would leave a
  previously-published PII key in place after the athlete toggles it off. Server
  counters (`viewCount`, `lastViewedAt`) are carried forward by hand instead.
- **`shareToken` and `userId` are immutable** after creation (rules-enforced).
- **A share token must be claimed before it can be published.**
  `recruitingTokens/{token}` is keyed by the token and is create-only, so
  Firestore's "create fails if it exists" is the atomic lock, and the
  `recruitingProfiles` create rule requires the writer to hold the claim for that
  athlete. Without this, `shareToken` is just an unconstrained client string:
  anyone who was *sent* a link could publish their own profile under it, and the
  CF's `where('shareToken','==',t).limit(1)` would arbitrarily serve the
  impostor's page at the victim's URL. Claims are **never deletable by clients** —
  releasing one while a profile still points at it re-opens the hijack — so the
  CF sweeps them on account deletion instead.
- **Storage paths, not URLs, in Firestore.** Both paths are derived
  deterministically (`recruiting_headshots/{uid}/{athleteId}.jpg`,
  `athlete_videos/{uid}/{fileName}`), never parsed from a stored download URL.
- **Only uploaded clips publish.** `VideoClip.isPublishableHighlight` gates the
  picker and is re-checked at write time — a local-only clip has nothing to sign
  and would render as a broken player. `isUploaded` is only a local flag, though,
  so publish also probes each path with `getMetadata()` first and reports what it
  dropped; only a genuine `objectNotFound` counts, or an offline device would
  quietly shrink the page.
- **Storage paths are anchored on `Auth.auth().currentUser?.uid`,** not
  `athlete.user?.firebaseAuthUid`. Every uploader uses the auth uid, and the local
  User row's cached copy can go stale (`AuthenticatedFlow`'s UID-mismatch branch
  can leave a second row behind). Publishing under a stale uid writes paths into a
  namespace nothing was uploaded to; the mismatch is now an explicit error.
- **The curated clip set is persisted** in `RecruitingInfo.publishedClipIDs` (blob
  field — no schema bump, no new sync sites, same reasoning as `publishConsentAt`).
  It was view state before, so a relaunch re-seeded the picker to newest-8 and the
  next "Update Published Profile" silently replaced the athlete's curation.
  ⚠️ `RecruitingProfileEditorView.persistIfChanged` snapshots the blob in `init`,
  so **anything a pushed screen writes needs a carry-forward line there** or the
  editor's autosave erases it on the way out.
- **Page strings are built once, in Swift.** `RecruitingInfo`'s display helpers
  and `RecruitingGolfStats` feed both the in-app preview and the publish
  snapshot, so the page can't word or format anything differently. The CF is a
  dumb renderer — resist teaching it about PlayResult, Club, or stat formatting.
- **`esc()` every interpolation** in `recruitingProfile.ts`. Bio/school/labels are
  athlete-authored free text on a public page.
- **A page must never outlive its athlete.** Four cascade sites:
  `Athlete.delete(in:)`, `performDeleteAthlete`, `deleteUserProfile` Step 11b,
  and the `cleanupUserDataOnDelete` CF step 14.

## Golf stat scope (subtle — read before "fixing" it)

Scoring (avg / best / rounds) is **tournament-only**. GIR / fairways / putts /
scrambling come from `GolfExportData.advancedStats`, which pools tournament AND
practice rounds. That asymmetry is inherited from the in-app Stats screen, and
`RecruitingGolfStats.footnote` is worded narrowly because of it. Do **not**
broaden the footnote to claim the whole band is tournament-only, and don't filter
advancedStats for the page alone — that would make the page disagree with the app.

## Public page hardening (2026-07-25)

- **Security headers on every response** — `X-Content-Type-Options: nosniff`,
  `Referrer-Policy: no-referrer`, HSTS, and a CSP (`default-src 'none'` widened
  only to signed Storage URLs for media/posters and `'self'` for the avatar).
  Function responses previously carried none of these; the static Hosting paths
  got HSTS, which made it easy to assume the page did too. `no-referrer` is not
  cosmetic: without it every media request leaks the page URL — **which contains
  the share token** — to Google in the `Referer` header.
- **`TOKEN_RE` matches the real UUID shape**, case-insensitively (Swift's
  `UUID().uuidString` is UPPERCASE). The old `[A-Za-z0-9-]{8,64}` let any junk
  string through to a Firestore query on an endpoint that is unauthenticated and
  has no App Check.
- **`/p/{token}/avatar` proxies the headshot** so `og:image` is a permanent URL.
  It used to be the 1-hour signed URL, which link-unfurl caches (iMessage, Slack,
  Gmail) hold long past expiry — so a shared profile's preview image broke on
  exactly the surface this feature grows through, and a signed Storage URL ended
  up parked in third-party cache infrastructure. The route runs the same
  published + Pro checks (`loadPublishedProfile`, which every content route must
  go through), caches for 5 minutes only so an unpublish takes a minor's photo
  down promptly, and never touches `viewCount`.
- **A filmless render says so.** The all-clips-failed-to-sign 500 now serves
  distinct copy instead of "unpublished or the link is incorrect" — that message
  sent athletes chasing a link problem when the actual cause is almost always the
  signBlob IAM role.

## Why there is no persisted clip `storagePath`

Considered and deliberately rejected. **Nothing anywhere records the Storage path
a clip was actually written to**: `VideoClip` has `filePath`/`thumbnailPath`
(on-device) and `cloudURL` (a tokenized download URL);
`FirestoreVideoMetadata` has no path; neither round-trip parser carries one. The
only `storagePath` string in the codebase is written to `pendingDeletions` and
read solely by a Cloud Function.

The `athlete_videos/{uid}/{fileName}` convention does hold in every traced flow —
coach-saved clips are **re-copied** under a fresh UUID filename with `cloudURL`
nil (`CoachVideoPlayerViewModel.saveToMyVideos`), `ClipTrimService` overwrites in
place, and person-group re-homes are hard-filtered to one `uploadedBy` uid so they
can't cross accounts. Adding a real `storagePath` would mean wiring a new field
through all six sync sites plus **both** parsers
(`.claude/skills/sync-field-check/SKILL.md`) to close a gap that currently fails
closed. The auth-uid anchor plus the pre-publish `getMetadata()` probe get the
same safety for a fraction of the blast radius.

## Deploy gates (the feature is inert until all three land)

1. **`firebase deploy --only firestore:rules`** — without the `recruitingProfiles`
   block, every publish is denied by the catch-all.
2. **`firebase deploy --only functions`** — ships `serveRecruitingProfile` (new)
   and the `cleanupUserDataOnDelete` step-14 sweep.
3. **`firebase deploy --only hosting`** — ships the `/p/**` rewrite. Deploying
   functions without hosting leaves the page reachable only at the raw function
   URL.

Also required, or every page renders with no film:

4. **IAM**: the functions runtime service account needs **Service Account Token
   Creator** (`iam.serviceAccounts.signBlob`). Without it `getSignedUrl()` fails
   for every object. The CF now returns a 500 + logs rather than serving a
   filmless 200, so check the logs if a published page won't load.

Then, before launch (not before build):

5. **DNS**: Firebase Console → Hosting → add custom domain
   `profiles.playerpath.net`; create the TXT (verification) + A records it
   issues. Until then the same page serves at `https://<project>.web.app/p/{token}`.
6. **Flip `RecruitingProfileService.publicBaseURL`** if it was pointed at
   `.web.app` for testing. It's the only place the host appears.

## Verification status

- ✅ `xcodebuild` (iphonesimulator) — **BUILD SUCCEEDED**, no warnings in touched files.
- ✅ `tsc` (firebase/functions) — clean, `strict` + `noUnusedLocals`.
- ✅ `playerpath-reviewer` on the full diff — found a **HIGH signed-URL oracle**
  (client-authored storage paths signed unchecked) and a **HIGH** set of
  model-access-after-await sites; both fixed, plus the lapsed-Pro at-rest gap, the
  `try?` token-regeneration bug, the filmless-200, the dropped viewCount, and
  consent-stamped-on-failure. Re-reviewed after fixing.
- ✅ **Rules tests 31/31** — `cd firebase/rules-tests && npm test` with
  `JAVA_HOME` exported (Temurin 21 at `~/.local/jdk/`, no sudo needed). The
  must-pass pair is "non-Pro cannot publish" + "non-Pro CAN unpublish"; note the
  latter passed throughout the period when the kill switch was unreachable in the
  app, which is the whole lesson of that invariant.
- ✅ Prod end-to-end (2026-07-25): real publish → 200 with hero `<video>`, signed
  media serving 206 partial content, `noindex`, correct OG description.
- ⬜ CF runtime test (emulator): published doc renders, unpublished → 404, bad
  token → 404, `<script>` in bio escapes, bot UA doesn't bump viewCount, **a
  forged `videoStoragePath` pointing at another uid signs nothing**, a non-Pro
  owner's page 404s, and `/p/{token}/avatar` 404s once unpublished.
- ⬜ **Kill switch on device** — drop the tier below Pro via
  `PlayerPathStoreKit.storekit`: the editor still opens, the upsell card shows,
  Publish opens the paywall, and **Unpublish works**. This is the regression test
  for the bug above; nothing automated covers the navigation.
- ⬜ Curation persistence on device: publish → curate to 2 clips in a non-default
  order → force-quit → reopen Share Profile → same 2, same order.
- ⬜ Re-unfurl a published link an hour after publishing (iMessage/Slack) — the
  preview image must still render.
- ⬜ Device end-to-end: publish (golf + baseball) → open link on a machine that
  has never seen the app → hero video plays → stats match the in-app band exactly
  → PII hidden unless opted in → unpublish → 404 → republish → **same token**.
- ⬜ Delete a published athlete → page dies.

## Open decisions

Three, all deliberately unresolved, all worth settling before this feature gets
real adoption. Detail in the sections below.

1. **A lapsed Pro page goes dark silently** — grace period, notification, or accept.
2. **One link per `Athlete` row, not per person-group** — a dual-sport kid sends
   coaches two links.
3. **Profile-doc squatting** — a connected coach with Pro can block an athlete
   from ever publishing.

### Decision 2: one link per Athlete row

The v1 framing in `RECRUITING_PROFILE_PLAN.md` was "one public link per
person-group". What shipped is one per `Athlete` row, because
`recruitingProfiles/{athleteId}` is keyed by the athlete UUID and a dual-sport
person is two rows linked by `personGroupID`. So a two-sport athlete has two
profiles, two share tokens, and two links to send.

Arguably correct — a golf coach does not want the baseball film, the golf stat
band is sport-specific, and each page stays focused. But it was never decided; it
fell out of the doc-ID choice. It also interacts with decision 3: re-keying
profiles by `shareToken` (one of the two squatting fixes) would make a
person-group-level link natural, since the athlete UUID would stop being the key.

## Product decision to revisit: a lapsed Pro page goes dark, silently

Because `serveRecruitingProfile` re-checks the owner's tier per render, the day a
family's Pro lapses their athlete's public link starts returning "profile
unavailable" — to every coach already holding it. That's the Pro hook working as
designed, and it's also the harshest possible version of it: no grace period, no
warning, no notification, and the athlete finds out when a coach tells them the
link is broken (or never tells them).

The app is honest about the state — `RecruitingPublishView` reports "Your profile
is offline", explains why, and hides Share/Copy so nobody mails a dead link — but
that only helps someone who opens the app and navigates to that screen.

Worth deciding before launch: a grace period (e.g. keep serving for N days after
lapse), a push/email when a published page goes dark, or accept it as-is. Payment
failures are common and recruiting season is time-sensitive; a silently dead link
during it is a bad way to find out about an expired card.

## Known gap: profile-doc squatting (open, narrow DoS)

`recruitingProfiles/{athleteId}` is keyed by the athlete UUID, and the create rule
can only check that `userId == request.auth.uid` — it cannot verify the caller
actually *owns* that athlete. Athlete docs are written with `addDocument`
(`FirestoreManager+EntitySync.createAthlete`), so their Firestore doc IDs are
auto-generated and the UUID lives in an `id` *field*; there's no
`exists(/users/{uid}/athletes/{athleteID})` check available, and rules can't query.

So an attacker who knows a victim's athlete UUID — a **connected coach does**, from
the shared-folder docs — and holds athlete Pro can pre-create
`recruitingProfiles/{victimAthleteUUID}` under their own `userId`. The victim can
then never publish: their create sees an existing doc, falls to the update rule,
and is denied because `resource.data.userId` isn't theirs.

Bounded: no data leak and no impersonation of the victim's URL (pages are served
by `shareToken`, which is claim-protected). It's denial-of-publish only, and it
needs Pro plus a UUID that isn't public. Not fixed because every fix is a real
change: an `athleteOwners/{athleteUUID} → uid` index collection (plus a backfill
for existing athletes), or re-keying profiles by `shareToken` so athlete UUIDs
stop being the primary key (which would also make `recruitingTokens` redundant —
doc-ID uniqueness would be the claim). Worth doing before this feature gets real
adoption; worth deciding deliberately, not in passing.

## Known deviations from earlier decisions

- **PII is filtered client-side, not server-side.**
  `RECRUITING_PROFILE_PHASE1.md` line 75 asked Phase 2 to "filter on the
  `include*` flags server-side, not trust the client preview". The approved
  publish design is client-direct (the golf stat engines live in Swift, so a CF
  publish endpoint couldn't validate any deeper without reimplementing them and
  reintroducing page-vs-preview drift). Filtering therefore happens in
  `RecruitingProfileService.applyBio`, which omits a key entirely unless its
  `include*` flag is set. The residual risk is narrow: the only actor who could
  bypass it is the profile's own owner, who can already type anything into the
  public free-text bio. Revisit if publishing ever moves server-side.
- ~~**Preview's clip strip isn't curation-aware.**~~ **CLOSED.**
  `RecruitingHighlightStrip` now takes `curatedClipIDs` and falls back to newest-8
  only when there is none (a never-published profile, where the two agree anyway).
  The publish screen has its own Preview row that passes the **live** selection —
  the only preview that can honestly carry the "This is what a college coach will
  see" copy. This mattered more than the original note implied: because the
  selection wasn't persisted, the preview and the page diverged on every relaunch,
  not just after a reorder.
- **No drift detection.** The plan mentioned an "Update published profile" hint
  when the bio/stats changed since `publishedAt`. Shipped simpler: while
  published, the update button is always available and republishing always
  re-snapshots. Comparing a live snapshot against the doc for a subtle hint
  wasn't worth the complexity for v1.
