# Recruiting profile — "done recruiting" closed state

**Date:** 2026-07-26
**Status:** design, server half approved — client half not yet designed. **Deferred, not started.**
**Feature area:** recruiting profile (`docs/RECRUITING_PROFILE_PLAN.md`, review `docs/RECRUITING_PROFILE_REVIEW_2026-07-25.md`)

---

## Problem

`unpublish` is the only way to take a recruiting page down, and its 404 body
(`firebase/functions/src/recruitingProfile.ts:681`) reads:

> **Profile unavailable** — This profile has been unpublished or the link is incorrect.

That copy is written for the **leak** case and is correct there. It is wrong for the
**done recruiting** case: a coach who bookmarked the link in October opens it in June
and gets a message that hedges between "taken down" and "you typed it wrong." The
athlete looks disorganized to the exact audience they spent a season courting.

The two cases are different problems:

- **Leaked / oversent link** — an access-control problem. Genuinely unsolvable at the
  mechanism level: recruiters never authenticate and every share channel is blind to
  who received it, so per-recipient revocation cannot exist. `Reset Link` (mint new,
  old dies permanently) is the honest ceiling and already ships.
- **Done recruiting** (committed, graduated, quit) — *not* an access problem. Nobody
  needs to be locked out; the athlete wants the page to stop representing an active
  search. Today the only tool for that is a control built to kill leaks.

### Non-problem: "what if the link is shared with 1000 coaches?"

One link per athlete profile. The doc is `recruitingProfiles/{athleteId}` holding a
single `shareToken` (`RecruitingProfileService.swift:254,280`); the public URL is
`profiles.playerpath.net/p/{shareToken}`. Sharing it 1000 times distributes 1000
copies of the *same* URL, and `unpublish` is one write flipping `isPublished` on that
one doc (`:488`) — every copy in the wild goes dark at once. The only multiplicity is
per *profile*: a dual-sport athlete has two, a Pro family up to five. Worst case is
five taps across five screens. **No bulk control is warranted.**

## Approach chosen

Considered three:

- **A. Live page, reframed** — keep the URL live, swap in a "Committed to X · Class of
  2026" banner, drop contact info, keep film. Rejected for now, though it is the only
  option that turns the end of recruiting into something the athlete wants to send
  *out*, and it is the natural follow-up if this ships well.
- **B. Dark, with honest copy** — a distinct closed state separate from the leak 404.
  **Chosen.**
- **C. Derive from `gradYear`** — zero taps, but closes the page out from under a
  gap-year or JUCO-transfer athlete, and silently changing what a coach sees is not a
  thing to do automatically. Rejected.

Within B, the mechanism is **a reason captured at unpublish time**, not a fifth
control. `RecruitingPublishView` already carries Publish, Unpublish, Reset Link, and
Delete Profile Data; another destructive button makes the two reversible actions
harder to distinguish from the two permanent ones, which is the opposite of what a
kill-switch screen wants.

---

## The trap that shapes the design

`loadPublishedProfile` (`recruitingProfile.ts:724`) returns `null` for three different
reasons — token unknown, `isPublished !== true`, **owner not Pro** (`:747`) — and all
three collapse into the same 404.

**"Done recruiting" and "cancelled Pro" are the same week.** An athlete who commits in
November closes their page and cancels the subscription in December. If the closed
page sits behind the Pro check it renders for about three weeks, then every coach
falls back to the generic "unpublished or the link is incorrect" — the feature would
quietly not exist for the case it was built for.

**The closed state must be evaluated before the tier check and must not require Pro.**
It costs nothing to serve: no film, no contact info, no name, one sentence and a
footer.

---

## Design — server (approved)

### Data

One new field on `recruitingProfiles/{athleteId}`:

```
closedAt: Timestamp
```

Presence means "done recruiting"; absence is the existing break/leak unpublish. No
enum — there is only one closed reason, and a string invites a second one nobody asked
for. `publish()` clears it with `FieldValue.delete()`, so reopening is just publishing
again.

### Rules — no change required

The update rule (`firestore.rules:1139`) is not a key allowlist. It validates
invariants: `userId` frozen, `shareToken` frozen unless Pro + `ownsShareToken`,
`highlights` is a list of ≤ 8, `isOwnHeadshotPath()`, and
`isPublished == false || hasProTier()`. Closing writes `isPublished: false` plus a new
field, satisfying every clause **at any tier** — the lapsed-owner kill switch keeps
working by construction.

Add one assertion to `firebase/rules-tests/recruitingProfiles.test.mjs` anyway:
*a lapsed (non-Pro) owner can set `closedAt` while setting `isPublished: false`.*
That is exactly the property that would rot silently under a future rules edit.

### Serve path

`loadPublishedProfile` returns a small discriminated result instead of `| null` —
`{ok} | {closed} | {unavailable}` — resolved in this order:

1. token matches no doc → `unavailable`, **404**
2. `closedAt` present → `closed`, **410**, *no tier check*
3. `isPublished !== true` → `unavailable`, **404**
4. owner not Pro → `unavailable`, **404** *(unchanged — a lapsed account's live page still goes dark)*

Step 2 preceding step 4 is the whole point; see the trap above.

The image routes (`serveProxiedImage`, `:783`) treat `closed` exactly like
`unavailable` — plain 404, no bytes. A closed page has no images to serve.

### HTTP status

**410 Gone**, not 404. Semantically correct, and it separates a designed response from
a genuine miss in the logs.

It does **not** on its own fix the Cloud Function Errors alert noise — that still wants
the log-based metric on `severity>=ERROR` (see `project_cloud_monitoring_alert_noise`).
410 only stops adding new noise to the pile.

### Copy

Deliberately **no athlete name** — reducing exposure is the point, and the coach
already knows whose link they clicked.

> **Recruiting closed**
> This athlete is no longer accepting recruiting inquiries.

Rendered through the existing `page()` helper, which already sets
`robots: noindex,nofollow` (`:670`) and needs no og:image.

---

## Design — client (NOT yet designed)

Sketched only. Resume the brainstorm here.

- **Unpublish confirmation gains a choice.** The existing `confirmationDialog`
  (`RecruitingPublishView.swift:445`) becomes three buttons: Cancel / *Taking a Break*
  (default role — reversible) / *Done Recruiting* (destructive role). The message copy
  has to explain the difference, replacing the current single-outcome text.
- **`unpublish(athleteId:sport:)`** (`RecruitingProfileService.swift:488`) takes a
  `closed: Bool` and writes `closedAt` accordingly.
- **`publish()`** must clear `closedAt` — otherwise a later plain unpublish silently
  inherits "done recruiting."
- **`RecruitingPublishStatus`** gains `closedAt: Date?` so the publish screen can show
  a closed banner and explain that publishing again reopens the page on the same link.

Open question not yet resolved: what the publish screen looks like in the closed
state — whether "Publish" relabels to something like "Reopen Recruiting," and whether
the closed banner belongs above or below the clips section.

---

## Explicitly out of scope (YAGNI)

- Bulk close across a family's profiles — max five, rare, not worth a control.
- Auto-close driven by `gradYear` — option C, rejected above.
- The "Committed to X" card — that is option A, a separate and larger bet.

## Verification when this is picked up

Per `docs/RECRUITING_PROFILE_REVIEW_2026-07-25.md` §"Verification checklist":

- iOS build (`DEVELOPER_DIR=... xcodebuild ... build`)
- Functions: `npm run build` in `firebase/functions` **before any deploy** — the
  predeploy guard blocks, but the failure mode is shipping stale JS
- Rules: run the mjs suite directly, **not** `npm test` (that script calls the
  x86_64 `firebase` binary, which cannot run on this machine)
- Device test: close a profile, confirm the 410 page, then confirm it still renders
  after the owner's Pro lapses — that is the case the whole design exists for
