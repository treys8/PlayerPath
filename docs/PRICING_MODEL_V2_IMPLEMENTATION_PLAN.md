# Pricing Model V2 — Implementation Plan

*Drafted 2026-06-11 from full server + client investigations. Companion to `PRICING_MODEL_V2_PROPOSAL.md` (the why).*

**STATUS: SHIPPED** — all phases below were deployed (server) and committed (client) by June 2026 (app v6.1.2). The per-phase notes are the original 2026-06-11 working snapshot, kept for detail.

**Status 2026-06-11:** Phase 0 script written (`firebase/functions/scripts/restore-lapsed-coach-access.js`, dry-run default, `--apply` to write) — NOT yet run (needs service-account creds or a console check showing zero `reason=='lapse'` docs). Phase 1 code COMPLETE (tsc green) — NOT yet deployed. Also removed `onAccessLapsedNotification` (dead once the lapse pipeline was gone). **Phase 2 + most of Phase 3 code COMPLETE** — all client gates removed (see below), paywall "Coach Sharing" row + Pro context message removed, `AthleteDowngradeManager.swift` DELETED (zero callers), `hasCoachingAccess` property deleted from `ComprehensiveAuthManager`, `proRequired()` modifier kept but now unused, permission-denied→"Pro required" error mapping replaced with generic authorization error, stale "requires Pro" copy fixed (DeepLinkHandler accept sheet, grace-period comment, dead ProfileView premium alert deleted). Beyond the original list, the `hasCoachingAccess` param threading through VideoClipCard/VideoClipRow/PracticeVideoClipRow/HighlightsView (lock-icon variants) was also removed. **Phase 4 COMPLETE (build green):** CoachSeatsPage inserted as onboarding page 3 (4-page flow, `seats_explained` step analytics, pending-invites-hold-seats called out); InviteAthleteSheet header shows live seat status ("Uses 1 of your N seats (X in use) — free for them", Academy/Int.max handled); CoachInvitationCard shows "{coach}'s plan covers this — free for you"; CoachPaywallView subtitle = "your athletes never pay"; new `coach_invitation_accepted` event + `acquisition_source=coach_invited` user property stamped in AthleteInvitationManager.acceptInvitation. Post-review fixes: dead `proRequired()` modifier + DeepLinkHandler dead paywall sheet removed; paywall table got a "Coach Sharing ✓✓✓ (all tiers)" row so the free loop is visible; CoachReadyPage "timestamped notes" copy fixed to plain notes.

**Run order:** (1) dry-run the Phase 0 script → review output → `--apply`; (2) `firebase deploy --only functions,firestore:rules` (confirms deletion of 2 removed function exports); (3) ship the client release (Phases 2–4 together); (4) bump build + device test: free athlete invites coach → coach accepts → share video → coach feedback lands.

**The change in one line:** coach connections are paid for by the coach's seat, never the athlete's tier. Athlete tiers re-anchor on storage + highlights + multi-athlete. Stats stay free everywhere.

**Confirmed by investigation (no work needed):**
- Coach slot enforcement already keys off coach tier server-side (`acceptAthleteToCoachInvitation`, `acceptCoachToAthleteInvitation`, `enforceCoachAthleteLimit`) — untouched.
- Coach-session clips already count against the **coach's** storage quota (`enforceStorageQuota` sums by `uploadedBy` UID, index.ts:3009) — the "your students never pay" promise needs zero storage work.
- Win-back flow (`WinBackSheet.swift`) never mentions coach sharing — no change.
- `SubscriptionModels.swift` has no coach-sharing feature flag — no change.
- Manual coach removal + coach-downgrade revocation flows are cleanly separated from the lapse pipeline by the `reason` field on `coach_access_revocations` — they survive intact.

---

## Phase 0 — Pre-deploy migration (MUST run before Phase 1)

Athletes currently mid-lapse (Pro lapsed → coach access revoked, `reason: 'lapse'` docs exist) would be **stranded forever** once the restore function is deleted. Restore them first — it's also a nice launch moment: those families get their coach back as the new model's first act.

1. One-time admin script: for every `coach_access_revocations` doc with `reason == 'lapse'`, run the existing restore logic (`restoreCoachAccessForResubscribedAthlete`, index.ts:3684+) — re-add coach to `sharedFolders.sharedWithCoachIDs`/`permissions`/`sharedWithCoachNames`, delete the revocation doc, recompute `coachAthleteCount`.
2. Respect the existing coach-limit guard (`computeCoachConnectionKeys` check at :3783). Coaches at limit → keep doc with `restoreDeferred` and surface nothing new (acceptable residue; see Phase 1 note).
3. Verify zero `reason == 'lapse'` docs remain (minus deferred ones) before deploying Phase 1.

## Phase 1 — Server (deploy BEFORE client ships)

Deploy order matters: server first. Old clients keep their client-side gates (harmlessly over-restrictive) while the server already allows; new clients then remove the gates.

### Cloud Functions (`firebase/functions/src/index.ts`)

**Remove entirely:**
- `syncCoachAccessOnAthleteTierChange` (:3573–3593) — the onUpdate trigger detecting Pro↔non-Pro
- `revokeCoachAccessForLapsedAthlete` (:3595–3682)
- `restoreCoachAccessForResubscribedAthlete` (:3684–3855) — only after Phase 0 ran

**Modify:**
- `sendCoachAccessRevokedEmail` (:1800–1937): remove the `reason === 'lapse'` branches (special email copy :1861–1870, notification phrasing :1906–1910). Keep: no-reason (manual removal) and `'downgrade'` (skip-email) paths, and the `coachAthleteCount` recompute.
- `acceptAthleteToCoachInvitation`: remove the inviting-athlete Pro check (:2181–2195). Keep the coach-limit transaction.
- `acceptCoachToAthleteInvitation`: remove the athlete Pro check (:2444–2458). Keep the coach-limit transaction.

**Note:** `appStoreServerNotifications` needs no logic change — writing `subscriptionTier = 'free'` simply no longer triggers anything coach-related.

**Residue policy:** any `restoreDeferred` lapse docs left by Phase 0 will block `canAccessFolder` for that folder+coach pair until the pair re-invites (accept paths delete the doc, :2300–2302). Acceptable; optionally batch-delete them and let the coach re-invite when they have room.

### `firestore.rules`

Remove three athlete-Pro gates (keep the `hasProTier()` helper itself — :24–27):
- `sharedFolders` create: drop `hasProTier()` (:338)
- `videos` create, folder-owner branch: drop `hasProTier()` (:390) — coach branch keeps `hasCoachTier()`
- `invitations` create, `athlete_to_coach`: drop `hasProTier()` (:809); update the design comment (:788–809)

**Keep every `hasCoachTier()` check unchanged.**

### Verify after deploy
- Free athlete sends coach invite → coach accepts → connection works, `coachAthleteCount` increments.
- Coach at limit still blocked from accepting (limit transaction intact).
- Athlete manual coach removal still sends email + cleans invites (no-reason path).
- Coach-downgrade shedding unchanged.
- Tier lapse on a connected athlete → **nothing happens** to coach access.

## Phase 2 — Client gate removal (iOS)

Central gate: `ComprehensiveAuthManager.hasCoachingAccess` (`currentTier >= .pro`, ComprehensiveAuthManager.swift:119). **Keep the property** (avoid touching unrelated call sites in one pass); remove its coach-sharing *uses*:

| File | Lines | Change |
|---|---|---|
| `Views/Coaches/ShareToCoachFolderView.swift` | :40, :88, :95–142 | Delete `unauthorizedState` + paywall-on-dismiss; always show folder picker |
| `Views/Coaches/InviteCoachSheet.swift` | :254–255, :287–289 | Delete gate + `coachingRequired` error path |
| `Views/Coaches/PendingCoachInvitationsView.swift` | :57–61, :136–152, :230–240 | Accept goes straight through; delete paywall sheet + `resumeAfterPaywall()` |
| `FirestoreManager+Invitations.swift` | :524 area | Remove the permission-denied → "Pro subscription required" error mapping (server no longer throws it; mislabels other permission errors) + the matching `proRequired` copy in `AthleteInvitationManager` |
| `CoachesView.swift` | :64–70, :89–118, :186–192 | "Invite a Coach" always visible; delete paywall trigger paths (sheet can stay if unreferenced→delete) |
| `AthleteFoldersListView.swift` | :188–208, :525, :542 | Delete "Coach Access Paused" banner + content gates |
| `SharedFolderManager.swift` | :62–63 | Delete `hasCoachingAccess` + `effectiveAthleteTier >= .pro` guards on folder creation |
| `ProfileView.swift` | :324, :337 | Remove gate + upgrade-prompt else-branch |
| `VideoPlayerView.swift` | :155 | Always show "Share to Coach Folder" (drop lock icon variant) |
| `DeepLinkHandler.swift` | :303 | Remove `hasCoachingAccess` guard on shared-folder deep link |

**Deprecate:** `Services/AthleteDowngradeManager.swift` — becomes dead code (its only UI, the paused banner, is deleted). Stop calling `evaluate()` from tier-change flows; delete the file in a later cleanup.

## Phase 3 — Paywall re-anchor (iOS)

- `ImprovedPaywallView.swift:169` — delete `case .pro: "Connecting with a coach requires Pro"`.
- `ImprovedPaywallView.swift:293–299` — delete the "Coach Sharing" row from the tier table.
- Re-anchor copy on the real drivers: storage, highlight reels (share/export), stats export + season comparison, multi-athlete. Headline keeps the journal framing.
- Audit remaining `paywallShown` sources so none fire from a coach flow.

## Phase 4 — Seats explainer + invite-moment messaging (iOS)

Design constraints: Calm Keepsake — cream surfaces, ONE accent (coach flows stay base terracotta), `Theme`/`DesignTokens` colors only. ⚠️ The investigator's draft snippet uses `Color.brandNavy` (removed in the seasons pass) and multi-color step icons (green/blue) — **do not copy verbatim**; use `Theme` tokens + single accent.

1. **`CoachOnboardingFlow.swift`** — insert a "How Seats Work" page between How-It-Works and Ready: `totalPages` 3→4 (:24), `coachStepNames` += `"seats_explained"` (:26), retag pages. Content: native SwiftUI seat diagram — (1) Your plan includes athlete seats; (2) Each seat = one student — *a pending invite holds a seat too* (preempts the known "limit reached" confusion); (3) "Your athletes pay nothing" — your clips, telestration, and drill cards reach them free.
2. **`InviteAthleteSheet`** — one compact line at send: "Uses 1 of your N seats — free for them." Reuse live seat counts from `CoachInvitationManager.pendingSentCount` + roster.
3. **`CoachLimitPaywallSheet`** — same seat visual, full state; frame upgrade as "more seats."
4. **Athlete side mirror** — invitation banner/accept sheet (`AthleteInvitationsBanner`, `PendingCoachInvitationsView`): "Coach {name}'s plan covers your connection — free for you."
5. **Analytics** — add `trackCoachInvitationAccepted(coachID:)` and an `acquisition_source: coach_invited | organic` user property set at accept; this powers the connected-family conversion sensitivity in the proposal doc.

## Sequencing & risk

1. Phase 0 (migration run) → 2. Phase 1 (deploy CFs + rules together) → 3. Phases 2–4 in one client release → 4. bump build, device test.
- **Riskiest step:** Phase 1 lapse-pipeline removal — isolated functions, but verify the manual-removal and downgrade flows on device/emulator after deploy (they share `sendCoachAccessRevokedEmail` and the revocations collection).
- **Old-client window:** between server deploy and app update, existing clients still show Pro gates on coach sharing. Harmless (over-restrictive, nothing breaks); keep the window short.
- **Revenue cannibalization:** current Pro subscribers who only wanted coach sharing lose their reason to pay — accepted trade per the proposal; user count is small enough that the channel unblocked is worth far more.
- No SwiftData schema change. No StoreKit product change. tsc + iOS builds must stay green per phase.
