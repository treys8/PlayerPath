# Server-side `onDelete` user-data cleanup — Design

**Date:** 2026-06-29
**Status:** Approved (Approach B — lean `recursiveDelete`)

## Problem

`ComprehensiveAuthManager.deleteAccount()` deletes the Firebase Auth user **first**
(`user.delete()`), then runs the best-effort client purge `FirestoreManager.deleteUserProfile`
(13 steps). That ordering is deliberate — a stale-reauth abort destroys nothing — but it has a
sharp edge:

**Once `user.delete()` succeeds there is no authenticated session left to retry the cleanup.**
If the app is backgrounded, killed, or loses network after Auth deletion but partway through the
13 steps, the user's data orphans **permanently** with no client retry path. The client literally
cannot finish. A server trigger is the only actor that can.

Secondary gaps it closes:
- **Out-of-band deletions** (Firebase Console / single Admin `deleteUser()`) currently run *zero* cleanup.
- **GDPR completeness** — backs the "within 30 days" copy in `AccountDeletionView` with a server guarantee.

This is **defense-in-depth**, not a behavior fix. Email reuse after deletion already works
(Auth record is gone). This function only guarantees the *data* is gone too.

## Approach (B — lean `recursiveDelete`)

A gen-1 `functions.auth.user().onDelete` trigger (consistent with the existing
`backfillInvitationsOnSignup` `onCreate` trigger). It mirrors `deleteUserProfile`, but collapses
every owned **document tree** into a single `admin.firestore().recursiveDelete(ref)` call
(Admin SDK ≥10; project is on `firebase-admin ^12`), so only the **cross-user references** and
**storage prefixes** are hand-written.

`recursiveDelete(users/{uid})` removes the profile doc and *all* descendant subcollections at any
depth — athletes→coaches, seasons, games→holes→shots, practices→notes — replacing the entire
manual bottom-up recursion in client Step 10 (and the `deleteHolesAndShots` helper) with one call.

### Steps (each wrapped in its own try/catch; errors collected and logged, never thrown — a
single failing step must not abort the rest)

1. **User tree** — `recursiveDelete(users/{uid})`. Covers profile + all subcollections incl. golf holes/shots.
2. **Owned shared folders** — query `sharedFolders where ownerAthleteID == uid`; for each, delete its
   `videos` (query `videos where sharedFolderID == folderID`, `recursiveDelete` each to drop
   annotations/comments/drillCards subcollections), then `recursiveDelete` the folder.
3. **Coach membership on others' folders** — `sharedFolders where sharedWithCoachIDs array-contains uid`:
   `arrayRemove(uid)` + delete `sharedWithCoachNames.{uid}` / `permissions.{uid}` + bump `updatedAt`.
   (Matches client Step 7. Removal-only, consistent with the rules invariant.)
4. **Authored content across all videos** — `collectionGroup` deletes:
   `annotations where userID == uid`, `comments where authorId == uid`, `drillCards where coachID == uid`.
5. **Coach sessions** — `coachSessions where coachID == uid`.
6. **Coach templates** — `recursiveDelete(coachTemplates/{uid})` (parent doc + `quickCues` subcollection).
7. **Notifications** — `recursiveDelete(notifications/{uid})` (parent doc + `items` subcollection).
8. **Invitations** — delete `invitations where athleteID == uid`, `where coachID == uid`, and (if email
   known) `where coachEmail == email` / `where athleteEmail == email` (GDPR right-to-erasure; matches client Step 4b).
9. **Access revocations** — `coach_access_revocations where athleteID == uid` and `where coachID == uid`.
10. **Orphan uploaded videos** — `videos where uploadedBy == uid` → set `isOrphaned: true`, `orphanedAt`.
    **Mark, do not delete** (these live in *other* users' folders — identical to client Step 8).
11. **Photos** — delete `photos where uploadedBy == uid`.
12. **pendingDeletions** — delete `pendingDeletions where ownerUID == uid`.
13. **Storage** — `bucket.deleteFiles({ prefix: 'athlete_videos/<uid>/' })` and `athlete_photos/<uid>/`.
    404-tolerant; same prefixes the client/cron use.

### Implementation notes

- **Batching:** collectionGroup / equality-query steps page in batches (≤400) and `BulkWriter`/batch-commit,
  matching the existing cron style. `recursiveDelete` handles its own throttling.
- **Idempotency / race with client:** the trigger fires immediately after `user.delete()`, so it may run
  *concurrently* with the client's own `deleteUserProfile`. Every operation is idempotent (deletes tolerate
  already-gone docs, `arrayRemove` is a no-op, orphan-marking is set-to-constant), so a double run is
  harmless — whichever finishes wins, and the trigger completes whatever the client didn't.
- **Trigger coverage caveat:** gen-1 `auth.onDelete` fires for client `user.delete()`, Console deletes, and
  single Admin `deleteUser()` — **not** bulk `deleteUsers()`. Acceptable; app never bulk-deletes.
- **No deploy in this change.** Deploys are the user's call.

## Out of scope

- Pre-delete `pendingAccountDeletions` marker + scheduled sweep (Approach C). Not chosen; the `onDelete`
  trigger covers the crash-mid-deletion case directly. Can be added later if trigger reliability proves insufficient.
- Refactoring the client `deleteUserProfile`. It stays as the primary path; this is a backstop.

## File touched

`firebase/functions/src/index.ts` — new exported function `cleanupUserDataOnDelete`.
