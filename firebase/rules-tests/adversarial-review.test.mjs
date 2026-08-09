/**
 * ADVERSARIAL second-opinion tests written during the independent review of the
 * 2026-08-06 security work. These deliberately cover what sharedFolders.test.mjs
 * does NOT:
 *
 *   A. Regression guards for the DEPLOYED rules changes against the REAL shipped
 *      client write shapes (the rules are live; the Swift client is not, so a
 *      false positive here is a production outage, not a future one).
 *   B. Residual holes the fixes left open.
 *
 * Tests whose name starts with "GAP:" assert CURRENT (permissive) behaviour on
 * purpose — they document a hole. Flip the assertion when the hole is closed.
 */

import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'node:test';
import {
  assertFails, assertSucceeds, initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  doc, deleteField, setDoc, updateDoc, writeBatch, increment,
} from 'firebase/firestore';

const ATHLETE_UID = 'athlete-owner';
const COACH_A = 'coach-a';
const COACH_B = 'coach-b';
const COACH_C = 'coach-c-attacker';

const FOLDER_ID = 'folder-1';
const FOLDER = `sharedFolders/${FOLDER_ID}`;

let testEnv;
const dbFor = (uid) => testEnv.authenticatedContext(uid).firestore();
const perm = (canUpload = true, canComment = true, canDelete = false) =>
  ({ canUpload, canComment, canDelete });

async function seedFolder(coachIDs = [], overrides = {}) {
  const permissions = {};
  for (const c of coachIDs) permissions[c] = perm();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), FOLDER), {
      ownerAthleteID: ATHLETE_UID,
      athleteUUID: 'athlete-uuid-1',
      name: 'Lessons',
      folderType: 'lessons',
      sharedWithCoachIDs: coachIDs,
      sharedWithCoachNames: Object.fromEntries(coachIDs.map((c) => [c, c])),
      permissions,
      videoCount: 0,
      ...overrides,
    });
  });
}

async function seedDoc(path, data) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), path), data);
  });
}

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-playerpath-rules-adversarial',
    firestore: {
      rules: readFileSync('../../firestore.rules', 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
});

after(async () => { await testEnv?.cleanup(); });

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'users', ATHLETE_UID), { role: 'athlete', subscriptionTier: 'free' });
    for (const c of [COACH_A, COACH_B, COACH_C]) {
      // NOTE: no coachAthleteCount / coachAthleteLimit — this is what a real
      // coach doc looks like before they have ever accepted an invitation.
      await setDoc(doc(db, 'users', c), {
        role: 'coach', subscriptionTier: 'free', coachSubscriptionTier: 'coach_instructor',
      });
    }
  });
});

// ===========================================================================
// A. Regression guards — the DEPLOYED rules vs the SHIPPED client write shapes
// ===========================================================================

describe('A. videos update — real shipped client shapes must still pass', () => {
  it('ALLOWS markVideoCompleted on a shared clip (updateData, folder owner)', async () => {
    await seedFolder([COACH_A]);
    await seedDoc('videos/pending-1', {
      fileName: 'clip.mov',
      firebaseStorageURL: '',
      uploadedBy: ATHLETE_UID,
      uploadedByName: 'Athlete',
      sharedFolderID: FOLDER_ID,
      videoType: 'clip',
      uploadStatus: 'pending',
      visibility: 'shared',
    });
    await assertSucceeds(updateDoc(doc(dbFor(ATHLETE_UID), 'videos/pending-1'), {
      firebaseStorageURL: `shared_folders/${FOLDER_ID}/clip.mov`,
      uploadStatus: 'completed',
      fileSize: 1234,
      thumbnail: { standardURL: `shared_folders/${FOLDER_ID}/thumbnails/clip_thumbnail.jpg` },
      thumbnailURL: `shared_folders/${FOLDER_ID}/thumbnails/clip_thumbnail.jpg`,
      updatedAt: new Date(),
    }));
  });

  it('ALLOWS the markVideoCompleted BATCH (video update + folder videoCount increment)', async () => {
    await seedFolder([COACH_A]);
    await seedDoc('videos/pending-2', {
      fileName: 'c.mov', firebaseStorageURL: '', uploadedBy: ATHLETE_UID,
      sharedFolderID: FOLDER_ID, uploadStatus: 'pending', visibility: 'shared',
    });
    const db = dbFor(ATHLETE_UID);
    const b = writeBatch(db);
    b.update(doc(db, 'videos/pending-2'), {
      firebaseStorageURL: `shared_folders/${FOLDER_ID}/c.mov`,
      uploadStatus: 'completed', fileSize: 10, updatedAt: new Date(),
    });
    b.update(doc(db, FOLDER), { videoCount: increment(1), updatedAt: new Date() });
    await assertSucceeds(b.commit());
  });

  it('ALLOWS a coach with upload permission completing their own session clip', async () => {
    await seedFolder([COACH_A]);
    await seedDoc('videos/coach-clip', {
      fileName: 'coach.mov', firebaseStorageURL: '', uploadedBy: COACH_A,
      sharedFolderID: FOLDER_ID, uploadStatus: 'pending', visibility: 'shared',
    });
    await assertSucceeds(updateDoc(doc(dbFor(COACH_A), 'videos/coach-clip'), {
      firebaseStorageURL: `shared_folders/${FOLDER_ID}/coach.mov`,
      uploadStatus: 'completed', fileSize: 99, updatedAt: new Date(),
    }));
  });

  it('ALLOWS re-sending an UNCHANGED sharedFolderID explicitly in the update', async () => {
    // Any client that echoes the whole doc back must not trip the new
    // unconditional get(...,null) equality.
    await seedFolder([COACH_A]);
    await seedDoc('videos/echo', {
      fileName: 'e.mov', firebaseStorageURL: '', uploadedBy: ATHLETE_UID,
      sharedFolderID: FOLDER_ID, uploadStatus: 'completed', visibility: 'shared',
    });
    await assertSucceeds(updateDoc(doc(dbFor(ATHLETE_UID), 'videos/echo'), {
      sharedFolderID: FOLDER_ID, note: 'hi', updatedAt: new Date(),
    }));
  });

  it('ALLOWS a full setData REPLACE of a personal clip (VideoCloudManager+Metadata:144 shape)', async () => {
    // saveVideoMetadataToFirestore uses setData WITHOUT merge. If the doc ever
    // carried sharedFolderID this would now be denied; it must pass for personal clips.
    await seedDoc('videos/personal-replace', {
      id: 'personal-replace', downloadURL: 'https://x/y', uploadedBy: ATHLETE_UID,
      athleteName: 'A', fileName: 'p.mov', isDeleted: false, visibility: 'private',
    });
    await assertSucceeds(setDoc(doc(dbFor(ATHLETE_UID), 'videos/personal-replace'), {
      id: 'personal-replace', downloadURL: 'https://x/z', uploadedBy: ATHLETE_UID,
      athleteName: 'A', fileName: 'p.mov', isDeleted: false, visibility: 'private',
    }));
  });

  it('DENIES clearing an existing sharedFolderID to null (unshare-by-nulling)', async () => {
    await seedFolder([COACH_A]);
    await seedDoc('videos/shared-null', {
      fileName: 's.mov', uploadedBy: ATHLETE_UID, sharedFolderID: FOLDER_ID,
      uploadStatus: 'completed', visibility: 'shared',
    });
    await assertFails(updateDoc(doc(dbFor(ATHLETE_UID), 'videos/shared-null'), {
      sharedFolderID: null, updatedAt: new Date(),
    }));
  });
});

describe('A. account-deletion step 7 — coach self-removal from a stranger folder', () => {
  it('ALLOWS the exact FirestoreManager+UserProfile.swift:472 write', async () => {
    await seedFolder([COACH_A, COACH_B]);
    await assertSucceeds(updateDoc(doc(dbFor(COACH_A), FOLDER), {
      sharedWithCoachIDs: [COACH_B],
      [`sharedWithCoachNames.${COACH_A}`]: deleteField(),
      [`permissions.${COACH_A}`]: deleteField(),
      updatedAt: new Date(),
    }));
  });

  it('ALLOWS the self-shed when the caller is the ONLY coach (permissions map empties)', async () => {
    await seedFolder([COACH_A]);
    await assertSucceeds(updateDoc(doc(dbFor(COACH_A), FOLDER), {
      sharedWithCoachIDs: [],
      [`sharedWithCoachNames.${COACH_A}`]: deleteField(),
      [`permissions.${COACH_A}`]: deleteField(),
      updatedAt: new Date(),
    }));
  });
});

describe('A. coach_access_revocations — shipped client still queries the coachID axis', () => {
  it('DENIES a coach deleting a revocation naming them (rules deployed ahead of client)', async () => {
    await seedFolder([]);
    await seedDoc(`coach_access_revocations/${FOLDER_ID}_${COACH_A}`, {
      folderID: FOLDER_ID, coachID: COACH_A, athleteID: ATHLETE_UID, revokedAt: new Date(),
    });
    // Build <=216 loops over ["athleteID","coachID"] in deletion step 6 and will
    // hit this. Confirms the failure mode is a caught per-step error, not silent success.
    const { deleteDoc } = await import('firebase/firestore');
    await assertFails(deleteDoc(doc(dbFor(COACH_A), `coach_access_revocations/${FOLDER_ID}_${COACH_A}`)));
  });
});

// ===========================================================================
// B. Residual holes
// ===========================================================================

describe('A. athlete-delete cascade — sibling safety is a RESULT-SET property, not just a permission', () => {
  it('returns ONLY the deleted athlete\'s folder on a family account with two children', async () => {
    // sharedFolders.test.mjs proves the query is PERMITTED. It does not prove it is
    // correctly scoped — and the thing that would destroy another child's film is
    // scope, not permission. Both folders below share ownerAthleteID (the account uid);
    // only athleteUUID separates them.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      for (const [id, uuid] of [['f-childA', 'uuid-A'], ['f-childB', 'uuid-B']]) {
        await setDoc(doc(db, 'sharedFolders', id), {
          ownerAthleteID: ATHLETE_UID, athleteUUID: uuid, name: 'Lessons',
          folderType: 'lessons', sharedWithCoachIDs: [], sharedWithCoachNames: {},
          permissions: {}, videoCount: 0,
        });
      }
      // Legacy folder with NO athleteUUID — documented as deliberately unmatched.
      await setDoc(doc(db, 'sharedFolders', 'f-legacy'), {
        ownerAthleteID: ATHLETE_UID, name: 'Old', folderType: 'games',
        sharedWithCoachIDs: [], sharedWithCoachNames: {}, permissions: {}, videoCount: 0,
      });
    });
    const { collection, getDocs, query, where } = await import('firebase/firestore');
    const snap = await getDocs(query(
      collection(dbFor(ATHLETE_UID), 'sharedFolders'),
      where('athleteUUID', '==', 'uuid-A'),
      where('ownerAthleteID', '==', ATHLETE_UID)
    ));
    const ids = snap.docs.map((d) => d.id);
    if (ids.length !== 1 || ids[0] !== 'f-childA') {
      throw new Error(`sibling scoping broken: expected ["f-childA"], got ${JSON.stringify(ids)}`);
    }
  });

  it('CASE SENSITIVITY: an uppercase Swift uuidString does not match a lowercased stored value', async () => {
    // Swift's UUID.uuidString is UPPERCASE. Both the write (CreateFolderView:158,
    // CoachesView:255 -> athlete.id.uuidString) and the cascade read
    // (performDeleteAthlete -> athleteID.uuidString) use it, so they agree today.
    // This pins that: if any writer ever lowercases, the cascade silently matches
    // nothing and a deleted child's folders stay live.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'sharedFolders', 'f-lower'), {
        ownerAthleteID: ATHLETE_UID,
        athleteUUID: '3f2b1a90-1111-2222-3333-444455556666', // lowercased
        name: 'Lessons', folderType: 'lessons', sharedWithCoachIDs: [],
        sharedWithCoachNames: {}, permissions: {}, videoCount: 0,
      });
    });
    const { collection, getDocs, query, where } = await import('firebase/firestore');
    const snap = await getDocs(query(
      collection(dbFor(ATHLETE_UID), 'sharedFolders'),
      where('athleteUUID', '==', '3F2B1A90-1111-2222-3333-444455556666'), // Swift shape
      where('ownerAthleteID', '==', ATHLETE_UID)
    ));
    if (snap.size !== 0) throw new Error('expected Firestore string equality to be case-sensitive');
  });
});

describe('B. users.coachAthleteCount can no longer be introduced when absent', () => {
  it('DENIES seeding a NEGATIVE coachAthleteCount on a doc that has none', async () => {
    // Was permitted: the users-update rule guarded this only with
    //   (!('coachAthleteCount' in resource.data) || new == old)
    // which is vacuous while the field is absent, and coachAthleteCount was missing from
    // the affectedKeys().hasAny([...]) deny list. index.ts uses
    // `coachSnap.data()?.coachAthleteCount ?? recompute` as the authoritative operand of
    // the seat-limit check inside both accept transactions — the cached value IS the
    // check — so a poisoned counter bought unlimited connections to minors on a free seat.
    await assertFails(updateDoc(doc(dbFor(COACH_A), `users/${COACH_A}`), {
      coachAthleteCount: -1000,
    }));
  });

  it('DENIES seeding coachAthleteCount: 0 on a doc that has none', async () => {
    await assertFails(updateDoc(doc(dbFor(COACH_A), `users/${COACH_A}`), {
      coachAthleteCount: 0,
    }));
  });

  it('control: coachAthleteLimit is correctly frozen even when absent', async () => {
    await assertFails(updateDoc(doc(dbFor(COACH_A), `users/${COACH_A}`), {
      coachAthleteLimit: 9999,
    }));
  });

  it('control: once coachAthleteCount exists it is frozen', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users', COACH_B), {
        role: 'coach', subscriptionTier: 'free',
        coachSubscriptionTier: 'coach_instructor', coachAthleteCount: 3,
      });
    });
    await assertFails(updateDoc(doc(dbFor(COACH_B), `users/${COACH_B}`), {
      coachAthleteCount: 0,
    }));
  });
});

describe('B. isCoachLeavingFolder — the per-coach maps are now caller-scoped', () => {
  it('DENIES a departing coach stripping a CO-COACH\'s permissions on the way out', async () => {
    // A subset check permits removing ANY key, not just the caller's. Coach B stays in
    // sharedWithCoachIDs but silently loses upload/comment/delete — hasPermission() reads
    // this map, and the athlete's UI badge reads it too, so nothing surfaces.
    await seedFolder([COACH_A, COACH_B]);
    await assertFails(updateDoc(doc(dbFor(COACH_A), FOLDER), {
      sharedWithCoachIDs: [COACH_B],
      [`permissions.${COACH_A}`]: deleteField(),
      [`permissions.${COACH_B}`]: deleteField(),
      updatedAt: new Date(),
    }));
  });

  it('DENIES a departing coach rewriting a co-coach\'s displayed name', async () => {
    // sharedWithCoachNames sat in the hasOnly allowlist with nothing constraining it.
    // Finding 3 named this ("C can be labelled with the ejected coach's name") and the
    // first fix constrained permissions only. A value change is invisible to a subset
    // check, which is why both maps now use .diff().affectedKeys().
    await seedFolder([COACH_A, COACH_B]);
    await assertFails(updateDoc(doc(dbFor(COACH_A), FOLDER), {
      sharedWithCoachIDs: [COACH_B],
      [`sharedWithCoachNames.${COACH_B}`]: 'Dr. Impostor',
      updatedAt: new Date(),
    }));
  });

  it('DENIES adding permissions for a new coach (the original subset check)', async () => {
    await seedFolder([COACH_A, COACH_B]);
    await assertFails(updateDoc(doc(dbFor(COACH_A), FOLDER), {
      sharedWithCoachIDs: [COACH_B],
      [`permissions.${COACH_C}`]: perm(true, true, true),
      updatedAt: new Date(),
    }));
  });

  it('still ALLOWS the caller removing their OWN keys alongside co-coach entries', async () => {
    // The self-shed must keep working on a multi-coach folder — the co-coach's entries
    // are present and untouched, which is exactly what hasOnly([uid]) permits.
    await seedFolder([COACH_A, COACH_B, COACH_C]);
    await assertSucceeds(updateDoc(doc(dbFor(COACH_A), FOLDER), {
      sharedWithCoachIDs: [COACH_B, COACH_C],
      [`sharedWithCoachNames.${COACH_A}`]: deleteField(),
      [`permissions.${COACH_A}`]: deleteField(),
      updatedAt: new Date(),
    }));
  });

  it('still ALLOWS the OWNER\'s full removeCoachFromFolder write shape', async () => {
    // Owner branch, not isCoachLeavingFolder — the new constraints must not leak into it.
    // Verbatim FirestoreManager+SharedFolders.swift:259.
    await seedFolder([COACH_A, COACH_B]);
    await assertSucceeds(updateDoc(doc(dbFor(ATHLETE_UID), FOLDER), {
      sharedWithCoachIDs: [COACH_B],
      [`sharedWithCoachNames.${COACH_A}`]: deleteField(),
      [`permissions.${COACH_A}`]: deleteField(),
      updatedAt: new Date(),
    }));
  });
});

describe('B. comments — canComment is enforced server-side', () => {
  async function seedFolderWithPerms(perms) {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), FOLDER), {
        ownerAthleteID: ATHLETE_UID, athleteUUID: 'athlete-uuid-1', name: 'Lessons',
        folderType: 'lessons', sharedWithCoachIDs: [COACH_A],
        sharedWithCoachNames: { [COACH_A]: 'A' },
        videoCount: 0,
        ...(perms === undefined ? {} : { permissions: perms }),
      });
    });
    await seedDoc('videos/v1', {
      fileName: 'v.mov', uploadedBy: ATHLETE_UID, sharedFolderID: FOLDER_ID,
      uploadStatus: 'completed', visibility: 'shared',
    });
  }
  const postAs = (uid, id) => setDoc(doc(dbFor(uid), `videos/v1/comments/${id}`), {
    authorId: uid, content: 'note', createdAt: new Date(),
  });

  it('DENIES a coach the athlete set to view-only (canComment:false)', async () => {
    await seedFolderWithPerms({ [COACH_A]: perm(false, false, false) });
    await assertFails(postAs(COACH_A, 'c1'));
  });

  it('ALLOWS a coach with canComment:true', async () => {
    await seedFolderWithPerms({ [COACH_A]: perm(false, true, false) });
    await assertSucceeds(postAs(COACH_A, 'c2'));
  });

  it('ALLOWS a coach on a LEGACY folder with no permissions map (must not silence them)', async () => {
    await seedFolderWithPerms(undefined);
    await assertSucceeds(postAs(COACH_A, 'c3'));
  });

  it('ALLOWS a coach present in the map but with no entry of their own', async () => {
    await seedFolderWithPerms({ [COACH_B]: perm() });
    await assertSucceeds(postAs(COACH_A, 'c4'));
  });

  it('ALLOWS the athlete owner regardless of the map', async () => {
    await seedFolderWithPerms({ [ATHLETE_UID]: perm(false, false, false) });
    await assertSucceeds(postAs(ATHLETE_UID, 'c5'));
  });
});

describe('B. coachSessions — coachID is frozen on update', () => {
  beforeEach(async () => {
    await seedDoc('coachSessions/s1', {
      coachID: COACH_A, folderID: FOLDER_ID, status: 'ended', title: 'Lesson',
    });
  });

  it('DENIES coach A reassigning their session doc to coach B', async () => {
    await assertFails(updateDoc(doc(dbFor(COACH_A), 'coachSessions/s1'), {
      coachID: COACH_B, status: 'live', title: 'Attacker-authored session',
    }));
  });

  it('ALLOWS an ordinary session update', async () => {
    await assertSucceeds(updateDoc(doc(dbFor(COACH_A), 'coachSessions/s1'), {
      status: 'live', title: 'Tuesday lesson',
    }));
  });
});
