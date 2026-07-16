# Recruiting Profile Phase 2 — Public Share Link (design)

> 2026-07-16. Supersedes §2 of `docs/RECRUITING_PROFILE_PLAN.md` where they
> disagree (that doc predates the Phase 1 build; its schema numbers and several
> field names are stale). Phase 1 is merged to main at `d986f10` + review fixes
> at `0733e47`.

## What Phase 2 adds

Phase 1 shipped the in-app half: a Pro-gated recruiting bio (`RecruitingInfo`
blob on `Athlete.recruitingProfileJSON`), an editor, and a preview. It has no
public surface — nothing leaves the app.

Phase 2 makes the profile **shareable as a public web link**: an athlete picks up
to 8 already-uploaded highlight clips, publishes, and gets an unguessable URL
(`https://profiles.playerpath.net/p/{token}`) that any college coach opens in a
browser — no account, no app, no login. Unpublishing kills the page instantly.

The growth loop is the page footer: every link a family blasts to 30+ schools
carries "Game film recorded & tagged in PlayerPath".

## Decisions settled during brainstorming

| Decision | Choice | Why |
|---|---|---|
| Hosting | `profiles.playerpath.net` → Firebase Hosting rewrite → CF | Reads as official; marketing site on the apex untouched. Works on `<project>.web.app` first, so DNS is a pre-launch step, not a build blocker. |
| Link scope | One link per **Athlete row** | Matches Phase 1 (editor is per-row); recruiting is sport-specific — a golf coach doesn't want baseball film. Dual-sport = two links. |
| Video layout | Clip grid, first clip renders as hero | Clips are already in Storage; zero new upload plumbing. Stitched reels are generated on-device and would need a publish-time upload. |
| Publish path | Client-direct write, rules-gated | Stats must be computed in Swift anyway (the golf engines live there), so a CF publish endpoint adds ceremony without deeper validation. |

Cut from the plan doc for v1: `seasonStats` rows and season-scoped publishing
(YAGNI), the optional baseball season stat line (the doc itself recommends
against it), PDF export (already cut), and a Pro-lapse audit cron (client shed +
rules cover it).

---

## 1. Collection `recruitingProfiles/{athleteId}`

**Doc ID = the athlete's canonical UUID** (`Athlete.id.uuidString`). SwiftData
`Athlete.id` equals the Firestore athlete `id` by invariant
(`project_athlete_uuid_canonical`), so a deterministic ID makes publish an
idempotent upsert: no lookup query, no duplicate-doc risk.

```
recruitingProfiles/{athleteId}
  userId                  // owner uid — every rule keys off this
  shareToken              // UUID string; minted once on first publish, NEVER rotated
  isPublished: Bool       // the kill switch
  sport                   // "baseball" | "softball" | "golf"
  name, gradYear?, heightInches?, weightLbs?, highSchool?, clubTeam?
  location?               // flattened from RecruitingInfo.locationLine ("Austin, TX")
  primaryPosition?, secondaryPosition?, bats?, throwsHand?   // baseball/softball
  bio?                    // free text "About"
  gpa?, contactEmail?, contactPhone?   // present ONLY when the include* flag is on
  headshotPath?           // Storage path; CF signs it at request time
  measurables? {          // baseball/softball, only when showMeasurables == true
    sixtyYardDash?, exitVelo?, throwingVelo?, pitchVelo?
  }
  golfStats? {            // golf only; snapshotted at publish
    estHandicap?, roundAvg?, bestScore?, roundCount,
    girPct?, firPct?, scramblingPct?, puttsPerRound?   // omitted when nil
  }
  highlights: [           // ordered by the athlete; first = hero; max 8
    { videoStoragePath, thumbnailStoragePath?, durationSeconds?, label }
  ]
  publishedAt, updatedAt, viewCount, lastViewedAt
```

Two shape rules that matter:

**Storage paths, not URLs.** Nothing in Firestore is a fetchable URL — the CF
signs paths at request time (1-hour expiry). Both paths are deterministic and
derived at publish, never parsed out of a stored download URL:

- headshot: `recruiting_headshots/{uid}/{athleteId}.jpg`
  (`VideoCloudManager+Photos.swift:61`)
- video: `athlete_videos/{uid}/{clip.fileName}`
  (`VideoCloudManager.swift:142`)

**Labels are pre-formatted at publish.** `"Triple vs Eagles · Mar 12"` /
`"Driver · Hole 7"` are built in Swift so the CF never needs to understand
`PlayResult` or `Club` enums.

## 2. Firestore rules

```
match /recruitingProfiles/{athleteId} {
  allow read, delete: if isOwner(resource.data.userId);
  allow create: if isOwner(request.resource.data.userId)
                && hasProTier()
                && request.resource.data.keys().hasAll(['userId','shareToken','isPublished','sport','name'])
                && request.resource.data.highlights.size() <= 8;
  allow update: if isOwner(resource.data.userId)
                && request.resource.data.userId == resource.data.userId
                && request.resource.data.shareToken == resource.data.shareToken
                && request.resource.data.highlights.size() <= 8
                && (request.resource.data.isPublished == false || hasProTier());
}
```

- **No public read.** Anonymous recruiters never touch Firestore; the CF reads
  via the Admin SDK, which bypasses rules.
- `hasProTier()` (`firestore.rules:25`) finally gains a caller — its comment says
  "no callers — kept for future athlete-tier-gated rules". Update that comment.
- **Unpublish is never tier-gated.** A lapsed-Pro user must always be able to
  take their kid's page down; only creating or *keeping* published needs Pro.
- `userId` and `shareToken` are pinned immutable on update — no reparenting a
  doc, no rotating a token out from under a coach's bookmark.

## 3. `serveRecruitingProfile` Cloud Function

New `onRequest` in `firebase/functions/src/index.ts` — the second ever (the
first is `appStoreServerNotifications`, `index.ts:3524`). Handles
`GET /p/{token}`:

1. Query `recruitingProfiles` where `shareToken == token` **and**
   `isPublished == true`, `limit(1)`. Equality-only, so no composite index is
   needed (mirrors the `enforceStorageQuota` lesson — a range clause there forced
   an index and crashed). Miss → branded 404 "This profile is unavailable."
2. Sign the headshot + ≤8 video/thumbnail paths — reuse the existing
   `getSignedUrl` pattern (`index.ts:2946`), 1-hour expiry.
3. Increment `viewCount` + `lastViewedAt`, fire-and-forget. **Skip known
   link-preview bots** by user-agent (iMessage/Slack/Twitter/facebook
   unfurlers) — an unfurl is not a coach view, and every shared link unfurls.
4. Render HTML via template literal (no framework, no build step).
5. `Cache-Control: no-store` — CDN caching would freeze view counts and
   eventually serve expired signed URLs.

**Page structure** (video-first, per the plan doc's core thesis):
hero video → clip grid (thumbnail posters, `preload="none"`) → bio chips →
sport-branched band (full golf band / self-reported measurables row) → contact →
PlayerPath footer.

**Head:**
- Open Graph: `og:title` = `"Jordan R. · Class of 2027 · SS"`, `og:description` =
  the headline stat line, `og:image` = signed headshot. This is what makes the
  link unfurl richly in iMessage/email.
- `<meta name="robots" content="noindex">` — these are minors; an unguessable
  token is not a reason to let Google index the page.

**Every interpolated user string is HTML-escaped.** `bio`, `name`, `highSchool`,
`clubTeam`, `location`, and clip labels are free text going into a public page —
this is a live XSS surface, not a theoretical one. One `esc()` helper, applied at
every interpolation site.

## 4. Hosting

Add a `hosting` block to `firebase.json` (currently firestore/storage/functions
only):

```json
"hosting": {
  "public": "firebase/hosting-public",
  "rewrites": [{ "source": "/p/**", "function": "serveRecruitingProfile" }]
}
```

`firebase/hosting-public/` holds only a static 404. Deploy
`--only hosting,functions`. Then in the Firebase console add the custom domain
`profiles.playerpath.net` and create the TXT (verify) + A/CNAME records it
issues. Links work on `<project>.web.app/p/{token}` immediately; the custom
domain takes over once DNS propagates. The client reads its base URL from one
constant so the swap is a one-line change.

## 5. `RecruitingProfileService.swift` (~170 lines, `@MainActor`)

```swift
func publish(athlete: Athlete, highlightClips: [VideoClip]) async throws -> String  // returns URL
func unpublish(athlete: Athlete) async throws
func refresh(athlete: Athlete) async throws        // re-snapshot bio + stats
func fetchStatus(athlete: Athlete) async throws -> RecruitingPublishStatus
```

`publish` upserts `recruitingProfiles/{athlete.id.uuidString}`:

- **Token:** read the doc first; reuse `shareToken` when present, mint
  `UUID().uuidString` only on first publish.
- **PII:** write `gpa`/`contactEmail`/`contactPhone` **only** when the matching
  `includeGPA`/`includeContactEmail`/`includeContactPhone` flag is true — omit
  the key entirely rather than writing null. Phase 1 deliberately stores value +
  explicit flag precisely so "not entered" and "entered but private" stay
  distinct; a stored-but-private value must never reach the server. Same for
  `measurables` behind `showMeasurables`.
- **SwiftData discipline:** snapshot every `athlete`/`clip` property into plain
  values **before the first `await`** (`feedback_swiftdata_model_access_across_await`).
- **Analytics:** `trackRecruitingProfilePublished(sport:clipCount:)` alongside
  the existing `trackRecruitingProfileSaved` (`AnalyticsService.swift:122`).

### Golf stats — one shared source

`RecruitingGolfStatBand` currently computes the whole golf pipeline inline in
`body` (`RecruitingGolfStatBand.swift:22-25`) — which is also the deferred Phase 1
review finding that it recomputes per render.

Extract that into a `RecruitingGolfStats` value type with a
`static func compute(for athlete: Athlete) -> RecruitingGolfStats`, wrapping the
same four calls at the same `season: nil` scope:
`GolfExportData.tournamentRounds` / `.summary().tournamentAverage` /
`.advancedStats`, plus `HandicapEstimator.estimatedIndex`. The band renders it;
publish serializes it. One source, so the public page can never disagree with the
in-app Stats screen — and the render-cost finding closes as a side effect.

Tournament rounds only: practice scores carry no recruiting credibility.

## 6. The `isUploaded` gate (the main new failure mode)

A highlight that hasn't finished uploading has no `athlete_videos/` object, so
the CF would sign a path to nothing and the coach gets a broken player.

- The picker offers only clips where `isUploaded == true && cloudURL != nil`.
- Local-only highlights render **greyed with an "Uploading…" badge** — visible
  but unselectable. Hiding them reads as data loss.
- If nothing is selectable yet, publish is disabled with "Your highlights are
  still uploading — this usually finishes on Wi-Fi."
- `publish` **re-checks the gate at write time** and drops any clip that lost its
  upload, rather than publishing a broken tile.

## 7. UI — two new files

**`RecruitingHighlightPicker.swift` (~120 lines):** multi-select over the
athlete's `isHighlight` clips, cap 8, drag-to-reorder (order = page order, first
= hero). Reuses `VideoThumbnailView`. Builds the clip labels.

**`RecruitingPublishView.swift` (~160 lines):** publish toggle, live URL + copy,
native `ShareLink`, "Viewed 12 times", "Update published profile" when bio/stats
have drifted since `publishedAt`, unpublish. Reached from a **Share Profile**
button added to the existing `RecruitingProfileView` preview — Phase 1's
editor → preview flow gains a third step rather than being restructured.

Both under `Views/Recruiting/`, both small and focused, matching the five Phase 1
files (97–232 lines each).

**Gating:** `.proRequired()` on the publish surface, mirroring the editor's
existing treatment (`ProfileView.swift:226`). Unpublish stays reachable at any
tier.

## 8. Delete cascade

A live public page must never outlive its athlete or its account.

- **Athlete delete (client):** delete `recruitingProfiles/{athleteId}` in the
  athlete-delete path, alongside the existing headshot cleanup.
- **Account delete (client):** sweep the user's profile docs in the GDPR delete
  flow, next to `deleteAllUserRecruitingHeadshots`.
- **CF backstop:** a step in `cleanupUserDataOnDelete` (`index.ts:1219`) deleting
  `recruitingProfiles` where `userId == uid`, exactly mirroring how the
  `recruiting_headshots/{uid}/` sweep was added in the Phase 1 review fixes
  (`index.ts:1395`). The Admin SDK bypasses rules, which matters here because the
  client can't clean up after Auth is torn down.

## 9. COPPA / privacy

Publish is the moment a minor's photo — and possibly their email and phone —
becomes world-readable. The app has no age gate anywhere.

- **First-publish confirm sheet only:** "I confirm I'm the parent/guardian, or
  I'm 13 or older." One-time, per athlete, stored on the profile doc. Cheap, and
  this is the one place it genuinely matters.
- Per-field PII opt-ins already exist and default off (Phase 1).
- No PII in the URL; the token is unguessable; `noindex`; unpublish is immediate
  and never tier-gated.

## 10. Testing

No test targets exist in this project — verification is by build + device.

- **Emulator:** rules tests for the `recruitingProfiles` matrix — owner
  read/write, non-owner denied, anonymous denied, non-Pro create denied, non-Pro
  unpublish **allowed**, `shareToken`/`userId` immutability, `highlights` cap.
- **CF local:** serve a seeded published doc, an unpublished doc (404), a bad
  token (404), and a doc whose `bio` contains `<script>` (escaped, not executed).
- **Device:** publish → open the link on a machine that has never seen the app →
  video plays → unpublish → same link 404s → republish → **same token**.

## Effort

| Piece | Est. |
|---|---|
| Rules + CF + hosting block + domain setup | ~2.5 d |
| Service + publish view + picker + golf-stats extraction | ~2.5 d |
| Delete cascade + COPPA confirm + analytics | ~1 d |
| **Total** | **~6 d** |

## Open items (not blockers)

1. DNS records for `profiles.playerpath.net` — needed before launch, not before
   build (`.web.app` works throughout development).
2. Phase 1's still-open device tests (over-the-top V34→V35 migration, Pro-gating,
   headshot upload, cross-device sync) remain open independently of this work.
