/**
 * Firestore rules tests for the coach-sharing seam: `sharedFolders`, `videos`,
 * `coach_access_revocations`, and the `users` tier-source freeze.
 *
 * These four rules are what stands between a family and a coach they revoked. Each
 * case below is a real defect found in the 2026-08-06 security review, written so it
 * FAILS against the old rules and passes against the current ones — the point is to
 * keep them from regressing, not to describe what the rules happen to do today.
 *
 * The trap this file exists for: three of the four holes were "the guard is present
 * but vacuous". A cardinality check that isn't a subset check, an immutability check
 * predicated on the field already existing, a deny-list missing one of a twin pair.
 * None of them look wrong when you read them, which is exactly why they need tests.
 *
 * Run: npm test   (from firebase/rules-tests/ — boots the Firestore emulator)
 */

import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection, deleteField, doc, getDocs, query, setDoc, updateDoc, deleteDoc, where,
} from 'firebase/firestore';

const ATHLETE_UID = 'athlete-owner';
const COACH_A = 'coach-a';
const COACH_B = 'coach-b';
const COACH_C = 'coach-c-attacker';

const FOLDER_ID = 'folder-1';
const FOLDER = `sharedFolders/${FOLDER_ID}`;

let testEnv;

const dbFor = (uid) => testEnv.authenticatedContext(uid).firestore();

const perm = (canUpload = true, canComment = true, canDelete = false) => ({
  canUpload, canComment, canDelete,
});

/** Seeds a folder owned by ATHLETE_UID, shared with `coachIDs`. */
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
    // Distinct from recruitingProfiles.test.mjs on purpose. `node --test` runs test
    // FILES in parallel processes against the one emulator, and projectId is what
    // namespaces their data — sharing it means each file's clearFirestore() wipes the
    // other's fixtures mid-run, which surfaces as random unrelated failures.
    projectId: 'demo-playerpath-rules-folders',
    firestore: {
      rules: readFileSync('../../firestore.rules', 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
});

after(async () => {
  await testEnv?.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'users', ATHLETE_UID), { role: 'athlete', subscriptionTier: 'free' });
    for (const c of [COACH_A, COACH_B, COACH_C]) {
      await setDoc(doc(db, 'users', c), {
        role: 'coach',
        subscriptionTier: 'free',
        coachSubscriptionTier: 'coach_instructor',
      });
    }
  });
});

describe('sharedFolders — isCoachLeavingFolder()', () => {
  it('ALLOWS a coach to remove only themselves (the downgrade self-shed this branch exists for)', async () => {
    await seedFolder([COACH_A, COACH_B]);
    await assertSucceeds(updateDoc(doc(dbFor(COACH_A), FOLDER), {
      sharedWithCoachIDs: [COACH_B],
      updatedAt: new Date(),
    }));
  });

  it('ALLOWS the real self-shed write shape — array remove PLUS deleting own permissions/name keys', async () => {
    // This is verbatim what FirestoreManager+SharedFolders.swift:420 and
    // FirestoreManager+UserProfile.swift:472 send during a coach downgrade. The
    // permissions subset check must treat key REMOVAL as fine — only additions are
    // refused — or the downgrade flow bricks.
    await seedFolder([COACH_A, COACH_B]);
    await assertSucceeds(updateDoc(doc(dbFor(COACH_A), FOLDER), {
      sharedWithCoachIDs: [COACH_B],
      [`sharedWithCoachNames.${COACH_A}`]: deleteField(),
      [`permissions.${COACH_A}`]: deleteField(),
      updatedAt: new Date(),
    }));
  });

  it('ALLOWS the self-shed on a legacy folder carrying no permissions map at all', async () => {
    // A bare field read on a missing `permissions` would ERROR, and an errored rule
    // denies — hence .get(...,{}) in isCoachLeavingFolder().
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), FOLDER), {
        ownerAthleteID: ATHLETE_UID,
        athleteUUID: 'athlete-uuid-1',
        name: 'Lessons',
        folderType: 'lessons',
        sharedWithCoachIDs: [COACH_A, COACH_B],
        videoCount: 0,
      });
    });
    await assertSucceeds(updateDoc(doc(dbFor(COACH_A), FOLDER), {
      sharedWithCoachIDs: [COACH_B],
      updatedAt: new Date(),
    }));
  });

  it('DENIES the swap [A,B] -> [C] — cardinality alone is not "none added"', async () => {
    // The original bug. Size 1 == 2-1 passes, and A really is absent from the new
    // array, so every clause of the old rule was satisfied: coach A ejected coach B
    // and injected an account the athlete never invited. C then carries no
    // coach_access_revocations doc, so a later revoke of A leaves C with access.
    await seedFolder([COACH_A, COACH_B]);
    await assertFails(updateDoc(doc(dbFor(COACH_A), FOLDER), {
      sharedWithCoachIDs: [COACH_C],
      updatedAt: new Date(),
    }));
  });

  it('DENIES granting permissions to a new coach in the same write', async () => {
    await seedFolder([COACH_A, COACH_B]);
    await assertFails(updateDoc(doc(dbFor(COACH_A), FOLDER), {
      sharedWithCoachIDs: [COACH_B],
      [`permissions.${COACH_C}`]: perm(true, true, true),
      updatedAt: new Date(),
    }));
  });

  it('DENIES a coach removing a DIFFERENT coach while staying themselves', async () => {
    await seedFolder([COACH_A, COACH_B]);
    await assertFails(updateDoc(doc(dbFor(COACH_A), FOLDER), {
      sharedWithCoachIDs: [COACH_A],
      updatedAt: new Date(),
    }));
  });

  it('DENIES a non-member writing the folder at all', async () => {
    await seedFolder([COACH_A]);
    await assertFails(updateDoc(doc(dbFor(COACH_C), FOLDER), {
      sharedWithCoachIDs: [COACH_A, COACH_C],
      updatedAt: new Date(),
    }));
  });
});

describe('sharedFolders — owner update branch', () => {
  it('ALLOWS the owner to remove a coach', async () => {
    await seedFolder([COACH_A, COACH_B]);
    await assertSucceeds(updateDoc(doc(dbFor(ATHLETE_UID), FOLDER), {
      sharedWithCoachIDs: [COACH_B],
      updatedAt: new Date(),
    }));
  });

  it('DENIES the owner ADDING a coach directly — that must go through the Cloud Function seat transaction', async () => {
    await seedFolder([COACH_A]);
    await assertFails(updateDoc(doc(dbFor(ATHLETE_UID), FOLDER), {
      sharedWithCoachIDs: [COACH_A, COACH_B],
      updatedAt: new Date(),
    }));
  });
});

describe('sharedFolders — the athlete-deletion cascade query', () => {
  // performDeleteAthlete finds an athlete's folders to tear down. Firestore evaluates
  // list rules against the query's POTENTIAL result set, not the documents actually
  // returned — so a query that isn't constrained the way the read rule is gets rejected
  // outright, even when every match would have been readable. If that happens here the
  // cascade throws, the catch logs it, and a deleted child's folders quietly stay live.
  beforeEach(async () => {
    await seedFolder([COACH_A], { athleteUUID: 'athlete-uuid-1' });
  });

  it('DENIES an athleteUUID-only query — it does not prove ownership to the read rule', async () => {
    await assertFails(getDocs(query(
      collection(dbFor(ATHLETE_UID), 'sharedFolders'),
      where('athleteUUID', '==', 'athlete-uuid-1')
    )));
  });

  it('ALLOWS athleteUUID + ownerAthleteID — per-athlete precision AND provable ownership', async () => {
    await assertSucceeds(getDocs(query(
      collection(dbFor(ATHLETE_UID), 'sharedFolders'),
      where('athleteUUID', '==', 'athlete-uuid-1'),
      where('ownerAthleteID', '==', ATHLETE_UID)
    )));
  });

  it('DENIES a stranger querying another account\'s folders even with both filters', async () => {
    await assertFails(getDocs(query(
      collection(dbFor(COACH_C), 'sharedFolders'),
      where('athleteUUID', '==', 'athlete-uuid-1'),
      where('ownerAthleteID', '==', ATHLETE_UID)
    )));
  });
});

describe('videos — sharedFolderID immutability', () => {
  const PERSONAL = 'videos/personal-clip';

  beforeEach(async () => {
    await seedFolder([COACH_A]);
    // A personal clip is created WITHOUT sharedFolderID — which is exactly what made
    // the old guard vacuous, since it only applied when the field already existed.
    await seedDoc(PERSONAL, {
      uploadedBy: COACH_C,
      fileName: 'clip.mov',
      firebaseStorageURL: '',
      uploadStatus: 'completed',
      visibility: 'private',
    });
  });

  it('DENIES adding a sharedFolderID to a personal clip by update', async () => {
    // The injection primitive: it put attacker-authored clips into a folder the
    // uploader has no access to, bypassing the create rule's hasPermission(upload) +
    // canAccessFolder pair — and fed the shared-folder branch of dailyStorageCleanup.
    await assertFails(updateDoc(doc(dbFor(COACH_C), PERSONAL), {
      sharedFolderID: FOLDER_ID,
      updatedAt: new Date(),
    }));
  });

  it('ALLOWS a normal update to a personal clip that leaves sharedFolderID absent', async () => {
    await assertSucceeds(updateDoc(doc(dbFor(COACH_C), PERSONAL), {
      visibility: 'private',
      updatedAt: new Date(),
    }));
  });

  it('DENIES changing an existing sharedFolderID to another folder', async () => {
    await seedDoc('videos/shared-clip', {
      uploadedBy: COACH_A,
      sharedFolderID: FOLDER_ID,
      fileName: 'shared.mov',
      firebaseStorageURL: '',
      uploadStatus: 'completed',
      visibility: 'shared',
    });
    await assertFails(updateDoc(doc(dbFor(COACH_A), 'videos/shared-clip'), {
      sharedFolderID: 'some-other-folder',
      updatedAt: new Date(),
    }));
  });
});

describe('coach_access_revocations — delete', () => {
  const REVOCATION = `coach_access_revocations/${FOLDER_ID}_${COACH_A}`;

  beforeEach(async () => {
    await seedFolder([]);
    await seedDoc(REVOCATION, {
      folderID: FOLDER_ID,
      coachID: COACH_A,
      athleteID: ATHLETE_UID,
      revokedAt: new Date(),
    });
  });

  it('DENIES the revoked coach deleting their own revocation record', async () => {
    // The subject of a deny-list entry must not control the entry.
    // isCoachRevokedFromFolder() is a bare exists() on this doc, so deleting it
    // clears the backstop — and nothing recreates it.
    await assertFails(deleteDoc(doc(dbFor(COACH_A), REVOCATION)));
  });

  it('ALLOWS the athlete to delete it (re-invite path)', async () => {
    await assertSucceeds(deleteDoc(doc(dbFor(ATHLETE_UID), REVOCATION)));
  });
});

describe('users — tier source fields are CF-managed', () => {
  it('DENIES a coach writing coachTierSource', async () => {
    // The one discriminator the server uses to decide whether a lapsed coach
    // subscription may be written back down. Client-writable meant: buy, set
    // 'manual', refund, keep the seats forever.
    await assertFails(updateDoc(doc(dbFor(COACH_A), `users/${COACH_A}`), {
      coachTierSource: 'manual',
    }));
  });

  it('DENIES a coach writing athleteTierSource (the twin that was already frozen)', async () => {
    await assertFails(updateDoc(doc(dbFor(COACH_A), `users/${COACH_A}`), {
      athleteTierSource: 'manual',
    }));
  });

  it('DENIES a coach escalating their own coachSubscriptionTier', async () => {
    await assertFails(updateDoc(doc(dbFor(COACH_A), `users/${COACH_A}`), {
      coachSubscriptionTier: 'coach_academy',
    }));
  });

  it('ALLOWS an ordinary profile update that touches none of them', async () => {
    await assertSucceeds(updateDoc(doc(dbFor(COACH_A), `users/${COACH_A}`), {
      displayName: 'Coach A',
    }));
  });
});
