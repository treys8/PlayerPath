#!/usr/bin/env node
/**
 * Pricing Model V2 — Phase 0 one-time migration.
 *
 * Restores coach access for athletes whose Pro lapse revoked it (revocation docs
 * with reason: 'lapse'). MUST run BEFORE deploying the Phase 1 Cloud Functions
 * (which delete restoreCoachAccessForResubscribedAthlete) — otherwise mid-lapse
 * athletes are stranded with no automatic restore path.
 *
 * Mirrors the semantics of restoreCoachAccessForResubscribedAthlete in
 * src/index.ts (pre-removal): person-keyed seat accounting, coach room check,
 * restore-deferred marking for coaches at limit, authoritative counter recompute.
 * Notifications/emails are intentionally NOT sent (silent migration).
 *
 * Usage (from firebase/functions/):
 *   GOOGLE_APPLICATION_CREDENTIALS=path/to/serviceAccount.json node scripts/restore-lapsed-coach-access.js          # dry run (default)
 *   GOOGLE_APPLICATION_CREDENTIALS=path/to/serviceAccount.json node scripts/restore-lapsed-coach-access.js --apply  # write changes
 */

const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();
const APPLY = process.argv.includes('--apply');

// Must match getCoachAthleteLimit in src/index.ts
function getCoachAthleteLimit(tier) {
  switch (tier) {
    case 'coach_instructor': return 10;
    case 'coach_pro_instructor': return 30;
    case 'coach_academy': return Number.MAX_SAFE_INTEGER;
    default: return 2; // coach_free
  }
}

// Mirror of computeCoachConnectionKeys in src/index.ts (UUID-aware dedup;
// see memory project_athlete_count_reconcile).
async function computeCoachConnectionKeys(coachID) {
  const uuids = new Set();
  const accountsWithUUID = new Set();
  const accountsNoUUID = new Set();

  const consider = (uuid, account) => {
    const u = typeof uuid === 'string' && uuid.length > 0 ? uuid : undefined;
    const a = typeof account === 'string' && account.length > 0 ? account : undefined;
    if (u) {
      uuids.add(u);
      if (a) accountsWithUUID.add(a);
    } else if (a) {
      accountsNoUUID.add(a);
    }
  };

  const foldersSnap = await db.collection('sharedFolders')
    .where('sharedWithCoachIDs', 'array-contains', coachID)
    .get();
  for (const d of foldersSnap.docs) {
    consider(d.data().personGroupID || d.data().athleteUUID, d.data().ownerAthleteID);
  }

  const acceptedSnap = await db.collection('invitations')
    .where('type', '==', 'coach_to_athlete')
    .where('coachID', '==', coachID)
    .where('status', '==', 'accepted')
    .get();
  for (const doc of acceptedSnap.docs) {
    consider(doc.data().personGroupID || doc.data().athleteUUID, doc.data().athleteUserID);
  }

  const keys = new Set(uuids);
  for (const acc of accountsNoUUID) {
    if (!accountsWithUUID.has(acc)) keys.add(acc);
  }
  return keys;
}

async function main() {
  console.log(`Mode: ${APPLY ? 'APPLY (writing changes)' : 'DRY RUN (pass --apply to write)'}\n`);

  const revSnap = await db.collection('coach_access_revocations')
    .where('reason', '==', 'lapse')
    .get();
  console.log(`Found ${revSnap.size} lapse revocation doc(s).`);
  if (revSnap.empty) {
    console.log('Nothing to restore. Safe to deploy Phase 1.');
    return;
  }

  // Group by athlete, then coach (same shape as the CF restore path).
  const byAthlete = new Map();
  for (const rev of revSnap.docs) {
    const athleteID = rev.data().athleteID;
    if (!athleteID) {
      console.log(`  ⚠️ ${rev.id}: missing athleteID — deleting orphan doc`);
      if (APPLY) await rev.ref.delete();
      continue;
    }
    const list = byAthlete.get(athleteID) || [];
    list.push(rev);
    byAthlete.set(athleteID, list);
  }

  const defaultPerms = { canUpload: true, canComment: true, canDelete: false };
  let restored = 0;
  let deferred = 0;
  const restoredCoachIDs = new Set();
  const restoredAthleteIDs = new Set();

  for (const [athleteID, revs] of byAthlete) {
    console.log(`\nAthlete ${athleteID}: ${revs.length} lapse revocation(s)`);

    const revsByCoach = new Map();
    for (const rev of revs) {
      const { folderID, coachID } = rev.data();
      if (!folderID || !coachID) {
        console.log(`  ⚠️ ${rev.id}: missing folderID/coachID — deleting orphan doc`);
        if (APPLY) await rev.ref.delete();
        continue;
      }
      const list = revsByCoach.get(coachID) || [];
      list.push(rev);
      revsByCoach.set(coachID, list);
    }

    for (const [coachID, coachRevs] of revsByCoach) {
      let coachName = 'Coach';
      let tier = 'coach_free';
      try {
        const cd = (await db.collection('users').doc(coachID).get()).data();
        coachName = (cd && (cd.displayName || (cd.email || '').split('@')[0])) || 'Coach';
        tier = (cd && cd.coachSubscriptionTier) || 'coach_free';
      } catch { /* defaults */ }
      const limit = getCoachAthleteLimit(tier);

      // Group this coach's revocations by person key (dual-sport person = 1 seat).
      const revsByPerson = new Map();
      for (const rev of coachRevs) {
        const folderID = rev.data().folderID;
        const ref = db.collection('sharedFolders').doc(folderID);
        const snap = await ref.get();
        let key = athleteID;
        if (snap.exists) {
          const fd = snap.data();
          key = fd.personGroupID || fd.athleteUUID || fd.ownerAthleteID || athleteID;
        }
        const list = revsByPerson.get(key) || [];
        list.push({ rev, ref, snap });
        revsByPerson.set(key, list);
      }

      const unlimited = limit === Number.MAX_SAFE_INTEGER;
      let existingKeys = new Set();
      let constrained = !unlimited;
      if (constrained) {
        try {
          existingKeys = await computeCoachConnectionKeys(coachID);
        } catch (e) {
          console.log(`  ⚠️ Room check failed for coach ${coachID}; restoring all:`, e.message);
          constrained = false;
        }
      }
      let availableSeats = constrained ? Math.max(0, limit - existingKeys.size) : Number.MAX_SAFE_INTEGER;

      for (const [personKey, entries] of revsByPerson) {
        const alreadyCounted = existingKeys.has(personKey);
        if (!alreadyCounted && availableSeats <= 0) {
          console.log(`  ⏸ coach ${coachID} (${tier}) at limit — deferring person ${personKey} (${entries.length} folder(s))`);
          deferred += entries.length;
          if (APPLY) {
            for (const { rev } of entries) {
              await rev.ref.set({
                restoreDeferred: true,
                restoreDeferredReason: 'coach_at_limit',
                restoreDeferredAt: admin.firestore.FieldValue.serverTimestamp(),
              }, { merge: true });
            }
          }
          continue;
        }
        if (!alreadyCounted) { availableSeats--; existingKeys.add(personKey); }
        for (const { rev, ref, snap } of entries) {
          if (snap.exists) {
            console.log(`  ✅ restore coach ${coachID} → folder ${ref.id}`);
            if (APPLY) {
              await ref.update({
                sharedWithCoachIDs: admin.firestore.FieldValue.arrayUnion(coachID),
                [`permissions.${coachID}`]: defaultPerms,
                [`sharedWithCoachNames.${coachID}`]: coachName,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              });
            }
            restoredCoachIDs.add(coachID);
            restoredAthleteIDs.add(athleteID);
            restored++;
          } else {
            console.log(`  🗑 folder ${ref.id} gone — deleting stale revocation ${rev.id}`);
          }
          if (APPLY) await rev.ref.delete();
        }
      }
    }
  }

  // Recompute counters for every coach we touched.
  for (const coachID of restoredCoachIDs) {
    const trueCount = (await computeCoachConnectionKeys(coachID)).size;
    console.log(`\nCoach ${coachID}: coachAthleteCount → ${trueCount}`);
    if (APPLY) {
      await db.collection('users').doc(coachID).update({ coachAthleteCount: trueCount });
    }
  }

  // Clear the "Coach Access Paused" and "Some Coaches Need to Reconnect" notices
  // for restored athletes — the deleted CF pipeline cleaned both; nothing else
  // ever will once it's gone.
  for (const athleteID of restoredAthleteIDs) {
    if (APPLY) {
      const items = db.collection('notifications').doc(athleteID).collection('items');
      try { await items.doc(`lapse_${athleteID}`).delete(); } catch { /* nothing to clear */ }
      try { await items.doc(`restore_blocked_${athleteID}`).delete(); } catch { /* nothing to clear */ }
    }
  }

  console.log(`\nDone. Restored ${restored} folder link(s); deferred ${deferred} (coach at limit).`);
  if (deferred > 0) {
    console.log('Deferred docs keep reason:\'lapse\' — after Phase 1 deploy they only block canAccessFolder');
    console.log('for that folder+coach pair until a re-invite (accept deletes the doc). Re-run this script');
    console.log('after a coach upgrades, or batch-delete them and let the pair re-invite.');
  }
  if (!APPLY) console.log('\nDRY RUN — no writes performed. Re-run with --apply.');
}

main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
