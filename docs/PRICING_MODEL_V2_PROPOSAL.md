# PlayerPath Pricing Model V2 — Proposal

*Drafted 2026-06-11. Companion to the instructor-channel growth strategy. Status: PROPOSAL — nothing implemented.*

---

## 1. The One Structural Rule

> **A coach connection is paid for by the coach's seat, never by the athlete's tier.**

Regardless of who initiates the invite, the gate is "does this coach have an open athlete slot?" — never "is this athlete on Pro?" The coach's subscription covers the link for every student on their roster. Athletes monetize on storage, highlights, and multi-athlete — the things filming families consume anyway.

**Why:** This is how CoachNow and OnForm seeded both sides. An instructor with 10 students can adopt PlayerPath in one afternoon with zero buy-in from 10 families. Under the current model (athlete needs Pro $12.99/mo for coach sharing), that same instructor must convince 10 families to spend $125/yr each before the relationship works — the channel sells *against* us.

---

## 2. The Ladders

### Athlete / Family

| | Free | Plus $5.99/mo · $57.99/yr | Pro $12.99/mo · $124.99/yr |
|---|---|---|---|
| Athlete profiles | 1 | 3 | 5 |
| Cloud storage | 2 GB | 25 GB | 100 GB |
| Record, tag, **full stats** | ✓ | ✓ | ✓ |
| Coach connection | ✓ *(via coach's seat)* | ✓ | ✓ |
| Auto-highlight reels — view/share/export | previews only | ✓ | ✓ |
| Stats export, season comparison | — | ✓ | ✓ |

**Changes from today:** coach sharing leaves Pro (moves to "free, when your coach has a seat"); everything else stays. Stats remain fully free at every tier — they are the *"might as well tag it while you're in here"* habit mechanic that fills storage and generates highlight material. We gate **outputs** (sharing the reel, exporting the season), never the record-keeping behavior itself.

**Upgrade drivers, in order:**
1. **Storage** — a filming family burns 2 GB in a few weeks of games. The paywall moment is organic: "you're out of room mid-tagging." (Google Photos model: the free tier is a fuse, not a product.)
2. **Highlights** — the post-event banner ("found 3 highlights from today's game") shows free users the reel exists; sharing it costs $5.99. Already built.
3. **Multi-athlete** — second kid starts playing → Plus.

### Coach / Instructor

| | Free | Instructor $9.99/mo · $95.99/yr | Pro Instructor $19.99/mo · $191.99/yr | Academy |
|---|---|---|---|---|
| Athlete slots | 2 | 10 | 30 | Unlimited |
| Telestration, drill cards, sessions | ✓ | ✓ | ✓ | ✓ |
| Students' coach connection | **free for the student** | free | free | free |

**Changes from today:** prices and slots unchanged (the undercut vs. OnForm $19.99-capped / CoachNow $49.99 / V1 ~$69 *is* the wedge). What changes is the meaning of a slot and the pitch:

> **"$9.99 a month. Ten students. They never pay a dime."**

**Supporting rule:** coach-session clips do **not** count against the *student's* storage quota (charge to a generous coach-tier allowance instead). Otherwise the coach's own lessons push free-tier students into a paywall and break the promise above.

### Flow at a glance

```
 INSTRUCTOR (pays $9.99–19.99/mo)
      │  invites student → FREE connection (uses a coach slot)
      ▼
 FAMILY (enters free)
      │  films games on their own → tags plays → stats accrue (free, always)
      │  storage fills / highlight banner fires
      ▼
 FAMILY converts to Plus/Pro (storage + highlights + 2nd kid)
      │  word of mouth in dugout / team chat
      ▼
 MORE FAMILIES (organic, free) → some pay → some bring THEIR instructor in
```

---

## 3. Use Cases (the personas behind the projection)

**UC-1 · The Hitting Instructor — "Marco," 12 students, lessons 2×/wk each.**
Today on CoachNow at $499/yr or juggling iMessage videos. Joins free (2 slots), runs 2 students for a month, upgrades to Instructor ($96/yr) to bring the rest. His 12 families all get the app free. *Revenue: $96/yr + downstream family conversions. The channel unit.*

**UC-2 · The Instructor-Connected Family — "the Nguyens," son takes lessons with Marco.**
Enter free via Marco's invite. They were already filming games on a phone; now they tag because the stats "might as well" happen. Storage fills in ~6 weeks of tournament play; the highlight banner fires after a 3-hit game. Convert to **Plus**. *Highest-converting segment — pre-sorted for willingness to pay (already spending ~$183/yr-equivalent on lessons, Project Play 2025 line item).*

**UC-3 · The Aggrieved Scorekeeper Parent — "Dana," travel-ball mom.**
Organic App Store / word-of-mouth entry. Furious that the team scorekeeper ruled a line drive an error. PlayerPath is *her* book: every stat with the video receipt. Tags religiously, hits the storage wall, converts to **Plus**. No coach involved. *Marketing voice for this segment: "The scorebook is the team's story. PlayerPath is your kid's — every stat, with the video to prove it."*

**UC-4 · The Two-Sport / Two-Kid Family — "the Parkers," daughter (softball) + son (golf).**
Need 2+ profiles + heavy storage → **Pro** ($125/yr). Junior golf combo (video + scorecards + instructor annotation) has **no competitor** — this segment has nowhere else to go.

**UC-5 · The Golf Pro — "Coach Ellis," teaching pro at a range, 25 juniors.**
On V1 (~$590/yr) or CoachNow (~$499/yr); annoyed by the Golf Genius integration churn. **Pro Instructor** ($192/yr) — still a 60%+ cost cut — and 25 junior families enter free. *Wave-two channel (after baseball/softball), timed to competitor churn windows.*

**UC-6 · The Casual Filming Parent — "Sam," rec-league, films sometimes.**
Organic entry. Free tier covers the use case for a long time; converts rarely (storage, eventually, maybe). *Huge population, weak urgency — this is the year-two market reached by word of mouth, NOT the acquisition target. Do not spend ad dollars here.*

**UC-7 · The Academy — facility with 4 instructors, 80+ students.**
Manually-granted Academy tier (Firestore, no StoreKit product — unchanged). Negotiated annual. *One relationship = dozens of channel units. Pursue after the single-instructor motion is proven.*

---

## 4. Revenue Projection — 12-Month Scenarios

### Unit economics (the numbers that matter)

**Per paying coach acquired (the channel unit):**

| Component | Assumption | Value |
|---|---|---|
| Coach subscription (blended Instructor/Pro Instructor mix ~80/20) | $96–192/yr | **~$115/yr** |
| Connected families per paying coach | avg roster | ~10 |
| Connected-family → Plus conversion | UC-2 segment, 12 mo | 15% |
| Connected-family → Pro conversion | multi-kid subset | 3% |
| Downstream family revenue | 10 × (.15×$58 + .03×$125) | **~$125/yr** |
| **Total per coach unit** | | **~$240/yr ARR** |

**Organic (non-connected) free users:** Plus conversion 4%, Pro 1% (UC-3 converts well; UC-6 barely — blended).

> Every assumption above is a guess to be replaced by your own analytics within 90 days. The structure of the model matters more than the numbers in v1.

### Scenarios (ARR at month 12, gross — Apple's 15% small-business cut not yet deducted)

| | **Conservative** | **Base** | **Optimistic** |
|---|---|---|---|
| Paying coaches | 25 | 100 | 300 |
| → Coach revenue | $2,900 | $11,500 | $34,500 |
| Connected families (≈10×) | 250 | 1,000 | 3,000 |
| → Plus (15%) × $58 | $2,200 | $8,700 | $26,100 |
| → Pro (3%) × $125 | $900 | $3,800 | $11,300 |
| Organic free users | 2,000 | 6,000 | 20,000 |
| → Plus (4%) × $58 | $4,600 | $13,900 | $46,400 |
| → Pro (1%) × $125 | $2,500 | $7,500 | $25,000 |
| **Gross ARR** | **~$13k** | **~$45k** | **~$143k** |
| **Net of Apple 15%** | ~$11k | ~$38k | ~$122k |

**What each scenario requires:**
- **Conservative** = the founding-instructor motion works modestly: ~2 new paying coaches/month after a slow start, minimal organic growth. Essentially "the channel exists."
- **Base** = the motion is repeatable: ~8–9 new paying coaches/month by mid-year (referrals between instructors at the same facilities), organic growth riding word of mouth from connected families. This is the "pour fuel on it" threshold.
- **Optimistic** = facility/academy deals land (UC-7), one sport's instructor community word-of-mouth tips, organic compounds. Not plannable — earned.

### Sensitivities (in order of leverage)

1. **Connected-family Plus conversion (15%)** — the single most important number. At 8% the coach unit drops to ~$165; at 25% it's ~$330. *Instrument this from day one* (`paywallShown` source attribution: coach-invited vs organic).
2. **Coaches acquired** — pure founder-hours at first. 10 founding instructors (free year) seed it; the projection counts only *paying* coaches.
3. **Roster size per coach (10)** — Instructor tier caps at 10; coaches who fill it and upgrade to Pro Instructor (30) double their unit value. Watch fill rates.
4. **Free→paid storage fuse timing** — if 2 GB lasts 6 months, conversions lag badly. If it's too tight, free users churn before habit forms. Tune with data; consider 5 GB if week-4 retention suffers.
5. **Churn (not modeled in v1)** — keepsake/journal framing is the retention bet; multi-season data is the lock-in. Model after 6 months of cohort data.

### What this is NOT
- Not a venture case — it's a solo-dev ramp to meaningful revenue with near-zero CAC (founder outreach replaces ad spend).
- Year-2 upside not modeled: Academy deals, the casual-parent market (UC-6) arriving via word of mouth, golf wave, recruiting-export features, coach web portal as a paid add-on.

---

## 5. Implementation Blast Radius (summary)

StoreKit products are **unchanged** — only gates and copy move.

| Area | Change |
|---|---|
| `SubscriptionGateService` | Remove athlete-Pro gate on coach sharing; gate = coach slot availability (CFs already enforce: `acceptAthleteToCoachInvitation`, `acceptCoachToAthleteInvitation`, `enforceCoachAthleteLimit`) |
| **Athlete Pro-lapse revocation pipeline** | ⚠️ Must be **inverted** — deployed server logic revokes coach access on athlete Pro lapse + restores on re-subscribe. Under V2, coach access keys off the *coach's* tier only. Most delicate piece: CFs + `firestore.rules` + restore path + `AthleteDowngradeManager`. |
| `firestore.rules` | Review every athlete-tier check gating folder/video access; `hasCoachTier()` unchanged |
| Storage quota | Coach-session clips → coach-tier allowance, not student quota |
| Paywalls (`ImprovedPaywallView`, `CoachPaywallView`) | Athlete: re-anchor on storage + highlights. Coach: "your students never pay" pitch. Remove all "upgrade to Pro to share with your coach" surfaces |
| Win-back flows | Update Pro win-back reasons (coach sharing no longer a Pro feature) |
| Analytics | Add invite-source attribution (coach-invited vs organic) to conversion events — required for the sensitivity table above |

**Sequencing:** ship this *before* founding-instructor outreach. The first 10 instructors will immediately exercise the invite→free-family path; it must be the smoothest flow in the app.
