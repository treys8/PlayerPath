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
 *
 * ## Why a missing claim is an availability bug, not just a gap
 *
 * Once rules require the claim, "has no claim" and "cannot publish" are the same
 * sentence — so minting one has to be guaranteed rather than best-effort. It is
 * guaranteed from two directions, because neither one alone is enough:
 *
 * • `claimAthleteOwnership` RETRIES a transient failure (`failurePolicy`), which
 *   covers the overwhelmingly common case. It did not always: the trigger used to
 *   swallow the error, and the `before.id === after.id` fast path then
 *   short-circuits every later write to that doc — so one bad moment left an
 *   athlete permanently unpublishable, reaching the family as an unactionable
 *   "couldn't reserve a link" and needing console surgery to undo.
 * • `reconcileAthleteOwners` sweeps DAILY, which covers what a retry cannot: the
 *   trigger not deployed yet, an instance killed before it ran, a region outage,
 *   a claim that exhausted its retry budget, and any athlete stranded before this
 *   existed. It is the repair path — and it is what lets the retry give up
 *   loudly instead of hammering for a week.
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
 * How long a failing claim keeps being retried before it becomes a log line.
 *
 * `failurePolicy` retries for up to SEVEN DAYS, which is the wrong shape for
 * this: a claim that is still failing after a few minutes is not failing
 * transiently, and a week of retries on every athlete write of a broken account
 * buys nothing the daily reconcile doesn't already cover. Past the budget the
 * trigger stops throwing and starts reporting.
 */
const CLAIM_RETRY_BUDGET_MS = 10 * 60 * 1000;

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
 * That fast path is also why a swallowed failure used to be permanent, and why
 * this function now RETRIES rather than logging and moving on: after the first
 * write, no later write to the same doc will try again. `claim()` is idempotent
 * (`create()` plus ALREADY_EXISTS handling), so a retry either succeeds or lands
 * on a hold — there is nothing for a duplicate attempt to corrupt.
 *
 * A `'conflict'` deliberately does NOT retry. It means the UUID is held by a
 * different account — a pre-existing squat or a collision — and no number of
 * attempts changes that; it needs a human, and `claim()` has already said so.
 *
 * Deletes never release a claim. A released UUID is a re-claimable UUID, and the
 * whole point is that this binding is permanent.
 */
export const claimAthleteOwnership = functions
  // Retries the transient case. See CLAIM_RETRY_BUDGET_MS for the bound.
  .runWith({ failurePolicy: true })
  .firestore.document('users/{userId}/athletes/{athleteDocId}')
  .onWrite(async (change, context) => {
    // ONE budget governs every throw out of this function, which is why the whole
    // body sits inside it rather than just the claim call. `failurePolicy` retries
    // on any unhandled error, and this trigger fires on EVERY athlete-doc write —
    // so an unrelated bug introduced here later would otherwise retry itself for
    // seven days per write across the entire user base. An unparseable timestamp
    // yields Infinity, i.e. "over budget", which is the fail-safe direction:
    // retrying forever on a clock we can't read is worse than handing the work to
    // the nightly reconcile.
    try {
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

      const ownerUID = context.params.userId as string;
      if ((await claim(admin.firestore(), athleteUUID, ownerUID)) !== 'error') return;

      // Throwing is the retry request. The message is what lands in the log on
      // every attempt, so it names the athlete rather than just the failure.
      throw new Error(
        `claimAthleteOwnership: claim for ${athleteUUID} (owner ${ownerUID}) failed, retrying`
      );
    } catch (err) {
      const eventMillis = Date.parse(context.timestamp);
      const eventAge = Number.isFinite(eventMillis) ? Date.now() - eventMillis : Infinity;
      if (eventAge <= CLAIM_RETRY_BUDGET_MS) throw err;
      console.error(
        `claimAthleteOwnership: giving up on ${change.after.ref.path} after ` +
          `${Math.round(eventAge / 1000)}s of retries — if this was a claim failure, that ` +
          'athlete CANNOT PUBLISH until reconcileAthleteOwners picks them up',
        err
      );
    }
  });

/**
 * Resume cursor for a sweep that ran out of time.
 *
 * 🚨 **Not in `appConfig`, and that is a security choice, not a naming one.**
 * `firestore.rules` grants `appConfig` read to every authenticated user, and this
 * cursor is a document PATH — `users/{someUID}/athletes/{docId}` — so parking it
 * there publishes one stranger's Firebase UID to the whole signed-in user base on
 * any night the sweep stops early. A UID is not a credential (storage.rules and
 * every users/{uid} rule gate on `request.auth.uid`), but handing out real account
 * identifiers for free is not something a cursor needs to do.
 *
 * `internalState` matches no rule, so the catch-all at the bottom of
 * firestore.rules denies it in both directions — the same closure `athleteOwners`
 * gets explicitly. Admin-SDK writes bypass rules, so nothing is given up.
 *
 * Also deliberately a DIFFERENT doc from `appConfig/athleteOwnersBackfill`, which
 * the one-time backfill stamped `completedAt`. That doc is the historical record
 * of the migration this function grew out of; overloading it would make "the
 * original backfill finished" and "last night's sweep stopped here" the same
 * field, and the first of those is what the rules deploy was once gated on.
 * ⚠️ That doc still holds the backfill's final `cursorPath` under the readable
 * rule — delete that one field from the console.
 */
const MARKER = 'internalState/athleteOwnersReconcile';
/** Stop this far into the 540 s budget and resume on the next run. */
const DEADLINE_MS = 480 * 1000;

/**
 * When the audit pass gives up, measured on the SAME clock as the sweep above.
 *
 * The audit runs after the sweep inside one invocation, so it inherits whatever
 * time the sweep left — which on a slow night is very little. Leaves ~20 s under
 * the 540 s timeout to print its own summary.
 */
const AUDIT_DEADLINE_MS = 520 * 1000;
const PAGE = 500;

/**
 * Documents checked at once. Bounds concurrent Firestore reads and writes.
 *
 * A one-time backfill could afford one awaited round trip per athlete; a NIGHTLY
 * pass over the whole collection cannot — that shape makes wall clock scale with
 * the user base, and it is the same per-item-await trap that has bitten
 * dailyStorageCleanup here before.
 */
const RECONCILE_CONCURRENCY = 10;

/** Runs `task` over `items` in bounded-concurrency chunks, preserving order. */
async function mapWithConcurrency<T, R>(
  items: T[],
  limit: number,
  task: (item: T) => Promise<R>
): Promise<R[]> {
  const results: R[] = [];
  for (let i = 0; i < items.length; i += limit) {
    results.push(...(await Promise.all(items.slice(i, i + limit).map(task))));
  }
  return results;
}

/**
 * The nightly sweep's per-athlete check.
 *
 * Reads the claim BEFORE attempting to write one, deliberately inverting
 * `claim()`'s create-first order. The trigger wants create-first: it may be racing
 * another writer, and Firestore's create semantics ARE the lock. This sweep has no
 * race to win, and in the steady state every athlete is already claimed — so
 * create-first would spend a rejected write *plus* a read on every healthy athlete
 * every single night, forever. One read is the whole cost here.
 *
 * When the claim really is missing it still goes through `claim()`, so a trigger
 * firing at the same moment resolves to first-writer-wins exactly as before.
 *
 * Never throws: both branches convert failure into a return value, which is what
 * lets the caller run these concurrently without a partial page losing its
 * siblings.
 */
async function reconcileOne(
  db: FirebaseFirestore.Firestore,
  athleteUUID: string,
  ownerUID: string
): Promise<'claimed' | 'held' | 'conflict' | 'error'> {
  try {
    const existing = await db.collection(OWNERS).doc(athleteUUID).get();
    if (existing.exists) {
      const holder = existing.data()?.userId;
      if (holder === ownerUID) return 'held';
      // WARN, not ERROR — unlike `claim()`'s conflict path, which keeps ERROR
      // because it fires from the trigger where a conflict is genuinely new
      // information. Here it is a nightly re-observation of a permanent, unrepairable
      // condition (a real one: `RecruitingProfileService.publish` documents how a
      // UID-mismatch sign-in can leave a second User row behind). This project
      // already alerts on severity>=ERROR, so logging it at ERROR would page every
      // night forever with no way to acknowledge it. The consequential case still
      // pages: auditExistingProfiles ERRORs when a PUBLISHED profile's claim
      // disagrees with its publisher.
      console.warn(
        `athleteOwners CONFLICT: ${athleteUUID} is held by ${holder}, but the athlete doc lives under ${ownerUID}`
      );
      return 'conflict';
    }
  } catch (err) {
    // "Can't tell" is not "fine" — an unreadable claim must not be counted as held.
    console.error(`reconcileAthleteOwners: could not read claim ${athleteUUID}`, err);
    return 'error';
  }
  return claim(db, athleteUUID, ownerUID);
}

/**
 * Daily sweep that claims any athlete the trigger did not, and reports anything
 * that looks wrong.
 *
 * **This is the repair path, not housekeeping.** A missing claim is a publish
 * that will be denied forever (see the module header), and the trigger cannot
 * cover every way one goes missing — it isn't running during a region outage, it
 * doesn't exist for an athlete written before it deployed, and it gives up after
 * CLAIM_RETRY_BUDGET_MS. Everything the trigger drops lands here.
 *
 * It began life as the one-time backfill for the athletes that predated the
 * squat gate — hence the paging, the cursor and the `__name__` ordering, which a
 * nightly full pass needs for exactly the same reasons. What changed is that it
 * no longer stops: the old `completedAt` gate (which the rules deploy waited on)
 * is gone, and the counters are now per-run rather than cumulative, because a
 * number that only ever grows says nothing about tonight.
 *
 * A scheduled function rather than a callable or an admin HTTP route: the
 * alternatives are hardcoding a uid, exposing a secret on a public route, or
 * running the Admin SDK locally with a service-account key. A schedule needs none
 * of them.
 */
export const reconcileAthleteOwners = functions
  .runWith({ timeoutSeconds: 540 })
  // An hour after recruitingViewDigest (01:00) so the two don't contend.
  .pubsub.schedule('0 2 * * *')
  .timeZone('UTC')
  .onRun(async () => {
    const db = admin.firestore();
    const markerRef = db.doc(MARKER);
    const marker = await markerRef.get();

    const started = Date.now();
    let claimed = 0;
    let held = 0;
    let conflicts = 0;
    let skipped = 0;
    let errors = 0;
    // Set only by a deadline stop, so a normal run starts from the top and sees
    // every athlete.
    let cursorPath: string | null = (marker.data()?.cursorPath as string) ?? null;
    if (cursorPath) console.log(`reconcileAthleteOwners: resuming from ${cursorPath}`);

    // Ordered by __name__ so the cursor is stable across runs. A collection-group
    // query is what reaches every user's athletes without listing users first;
    // the owner uid is the grandparent document's ID.
    for (;;) {
      let q = db.collectionGroup('athletes').orderBy(admin.firestore.FieldPath.documentId()).limit(PAGE);
      if (cursorPath) q = q.startAfter(db.doc(cursorPath));

      const snap = await q.get();
      if (snap.empty) break;

      // Resolve the page into a plain work list first, so the malformed-doc
      // bookkeeping stays serial and the concurrency below has nothing to skip.
      const work: Array<{ athleteUUID: string; ownerUID: string }> = [];
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
        work.push({ athleteUUID, ownerUID });
      }

      // reconcileOne never throws, so Promise.all inside here cannot lose a page.
      for (const result of await mapWithConcurrency(work, RECONCILE_CONCURRENCY, (item) =>
        reconcileOne(db, item.athleteUUID, item.ownerUID)
      )) {
        if (result === 'claimed') claimed += 1;
        else if (result === 'held') held += 1;
        else if (result === 'conflict') conflicts += 1;
        else errors += 1;
      }

      cursorPath = snap.docs[snap.docs.length - 1].ref.path;

      if (Date.now() - started > DEADLINE_MS) {
        // Park the cursor and pick up here tomorrow. Loudly, not silently: a
        // sweep that can't finish inside 8 minutes means the collection has
        // outgrown a nightly full pass and wants sharding, not a bigger deadline
        // — and until it finishes, the athletes past this cursor have no repair
        // path at all.
        await markerRef.set(
          { cursorPath, stoppedAt: admin.firestore.FieldValue.serverTimestamp() },
          { merge: true }
        );
        console.error(
          `🚨 reconcileAthleteOwners: deadline hit at ${cursorPath} — claimed ${claimed}, ` +
            `held ${held}, conflicts ${conflicts}, skipped ${skipped}, errors ${errors}. ` +
            'Athletes past this cursor were NOT checked; resuming next run.'
        );
        return null;
      }

      // A short page is the last page.
      if (snap.size < PAGE) break;
    }

    // Swept to the end, so clear any parked cursor — tomorrow starts from the top.
    await markerRef.set(
      { cursorPath: null, ranAt: admin.firestore.FieldValue.serverTimestamp() },
      { merge: true }
    );

    // This log IS the alerting surface for the whole mechanism, so each counter
    // says what it actually means rather than being lumped into one number:
    //  • claimed  — the trigger MISSED these and they could not publish until now.
    //               A successful trigger claim reports 'held', so in steady state
    //               this is zero and anything else is a real gap that just closed.
    //  • conflicts — held by a DIFFERENT account. Not repaired and not repairable
    //               from here: a squat or a UUID collision, and it needs a human.
    //  • errors   — could not be verified either way. Not "fine".
    //  • held/skipped — the healthy majority and the malformed-legacy tail.
    const healthy = `already held ${held}, skipped ${skipped}`;
    if (claimed > 0 || errors > 0) {
      console.error(
        `🚨 reconcileAthleteOwners: ${claimed} athlete(s) the trigger missed and this run ` +
          `repaired, ${errors} unverified; ${healthy}`
      );
    } else {
      console.log(`✅ reconcileAthleteOwners: ${healthy}`);
    }
    // Deliberately outside the ERROR branch, for the reason in reconcileOne: a
    // conflict is permanent and unrepairable from here, so it must not page nightly.
    if (conflicts > 0) {
      console.warn(
        `reconcileAthleteOwners: ${conflicts} athlete UUID(s) held by a different account — ` +
          'each was named above; these need a human and will be re-counted every run'
      );
    }

    await auditExistingProfiles(db, started);
    return null;
  });

/**
 * Reports two things about every published profile, both read-only:
 *
 * 1. An athlete UUID not owned by the account that published it — i.e. a squat
 *    that landed before the gate existed.
 * 2. A headshot that isn't a JPEG (see the check itself for why that matters).
 *
 * Read-only on purpose. Deleting someone's profile doc, or their photo, from a
 * cron because an index or a content type disagrees with it is not a decision a
 * sweep gets to make; the log names the doc and a human resolves it.
 */
async function auditExistingProfiles(
  db: FirebaseFirestore.Firestore,
  started: number
): Promise<void> {
  const bucket = admin.storage().bucket();
  let cursor: FirebaseFirestore.QueryDocumentSnapshot | null = null;
  let checked = 0;
  let bad = 0;
  let nonJpeg = 0;
  let under13Contact = 0;
  let truncated = false;

  for (;;) {
    let q = db.collection('recruitingProfiles').orderBy(admin.firestore.FieldPath.documentId()).limit(PAGE);
    if (cursor) q = q.startAfter(cursor);
    const snap = await q.get();
    if (snap.empty) break;

    // Two round trips per profile (the claim, then the headshot metadata), so the
    // page runs with the same bounded concurrency as the athlete sweep rather than
    // one awaited profile at a time.
    const findings = await mapWithConcurrency(snap.docs, RECONCILE_CONCURRENCY, async (doc) => {
      let squat = false;
      let wrongType = false;
      const profileOwner = doc.data()?.userId;
      const owner = await db.collection(OWNERS).doc(doc.id).get().catch(() => null);
      const holder = owner?.exists ? owner.data()?.userId : null;
      if (!holder) {
        squat = true;
        console.error(`recruitingProfiles AUDIT: ${doc.id} has no ownership claim (published by ${profileOwner})`);
      } else if (holder !== profileOwner) {
        squat = true;
        console.error(
          `recruitingProfiles AUDIT: ${doc.id} was published by ${profileOwner} but the athlete belongs to ${holder} — SQUAT`
        );
      }

      // The headshot is the only user-uploaded file the public page streams, and
      // storage.rules narrowed the write from image/.* to image/jpeg only after
      // some headshots had already been stored. That narrowing is not
      // retroactive, so anything written under the old rule survives — an SVG
      // among them is script-bearing markup whose only neutraliser is the avatar
      // proxy forcing image/jpeg + nosniff on the way out. A response header
      // should not be the last line of defence, so name any survivor here.
      // (gcloud/gsutil aren't installed on the dev machine, which is why this
      // lives in a sweep rather than a one-off command.)
      //
      // The path is CLIENT-AUTHORED. Prefix-check it against the publisher first
      // — the same constraint ownedPath() applies in recruitingProfile.ts,
      // inlined rather than imported to keep this module free of that dependency.
      // Without it a crafted path would turn this sweep into a probe that logs
      // the content type of arbitrary bucket objects.
      const headshotPath = doc.data()?.headshotPath;
      if (
        typeof headshotPath === 'string' &&
        typeof profileOwner === 'string' &&
        !headshotPath.includes('..') &&
        headshotPath.startsWith(`recruiting_headshots/${profileOwner}/`)
      ) {
        try {
          const [metadata] = await bucket.file(headshotPath).getMetadata();
          if (metadata.contentType !== 'image/jpeg') {
            wrongType = true;
            console.error(
              `recruitingProfiles AUDIT: ${doc.id} headshot is ${metadata.contentType}, ` +
                `not image/jpeg — ${headshotPath}`
            );
          }
        } catch {
          // A missing object is the normal case, not a finding: "Delete Profile
          // Data" removes the JPEG and leaves the doc, and the page already
          // degrades to no headshot when the object is gone.
        }
      }
      // Profiles published before the under-13 contact gate existed, or from a
      // device on an older build. serveRecruitingProfile now withholds the contact
      // card for these at render time, so the exposure is closed either way — this
      // exists to say how many there were, because a silent retroactive fix leaves
      // nobody able to answer "was a child's phone number ever public, and whose".
      const gradYear = doc.data()?.gradYear;
      const staleUnder13 =
        typeof gradYear === 'number' &&
        gradYear >= new Date().getUTCFullYear() + 6 &&
        Array.isArray(doc.data()?.contact) &&
        doc.data()?.contact.length > 0;
      if (staleUnder13) {
        console.error(
          `recruitingProfiles AUDIT: ${doc.id} (grad ${gradYear}, published by ${profileOwner}) ` +
            'still stores contact PII for an implied-under-13 athlete — withheld at render, ' +
            'cleared on the next republish'
        );
      }
      return { squat, wrongType, staleUnder13 };
    });

    checked += findings.length;
    bad += findings.filter((f) => f.squat).length;
    nonJpeg += findings.filter((f) => f.wrongType).length;
    under13Contact += findings.filter((f) => f.staleUnder13).length;

    cursor = snap.docs[snap.docs.length - 1];
    if (snap.size < PAGE) break;
    // Shares the SWEEP's clock, not its own. The sweep is allowed to run to
    // DEADLINE_MS and then hand over, so measuring from zero here would let the two
    // together blow the 540 s timeout — and being killed mid-audit means this
    // summary never prints, which is the same "a truncated run read as a clean one"
    // failure the sweep's deadline exists to prevent. It also surfaces as a CF
    // timeout ERROR, which pages.
    if (Date.now() - started > AUDIT_DEADLINE_MS) {
      truncated = true;
      break;
    }
  }

  console.log(
    `recruitingProfiles AUDIT: checked ${checked}, suspicious ${bad}, non-JPEG headshots ` +
      `${nonJpeg}, under-13 contact PII at rest ${under13Contact}`
  );
  if (truncated) {
    console.error(
      `🚨 recruitingProfiles AUDIT: deadline hit after ${checked} profile(s) — the rest were ` +
        'NOT audited this run'
    );
  }
}
