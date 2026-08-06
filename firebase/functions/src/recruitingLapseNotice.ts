/**
 * Tells an athlete when their public recruiting page has gone dark.
 *
 * ## The gap this closes
 *
 * `serveRecruitingProfile` re-checks the owner's subscription tier on every
 * render, because firestore.rules gate writes and cannot expire an at-rest doc —
 * without that check, "publish on Pro, then cancel" would leave the page up
 * forever. It is the right design and it stays.
 *
 * But its failure mode is silent on both ends. The moment Pro lapses, every
 * college coach holding the link gets *"This profile has been unpublished or the
 * link is incorrect"* — and nothing told the athlete. They may have mailed that
 * link to thirty programs; the page reads as broken, not as unpaid, so nobody
 * writes back to say so. `RecruitingPublishView.upgradeSection` explains it
 * properly, but only to someone who happens to open that screen.
 *
 * ## Why a daily sweep and not a trigger on the tier change
 *
 * A `users/{uid}` onUpdate trigger firing on `pro` → non-`pro` would be instant
 * and cost nothing in the common case. It was rejected because
 * `syncSubscriptionTier` can briefly resolve `free` on a StoreKit hiccup — it
 * writes the tier from an AppTransaction fetch, and a failed fetch reads as "no
 * entitlement". An instant push would then tell a paying customer their kid's
 * page is offline, minutes before it corrected itself. A sweep absorbs that: a
 * tier restored within the day is never reported at all.
 *
 * The cost is up to 24 h of latency on the notice, which is the right trade for
 * "your page is offline" — a message that must never be wrong is worth more than
 * one that is merely fast.
 *
 * ## Notes for the next person
 *
 * • The watermark lives on `users/{uid}`, NOT on the profile doc. Publish is a
 *   full-overwrite `setData`, so a field there would need a carry-forward line in
 *   `RecruitingProfileService.publish` — the same reason `lastRecruitingNotifiedAt`
 *   moved to the account doc. Nothing here needs adding to that list.
 * • **One notice per lapse, and its PRESENCE is the state — not its age.** A
 *   time-windowed watermark was the first shape and it was wrong: a lapse persists
 *   until someone pays, so "re-notify after N days" means telling a family who
 *   deliberately cancelled that their page is offline every N days forever, which
 *   is a reason to mute notifications rather than to renew. Instead the watermark
 *   is CLEARED whenever the account is seen back on Pro, so a renewal re-arms the
 *   next lapse as its own episode. The accepted cost is that an undelivered push
 *   is not retried — `RecruitingPublishView.upgradeSection` is the standing
 *   in-app explanation for anyone who missed it.
 * • Writing `users/{uid}` is safe: no Cloud Function triggers on that document
 *   (only on its subcollections), so this cannot feed itself.
 * • Stamp BEFORE the send, the same invariant the render path and
 *   `recruitingViewDigest` both keep: no stamp, no push. A failed write must not
 *   be able to turn into a nightly repeat.
 * • This push is deliberately NOT gated by the `recruitingViews` preference. That
 *   toggle is for "a coach looked at your page"; this is a status change with
 *   consequences the athlete is paying for, closer to an invitation than to
 *   activity. See the comment in push.ts.
 */

import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import { sendPushNotification } from './push';

/** Docs per page. Bounds peak memory; nothing else depends on it. */
const LAPSE_PAGE_SIZE = 300;

/** Owners stamped + notified in parallel. Bounds concurrent writes and FCM sends. */
const LAPSE_OWNER_CONCURRENCY = 10;

/**
 * When to stop and report rather than be killed mid-send.
 *
 * Same reasoning as recruitingViewDigest's deadlines: an owner this run never
 * reached simply gets tomorrow's run instead — nothing is lost, unlike the
 * digest's view deltas — but a truncated sweep must still never read as a clean
 * one, or the day the corpus outgrows the pass is the day this silently stops
 * covering half of it.
 */
const LAPSE_DEADLINE_MS = 500 * 1000;

/** A published profile awaiting the tier check on its owner. */
interface PublishedProfile {
  athleteId: string;
  name: string;
}

export const recruitingLapseNotice = functions
  .runWith({ timeoutSeconds: 540, memory: '512MB' })
  // After recruitingViewDigest (01:00) and reconcileAthleteOwners (02:00).
  .pubsub.schedule('0 3 * * *')
  .timeZone('UTC')
  .onRun(async () => {
    const db = admin.firestore();
    const startedAt = Date.now();

    // Group by owner first: the tier is an ACCOUNT property, so a parent with
    // three published kids has one lapse, not three. This is also what makes the
    // users/{uid} read once-per-account instead of once-per-profile.
    const byOwner = new Map<string, PublishedProfile[]>();
    let scanned = 0;
    let truncated = false;

    // Single equality filter ordered by __name__, which the automatic
    // (isPublished, __name__) single-field index serves directly — no composite
    // index, same shape as enforceStorageQuota.
    let cursor: admin.firestore.QueryDocumentSnapshot | null = null;
    for (;;) {
      let query = db
        .collection('recruitingProfiles')
        .where('isPublished', '==', true)
        .orderBy(admin.firestore.FieldPath.documentId())
        .limit(LAPSE_PAGE_SIZE);
      if (cursor) query = query.startAfter(cursor);

      const snap = await query.get();
      if (snap.empty) break;
      cursor = snap.docs[snap.docs.length - 1];

      for (const doc of snap.docs) {
        scanned++;
        const data = doc.data() as Record<string, unknown>;
        if (typeof data.userId !== 'string' || !data.userId) continue;
        const entry: PublishedProfile = {
          athleteId: doc.id,
          name: typeof data.name === 'string' && data.name ? data.name : 'Your athlete',
        };
        const existing = byOwner.get(data.userId);
        if (existing) existing.push(entry);
        else byOwner.set(data.userId, [entry]);
      }

      // A short page is the last page.
      if (snap.size < LAPSE_PAGE_SIZE) break;
      if (Date.now() - startedAt > LAPSE_DEADLINE_MS) {
        truncated = true;
        break;
      }
    }

    /** Returns true when this owner was actually told. */
    const noticeFor = async (
      userId: string,
      profiles: PublishedProfile[]
    ): Promise<boolean> => {
      const userRef = db.collection('users').doc(userId);
      const userSnap = await userRef.get();
      // A published profile whose account doc is gone is a data bug, and
      // serveRecruitingProfile now logs it on every render — don't double-report
      // it here, and there is nobody to push to anyway.
      if (!userSnap.exists) return false;

      const data = userSnap.data() ?? {};
      const alreadyToldThisLapse = data.lastRecruitingLapseNotifiedAt !== undefined;

      if (data.subscriptionTier === 'pro') {
        // Live again. Clearing the watermark is what makes the NEXT lapse a fresh
        // episode with its own notice — without it the only options are "never tell
        // them twice, ever" and "nag forever". Normally a no-op: the field only
        // exists for an account that has actually lapsed before.
        if (alreadyToldThisLapse) {
          await userRef.update({
            lastRecruitingLapseNotifiedAt: admin.firestore.FieldValue.delete(),
          });
        }
        return false;
      }

      // Already told about THIS lapse. A page that stays down after that is their
      // decision, and repeating it is how you get muted.
      if (alreadyToldThisLapse) return false;

      // No registered device means there is no notice to burn the episode on.
      // `sendPushNotification` returns silently on an empty `fcmTokens`, so stamping
      // first would consume the one-shot for a send that never had a recipient —
      // and because this push type writes no `notifications/` doc, there is no
      // in-app mirror to fall back on. Leaving the episode open costs one read a
      // night until they have a device.
      //
      // ⚠️ Scope: this covers an account that NEVER registered a token (notifications
      // declined at the prompt). It does NOT cover tokens that went dead — those are
      // pruned by `sendPushNotification` only AFTER a failed send, so a stale array
      // passes this guard, gets stamped, sends to nothing, and is empty by the time
      // the next run's `alreadyToldThisLapse` short-circuits ahead of this check.
      // That case sits inside the deliberate "a delivery failure burns the episode"
      // line; don't read this guard as closing it.
      const tokens = data.fcmTokens;
      if (!Array.isArray(tokens) || tokens.length === 0) return false;

      // Stamp first — no stamp, no push.
      await userRef.set(
        { lastRecruitingLapseNotifiedAt: admin.firestore.FieldValue.serverTimestamp() },
        { merge: true }
      );

      const single = profiles.length === 1;
      // Only a single-profile notice can deep-link; with several there is no one
      // page to open, and MainTabView's observer lands a push carrying no
      // athleteId on the More tab root rather than guessing. Same rule as the
      // digest.
      const payload: Record<string, string> = single
        ? { type: 'recruiting_offline', athleteId: profiles[0].athleteId }
        : { type: 'recruiting_offline' };

      await sendPushNotification(
        userId,
        single ? 'Your recruiting page is offline' : 'Your recruiting pages are offline',
        // Says what broke, what it looks like to a coach, and that the link
        // survives — the last part is the promise upgradeSection already makes,
        // and it is the difference between renewing and re-sending 30 emails.
        single
          ? `${profiles[0].name}'s page isn't loading for coaches because Pro ended. Renew and the same link works again.`
          : `${profiles.length} of your athletes' pages aren't loading for coaches because Pro ended. Renew and the same links work again.`,
        payload
      );
      return true;
    };

    let notified = 0;
    let unreached = 0;
    const owners = Array.from(byOwner.entries());
    for (let i = 0; i < owners.length; i += LAPSE_OWNER_CONCURRENCY) {
      if (Date.now() - startedAt > LAPSE_DEADLINE_MS) {
        unreached = owners.length - i;
        break;
      }
      const chunk = owners.slice(i, i + LAPSE_OWNER_CONCURRENCY);
      const results = await Promise.allSettled(
        chunk.map(([userId, profiles]) => noticeFor(userId, profiles))
      );
      results.forEach((result, index) => {
        if (result.status === 'fulfilled') {
          if (result.value) notified++;
        } else {
          // Per-owner isolation: one unreadable account doc or failed stamp must
          // not cost the rest of the chunk their notice.
          console.warn(`recruitingLapseNotice: ${chunk[index][0]}`, result.reason);
        }
      });
    }

    // "handed to FCM", not "sent": sendPushNotification swallows delivery failures
    // by design, so this counts accounts that were stamped AND had a device, which
    // is the most this layer can honestly claim.
    console.log(
      `✅ recruitingLapseNotice: ${scanned} published profile(s) across ${owners.length} ` +
        `account(s), ${notified} notice(s) handed to FCM`
    );
    if (truncated) {
      console.error(
        `🚨 recruitingLapseNotice: scan deadline hit after ${scanned} profile(s) — the rest ` +
          'were not checked this run'
      );
    }
    if (unreached > 0) {
      console.error(
        `🚨 recruitingLapseNotice: send deadline hit — ${unreached} account(s) were not checked ` +
          'this run'
      );
    }
    return null;
  });
