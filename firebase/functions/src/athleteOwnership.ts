/**
 * Athlete-UUID ownership claims — the resource-authorization layer under
 * `recruitingProfiles`.
 *
 * ## The gap this closes
 *
 * `recruitingProfiles/{athleteID}` is keyed by the athlete's canonical UUID, and
 * firestore.rules could never prove that UUID belongs to the caller: athlete docs
 * are created with `addDocument` (auto-IDs) and the UUID lives only in the `id`
 * FIELD, so `exists(/users/$(uid)/athletes/$(athleteID))` matches nothing and
 * rules cannot query by field. Every gate on the publish path therefore
 * authorized the *token* and the *media paths* but never the *athlete*.
 *
 * A `subscriptionTier == "pro"` account that knew a victim's UUID — every
 * connected coach does; it is `sharedFolders.athleteUUID` — could claim a share
 * token for it and create `recruitingProfiles/{victimUUID}` first. After that the
 * real owner is locked out permanently: create is denied (the doc exists), update
 * is denied (`userId` is frozen to the attacker), and even READ is denied, so
 * `publish()`'s pre-read throws and the family gets an unactionable error forever.
 * DoS only — no data leaks — but it needs console surgery to undo.
 *
 * ## The shape
 *
 * `athleteOwners/{athleteUUID} → { userId }`, written ONLY by the Admin SDK from
 * this module, which is what makes it authoritative: the claim can be minted only
 * by code that has seen the athlete doc living under that uid. Clients cannot
 * create, update or delete it (firestore.rules denies the collection outright —
 * rule-internal `get()`/`exists()` bypass read rules, so nothing is lost).
 *
 * Rules then require `ownsAthlete(athleteID)` on `recruitingProfiles` CREATE and
 * `recruitingTokens` CREATE. Deliberately NOT on update: update is how unpublish
 * works, and a kill switch that a missed claim can disable is the same failure
 * class as paywalling one.
 */

import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

/** Where the claims live. */
const OWNERS = 'athleteOwners';

/**
 * The athlete `id` field is client-written, and it is about to become a document
 * ID. An unvalidated value is a path-injection: `.doc('a/b')` addresses a
 * subcollection, and '.'/'..' are reserved. Only a canonical UUID is ever
 * legitimate here (`Athlete.id.uuidString`), so anything else is dropped rather
 * than sanitized — there is no correct claim to write for a malformed UUID.
 */
const UUID_RE = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

function validUUID(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  return UUID_RE.test(trimmed) ? trimmed : null;
}

/** gRPC status for "document already exists" — the ONLY expected create failure. */
const ALREADY_EXISTS = 6;

/**
 * Writes the claim if it is unheld. `create()` (not `set()`) so the first writer
 * wins atomically and a conflict is observable rather than silently overwritten.
 *
 * Returns what happened, for the backfill's counters. `'error'` is distinct from
 * `'held'` on purpose: a transient failure that reported success-ish would let
 * the backfill mark itself complete over athletes it never claimed, and the rules
 * deploy is gated on exactly that verdict — the athlete would silently lose the
 * ability to publish.
 */
async function claim(
  db: FirebaseFirestore.Firestore,
  athleteUUID: string,
  userId: string
): Promise<'claimed' | 'held' | 'conflict' | 'error'> {
  const ref = db.collection(OWNERS).doc(athleteUUID);
  try {
    await ref.create({
      userId,
      athleteId: athleteUUID,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return 'claimed';
  } catch (err) {
    if ((err as { code?: number })?.code !== ALREADY_EXISTS) {
      console.error(`athleteOwners: claim failed for ${athleteUUID} (${userId})`, err);
      return 'error';
    }
    // ALREADY_EXISTS is the normal steady state — every athlete write after the
    // first re-reaches this path. Only a claim held by a DIFFERENT account is
    // worth reporting: that is either a squat that predates this module or a UUID
    // collision, and both need a human.
    try {
      const existing = await ref.get();
      const holder = existing.exists ? existing.data()?.userId : null;
      if (holder && holder !== userId) {
        console.error(
          `athleteOwners CONFLICT: ${athleteUUID} is held by ${holder}, but the athlete doc lives under ${userId}`
        );
        return 'conflict';
      }
      return 'held';
    } catch (readErr) {
      // The write said the doc exists but we can't see who holds it. Unknown is
      // not "fine" — surface it rather than counting a clean hold.
      console.error(`athleteOwners: could not read existing claim ${athleteUUID}`, readErr);
      return 'error';
    }
  }
}

/**
 * Claims the UUID of every athlete doc as it is written.
 *
 * `onWrite`, not `onCreate`: the reconciliation paths in
 * `SyncCoordinator+Athletes.downloadRemoteAthletes` can rewrite `id` on an
 * EXISTING doc (reinstall / second-device drift recovery), and an onCreate-only
 * trigger would leave that new UUID unclaimed and unpublishable. The
 * `before.id === after.id` guard means the common case — a version bump on a
 * dirty sync — costs no reads at all.
 *
 * Deletes never release a claim. A released UUID is a re-claimable UUID, and the
 * whole point is that this binding is permanent.
 */
export const claimAthleteOwnership = functions.firestore
  .document('users/{userId}/athletes/{athleteDocId}')
  .onWrite(async (change, context) => {
    if (!change.after.exists) return;

    const after = change.after.data() ?? {};
    const before = change.before.exists ? change.before.data() ?? {} : null;
    if (before && before.id === after.id) return;

    const athleteUUID = validUUID(after.id);
    if (!athleteUUID) {
      // Not an error worth alerting on: legacy docs and partial writes exist.
      console.warn(
        `claimAthleteOwnership: skipping ${change.after.ref.path} — id is not a UUID`
      );
      return;
    }

    await claim(admin.firestore(), athleteUUID, context.params.userId as string);
  });

/** Marker doc: makes the backfill idempotent and resumable. */
const MARKER = 'appConfig/athleteOwnersBackfill';
/** Stop this far into the 540 s budget and resume on the next tick. */
const DEADLINE_MS = 480 * 1000;
const PAGE = 500;

/**
 * One-time sweep that claims every athlete that existed before the trigger
 * shipped, plus an audit pass that reports pre-existing squats.
 *
 * **This is load-bearing, not a convenience.** Clients already in the field know
 * nothing about `athleteOwners`; if the rules start requiring a claim before every
 * existing athlete has one, every installed app loses the ability to publish. The
 * rules deploy MUST wait for `completedAt` on the marker doc.
 *
 * A scheduled function rather than a callable or an admin HTTP route: a one-shot
 * needs authorization, and the alternatives are hardcoding a uid, exposing a
 * secret on a public route, or running the Admin SDK locally with a service-account
 * key. A marker-guarded schedule needs none of them. DELETE THIS FUNCTION in a
 * follow-up deploy once the log reports a clean completion.
 */
export const backfillAthleteOwners = functions
  .runWith({ timeoutSeconds: 540 })
  .pubsub.schedule('every 5 minutes')
  .onRun(async () => {
    const db = admin.firestore();
    const markerRef = db.doc(MARKER);
    const marker = await markerRef.get();
    if (marker.exists && marker.data()?.completedAt) return null;

    const started = Date.now();
    let cursorPath: string | null = (marker.data()?.cursorPath as string) ?? null;
    let claimed = (marker.data()?.claimed as number) ?? 0;
    let held = (marker.data()?.held as number) ?? 0;
    let conflicts = (marker.data()?.conflicts as number) ?? 0;
    let skipped = (marker.data()?.skipped as number) ?? 0;
    let errors = (marker.data()?.errors as number) ?? 0;

    // Ordered by __name__ so the cursor is stable across runs. A collection-group
    // query is what reaches every user's athletes without listing users first;
    // the owner uid is the grandparent document's ID.
    for (;;) {
      let q = db.collectionGroup('athletes').orderBy(admin.firestore.FieldPath.documentId()).limit(PAGE);
      if (cursorPath) q = q.startAfter(db.doc(cursorPath));

      const snap = await q.get();
      if (snap.empty) {
        // A sweep that hit write errors has NOT covered every athlete, and
        // stamping completedAt would green-light the rules deploy over the gap.
        // Leave the marker unstamped so the next tick resumes from the cursor.
        if (errors > 0) {
          console.error(
            `backfillAthleteOwners: reached the end with ${errors} failed claims — NOT marking complete, DO NOT deploy rules. Retrying from the start next tick.`
          );
          await markerRef.set(
            { cursorPath: null, claimed, held, conflicts, skipped, errors: 0 },
            { merge: true }
          );
          break;
        }
        await markerRef.set(
          {
            completedAt: admin.firestore.FieldValue.serverTimestamp(),
            claimed,
            held,
            conflicts,
            skipped,
          },
          { merge: true }
        );
        console.log(
          `backfillAthleteOwners: COMPLETE — claimed ${claimed}, already held ${held}, conflicts ${conflicts}, skipped ${skipped}`
        );
        break;
      }

      for (const doc of snap.docs) {
        // A collection-group query matches ANY collection named 'athletes' at any
        // depth. Only `users/{uid}/athletes` carries an owner in the grandparent
        // slot, so pin the shape rather than trusting the name.
        const userDoc = doc.ref.parent.parent;
        const ownerUID = userDoc?.parent.id === 'users' ? userDoc.id : null;
        const athleteUUID = validUUID(doc.data()?.id);
        if (!ownerUID || !athleteUUID) {
          skipped += 1;
          continue;
        }
        const result = await claim(db, athleteUUID, ownerUID);
        if (result === 'claimed') claimed += 1;
        else if (result === 'held') held += 1;
        else if (result === 'conflict') conflicts += 1;
        else errors += 1;
      }

      cursorPath = snap.docs[snap.docs.length - 1].ref.path;
      await markerRef.set({ cursorPath, claimed, held, conflicts, skipped, errors }, { merge: true });

      if (Date.now() - started > DEADLINE_MS) {
        // Loudly, not silently: a truncated sweep must never read as a clean run,
        // because the rules deploy is gated on this function's own verdict.
        console.error(
          `backfillAthleteOwners: deadline hit mid-sweep at ${cursorPath} — resuming next tick (claimed ${claimed} so far). DO NOT deploy rules yet.`
        );
        return null;
      }
    }

    await auditExistingProfiles(db);
    return null;
  });

/**
 * Reports any published profile whose athlete UUID is not owned by the account
 * that published it — i.e. a squat that landed before the gate existed.
 *
 * Read-only on purpose. Deleting someone's profile doc from a cron because an
 * index disagrees with it is not a decision a sweep gets to make; the log names
 * the doc and a human resolves it.
 */
async function auditExistingProfiles(db: FirebaseFirestore.Firestore): Promise<void> {
  let cursor: FirebaseFirestore.QueryDocumentSnapshot | null = null;
  let checked = 0;
  let bad = 0;

  for (;;) {
    let q = db.collection('recruitingProfiles').orderBy(admin.firestore.FieldPath.documentId()).limit(PAGE);
    if (cursor) q = q.startAfter(cursor);
    const snap = await q.get();
    if (snap.empty) break;

    for (const doc of snap.docs) {
      checked += 1;
      const profileOwner = doc.data()?.userId;
      const owner = await db.collection(OWNERS).doc(doc.id).get().catch(() => null);
      const holder = owner?.exists ? owner.data()?.userId : null;
      if (!holder) {
        bad += 1;
        console.error(`recruitingProfiles AUDIT: ${doc.id} has no ownership claim (published by ${profileOwner})`);
      } else if (holder !== profileOwner) {
        bad += 1;
        console.error(
          `recruitingProfiles AUDIT: ${doc.id} was published by ${profileOwner} but the athlete belongs to ${holder} — SQUAT`
        );
      }
    }

    cursor = snap.docs[snap.docs.length - 1];
  }

  console.log(`recruitingProfiles AUDIT: checked ${checked}, suspicious ${bad}`);
}
