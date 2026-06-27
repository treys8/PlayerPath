# PlayerPath — Priorities & Roadmap

**Last verified:** 2026-06-27 (statuses checked against current `main`)

The prioritization lens: **for a shipped app with paying users, trust and money come before growth, growth comes before polish, and polish comes before future bets.** Re-verify statuses against code before acting — they drift as work lands outside tracked sessions.

---

## The next needle mover

**The recruiting profile** (public, video-first athlete page — `docs/RECRUITING_PROFILE_PLAN.md`).

It's the only item that *moves* the growth curve rather than protecting it. It changes *why* people use the app — from "track my kid's stats" (a retention product that competes on features against GameChanger) to "help my kid get seen" (the highest willingness-to-pay motivation in youth sports). It hits all three levers at once:

- **Acquisition** — every profile is a public link athletes share with college coaches, on social, in family group chats. Each share carries PlayerPath branding to exactly the right audience. A referral loop that doesn't exist today; your clips are currently trapped inside the app.
- **Monetization** — justifies a premium tier or its own SKU; the clearest "worth paying for" feature you could ship, because the value is external and legible.
- **Retention** — a *live* public profile gives a reason to keep capturing (kept current like a LinkedIn).

**Cost (honest):** biggest lift on the list — it implies a **web surface** (public read access, hosting, privacy/unpublish controls, PII discipline), not another in-app screen.

**Smallest version that still moves the needle:** one public link per person-group, hero highlight reel up top, thin stat band (de-emphasized for baseball, full band for golf), grad year / position / contact, opt-in publish toggle with an unpublish kill switch. The PlayerPath watermark on that page *is* the growth engine. Ship that, get five real athletes to share their link, watch for click-throughs. That's the signal.

---

## Tier 1 — Finish what's half-done or silently broken (do first)

Trust / revenue / legal. Mostly closing loops already opened — which is why they slip, and why they go first.

1. **Pricing Model V2** — ✅ **server side fully closed.** Functions live (deploy 2026-06-27) and the ASSN webhook is **confirmed configured & working** — `appStoreServerNotifications` logs show Apple delivering real `DID_RENEW` events → HTTP 200 (06-14 → 06-16). The earlier "set the webhook URL" item was already done. **Remaining (optional):** on-device coach-removal retest.
2. **Coach revoke silent-fail on legacy folders** — ✅ **DONE in code** (`personMatches` group-expansion). Ships next build.
3. **Security fixes** — ✅ **DEPLOYED 2026-06-27.** Both accept CFs (`email_verified` guard) + `dailyStorageCleanup` (storagePath ownership guard) updated live; Firestore rules (pendingDeletions guard) were already current (deploy was a no-op release). All confirmed live.
4. **GDPR subcollection orphans** — ✅ **DONE in code (2026-06-27, build green).** Account deletion Step 10 (`FirestoreManager+UserProfile.swift`) now recurses `holes → shots` under every game and practice via a new private `deleteHolesAndShots(under:)` helper (games switched from bulk batch to per-doc iteration). Client-side, so it ships with the next App Store build — no deploy. *(Per-game/practice `deleteGame`/`deletePractice` are soft deletes — parent retained, so no orphaning there; the gap was only the GDPR hard-delete path.)*
5. **Settings** — ✅ **DONE.** FCM preference-gate CFs deployed 2026-06-27; `AppStoreConstants.appStoreID` set to `6754497342` (Rate/Share rows now appear, review deep-links resolve). Ships next build.

> **Deploy note (2026-06-27):** the full deploy also *created* `auditCoachDowngrades` — it existed in code but had **never been deployed**, so the coach over-limit downgrade-audit cron backstop was not running until now. It is now live. No function deletions were needed (local source ⊇ all live functions).

## Tier 2 — The growth bet

6. **Video-first recruiting profile** — see "next needle mover" above. The most important *new* thing on the list. Was gated on "post-V2"; **V2 server side is now closed (2026-06-27), so this is unblocked** — the highest-value next code work.

## Tier 3 — Core UX that improves daily use / retention

7. **Dual-sport Person Card UX** — the two-row model ships, but "two sports = one person" stays confusing until linked profiles visually become one card. Finishing the headline feature already built. (Coach session picker `StartSessionSheet` still keys by `athleteUUID` and needs a sport sub-picker — see notes.)
8. **Coach-feedback-in-feed** — surface coach feedback in the athlete Home/Journal feed (the #1 deferred Journal item). Directly tied to the coach value prop you now charge for.
9. **Promote universal search to top-level** — `AdvancedSearchView` is buried on the Videos tab. High utility, low effort; add notes/season/athlete-name search.

## Tier 4 — Polish & platform (worth it, not ahead of the above)

10. **Celebration animation** — cheap, bounded, real brand value. Two low-frequency, high-meaning moments only: **highlight-reel-ready reveal** + **personal-best / record stamp**. One consistent, sport-aware motion language. Keep the Journal feed calm (don't undo scroll-perf work). Build small as an experiment, not a framework. *(Brand/hero animation is a later, self-contained follow-up using the same motion language.)*
11. **iPad coach tooling** — sidebar → split comparison → filmstrip → slow-mo. Valuable for the segment that now pays per seat, smaller audience than athletes.
12. **Live Activities + notification toggles** — engagement surface, not load-bearing.

## Tier 5 — Future bets & big refactors (important eventually, not urgent)

13. **Golf sport-abstraction refactor (~262 sites)** — real tech debt that slows every future sport feature, but invisible to users. Do it when it actively blocks you.
14. **Family/Fan viewer role** — strong long-term retention play, but a net-new audience; can wait.
15. **Multi-device dup-games / per-device quota, photo quota, scorecard-scan Phase 2, Strokes Gained v2** — edge cases and enhancements; pick up opportunistically.

---

**If you only touch three things next:** close out V2 (#1), confirm the security deploy (#3), then start the recruiting profile (#6). Protect revenue, protect trust, then swing at growth.

The bias to watch in this ranking: it's *strategic importance*, not *what's fun*. Tier 1 is tedious; Tier 2 is exciting. Discipline is doing Tier 1 first anyway.
