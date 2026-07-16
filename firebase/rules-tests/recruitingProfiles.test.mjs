/**
 * Firestore rules tests for `recruitingProfiles`.
 *
 * These back a PUBLIC web page, so the rules carry more weight than most:
 * getting the tier gate backwards would either paywall a kill switch or let a
 * free account publish a minor's photo to the open internet.
 *
 * The load-bearing pair is "a non-Pro account CANNOT publish" + "a non-Pro
 * account CAN unpublish". They look like one rule and are two, and inverting the
 * second is invisible until a family's card lapses and they can't take their
 * kid's page down.
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
import { doc, getDoc, setDoc, updateDoc, deleteDoc } from 'firebase/firestore';

const PRO_UID = 'pro-owner';
const FREE_UID = 'free-owner';
const OTHER_UID = 'someone-else';
const ATHLETE_ID = 'athlete-uuid-1';
const TOKEN = 'token-abc';
const PROFILE = `recruitingProfiles/${ATHLETE_ID}`;

let testEnv;

/** A valid published-profile payload owned by `uid`. */
function profileData(uid, overrides = {}) {
  return {
    userId: uid,
    athleteId: ATHLETE_ID,
    shareToken: TOKEN,
    isPublished: true,
    sport: 'baseball',
    name: 'Jordan R.',
    highlights: [{ videoStoragePath: `athlete_videos/${uid}/a.mov`, label: 'Triple' }],
    ...overrides,
  };
}

/** Grants `uid` the token claim that a profile create requires. */
async function seedTokenClaim(uid, token = TOKEN, athleteId = ATHLETE_ID) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'recruitingTokens', token), { userId: uid, athleteId });
  });
}

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-playerpath-rules',
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
  // hasProTier() reads users/{uid}.subscriptionTier, so the tier lives on a doc
  // the tests must seed with rules disabled.
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'users', PRO_UID), { subscriptionTier: 'pro' });
    await setDoc(doc(db, 'users', FREE_UID), { subscriptionTier: 'free' });
    await setDoc(doc(db, 'users', OTHER_UID), { subscriptionTier: 'pro' });
  });
});

/** Seeds an existing published profile owned by `uid`, bypassing rules. */
async function seedProfile(uid, overrides = {}) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), PROFILE), profileData(uid, overrides));
  });
}

const dbFor = (uid) => testEnv.authenticatedContext(uid).firestore();
const anonDb = () => testEnv.unauthenticatedContext().firestore();

describe('recruitingProfiles — create', () => {
  // Publishing requires holding the token claim, so every create case starts from
  // a legitimately claimed token unless it's testing the claim itself.
  beforeEach(async () => {
    await seedTokenClaim(PRO_UID);
  });

  it('allows a Pro owner to publish', async () => {
    await assertSucceeds(setDoc(doc(dbFor(PRO_UID), PROFILE), profileData(PRO_UID)));
  });

  it('denies a free-tier owner (publishing is the Pro hook)', async () => {
    await seedTokenClaim(FREE_UID, 'token-free');
    await assertFails(
      setDoc(doc(dbFor(FREE_UID), PROFILE), profileData(FREE_UID, { shareToken: 'token-free' }))
    );
  });

  it('denies writing a profile owned by someone else', async () => {
    await assertFails(setDoc(doc(dbFor(PRO_UID), PROFILE), profileData(OTHER_UID)));
  });

  it('denies a payload missing a required key', async () => {
    const { name, ...withoutName } = profileData(PRO_UID);
    await assertFails(setDoc(doc(dbFor(PRO_UID), PROFILE), withoutName));
  });

  it('denies more than 8 highlights', async () => {
    const highlights = Array.from({ length: 9 }, (_, i) => ({
      videoStoragePath: `athlete_videos/${PRO_UID}/${i}.mov`,
      label: `Clip ${i}`,
    }));
    await assertFails(setDoc(doc(dbFor(PRO_UID), PROFILE), profileData(PRO_UID, { highlights })));
  });

  it('denies a doc id that does not match athleteId', async () => {
    await assertFails(
      setDoc(doc(dbFor(PRO_UID), 'recruitingProfiles/some-other-id'), profileData(PRO_UID))
    );
  });

  // serveRecruitingProfile signs headshotPath with the Admin SDK, which ignores
  // storage.rules — so a path pointing at someone else's namespace would come
  // back as a working signed URL to their private object.
  it("denies a headshotPath in another user's storage namespace", async () => {
    await assertFails(
      setDoc(
        doc(dbFor(PRO_UID), PROFILE),
        profileData(PRO_UID, { headshotPath: `recruiting_headshots/${OTHER_UID}/x.jpg` })
      )
    );
  });

  it('denies a headshotPath outside the recruiting_headshots namespace', async () => {
    await assertFails(
      setDoc(
        doc(dbFor(PRO_UID), PROFILE),
        profileData(PRO_UID, { headshotPath: `athlete_videos/${PRO_UID}/private.mov` })
      )
    );
  });

  it('allows the athlete’s own headshotPath', async () => {
    await assertSucceeds(
      setDoc(
        doc(dbFor(PRO_UID), PROFILE),
        profileData(PRO_UID, { headshotPath: `recruiting_headshots/${PRO_UID}/${ATHLETE_ID}.jpg` })
      )
    );
  });

  it('denies a headshotPath escaping the namespace with ..', async () => {
    await assertFails(
      setDoc(
        doc(dbFor(PRO_UID), PROFILE),
        profileData(PRO_UID, {
          headshotPath: `recruiting_headshots/${PRO_UID}/../../athlete_videos/${OTHER_UID}/x.mov`,
        })
      )
    );
  });

  it('denies publishing with a shareToken this account has no claim on', async () => {
    await assertFails(
      setDoc(doc(dbFor(PRO_UID), PROFILE), profileData(PRO_UID, { shareToken: 'never-claimed' }))
    );
  });
});

// A share token travels in emails, so anyone the link was forwarded to knows it.
// Without an atomic claim, they could publish their own profile under it and the
// CF's `where(shareToken).limit(1)` would arbitrarily serve their page at the
// victim's URL.
describe('recruitingTokens — the uniqueness claim', () => {
  const CLAIM = `recruitingTokens/${TOKEN}`;

  it('allows claiming a free token', async () => {
    await assertSucceeds(
      setDoc(doc(dbFor(PRO_UID), CLAIM), { userId: PRO_UID, athleteId: ATHLETE_ID })
    );
  });

  it('denies claiming a token someone else already holds', async () => {
    await seedTokenClaim(OTHER_UID);
    await assertFails(
      setDoc(doc(dbFor(PRO_UID), CLAIM), { userId: PRO_UID, athleteId: ATHLETE_ID })
    );
  });

  it('denies claiming on behalf of another user', async () => {
    await assertFails(
      setDoc(doc(dbFor(PRO_UID), CLAIM), { userId: OTHER_UID, athleteId: ATHLETE_ID })
    );
  });

  it('denies deleting a claim — releasing it would let a live link be hijacked', async () => {
    await seedTokenClaim(PRO_UID);
    await assertFails(deleteDoc(doc(dbFor(PRO_UID), CLAIM)));
  });

  it('denies publishing under another account’s claimed token', async () => {
    // OTHER_UID holds the token; PRO_UID knows it (they were sent the link).
    await seedTokenClaim(OTHER_UID);
    await assertFails(setDoc(doc(dbFor(PRO_UID), PROFILE), profileData(PRO_UID)));
  });

  it('denies reusing a claim minted for a different athlete', async () => {
    await seedTokenClaim(PRO_UID, TOKEN, 'a-different-athlete');
    await assertFails(setDoc(doc(dbFor(PRO_UID), PROFILE), profileData(PRO_UID)));
  });
});

describe('recruitingProfiles — read', () => {
  it('allows the owner to read their own', async () => {
    await seedProfile(PRO_UID);
    await assertSucceeds(getDoc(doc(dbFor(PRO_UID), PROFILE)));
  });

  it('denies another signed-in user', async () => {
    await seedProfile(PRO_UID);
    await assertFails(getDoc(doc(dbFor(OTHER_UID), PROFILE)));
  });

  it('denies anonymous reads — the page is served by the CF, not the client', async () => {
    await seedProfile(PRO_UID);
    await assertFails(getDoc(doc(anonDb(), PROFILE)));
  });
});

describe('recruitingProfiles — update', () => {
  it('allows a Pro owner to republish', async () => {
    await seedProfile(PRO_UID);
    await assertSucceeds(
      updateDoc(doc(dbFor(PRO_UID), PROFILE), { name: 'Jordan Rivera', isPublished: true })
    );
  });

  it('ALLOWS a lapsed (free) owner to unpublish — the kill switch is never paywalled', async () => {
    await seedProfile(FREE_UID);
    await assertSucceeds(updateDoc(doc(dbFor(FREE_UID), PROFILE), { isPublished: false }));
  });

  it('DENIES a free owner keeping the page published', async () => {
    await seedProfile(FREE_UID);
    await assertFails(updateDoc(doc(dbFor(FREE_UID), PROFILE), { name: 'New Name' }));
  });

  it('denies rotating the shareToken (would break a coach bookmark)', async () => {
    await seedProfile(PRO_UID);
    await assertFails(updateDoc(doc(dbFor(PRO_UID), PROFILE), { shareToken: 'token-xyz' }));
  });

  it('denies reassigning userId', async () => {
    await seedProfile(PRO_UID);
    await assertFails(updateDoc(doc(dbFor(PRO_UID), PROFILE), { userId: OTHER_UID }));
  });

  it('denies a non-owner update', async () => {
    await seedProfile(PRO_UID);
    await assertFails(updateDoc(doc(dbFor(OTHER_UID), PROFILE), { isPublished: false }));
  });

  it('denies growing highlights past the cap', async () => {
    await seedProfile(PRO_UID);
    const highlights = Array.from({ length: 9 }, (_, i) => ({
      videoStoragePath: `athlete_videos/${PRO_UID}/${i}.mov`,
      label: `Clip ${i}`,
    }));
    await assertFails(updateDoc(doc(dbFor(PRO_UID), PROFILE), { highlights }));
  });
});

describe('recruitingProfiles — delete', () => {
  it('allows the owner to delete (athlete deletion must kill the page)', async () => {
    await seedProfile(PRO_UID);
    await assertSucceeds(deleteDoc(doc(dbFor(PRO_UID), PROFILE)));
  });

  it('denies a non-owner delete', async () => {
    await seedProfile(PRO_UID);
    await assertFails(deleteDoc(doc(dbFor(OTHER_UID), PROFILE)));
  });
});
