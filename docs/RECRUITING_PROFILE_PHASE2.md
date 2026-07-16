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
                │                       ├─ re-checks owner tier is Pro
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

- **Unpublish is never tier-gated.** `firestore.rules` allows an update at any
  tier as long as it results in `isPublished == false`, and
  `RecruitingPublishView` is deliberately NOT wrapped in `.proRequired()` (that
  modifier replaces the whole screen and would lock a lapsed-Pro family out of
  their own kill switch). Only the publish action checks Pro.
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
  and would render as a broken player.
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
- ⬜ **Rules tests unrun** — `firebase/rules-tests/` is written (29 cases) but this
  machine has **no Java**, which the Firestore emulator requires. See
  `firebase/rules-tests/README.md` for the one-time install. The must-pass pair is
  "non-Pro cannot publish" + "non-Pro CAN unpublish"; the path-forgery cases are
  the other priority.
- ⬜ CF runtime test (needs the emulator → also Java): published doc renders,
  unpublished → 404, bad token → 404, `<script>` in bio escapes, bot UA doesn't
  bump viewCount, **a forged `videoStoragePath` pointing at another uid signs
  nothing**, and a non-Pro owner's page 404s.
- ⬜ Device end-to-end: publish (golf + baseball) → open link on a machine that
  has never seen the app → hero video plays → stats match the in-app band exactly
  → PII hidden unless opted in → unpublish → 404 → republish → **same token**.
- ⬜ Delete a published athlete → page dies.

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
- **Preview's clip strip isn't curation-aware.** `RecruitingHighlightStrip`
  (Phase 1) shows the athlete's newest 8 highlights; the published page shows the
  clips they picked, in their order. These agree on a first publish — the picker
  defaults to exactly newest-8 — and diverge only after the athlete reorders or
  swaps clips, at which point they're looking at the picker (which shows the real
  order) rather than the preview. Worth closing if the preview ever becomes the
  primary pre-publish check: thread the selection into
  `RecruitingProfileView`/`RecruitingHighlightStrip` and preview from the publish
  screen. Everything else on the page — every stat, label, and line of copy — is
  built from one shared source specifically so it can't drift.
- **No drift detection.** The plan mentioned an "Update published profile" hint
  when the bio/stats changed since `publishedAt`. Shipped simpler: while
  published, the update button is always available and republishing always
  re-snapshots. Comparing a live snapshot against the doc for a subtle hint
  wasn't worth the complexity for v1.
