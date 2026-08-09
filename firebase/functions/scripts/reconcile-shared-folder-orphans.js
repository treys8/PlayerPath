#!/usr/bin/env node
/**
 * Security review 2026-08-06, finding #4 — one-time backfill.
 *
 * Deletes Storage objects under `shared_folders/{folderID}/` whose folder document no
 * longer exists in Firestore.
 *
 * WHY THESE EXIST: until 2026-08-06 nothing ever deleted shared-folder Storage objects.
 * cleanupUserDataOnDelete swept only athlete_videos/, athlete_photos/ and
 * recruiting_headshots/, and the client folder-delete path could leave bytes behind on any
 * failure. So every clip an athlete shared with a coach survived account deletion —
 * permanently, and reachable through the non-expiring download token minted at upload.
 * Once the Firestore docs were gone there was no query left that could even find them,
 * which is exactly why this has to walk the bucket instead.
 *
 * The code fix (deleteFiles in cleanupUserDataOnDelete + the onSharedFolderDeleted
 * backstop) only prevents NEW orphans. This clears the existing ones.
 *
 * Usage (from firebase/functions/):
 *   GOOGLE_APPLICATION_CREDENTIALS=path/to/serviceAccount.json node scripts/reconcile-shared-folder-orphans.js          # dry run (default)
 *   GOOGLE_APPLICATION_CREDENTIALS=path/to/serviceAccount.json node scripts/reconcile-shared-folder-orphans.js --apply  # actually delete
 *
 * READ THE DRY-RUN OUTPUT BEFORE PASSING --apply. This deletes real families' video
 * permanently. Check the bucket's soft-delete policy first — it is the only undo:
 *   gcloud storage buckets describe gs://<bucket> --format='value(soft_delete_policy)'
 *
 * ── Why the delete path looks paranoid ────────────────────────────────────────────────
 * "Its folder doc is missing" is a single, racy signal, and the first version of this
 * script acted on it directly. Three things were wrong and all three are fixed below.
 *
 *  1. ORDERING. Firestore was read first and the bucket listed second. On a large bucket
 *     the listing takes minutes, and the athlete flow is literally "create folder doc →
 *     upload clip" — so a folder created during the listing was classified as an orphan
 *     and deleted. Now: Storage is listed FIRST, and every candidate is re-read from
 *     Firestore immediately before its delete.
 *  2. DELETE BY PREFIX. `bucket.deleteFiles({ prefix })` runs its OWN listing at delete
 *     time, so it removes whatever is under the prefix THEN — including objects uploaded
 *     after the dry run. The dry-run output was therefore not a contract about what
 *     --apply would destroy. Now: the enumerated File objects are deleted individually,
 *     pinned with ifGenerationMatch so a re-uploaded same-named object is never hit.
 *  3. ONE SIGNAL. Now cross-checked against `videos where sharedFolderID == id`. That is
 *     a real independent signal, not belt-and-braces: deleteSharedFolder DELIBERATELY
 *     preserves video docs whose Storage delete failed, so surviving docs mean the prefix
 *     is not dead.
 */

const fs = require('fs');
const path = require('path');
const { preflight } = require('./_preflight');

const { db, bucket } = preflight();
const APPLY = process.argv.includes('--apply');

/**
 * Refuse to act if the orphan share looks implausibly high.
 *
 * The catastrophic failure mode is a Firestore read that returns little or nothing — a
 * permissions problem, the wrong project, an empty emulator — because then everything looks
 * orphaned. A bucket holding many folder prefixes while Firestore reports almost no folders
 * is not a plausible steady state; it is the signature of a bad read.
 *
 * Named for what it is. It was `MIN_PLAUSIBLE_RATIO`, which reads as a floor while being
 * used as a ceiling.
 *
 * This is a coarse net and it is NOT the real protection — on a small folder population a
 * legitimate run can trip it (3 live folders, 4 orphans = 57%), and a guard whose documented
 * remedy is an env var that disables it trains you to disable it. The real protection is the
 * per-candidate re-read and videos cross-check in `isConfirmedOrphan`, which never needs an
 * override.
 */
const MAX_ORPHAN_RATIO = 0.5;

/**
 * Second-stage verification, run immediately before each delete rather than once up front.
 * Both checks are cheap (one doc read, one single-field equality query) and both close a
 * race the batch classification cannot.
 */
async function isConfirmedOrphan(folderID) {
  const folderSnap = await db.collection('sharedFolders').doc(folderID).get();
  if (folderSnap.exists) {
    return { ok: false, reason: 'folder doc exists now (created during this run)' };
  }
  const vids = await db.collection('videos')
    .where('sharedFolderID', '==', folderID)
    .limit(1)
    .get();
  if (!vids.empty) {
    return { ok: false, reason: 'live videos doc(s) still reference this folder' };
  }
  return { ok: true };
}

async function main() {
  console.log(`Mode: ${APPLY ? 'APPLY (objects will be DELETED)' : 'DRY RUN'}\n`);

  // 1. Every folder prefix present in Storage, with its objects and byte count.
  //    Listed FIRST so the Firestore snapshot below is strictly NEWER than the listing —
  //    a folder created mid-run then appears live rather than orphaned.
  const byFolder = new Map(); // folderID -> { files: File[], bytes: number }
  let pageToken;
  let totalObjects = 0;
  do {
    const [files, nextQuery] = await bucket.getFiles({
      prefix: 'shared_folders/',
      maxResults: 1000,
      autoPaginate: false,
      pageToken,
    });
    for (const f of files) {
      totalObjects++;
      // shared_folders/{folderID}/... — including .../thumbnails/{name}
      const parts = f.name.split('/');
      if (parts.length < 3 || parts[0] !== 'shared_folders' || !parts[1]) continue;
      const folderID = parts[1];
      if (!byFolder.has(folderID)) byFolder.set(folderID, { files: [], bytes: 0 });
      const entry = byFolder.get(folderID);
      entry.files.push(f);
      entry.bytes += Number(f.metadata?.size || 0);
    }
    pageToken = nextQuery?.pageToken;
  } while (pageToken);

  console.log(`Storage objects under shared_folders/: ${totalObjects}`);
  console.log(`Distinct folder prefixes in Storage:   ${byFolder.size}`);

  // 2. Every folder ID that exists in Firestore. Complete — cursor-paged, no limit.
  const liveFolderIDs = new Set();
  let cursor;
  while (true) {
    let q = db.collection('sharedFolders').orderBy('__name__').limit(500);
    if (cursor) q = q.startAfter(cursor);
    const snap = await q.get();
    if (snap.empty) break;
    snap.docs.forEach((d) => liveFolderIDs.add(d.id));
    cursor = snap.docs[snap.docs.length - 1];
    if (snap.size < 500) break;
  }
  console.log(`Live sharedFolders docs:               ${liveFolderIDs.size}\n`);

  const orphans = [...byFolder.entries()].filter(([id]) => !liveFolderIDs.has(id));
  const orphanBytes = orphans.reduce((n, [, v]) => n + v.bytes, 0);
  const orphanObjects = orphans.reduce((n, [, v]) => n + v.files.length, 0);

  // 3. Sanity gate — see MAX_ORPHAN_RATIO.
  if (byFolder.size > 0 && liveFolderIDs.size === 0) {
    console.error('\n❌ ABORT: Storage has folder prefixes but Firestore returned ZERO sharedFolders docs.');
    console.error('   That is far more likely to be a credentials/project problem than a real state.');
    console.error('   Refusing to treat every object as an orphan.');
    process.exit(1);
  }
  if (byFolder.size > 0 && orphans.length / byFolder.size > MAX_ORPHAN_RATIO) {
    console.error(`\n⚠️  ${orphans.length} of ${byFolder.size} folder prefixes (${Math.round(100 * orphans.length / byFolder.size)}%) look orphaned.`);
    console.error('   That is high enough to suspect a bad Firestore read rather than real orphans.');
    if (APPLY && !process.env.FORCE_HIGH_RATIO) {
      console.error('   Refusing to --apply. Re-run the dry run, confirm the sample below is genuinely');
      console.error('   dead, then re-run with FORCE_HIGH_RATIO=1 to override.');
      process.exit(1);
    }
    if (APPLY) {
      console.error('   FORCE_HIGH_RATIO is set — proceeding. Per-folder verification still applies.');
    }
  }

  console.log(`Orphaned folder prefixes: ${orphans.length}`);
  console.log(`Orphaned objects:         ${orphanObjects}`);
  console.log(`Orphaned bytes:           ${(orphanBytes / 1e9).toFixed(2)} GB\n`);

  if (orphans.length === 0) {
    console.log('Nothing to do.');
    return;
  }

  console.log('Sample (first 10 orphaned prefixes):');
  for (const [id, v] of orphans.slice(0, 10)) {
    console.log(`  shared_folders/${id}/  — ${v.files.length} object(s), ${(v.bytes / 1e6).toFixed(1)} MB`);
  }
  console.log('');

  if (!APPLY) {
    console.log('DRY RUN — nothing deleted. Re-run with --apply once the above looks right.');
    return;
  }

  // 4. Manifest BEFORE the first delete. Deleting a child's video with no record of what
  //    was removed is indefensible, and it is the only way to answer "what did we lose?"
  //    if the classification turns out to have been wrong.
  const manifestPath = path.resolve(
    process.cwd(),
    `orphan-manifest-${new Date().toISOString().replace(/[:.]/g, '-')}.json`,
  );
  fs.writeFileSync(manifestPath, JSON.stringify({
    generatedAt: new Date().toISOString(),
    bucket: bucket.name,
    liveFolderCount: liveFolderIDs.size,
    orphans: orphans.map(([id, v]) => ({
      folderID: id,
      bytes: v.bytes,
      files: v.files.map((f) => ({
        name: f.name,
        size: Number(f.metadata?.size || 0),
        generation: f.metadata?.generation,
        updated: f.metadata?.updated,
      })),
    })),
  }, null, 2));
  console.log(`Manifest written: ${manifestPath}\n`);

  let deleted = 0;
  let skipped = 0;
  let failed = 0;
  for (const [id, v] of orphans) {
    const verdict = await isConfirmedOrphan(id);
    if (!verdict.ok) {
      skipped++;
      console.log(`↷ skip shared_folders/${id}/ — ${verdict.reason}`);
      continue;
    }
    // Delete the objects we actually ENUMERATED, pinned to the generation we saw. Never
    // deleteFiles({prefix}), which re-lists and would sweep up anything uploaded since.
    let folderDeleted = 0;
    for (const f of v.files) {
      try {
        await f.delete({ ifGenerationMatch: f.metadata.generation });
        folderDeleted++;
      } catch (err) {
        if (err.code === 404) continue; // already gone — fine, idempotent
        failed++;
        console.error(`✘ ${f.name} —`, err.message);
      }
    }
    deleted += folderDeleted;
    console.log(`✔ shared_folders/${id}/ — ${folderDeleted}/${v.files.length} objects deleted`);
  }

  console.log(`\nDone. ${deleted} object(s) deleted, ${skipped} prefix(es) skipped as not-orphaned, ${failed} object(s) failed.`);
  console.log(`Manifest: ${manifestPath}`);
  if (failed > 0) process.exitCode = 1;
}

main().catch((err) => {
  console.error('Fatal:', err);
  process.exit(1);
});
