/**
 * Firestore rules tests for `appConfig/{docID}`.
 *
 * appConfig/killSwitches can switch features OFF for every user, so the rule
 * that matters is the one that ISN'T there: no client write path. Reads are
 * open to any signed-in user (and only them) — which is also why nothing
 * secret may live in these docs.
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
import { deleteDoc, doc, getDoc, setDoc, updateDoc } from 'firebase/firestore';

const KILL_DOC = 'appConfig/killSwitches';

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    // Distinct projectId: test FILES run in parallel against one emulator and
    // projectId namespaces their data (see sharedFolders.test.mjs).
    projectId: 'demo-playerpath-rules-appconfig',
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
    await setDoc(doc(ctx.firestore(), KILL_DOC), {
      bulkVideoImport: { off: false },
    });
  });
});

describe('appConfig', () => {
  it('lets a signed-in user read the kill switches', async () => {
    const db = testEnv.authenticatedContext('any-user').firestore();
    await assertSucceeds(getDoc(doc(db, KILL_DOC)));
  });

  it('denies signed-out reads', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, KILL_DOC)));
  });

  it('denies a signed-in user flipping a switch', async () => {
    const db = testEnv.authenticatedContext('any-user').firestore();
    await assertFails(updateDoc(doc(db, KILL_DOC), { 'bulkVideoImport.off': true }));
  });

  it('denies a signed-in user overwriting or creating a config doc', async () => {
    const db = testEnv.authenticatedContext('any-user').firestore();
    await assertFails(setDoc(doc(db, KILL_DOC), { reelGeneration: { off: true } }));
    await assertFails(setDoc(doc(db, 'appConfig/current'), { minimumVersion: '99.0' }));
  });

  it('denies a signed-in user deleting a config doc', async () => {
    const db = testEnv.authenticatedContext('any-user').firestore();
    await assertFails(deleteDoc(doc(db, KILL_DOC)));
  });
});
