# PlayerPath — Product Overview

*What the app is, who it's for, and how the pieces fit together. Written for anyone new to the project — a collaborator, a contractor, a partner, or future-you. Last updated 2026-08-07 (app v6.5.0, build 215).*

For brand/creative direction (palette, type, tone) see [MARKETING_BRIEF.md](./MARKETING_BRIEF.md). For how it's built, see [architecture/ARCHITECTURE_OVERVIEW.md](./architecture/ARCHITECTURE_OVERVIEW.md).

---

## 1. The one-liner

**PlayerPath is an iOS app where a youth or high-school athlete records their games, gets real stats out of that video automatically, sends clips to their private coach for marked-up feedback, and ends up with a public recruiting page and a keepsake of their whole athletic career.**

It supports **baseball, softball, and golf** today, and it serves two distinct kinds of user — **athletes/families** and **private skills coaches** — each with their own tab bar, their own subscription ladder, and their own reason to open the app.

---

## 2. The problem it solves

A serious youth athlete's career is currently scattered across five places:

- Game video sits in the camera roll, thousands of untagged clips deep.
- Stats live in a team app the family doesn't control, or in a parent's spreadsheet, or nowhere.
- Private-lesson feedback happens verbally at the facility and evaporates by Tuesday.
- Photos are in a different camera roll folder.
- Recruiting material is a last-minute scramble in junior year — a hand-cut highlight video and a Google Doc.

None of those talk to each other, and none of them follow the athlete when they change teams, change coaches, or add a sport. PlayerPath's premise is that all of it is **one timeline that belongs to the athlete**, not to a team, a season, or an app the coach picked.

---

## 3. Who it's for

### Primary: youth & high-school athletes and their parents

In practice the account holder is very often **a parent**, and the app is built for that: one account can host multiple athlete profiles, so a family with two kids playing three sports between them is a first-class case, not a workaround.

The sweet spot is the family that has already decided to invest in the sport — travel ball, private lessons, tournament golf. They're spending money on instruction and time on video; they just have nowhere for it all to live.

**What they get:**
- Record at-bats, pitches, swings, or a full round in-app (or bulk-import from the camera roll).
- Tag each play once — single, strikeout, birdie — and the app derives the statistics.
- Batting, pitching (ERA/WHIP/IP), and golf scoring stats across games, seasons, and a career.
- A **Journal** home feed: every game, practice, clip, and photo in one timeline.
- Auto-generated highlight reels (birdie-or-better rounds bundle themselves automatically in golf).
- Milestones and season-over-season comparison.
- A **public recruiting profile** — a shareable, video-first page for college coaches.

### Secondary: private / skills coaches and small academies

A hitting coach, pitching coach, or golf instructor with a book of one-on-one students. Not a team manager.

**What they get:**
- Athlete clips arriving in a "Needs Review" queue.
- **Telestration** — draw on the video with a finger or Apple Pencil.
- **Drill cards** and lesson notes attached to specific clips.
- **Live sessions** that record clips straight into the athlete's folder during a lesson.
- A dashboard for their whole roster.

### Explicitly *not* the target

- **Team management.** No lineup cards, no team schedules, no parent broadcast messaging. Coach sharing is built for **private instruction**, and that boundary is deliberate — it's what keeps the product from becoming a worse GameChanger.
- **Team-level scorekeeping for spectators.** The unit of value is one athlete's development, not one game's box score.

---

## 4. The core loop

1. **Record** — film in-app, or import from Photos in bulk. Clips attach to a game, a practice, or nothing at all.
2. **Tag** — mark what happened. One tap per play in baseball/softball; per-hole (and opt-in shot-by-shot) in golf.
3. **Track** — tags feed the stats engine. No spreadsheet, no double entry.
4. **Review** — share a clip to a coach's folder; feedback comes back as telestration + notes + drills, and lands in the athlete's feed.
5. **Keep** — everything stays in the Journal, across seasons and years.
6. **Share** — highlight reels export out, and the recruiting profile publishes a public link.

Steps 1–3 are the habit. Step 4 is what a family will pay a coach for. Steps 5–6 are why they don't churn after the season ends.

---

## 5. Two structural ideas worth knowing

**Dual-sport people.** A kid who plays baseball in spring and golf in summer is modeled as **two athlete profiles linked by a shared `personGroupID`** — separate stats, separate seasons, separate sport-specific UI (the app's accent color even changes from terracotta to fairway green in golf), but **one subscription slot** and one person in every picker. Two sports should never cost twice.

**The recruiting profile.** An athlete can publish a public web page — hero highlight reel, a thin stat band, grad year, position, contact — behind an opt-in toggle with an unpublish kill switch. It's the app's growth bet: it changes the motivation from *"track my kid's stats"* to *"help my kid get seen,"* and every shared link carries PlayerPath branding to exactly the right audience. Publishing requires **Pro**; the editor and the unpublish switch deliberately do **not**, so nobody's live page can get stranded by a lapsed subscription.

---

## 6. How it makes money

Subscriptions, on **two separate ladders**.

**Athletes / families**

| | Free | Plus | Pro |
|---|---|---|---|
| Athlete profiles | 1 | 3 | 5 |
| Cloud storage | 2 GB | 25 GB | 100 GB |
| Monthly | — | $5.99 | $12.99 |
| Annual | — | $57.99 | $124.99 |

Plus unlocks auto-highlights, stats export, and season comparison. Pro adds the published recruiting profile and the largest storage tier.

**Coaches**

| | Free | Instructor | Pro Instructor | Academy |
|---|---|---|---|---|
| Athletes | 2 | 10 | 30 | Unlimited |
| Monthly | — | $9.99 | $19.99 | Contact us |
| Annual | — | $95.99 | $191.99 | Contact us |

Academy is granted manually — there is no StoreKit product for it.

**The key pricing decision (Pricing Model V2):** *coach sharing is not gated by the athlete's tier.* The **coach** pays per connection out of their seat count, so an athlete on the Free tier can still work with their instructor. This matters because the coach is the one with a business reason to pay, and because a paywall between a paying student and their paid coach is the fastest way to kill the loop that makes the product sticky. Athlete tiers therefore re-anchor on storage, multi-athlete, and the Plus/Pro feature set — not on access to coaching.

---

## 7. What it runs on

- **iOS 17+**, iPhone and iPad, native SwiftUI. Light appearance only — the cream background is the brand.
- **Local-first**: SwiftData on device, synced bidirectionally to **Firebase** (Firestore + Storage + Cloud Functions). The app works on the field with bad signal and reconciles later.
- Video uploads run through a background queue with retry, so a full game's footage survives a backgrounded app.
- The recruiting profile is served publicly by a Cloud Function — the only part of the product that lives outside the app.

---

## 8. The short version of "why this and not GameChanger"

GameChanger owns team scorekeeping and streaming, and PlayerPath does not try to take that. The wedge is everything GameChanger structurally can't do, because its unit is *the team's game* and PlayerPath's unit is *the athlete's development*:

- Data that follows the athlete across teams, coaches, seasons, and sports.
- The private-lesson feedback loop — telestration, drills, notes — as a native surface, not a bolt-on.
- Golf at all.
- A recruiting page the family controls and can publish on their own timeline.
- A keepsake framing that gives parents a reason to keep the account alive after the season, and after the sport.
