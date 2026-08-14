# PlayerPath — State of Play

**Snapshot: 2026-08-09.** Written to be uploaded as a self-contained context file (e.g. into a claude.ai
project's Context panel), so it assumes no access to the repo, the codebase, or Claude Code's local memory.

Everything below was verified against `main` on the snapshot date. It is a **point-in-time photograph, not
live state** — this project moves fast and Trey commits outside assistant sessions. Anything version-,
deploy-, or status-shaped goes stale within weeks. Regenerate rather than trust an old copy.

---

## 1. What the product is

PlayerPath is a **dual-sport iOS performance-tracking app** (SwiftUI, iOS 17+), built and shipped solo by
Trey. It covers two sports with genuinely different shapes:

- **Baseball / softball** — record game and practice video, tag it play-by-play, track batting and pitching
  stats across seasons.
- **Golf** — round and tournament scoring, per-hole stats plus opt-in shot-by-shot detail, and
  birdie-or-better rounds that auto-bundle into highlight reels.

Around that core sit three things that matter strategically:

1. **Coach sharing** — athletes share clips into folders with a private instructor, who reviews them with
   telestration, drill cards, and notes. This models *personal instruction* (paid lessons), **not** team
   practice management. Coach feedback is one-way (coach → athlete) by design in v1.
2. **The recruiting profile** — a Pro athlete publishes a public web page at
   `profiles.playerpath.net/p/{token}` for college coaches. Video-first, not stats-first.
3. **Dual-sport modeling** — a person who plays two sports is **two `Athlete` rows linked by a shared
   `personGroupID`**, counting as **one subscription slot**. This is the single most counter-intuitive
   modeling decision in the app; almost every counting, billing, and picker bug in its history traces back
   to code that keyed on the athlete row instead of the person group, or vice versa.

**The strategic wedge** (Trey's call, and it's correct): college baseball/softball coaches *discount*
self- or parent-logged high-school stats — they recruit on video and showcase-verified measurables. So
"we track it, therefore it's credible" is false for baseball. The real asset is the video pipeline that
already exists. Golf is the exception: scoring is objective and *is* the recruiting currency, so golf gets
a full stat band while baseball gets clips plus optional self-reported measurables.

---

## 2. Monetization

**Player tiers:**

| | Free | Plus | Pro |
|---|---|---|---|
| Athletes | 1 | 3 | 5 |
| Storage | 2GB | 25GB | 100GB |
| Monthly | — | $5.99 | $12.99 |
| Annual | — | $57.99 | $124.99 |

**Coach tiers:**

| | Free | Instructor | Pro Instructor | Academy |
|---|---|---|---|---|
| Athletes | 2 | 10 | 30 | Unlimited |
| Monthly | — | $9.99 | $19.99 | Contact Us |
| Annual | — | $95.99 | $191.99 | Contact Us |

Academy is granted manually in Firestore — no StoreKit product exists for it.

**Pricing Model V2 (shipped):** coach sharing is **not** gated by athlete tier. The *coach* pays for each
connection out of their seat allowance, so an athlete on any tier can share with a coach. Athlete tiers
re-anchor on storage, multi-athlete support, and Plus+ features (auto highlights, stats export, season
comparison). Billed through StoreKit 2 subscriptions.

---

## 3. Where the app stands right now

- **Version 6.4.4, build 208** (HEAD `2c8f143d`, working tree clean as of the snapshot).
- Shipped and approved on the App Store; public launch was v5.0, with v6.x carrying the golf releases.
- Local persistence is SwiftData at **schema V37**; cloud is Firebase (Firestore, Storage, Auth, ~38 Cloud
  Functions, Hosting). Firebase project `playerpath-159b2`.
- **The recruiting profile is ON.** Phases 1–3 have been live in prod since late July 2026; the feature was
  deliberately hidden from a first App Store submission behind a compile-time flag
  (`RecruitingFeature.isEnabled`) and that flag was **turned on 2026-08-09**, so recruiting ships with the
  next submission. It stays compile-time on purpose — revealing a feature App Review never saw would be an
  App Store guideline 2.3.1 problem, so turning it on or off is a resubmit, never a remote switch.
- Security posture has had two full review passes (2026-07 and 2026-08-06, the latter a 41-agent audit with
  20 ranked findings). Server-side remediation is deployed in two batches; **the client halves of those
  batches have not shipped to users yet** — they ride the next App Store build.

---

## 4. The biggest open risk: device QA, not code

The pattern across the last two months: code lands, gets reviewed hard, gets deployed — and then the
on-device verification lags. Multiple feature areas are marked "done in code, device tests pending":

- **Recruiting** — roughly 1–2 of ~14 critical tests run. The one that passed is the important one (film
  plays on Edge/Windows, Firefox, Chrome, which proves the H.264 web renditions are real). Still unrun:
  the over-the-top SwiftData migration test, unpublish, Reset Link (irreversible), the dual-athlete push
  deep-link, and the "Delete Profile Data" headshot-resurrection regression.
- **Highlights, photos, practices-delete, athlete-delete cascade, reel title cards** — each has a fixed
  batch awaiting device confirmation.
- **Coach removal / over-limit recovery** — retest outstanding from the Pricing V2 pivot.

The honest framing: the repo's risk is concentrated in *unverified* work, not unwritten work.

---

## 5. Roadmap

The canonical ranked list lives in `docs/PRIORITIES.md` (statuses last verified 2026-08-01). The lens:
**trust and money before growth, growth before polish, polish before future bets.**

- **Tier 1 (trust/revenue/legal) — cleared.** Pricing V2 server side closed, GDPR subcollection orphans
  fixed, security fixes deployed, settings compliance done.
- **Tier 2 — the recruiting profile**, and it is now *ship-and-verify*, not *build*. It was chosen as "the
  next needle mover" because it's the only item that moves the growth curve rather than protecting it: every
  published page is a branded public link aimed at exactly the right audience, it justifies the Pro tier
  with value that's legible *outside* the app, and a live page gives a reason to keep capturing. The success
  test was defined up front: get five real athletes to share a link, watch for click-throughs.
- **Tier 3 — core UX,** athlete-facing core shipped. Deferred: a sport sub-picker in the coach session
  picker, and cross-athlete name search.
- **Tier 4 — polish:** celebration animation (two moments only — highlight-reel-ready reveal and
  personal-best stamp), iPad coach tooling, Live Activities, and the recruiting "done recruiting" closed
  state (designed, server half approved, client half unbuilt).
- **Tier 5 — future bets:** the golf sport-abstraction refactor (~262 call sites of real tech debt), a
  Family/Fan read-only viewer role, and assorted multi-device edge cases.

---

## 6. Open decisions worth knowing about

These are unresolved *product* questions, not bugs:

- **Age posture is internally contradictory.** Signup says 18+, the TOS says 13+, and the privacy policy
  assumes a parent-run account. This blocks any self-managed-minor flow and it shadows every marketing
  decision aimed at athletes directly. A COPPA-driven under-13 gate now withholds contact details and GPA
  from published recruiting pages — including when the grad year is simply *unknown*, which fails closed —
  but the top-level posture question is still open.
- **The "done recruiting" closed state** — unpublishing currently serves "unpublished or the link is
  incorrect," which is wrong for an athlete who committed and reads as a broken link to every coach still
  holding it.
- **App Check is wired but only in Monitoring mode** — zero actual enforcement. Enforcing needs dev debug
  tokens registered first, and the Cloud Functions path doesn't send the App Check header because calls are
  hand-rolled URLSession requests.
- **Coach free-tier multi-account abuse** — email normalization is done; device fingerprinting is not.
- **Athlete-direct marketing funnel** — reviewed 2026-08-08 and found to have three blockers, two of which
  are the age posture above.

---

## 7. Invariants that constrain answers

Non-obvious rules that a plausible-sounding suggestion will violate:

- **The recruiting page stores Storage *paths*, never URLs.** They're signed per request with a short
  expiry, so nothing durable in the database is fetchable. PII keys are *omitted*, never written as null.
- **The unpublish kill switch is never tier-gated.** A lapsed Pro must still be able to take their page
  down. This has already been broken once by gating the *route* to it rather than the action.
- **Highlights on the public page are served as separate H.264/AAC MP4 renditions**, never the HEVC master
  — the master silently fails on Firefox and on Windows without Microsoft's paid HEVC extensions.
- **Coach athlete-limit enforcement lives in Cloud Function transactions, not security rules.** Rules can't
  safely count via a list query.
- **Cloud Functions are never called via `HTTPSCallable`** — every call site is a direct URLSession POST
  with a Bearer ID token, working around a Firebase iOS SDK crash on iOS 26.4.
- **`firebase deploy --only functions` does not compile TypeScript.** It ships whatever is in `lib/`.
- **The app has no test target.** Swift changes are verified by building; the Firestore security rules *do*
  have a real test suite and it's the gate for any rules edit.

---

## 8. How Trey works

- **Solo, first-time iOS developer** who has now been all the way through App Store review, TestFlight, and
  App Store Connect several times. Commits directly to `main`, frequently, and often outside assistant
  sessions — so any "uncommitted" claim in a document like this is suspect by the time you read it.
- **Prefers careful, well-researched work over speed.** Plans should be grounded in actual code, not
  sketched at a high level. Think hard up front, fix less afterward.
- **Trey owns version and build numbers** (as of 2026-08-09) — never propose one. Note that older documents
  and assistant memories reference build numbers that were assistant-chosen and never matched his release
  plan; treat any specific build number in an older document as unreliable.
- Prefers small, focused source files; TipKit popovers over custom tooltip overlays; plain coach notes over
  timestamped annotations.
- **The design system is mid-migration** — a canonical cream/terracotta palette and `.pp*` type scale, and a
  deprecated-but-load-bearing legacy palette that still outnumbers it roughly 6:1. Any claim that the
  migration is "finished" is stale.

---

## 9. What this file is and isn't

This is a **generated digest**. Three separate stores exist and none of them sync:

1. **`CLAUDE.md` in the repo** — instructions read by Claude Code only.
2. **Claude Code's local memory** — 113 files (~750K) on Trey's Mac under
   `~/.claude/projects/-Users-Trey-Desktop-PlayerPath/memory/`, indexed by a `MEMORY.md` that is a table of
   contents, not content. That's where the granular engineering history lives: per-feature fix batches,
   do-not-re-raise lists, and hard-won footguns.
3. **This file** — the only one of the three that can travel into a chat that has no filesystem access.

Nothing here updates itself. When it drifts, regenerate it from the repo and re-upload, rather than editing
it in place from memory.
