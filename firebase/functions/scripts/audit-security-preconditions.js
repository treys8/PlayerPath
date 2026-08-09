#!/usr/bin/env node
/**
 * READ-ONLY. Writes nothing, deletes nothing, has no --apply.
 *
 * Checks the production data-state assumptions that the 2026-08-06 security remediation
 * relies on but never verified. Each section corresponds to a deployed change whose
 * correctness depends on a fact about existing data rather than about code — which means
 * reading the code cannot tell you whether it is safe, and the failure modes are silent.
 *
 * Run this before trusting the remediation, and after any related deploy.
 *
 * Usage (from firebase/functions/):
 *   GOOGLE_APPLICATION_CREDENTIALS=path/to/serviceAccount.json node scripts/audit-security-preconditions.js
 */

const { preflight } = require('./_preflight');

const { db } = preflight();

const findings = [];
function flag(section, msg) {
  findings.push(`[${section}] ${msg}`);
  console.log(`  ⚠️  ${msg}`);
}

/** Cursor-paged full scan. No limit, so results are complete. */
async function scanAll(collection, perDoc, pageSize = 500) {
  let cursor;
  let count = 0;
  while (true) {
    let q = db.collection(collection).orderBy('__name__').limit(pageSize);
    if (cursor) q = q.startAfter(cursor);
    const snap = await q.get();
    if (snap.empty) break;
    for (const d of snap.docs) { count++; await perDoc(d); }
    cursor = snap.docs[snap.docs.length - 1];
    if (snap.size < pageSize) break;
  }
  return count;
}

/**
 * §1 — Tier-source markers.
 *
 * `syncSubscriptionTier` and the App Store notification handler decide whether a lapse may
 * revoke a tier by testing tierSource. The canonical comp marker is ABSENCE; 'storekit' is
 * the only value the server ever writes. Anything else is a hand-typed sentinel, and how it
 * is interpreted differs by axis on purpose:
 *
 *   • coachTierSource  — was client-writable until 2026-08-06, so an unrecognized value is
 *     treated as revocable ('storekit'). A genuine coach comp carrying a sentinel WILL be
 *     written down, unless it is coach_academy, which is excluded at both write-down sites.
 *   • athleteTierSource — was never client-writable, so an unrecognized value is preserved
 *     as a comp. Nothing breaks, but the field should still be cleaned up.
 *
 * Either way the fix is the same: CLEAR the field on real comps rather than leaving a
 * sentinel that no longer means what whoever typed it intended.
 */
async function auditTierSources() {
  console.log('§1 users.athleteTierSource / coachTierSource — non-canonical markers');
  let checked = 0;
  await scanAll('users', async (d) => {
    checked++;
    const u = d.data();
    const a = u.athleteTierSource;
    const c = u.coachTierSource;
    if (a !== undefined && a !== null && a !== 'storekit') {
      flag('§1', `users/${d.id}: athleteTierSource=${JSON.stringify(a)} ` +
                 `(subscriptionTier=${u.subscriptionTier ?? 'free'}) — preserved as a comp; clear the field.`);
    }
    if (c !== undefined && c !== null && c !== 'storekit') {
      const tier = u.coachSubscriptionTier ?? 'coach_free';
      const atRisk = tier !== 'coach_free' && tier !== 'coach_academy';
      flag('§1', `users/${d.id}: coachTierSource=${JSON.stringify(c)} (coachSubscriptionTier=${tier})` +
                 (atRisk ? ' — 🔴 WILL BE WRITTEN DOWN to coach_free on the next sync. Clear the field NOW if this is a real comp.'
                         : ' — safe (free or academy), but clear the field.'));
    }
  });
  console.log(`  scanned ${checked} users\n`);
}

/**
 * §2 — users.coachAthleteCount sanity.
 *
 * The seat-limit check inside both accept transactions reads
 * `coachSnap.data()?.coachAthleteCount ?? <recompute>` — the cached counter IS the operand.
 * It was client-introducible while absent (fixed in firestore.rules 2026-08-08), so any
 * value already at rest could have been seeded. Negative or absurd values are the signature.
 */
async function auditCoachAthleteCounts() {
  console.log('§2 users.coachAthleteCount — implausible cached seat counts');
  let checked = 0;
  await scanAll('users', async (d) => {
    const u = d.data();
    if (u.coachAthleteCount === undefined) return;
    checked++;
    if (typeof u.coachAthleteCount !== 'number' || !Number.isInteger(u.coachAthleteCount)) {
      flag('§2', `users/${d.id}: coachAthleteCount=${JSON.stringify(u.coachAthleteCount)} is not an integer.`);
    } else if (u.coachAthleteCount < 0) {
      flag('§2', `users/${d.id}: coachAthleteCount=${u.coachAthleteCount} is NEGATIVE — seeded, not computed. ` +
                 `Recompute it (auditCoachDowngrades does) before trusting the seat gate for this coach.`);
    }
  });
  console.log(`  scanned ${checked} users carrying the field\n`);
}

/**
 * §3 — Invitations naming a folder their sender does not own.
 *
 * `acceptAthleteToCoachInvitation` now THROWS permission-denied when
 * `folder.ownerAthleteID !== inv.athleteID`. Every folder-creating code path sets
 * ownerAthleteID to the creating account's uid, so no new invitation can trip it — but that
 * guard is deployed and any pre-existing pending invitation in this state is now permanently
 * un-acceptable, with an opaque error for the coach. This is the query the remediation doc
 * listed as required-before-this-is-real and that was never run.
 */
async function auditInvitationFolderOwnership() {
  console.log('§3 invitations — pending invites naming a folder the sender does not own');
  const snap = await db.collection('invitations')
    .where('type', '==', 'athlete_to_coach')
    .where('status', '==', 'pending')
    .get();
  let withFolder = 0;
  for (const d of snap.docs) {
    const inv = d.data();
    if (!inv.folderID || typeof inv.folderID !== 'string') continue;
    withFolder++;
    const f = await db.collection('sharedFolders').doc(inv.folderID).get();
    if (!f.exists) {
      // Not blocked — the guard only fires when the folder EXISTS. Worth knowing anyway.
      flag('§3', `invitations/${d.id}: folderID=${inv.folderID} does not exist (accept will fall through ` +
                 `to reuseOrCreateSharedFolders — not blocked).`);
      continue;
    }
    const owner = f.data()?.ownerAthleteID;
    if (typeof owner !== 'string' || owner !== inv.athleteID) {
      flag('§3', `invitations/${d.id}: 🔴 folder ${inv.folderID} ownerAthleteID=${JSON.stringify(owner)} ` +
                 `but sender athleteID=${JSON.stringify(inv.athleteID)} — this invite now THROWS on accept. ` +
                 `Either it is the attack the guard was added for, or legacy data that needs the invite resent.`);
    }
  }
  console.log(`  scanned ${snap.size} pending athlete_to_coach invitations (${withFolder} naming a folder)\n`);
}

/**
 * §4 — Folders that carry athleteUUID but no ownerAthleteID.
 *
 * Two deployed things assume the pair travels together: `reuseOrCreateSharedFolders`'
 * owner-scoped reuse query, and the client's `sharedFolderIDs(forAthleteUUID:ownerAccountUID:)`
 * athlete-deletion cascade. A folder missing ownerAthleteID matches neither, and is also
 * unreadable by its own owner (the read rule compares ownerAthleteID to the uid), so it
 * would be invisible AND uncleanable rather than merely stale.
 */
async function auditFolderKeys() {
  console.log('§4 sharedFolders — athleteUUID present without ownerAthleteID');
  let total = 0;
  let noUUID = 0;
  await scanAll('sharedFolders', async (d) => {
    total++;
    const f = d.data();
    const hasOwner = typeof f.ownerAthleteID === 'string' && f.ownerAthleteID.length > 0;
    const hasUUID = typeof f.athleteUUID === 'string' && f.athleteUUID.length > 0;
    if (!hasOwner) {
      flag('§4', `sharedFolders/${d.id}: no ownerAthleteID — unreadable by its owner and skipped by ` +
                 `both the reuse query and the athlete-delete cascade.`);
    }
    if (hasOwner && !hasUUID) noUUID++;
  });
  console.log(`  scanned ${total} folders; ${noUUID} legacy folder(s) have no athleteUUID`);
  if (noUUID > 0) {
    console.log(`  note: those ${noUUID} are NOT matched by the per-athlete delete cascade by design ` +
                `(it must not guess). They are covered only by full account deletion.\n`);
  } else {
    console.log('');
  }
}

async function main() {
  console.log('READ-ONLY audit of security-remediation preconditions\n');
  await auditTierSources();
  await auditCoachAthleteCounts();
  await auditInvitationFolderOwnership();
  await auditFolderKeys();

  console.log('─'.repeat(72));
  if (findings.length === 0) {
    console.log('✅ No findings. Every audited precondition holds.');
  } else {
    console.log(`${findings.length} finding(s):`);
    for (const f of findings) console.log(`  ${f}`);
    process.exitCode = 1;
  }
}

main().catch((err) => {
  console.error('Fatal:', err);
  process.exit(1);
});
