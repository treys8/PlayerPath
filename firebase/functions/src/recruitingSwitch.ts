/**
 * Server-side on/off switch for the whole recruiting surface: the public page
 * (`serveRecruitingProfile`) and both recruiting pushes (`recruitingViewDigest`,
 * `recruitingLapseNotice`).
 *
 * Recruiting was hidden in the app on 2026-10-01 (`RecruitingFeature.isEnabled =
 * false`) pending more research. Hiding the editor alone would leave published
 * pages live with no in-app route to unpublish them, so the server goes dark too.
 *
 * **Fails closed.** Recruiting is OFF unless `internalState/recruiting` has
 * `enabled: true` (boolean, or the string "true" — the console's default type).
 * A missing doc or a failed read means off. To bring pages and pushes back, set
 * that field in the console; no deploy needed. Nothing is deleted while off, so
 * every share link resumes at the same URL.
 *
 * `internalState` matches no rule in firestore.rules, so clients can neither read
 * nor write it (see the MARKER note in athleteOwnership.ts). Not `appConfig`:
 * that is readable by every signed-in user and is the app's kill-only channel.
 */
import * as admin from 'firebase-admin';

const SWITCH_DOC = 'internalState/recruiting';
/** Per-instance cache, so the page route isn't a Firestore read per request. */
const CACHE_MS = 60 * 1000;

let cached: { enabled: boolean; at: number } | null = null;

export async function recruitingEnabled(): Promise<boolean> {
  if (cached && Date.now() - cached.at < CACHE_MS) return cached.enabled;
  let enabled = false;
  try {
    const snap = await admin.firestore().doc(SWITCH_DOC).get();
    const raw = snap.get('enabled');
    enabled = raw === true || (typeof raw === 'string' && raw.trim().toLowerCase() === 'true');
  } catch (err) {
    console.warn(`recruitingEnabled: could not read ${SWITCH_DOC} — treating as off`, err);
  }
  cached = { enabled, at: Date.now() };
  return enabled;
}
