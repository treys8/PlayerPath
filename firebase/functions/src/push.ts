/**
 * FCM push helpers, shared across modules.
 *
 * Lived in index.ts until recruitingProfile.ts needed to send a push:
 * index.ts re-exports recruitingProfile.ts, so importing back the other way
 * would be circular. Bodies are moved verbatim; call sites are unchanged.
 */

import * as admin from 'firebase-admin';

/**
 * APNs grouping/replacement options for a push.
 *
 * `threadId` (aps `thread-id`) groups notifications into one stack in
 * Notification Center. `collapseId` (the `apns-collapse-id` header) makes a new
 * push REPLACE the previous undelivered/displayed one with the same id, which
 * is what keeps a 15-clip upload from stacking 15 banners. Neither is set by
 * default — a caller opts in per notification family.
 *
 * `apns-collapse-id` is limited to 64 bytes by APNs; callers build ids from a
 * short prefix plus a UUID, which stays well inside that.
 */
export interface PushGrouping {
  /** aps `thread-id` — groups in Notification Center. */
  threadId?: string;
  /** `apns-collapse-id` — replaces the previous banner with the same id. */
  collapseId?: string;
}

/**
 * Sends an FCM push notification to a specific user's devices.
 * Reads fcmTokens from the user's Firestore document.
 * Automatically cleans up invalid/expired tokens.
 * Best-effort — failures are logged but never thrown.
 */
export async function sendPushNotification(
  userID: string,
  title: string,
  body: string,
  data: Record<string, string> = {},
  category?: string,
  grouping?: PushGrouping
): Promise<void> {
  try {
    const userDoc = await admin.firestore().collection('users').doc(userID).get();
    if (!userDoc.exists) return;

    const userData = userDoc.data()!;
    const fcmTokens: string[] = userData.fcmTokens || [];
    if (fcmTokens.length === 0) return;

    // Respect the recipient's activity-notification toggles. Only these push
    // types are user-toggleable; uploads/weekly-stats/game-reminders are
    // local (on-device) notifications and invitations are transactional, so
    // they are never gated here. Suppress only on an explicit `false` — a
    // missing pref defaults to enabled, matching the client default.
    const prefs = userData.notificationPreferences || {};
    const pushType = data.type || '';
    if ((pushType === 'coach_comment' || pushType === 'drill_card') && prefs.coachActivity === false) {
      console.log(`Suppressing ${pushType} push for ${userID} — coachActivity off`);
      return;
    }
    if (pushType === 'new_video' && prefs.athleteActivity === false) {
      console.log(`Suppressing ${pushType} push for ${userID} — athleteActivity off`);
      return;
    }
    // Recruiting profile-view pushes, gated by the "Profile View Alerts" toggle.
    if (pushType === 'recruiting_view' && prefs.recruitingViews === false) {
      console.log(`Suppressing ${pushType} push for ${userID} — recruitingViews off`);
      return;
    }
    // NOTE: `recruiting_offline` is deliberately absent from this list.
    // `recruitingViews` means "tell me when a coach looks at the page"; going dark
    // because Pro lapsed is a status change with consequences the athlete is
    // paying for — closer to an invitation than to activity, and the one message
    // they most need even with activity alerts off. The omission is a decision,
    // not an oversight; see recruitingLapseNotice.ts.

    const message: admin.messaging.MulticastMessage = {
      tokens: fcmTokens,
      notification: { title, body },
      // "source: activity" lets the iOS foreground handler distinguish these
      // activity-feed pushes (already mirrored by the in-app banner) from
      // locally-scheduled UN notifications, so only the former get suppressed
      // while the app is active.
      data: { ...data, type: data.type || '', source: 'activity' },
      apns: {
        // `apns-collapse-id` replaces the previously shown banner with this one
        // instead of stacking another. Set for bursty families (a multi-clip
        // share, a coach's note+drawing+drill-card pass over one clip).
        ...(grouping?.collapseId ? { headers: { 'apns-collapse-id': grouping.collapseId } } : {}),
        payload: {
          aps: {
            sound: 'default',
            // Groups this notification into one stack in Notification Center.
            ...(grouping?.threadId ? { 'thread-id': grouping.threadId } : {}),
            // Intentionally no `badge`. A hardcoded `1` lies when multiple
            // notifications stack while backgrounded (displays "1" until the
            // iOS listener attaches and resyncs via setBadgeCount, producing
            // a visible "1 → real-count" flash). The in-app
            // ActivityNotificationService is the sole badge authority.
            ...(category ? { category } : {}),
          },
        },
      },
    };

    const response = await admin.messaging().sendEachForMulticast(message);

    // Clean up invalid tokens
    if (response.failureCount > 0) {
      const tokensToRemove: string[] = [];
      response.responses.forEach((resp, idx) => {
        if (resp.error) {
          const code = resp.error.code;
          if (
            code === 'messaging/invalid-registration-token' ||
            code === 'messaging/registration-token-not-registered'
          ) {
            tokensToRemove.push(fcmTokens[idx]);
          }
        }
      });

      if (tokensToRemove.length > 0) {
        await admin.firestore().collection('users').doc(userID).update({
          fcmTokens: admin.firestore.FieldValue.arrayRemove(...tokensToRemove),
        });
        console.log(`Removed ${tokensToRemove.length} invalid FCM token(s) for user ${userID}`);
      }
    }

    console.log(`FCM sent to ${userID}: ${response.successCount} success, ${response.failureCount} fail`);
  } catch (error) {
    // Best-effort — don't fail the calling function
    console.warn(`⚠️ FCM send failed for user ${userID}:`, error);
  }
}

/**
 * Sends FCM push to multiple users in parallel.
 */
export async function sendPushToMultipleUsers(
  userIDs: string[],
  title: string,
  body: string,
  data: Record<string, string> = {},
  category?: string,
  grouping?: PushGrouping
): Promise<void> {
  await Promise.allSettled(
    userIDs.map(uid => sendPushNotification(uid, title, body, data, category, grouping))
  );
}
