/**
 * Shared startup guard for the Admin-SDK maintenance scripts.
 *
 * These scripts run by hand against production, with credentials that bypass both
 * firestore.rules and storage.rules, against data that is video of children. The guard
 * exists because two things were wrong with the ad-hoc `admin.initializeApp()` they used:
 *
 *  1. **It did not work.** With only GOOGLE_APPLICATION_CREDENTIALS set, `options.storageBucket`
 *     is undefined and `admin.storage().bucket()` throws
 *     "Bucket name not specified or invalid" at module load — so the usage line in each
 *     script's own header was wrong. Failing loud is fine; the hazard is the operator
 *     improvising a fix under pressure on a script that deletes things.
 *
 *  2. **It never said which project it was about to touch.** `admin.app().options.projectId`
 *     is undefined under ADC, so the banner read "(from credentials)" — i.e. nothing.
 *
 * And one thing that was merely waiting to go wrong: this repo runs a Firestore emulator for
 * the rules tests (`firebase/rules-tests`). With FIRESTORE_EMULATOR_HOST still exported in the
 * shell, Firestore reads would hit an empty emulator while Storage hit real GCS — which for
 * the reconcile script means every object in production looks orphaned.
 */

const path = require('path');
const admin = require('firebase-admin');

const EXPECTED_PROJECT = 'playerpath-159b2';
const EXPECTED_BUCKET = 'playerpath-159b2.firebasestorage.app';

const EMULATOR_VARS = [
  'FIRESTORE_EMULATOR_HOST',
  'STORAGE_EMULATOR_HOST',
  'FIREBASE_STORAGE_EMULATOR_HOST',
  'FIREBASE_AUTH_EMULATOR_HOST',
  'FIREBASE_EMULATOR_HUB',
];

function die(msg) {
  console.error(`ABORT: ${msg}`);
  process.exit(1);
}

/**
 * Validates the environment and initializes the Admin SDK against the expected project.
 * Returns `{ admin, db, bucket }`. Exits non-zero rather than guessing.
 */
function preflight() {
  for (const v of EMULATOR_VARS) {
    if (process.env[v]) {
      die(`${v}=${process.env[v]} is set. Refusing to run with an emulator in the environment — ` +
          `a half-emulated run reads an empty Firestore against a real bucket.`);
    }
  }

  const credPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (!credPath) {
    die('GOOGLE_APPLICATION_CREDENTIALS is not set. Point it at a service-account JSON for ' +
        `${EXPECTED_PROJECT}.`);
  }

  let sa;
  try {
    sa = require(path.resolve(credPath));
  } catch (err) {
    die(`could not read GOOGLE_APPLICATION_CREDENTIALS (${credPath}): ${err.message}`);
  }

  if (sa.project_id !== EXPECTED_PROJECT) {
    die(`credentials are for project '${sa.project_id}', expected '${EXPECTED_PROJECT}'.`);
  }

  // Explicit, so the bucket is never inferred and the banner below can never lie.
  admin.initializeApp({
    projectId: EXPECTED_PROJECT,
    storageBucket: EXPECTED_BUCKET,
    credential: admin.credential.applicationDefault(),
  });

  console.log(`Project: ${EXPECTED_PROJECT}`);
  console.log(`Bucket:  ${EXPECTED_BUCKET}`);
  console.log(`Service account: ${sa.client_email}\n`);

  return {
    admin,
    db: admin.firestore(),
    bucket: admin.storage().bucket(),
  };
}

module.exports = { preflight, EXPECTED_PROJECT, EXPECTED_BUCKET };
