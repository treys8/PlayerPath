# Notifications Refactor — Deploy Runbook

Step-by-step instructions for shipping the server-as-single-writer refactor safely. Ordering is load-bearing — doing these out of order can break notifications for live users.

See [NOTIFICATIONS_ARCHITECTURE.md](./NOTIFICATIONS_ARCHITECTURE.md) for the design intent. This file is the operational checklist.

## Commits involved

In commit order, local `main`:

| SHA | Scope | Side |
|---|---|---|
| `f065571` | Invitation manager cleanup | iOS |
| `a77d36c` | FCM push for invitation_accepted + access_lapsed, foreground dedup | iOS + CFs |
| `40a960b` | Server CFs write feedback notifications (shadow mode) | CFs |
| `b7aa69e` | Server CFs centralize invitation + access-revoked | CFs |
| `66f7790` | Client switches to deterministic IDs | iOS |
| `85f3365` | Delete client postXxx writers | iOS |
| `18aff7e` | Tighten notifications/ security rules | rules |
| `a04b2e3` | Architecture doc | docs |
| `7c61db7` | Rule fix — allow empty senderID for upload_failed | rules |
| `295aa5f` | onInvitationAccepted fix — correct field + two-step handling | CFs |

## Deploy order

### Phase 1 — ship iOS first release (client aligns to deterministic IDs)

**What ships:** `f065571`, `a77d36c`, `66f7790` (already-live invitation cleanup + foreground dedup + deterministic-ID alignment).

**What does NOT ship yet:** `85f3365` (client writes deleted) — stays on local main until Phase 3.

**Steps:**
1. Check out the branch at `66f7790`: `git checkout 66f7790` (or tag it)
2. Bump build number: `./increment_build_number.sh`
3. Archive and upload via Xcode
4. Submit for App Store review
5. Wait for approval + release

**What users experience during this phase:**
- Behavior unchanged. Client writes notifications with matching deterministic IDs but there's nothing on the server side to collide with yet.

### Phase 2 — deploy Cloud Functions

**Only do this AFTER Phase 1 is live AND has meaningful user adoption** (e.g., 70%+ of weekly actives on the new version). Check in App Store Connect > Analytics > App Versions.

**Steps:**
```bash
cd firebase/functions
npm run build   # or npx tsc
firebase deploy --only functions
```

Deploys the full function set including the source-triggered CFs that write notifications.

**Verify after deploy:**
1. Open Firebase Console > Functions. Confirm all the following exist and are "healthy":
   - `onNewSharedVideo`, `onVideoPublished`, `onNewComment`, `onNewAnnotation`, `onCoachNoteUpdated`, `onNewDrillCard`
   - `onInvitationCreated`, `onInvitationAccepted`
   - `sendCoachAccessRevokedEmail` (extended)
   - `backfillInvitationsOnSignup` (updated)
   - `onAccessLapsedNotification` (kept — access_lapsed not yet source-migrated)
2. Open Firebase Console > Functions > Logs. Trigger a test notification from a test account (e.g., add a comment on a shared video). Confirm the relevant CF fires and writes to `notifications/{recipientID}/items/`.
3. Confirm the recipient's iOS app shows the notification in-app (listener picks up the Firestore write). FCM push should also deliver.

**What users experience during this phase:**
- Users on Phase 1 build: client and server both write notifications with matching deterministic IDs. `.create()` ensures one doc per event. No duplicates.
- Users on older pre-Phase-1 builds: client writes with auto-gen IDs, server writes with deterministic IDs. Two docs per event until user updates. Mildly annoying, not broken.

### Phase 3 — bake (~1 week)

**Purpose:** catch any CF bug before stripping client writes.

**What to watch for:**
- Users reporting missing notifications (especially via the support inbox)
- Firebase Console > Functions > Logs for errors or unexpected early returns
- Unusual volume of ALREADY_EXISTS warnings (expected during shadow mode) vs other errors
- Push delivery metrics (Crashlytics or your analytics) — any drop in FCM delivery

**Go/no-go checklist before Phase 4:**
- [ ] No spike in "missing notification" support tickets
- [ ] All CFs show normal execution counts
- [ ] A test user can send every notification type and see it deliver end-to-end
- [ ] No unresolved rule-rejection errors in logs

If any of these fail: investigate, fix forward on the server, don't rush to Phase 4.

### Phase 4 — ship iOS second release (delete client writes)

**What ships:** commit `85f3365`.

**Steps:**
1. `git checkout 85f3365` (or more recent)
2. Increment build number
3. Archive, upload, submit, release

**What users experience:**
- Users on new build: client no longer writes. Server CFs are sole authors.
- Users still on Phase 1 build: client continues writing, server continues writing, `.create()` dedupe handles the collision. Same behavior as Phase 2.
- Users on pre-Phase-1 builds: still get duplicates until they update.

### Phase 5 — tighten Firestore rules

**When:** after Phase 4 is live AND has meaningful adoption.

**What ships:** commits `18aff7e` + `7c61db7` (rule tightening + the senderID-empty fix).

```bash
firebase deploy --only firestore:rules
```

**What this does:** rejects client writes for server-owned notification types. Defense in depth against regressions.

**Risk if deployed too early:** clients still calling `postXxx` methods (on pre-Phase-4 iOS) would have those writes rejected by Firestore, breaking their notifications. Firebase rules deploy is instant and global — there's no staged rollout.

**Verify:** pick a test user on pre-Phase-4 iOS (e.g., TestFlight), trigger a notification-producing action, confirm the FCM arrives via the server CF (proving rule rejection of client writes doesn't matter because server handles it). Then trigger on a current-build user and confirm same.

## Rollback plan

### Cloud Functions rollback

If a CF has a bug that's corrupting notifications:

```bash
firebase functions:log --only <function-name>   # diagnose
# Fix the code locally
firebase deploy --only functions:<function-name>  # re-deploy just the broken one
```

If the issue is severe enough to need to revert the whole refactor:

```bash
git revert <commit-SHA>   # revert the offending commit
cd firebase/functions
firebase deploy --only functions
```

### iOS rollback

The App Store doesn't support rollback — you can only ship forward. Ensure Phase 1 and Phase 4 both have robust Phase-0 fallback:
- Phase 1 doesn't remove any functionality; users on this build still get notifications from their own client writes.
- Phase 4 depends on server CFs. If the server breaks after Phase 4 ships, hotfix the server (no client change required).

### Rules rollback

```bash
# Revert the rule commit and re-deploy
git revert 18aff7e 7c61db7
firebase deploy --only firestore:rules
```

## Troubleshooting

### "A user reports they stopped getting notifications"

1. Determine their iOS build version (support ticket, TestFlight logs).
2. Determine their user ID.
3. Check Firebase Console > Firestore > `notifications/{userID}/items/` — are docs being written?
4. If YES and they're not seeing them: it's a client listener problem (look at `ActivityNotificationService.attachListener` logs in the client's console).
5. If NO docs are being written: it's a CF problem. Check Functions logs for the relevant trigger around the time the event happened.
6. If the event was an action by ANOTHER user (e.g., coach commented): check that user's side for whether the source doc (comment/video/invitation) was written.

### "A user reports duplicate notifications"

1. Check which phase they're on.
2. If pre-Phase-1: expected during Phase 2 shadow mode. Will resolve when they update.
3. If on Phase 1 or Phase 4: should not happen. Check if the deterministic IDs are matching — open `notifications/{userID}/items/` and look for two docs for the same event with different IDs. If found, file a bug.

### "The security rules rejected a legitimate client write"

Likely an unmigrated notification type the client is trying to write. Check `firestore.rules` `allow create` on `notifications/{userID}/items/{itemID}`. The allowed client types are:
- `upload_failed` (self, senderID='')
- `access_revoked` self-authored upload-failed variant (self, senderID='')
- `access_revoked` / `access_lapsed` tier-change (senderID==auth.uid, targetType=folder, folder exists)

If you need to allow another type, prefer migrating it to a CF. If you must keep it client-side, update the rule AND document it in `NOTIFICATIONS_ARCHITECTURE.md`.

## Contacts

- Firebase project: (check .firebaserc)
- App Store Connect team: (your team)
- On-call rotation for notification issues: n/a (solo dev today)
