#!/usr/bin/env node
/**
 * Security review 2026-08-06, finding #5 — one-time remediation.
 *
 * REMOVES `firebaseStorageDownloadTokens` from every object under `shared_folders/`, which
 * **invalidates every download URL ever issued for them**.
 *
 * WHY: until 2026-08-08 the client finalized shared-folder uploads with `downloadURL()`.
 * That permanently attaches a token to the object and returns a link Firebase serves with NO
 * authentication and WITHOUT evaluating storage.rules — forever. The string was persisted to
 * `videos/{id}.firebaseStorageURL`, readable by every coach on the folder, and nothing ever
 * rotated it. Removing a coach only arrayRemoves them and writes a revocation doc; neither
 * touches the token. So any coach who saved those URLs while authorized could keep streaming
 * a minor's clips after the family revoked them, signed out, from any browser.
 *
 * The client fix stops NEW tokens being minted. Only this retires the ones already handed out.
 *
 * REMOVES rather than ROTATES, deliberately. Writing a fresh UUID (the first version of this
 * script) swaps one permanent unauthenticated public link for another one that merely happens
 * to be unknown — the capability class survives, and any current folder member can call
 * getDownloadURL() to learn the new value, which then outlives their own revocation. Removing
 * the key leaves no public link at all. It also makes success VERIFIABLE: after a clean run,
 * re-running must report `Carrying a token: 0`. A rotate-to-new-UUID run reports the same
 * count forever, so it can never be confirmed.
 *
 * SAFE TO RUN, with one caveat. Nothing at HEAD reads these URLs: playback resolves through
 * CoachVideoLoader → SecureURLManager → getSignedVideoURL (membership + revocation re-checked,
 * short expiry), and thumbnails go through RemoteThumbnailView's secure branch, which every
 * shared-folder call site takes. Signed URLs are HMAC signatures and are completely
 * independent of the download token, so they are unaffected.
 *   ⚠️ CAVEAT: app builds older than 2026-03-23 (commit 31ad7118) predate that secure
 *   thumbnail branch and fetched the stored token URL directly. Installs on those builds will
 *   show placeholder thumbnails after this runs; playback still works, because
 *   getSecureVideoURL predates them. Check the active-version spread in App Store Connect
 *   first. Third-party caches may also serve stale thumbnails for up to a year
 *   (cacheControl: max-age=31536000), regardless of this script.
 *
 * Usage (from firebase/functions/):
 *   GOOGLE_APPLICATION_CREDENTIALS=path/to/serviceAccount.json node scripts/rotate-shared-folder-tokens.js          # dry run (default)
 *   GOOGLE_APPLICATION_CREDENTIALS=path/to/serviceAccount.json node scripts/rotate-shared-folder-tokens.js --apply  # remove tokens
 *
 * Idempotent and resumable: objects with no token are skipped, so a re-run after a partial
 * failure only revisits what is left. Exits non-zero if any object failed.
 */

const { preflight } = require('./_preflight');

const { bucket } = preflight();
const APPLY = process.argv.includes('--apply');

async function main() {
  console.log(`Mode: ${APPLY ? 'APPLY (tokens will be REMOVED)' : 'DRY RUN'}\n`);

  let scanned = 0;
  let tokened = 0;
  let cleared = 0;
  let failed = 0;
  const failures = [];
  let pageToken;

  do {
    const [files, nextQuery] = await bucket.getFiles({
      prefix: 'shared_folders/',
      maxResults: 500,
      autoPaginate: false,
      pageToken,
    });

    for (const file of files) {
      scanned++;
      // Only objects that actually carry a token have a live public link. Ones uploaded by
      // the fixed client never got one, so there is nothing to retire and no reason to
      // issue a write for them. This is also what makes the script resumable.
      const existing = file.metadata?.metadata?.firebaseStorageDownloadTokens;
      if (!existing) continue;
      tokened++;

      if (!APPLY) {
        if (tokened <= 10) console.log(`  would clear: ${file.name}`);
        continue;
      }

      try {
        // `null` removes the key. GCS objects.patch MERGES the custom-metadata map, so
        // contentType, cacheControl and any other custom keys are untouched.
        //
        // ifMetagenerationMatch does two jobs. It is an optimistic-concurrency guard, and —
        // less obviously — it is what re-enables retries: @google-cloud/storage classifies a
        // setMetadata WITHOUT a precondition as non-idempotent and DISABLES its automatic
        // retry, so every transient 429/503 would otherwise land straight in `failed`.
        await file.setMetadata(
          { metadata: { firebaseStorageDownloadTokens: null } },
          { ifMetagenerationMatch: file.metadata.metageneration },
        );
        cleared++;
        if (cleared % 100 === 0) console.log(`  ...cleared ${cleared}`);
      } catch (err) {
        failed++;
        failures.push(file.name);
        console.error(`✘ ${file.name} —`, err.message);
      }
    }

    pageToken = nextQuery?.pageToken;
  } while (pageToken);

  console.log(`\nScanned:            ${scanned}`);
  console.log(`Carrying a token:   ${tokened}   <- these had live public links`);
  if (APPLY) {
    console.log(`Cleared:            ${cleared}`);
    console.log(`Failed:             ${failed}`);
    if (failed > 0) {
      console.error(`\n⚠️  ${failed} object(s) still carry a public token. Re-run to retry just those.`);
      console.error('   First 20:');
      for (const name of failures.slice(0, 20)) console.error(`     ${name}`);
      // Non-zero exit: a security remediation that partially failed must not look like success.
      process.exitCode = 1;
    } else {
      console.log('\nEvery previously-issued shared-folder download URL is now dead.');
      console.log('Verify by re-running the dry run — "Carrying a token" must be 0.');
    }
  } else {
    console.log('\nDRY RUN — nothing changed. Re-run with --apply to retire those links.');
  }
}

main().catch((err) => {
  console.error('Fatal:', err);
  process.exit(1);
});
