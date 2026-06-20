import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import { Resend } from 'resend';
import { SignedDataVerifier, Environment, JWSTransactionDecodedPayload, NotificationTypeV2 } from '@apple/app-store-server-library';
import * as fs from 'fs';
import * as path from 'path';

// Initialize Firebase Admin
admin.initializeApp();

// Lazy-initialize Resend so deploy analysis doesn't crash when env var is absent
let _resend: Resend | null = null;
function getResend(): Resend {
  if (!_resend) {
    const key = process.env.RESEND_KEY;
    if (!key) throw new Error('RESEND_KEY environment variable is not set');
    _resend = new Resend(key);
  }
  return _resend;
}

// App Store download link — update with the actual App Store ID once published
const APP_STORE_URL = 'https://apps.apple.com/us/app/playerpath/id6754497342';

// Maximum signed URL expiration (30 days)
const MAX_EXPIRATION_HOURS = 720;

// Maximum batch size for signed URL requests
const MAX_BATCH_SIZE = 50;

/**
 * Escapes HTML special characters to prevent injection in email templates.
 */
function escapeHtml(str: string): string {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/**
 * Builds a human-readable clip reference for notification text.
 * Prefers a date parsed from the filename (coach-recorded `instruction_YYYY-MM-DD_…`),
 * falling back to the video's createdAt and finally a generic "your clip".
 * Avoids embedding raw UUID filenames in user-facing notification titles/bodies.
 */
function clipDescription(video: FirebaseFirestore.DocumentData | undefined | null): string {
  const fileName: string = (video?.fileName || video?.name || '') as string;
  const fromName = parseDateFromFileName(fileName);
  if (fromName) return `your ${formatClipDate(fromName)} clip`;

  const created = video?.createdAt;
  const createdDate: Date | null = created?.toDate ? created.toDate() : (created instanceof Date ? created : null);
  if (createdDate) return `your ${formatClipDate(createdDate)} clip`;

  return 'your clip';
}

function parseDateFromFileName(fileName: string): Date | null {
  const m = fileName.match(/(?:^|_)(\d{4})-(\d{2})-(\d{2})(?:_|\.|$)/);
  if (!m) return null;
  const [, y, mo, d] = m;
  const date = new Date(Date.UTC(Number(y), Number(mo) - 1, Number(d)));
  return isNaN(date.getTime()) ? null : date;
}

function formatClipDate(date: Date): string {
  return date.toLocaleDateString('en-US', {
    month: 'short', day: 'numeric', year: 'numeric', timeZone: 'UTC',
  });
}

/**
 * Sanitizes a file name to prevent path traversal.
 * Strips directory separators and ".." sequences.
 */
function sanitizeFileName(fileName: string): string {
  // Take only the last path component and reject ".."
  const base = fileName.split('/').pop()?.split('\\').pop() || '';
  if (base === '..' || base === '.' || base === '') {
    throw new functions.https.HttpsError('invalid-argument', 'Invalid file name');
  }
  return base;
}

/**
 * Clamps expiration hours to MAX_EXPIRATION_HOURS.
 */
function clampExpiration(hours: number): number {
  return Math.max(1, Math.min(hours, MAX_EXPIRATION_HOURS));
}

// Maximum emails a single user can trigger per hour
const EMAIL_RATE_LIMIT = 10;
const RATE_LIMIT_WINDOW_MS = 60 * 60 * 1000; // 1 hour

/**
 * Checks whether a user has exceeded the email rate limit.
 * Uses a Firestore counter document at emailRateLimits/{uid}.
 * Returns true if the request should be allowed, false if rate-limited.
 */
async function checkEmailRateLimit(uid: string): Promise<boolean> {
  const ref = admin.firestore().collection('emailRateLimits').doc(uid);
  const doc = await ref.get();
  const now = Date.now();

  if (!doc.exists) {
    await ref.set({ count: 1, windowStart: now });
    return true;
  }

  const data = doc.data()!;
  const windowStart = data.windowStart as number;
  const count = data.count as number;

  if (now - windowStart > RATE_LIMIT_WINDOW_MS) {
    // Window expired — reset
    await ref.set({ count: 1, windowStart: now });
    return true;
  }

  if (count >= EMAIL_RATE_LIMIT) {
    return false;
  }

  await ref.update({ count: admin.firestore.FieldValue.increment(1) });
  return true;
}

// ============================================================
// FCM Push Notification Helper
// ============================================================

/**
 * Sends an FCM push notification to a specific user's devices.
 * Reads fcmTokens from the user's Firestore document.
 * Automatically cleans up invalid/expired tokens.
 * Best-effort — failures are logged but never thrown.
 */
async function sendPushNotification(
  userID: string,
  title: string,
  body: string,
  data: Record<string, string> = {},
  category?: string
): Promise<void> {
  try {
    const userDoc = await admin.firestore().collection('users').doc(userID).get();
    if (!userDoc.exists) return;

    const userData = userDoc.data()!;
    const fcmTokens: string[] = userData.fcmTokens || [];
    if (fcmTokens.length === 0) return;

    // Respect the recipient's activity-notification toggles. Only these two
    // push types are user-toggleable; uploads/weekly-stats/game-reminders are
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

    const message: admin.messaging.MulticastMessage = {
      tokens: fcmTokens,
      notification: { title, body },
      // "source: activity" lets the iOS foreground handler distinguish these
      // activity-feed pushes (already mirrored by the in-app banner) from
      // locally-scheduled UN notifications, so only the former get suppressed
      // while the app is active.
      data: { ...data, type: data.type || '', source: 'activity' },
      apns: {
        payload: {
          aps: {
            sound: 'default',
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
async function sendPushToMultipleUsers(
  userIDs: string[],
  title: string,
  body: string,
  data: Record<string, string> = {},
  category?: string
): Promise<void> {
  await Promise.allSettled(
    userIDs.map(uid => sendPushNotification(uid, title, body, data, category))
  );
}

// ============================================================
// Activity Notification Write Helper
// ============================================================

/**
 * Writes a single activity notification to
 * `notifications/{recipientID}/items/{deterministicID}`.
 *
 * Uses `.create()` so if the client already wrote the same doc ID (shadow-mode
 * rollout of server-authored notifications) we silently skip rather than
 * overwrite and reset isRead/title/body. All notification-producing Cloud
 * Functions should call this helper — it is the single canonical server-side
 * writer. The deterministic ID is the coordination point between client and
 * server during the migration window; post-migration the client stops writing
 * entirely and the server is the sole author.
 */
async function writeActivityNotification(
  recipientID: string,
  deterministicID: string,
  data: {
    type: string;
    title: string;
    body: string;
    senderName: string;
    senderID: string;
    targetID?: string;
    targetType?: 'folder' | 'video' | 'invitation';
    folderID?: string;
  }
): Promise<void> {
  if (!recipientID || recipientID === data.senderID) return;
  const payload: Record<string, any> = {
    type: data.type,
    title: data.title,
    body: data.body,
    senderName: data.senderName,
    senderID: data.senderID,
    isRead: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (data.targetID !== undefined) payload.targetID = data.targetID;
  if (data.targetType !== undefined) payload.targetType = data.targetType;
  if (data.folderID !== undefined) payload.folderID = data.folderID;

  const ref = admin.firestore()
    .collection('notifications')
    .doc(recipientID)
    .collection('items')
    .doc(deterministicID);
  try {
    await ref.create(payload);
  } catch (err: any) {
    // 6 = ALREADY_EXISTS — expected during shadow-mode when client beat us to the doc.
    if (err?.code !== 6) {
      console.warn(`writeActivityNotification failed for ${recipientID}/${deterministicID}:`, err);
    }
  }
}

/**
 * Fans out the same notification to many recipients in parallel, scoping the
 * deterministic ID per recipient so each user's feed gets its own doc.
 */
async function writeActivityNotifications(
  recipientIDs: string[],
  deterministicIDFor: (recipientID: string) => string,
  data: Parameters<typeof writeActivityNotification>[2]
): Promise<void> {
  await Promise.allSettled(
    recipientIDs.map(rid =>
      writeActivityNotification(rid, deterministicIDFor(rid), data)
    )
  );
}

/**
 * Looks up a Firebase user ID by email. Returns null if no account exists —
 * in that case notification writes should be skipped (backfillInvitationsOnSignup
 * will cover them when the user eventually signs up).
 */
async function lookupUserIDByEmail(email: string): Promise<string | null> {
  const normalized = (email || '').toLowerCase().trim();
  if (!normalized) return null;
  try {
    const snap = await admin.firestore()
      .collection('users')
      .where('email', '==', normalized)
      .limit(1)
      .get();
    return snap.empty ? null : snap.docs[0].id;
  } catch (err) {
    console.warn(`lookupUserIDByEmail failed for ${normalized}:`, err);
    return null;
  }
}

// ============================================================
// FCM + Activity Notification Triggers for Coach/Athlete Events
// ============================================================

/**
 * When a new video is added to a shared folder, push-notify relevant users.
 * - Athlete uploads → notify all coaches with folder access
 * - Coach uploads with visibility "shared" → notify the folder owner (athlete)
 */
export const onNewSharedVideo = functions.firestore
  .document('videos/{videoId}')
  .onCreate(async (snap, context) => {
    const video = snap.data();
    const folderID = video.sharedFolderID;
    if (!folderID) return; // Personal video, not shared

    // Only notify for completed/visible videos
    if (video.uploadStatus === 'pending' || video.uploadStatus === 'failed') return;
    if (video.visibility === 'private') return;

    const folderDoc = await admin.firestore().collection('sharedFolders').doc(folderID).get();
    if (!folderDoc.exists) return;
    const folder = folderDoc.data()!;

    const videoID = context.params.videoId;
    const uploaderName = video.uploadedByName || 'Someone';
    const uploaderID: string = video.uploadedBy || '';
    const uploaderType = video.uploadedByType; // "athlete" or "coach"
    const folderName: string = folder.name || 'a folder';
    const clipRef: string = clipDescription(video);

    if (uploaderType === 'athlete') {
      // Notify all coaches with folder access
      const coachIDs: string[] = folder.sharedWithCoachIDs || [];
      if (coachIDs.length > 0) {
        await sendPushToMultipleUsers(
          coachIDs,
          'New Video Shared',
          `${uploaderName} shared a new video in ${folderName}`,
          { type: 'new_video', folderID },
          'COACH_VIDEO'
        );
        // Matches client postNewVideoNotification: targetType: folder, targetID: folderID.
        await writeActivityNotifications(
          coachIDs,
          (rid) => `newvideo_${videoID}_${rid}`,
          {
            type: 'new_video',
            title: `New Video in ${folderName}`,
            body: `${uploaderName} uploaded ${clipRef}`,
            senderName: uploaderName,
            senderID: uploaderID,
            targetID: folderID,
            targetType: 'folder',
            folderID,
          }
        );
      }
    } else if (uploaderType === 'coach') {
      // Notify the folder owner (athlete)
      const athleteID = folder.ownerAthleteID;
      if (athleteID) {
        await sendPushNotification(
          athleteID,
          'New Coach Video',
          `${uploaderName} uploaded a video for you`,
          { type: 'new_video', folderID },
          'COACH_VIDEO'
        );
        // Matches client postCoachSharedClipNotification: targetType: video, targetID: videoID.
        await writeActivityNotification(
          athleteID,
          `newvideo_${videoID}_${athleteID}`,
          {
            type: 'new_video',
            title: `New Clip from ${uploaderName}`,
            body: `${uploaderName} shared a new clip in ${folderName}`,
            senderName: uploaderName,
            senderID: uploaderID,
            targetID: videoID,
            targetType: 'video',
            folderID,
          }
        );
      }
    }
  });

/**
 * When a private video is published (visibility changes from "private" to "shared"),
 * send an FCM push to the folder owner (athlete). This covers coach session clips
 * that are shared after review — the onCreate trigger skips private videos.
 */
export const onVideoPublished = functions.firestore
  .document('videos/{videoId}')
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();

    // Only fire when visibility transitions from private to non-private
    if (before.visibility === 'private' && after.visibility !== 'private') {
      const folderID = after.sharedFolderID;
      if (!folderID) return;

      // Only notify for coach uploads — athlete uploads are already handled by onCreate
      if (after.uploadedByType !== 'coach') return;

      const folderDoc = await admin.firestore().collection('sharedFolders').doc(folderID).get();
      if (!folderDoc.exists) return;
      const folder = folderDoc.data()!;

      const videoID = context.params.videoId;
      const coachName = after.uploadedByName || 'Your coach';
      const coachID: string = after.uploadedBy || '';
      const athleteID = folder.ownerAthleteID;
      if (!athleteID) return;
      const folderName: string = folder.name || 'a folder';

      await sendPushNotification(
        athleteID,
        'New Session Video',
        `${coachName} shared a lesson clip with you`,
        { type: 'new_video', folderID },
        'COACH_VIDEO'
      );
      // Matches client postCoachSharedClipNotification. Shares the newvideo_{videoID}_{athleteID}
      // key with onNewSharedVideo so a private-then-published coach clip produces only one doc.
      await writeActivityNotification(
        athleteID,
        `newvideo_${videoID}_${athleteID}`,
        {
          type: 'new_video',
          title: `New Clip from ${coachName}`,
          body: `${coachName} shared a new clip in ${folderName}`,
          senderName: coachName,
          senderID: coachID,
          targetID: videoID,
          targetType: 'video',
          folderID,
        }
      );
    }
  });

/**
 * When a shared folder is deleted, notify every coach who had access. The client
 * path (SharedFolderManager.deleteFolder) attempts this in-app notification first,
 * but that only works if the deleting device is online and reaches the loop. This
 * server-side trigger covers:
 *   - athlete deletes while offline; coach is on a different device
 *   - direct admin console / server deletes that bypass the client
 *
 * Uses deterministic doc IDs matching the client path so duplicates overwrite
 * rather than producing two identical items in the coach's feed.
 */
export const onSharedFolderDeleted = functions.firestore
  .document('sharedFolders/{folderID}')
  .onDelete(async (snap) => {
    const folder = snap.data();
    const folderID = snap.id;
    const coachIDs: string[] = folder?.sharedWithCoachIDs || [];
    if (coachIDs.length === 0) return;

    const athleteName = folder?.ownerAthleteName || 'The athlete';
    const athleteID = folder?.ownerAthleteID || '';
    const folderName = folder?.name || 'a shared folder';

    // Use per-doc create() (not set/merge) so if the client already wrote the
    // same deterministic ID we leave its title/body/isRead alone. This prevents
    // a read notification from resurfacing as unread and the body from flipping
    // between "Folder Access Removed" (client) and "Folder Deleted" (server).
    await Promise.allSettled(
      coachIDs
        .filter((coachID) => coachID !== athleteID)
        .map(async (coachID) => {
          const ref = admin.firestore()
            .collection('notifications')
            .doc(coachID)
            .collection('items')
            .doc(`revoked_${folderID}_${coachID}`);
          try {
            await ref.create({
              type: 'access_revoked',
              title: 'Folder Deleted',
              body: `${athleteName} deleted "${folderName}"`,
              senderName: athleteName,
              senderID: athleteID,
              targetID: folderID,
              targetType: 'folder',
              isRead: false,
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
          } catch (err: any) {
            // ALREADY_EXISTS (code 6) is expected when the client beat us to it
            if (err?.code !== 6) {
              console.warn(`onSharedFolderDeleted create failed for ${coachID}:`, err);
            }
          }
        })
    );

    // Also push-notify coaches so they get an FCM banner on device
    await sendPushToMultipleUsers(
      coachIDs.filter((id) => id !== athleteID),
      'Folder Deleted',
      `${athleteName} deleted "${folderName}"`,
      { type: 'access_revoked', folderID },
      'ACCESS_REVOKED'
    );
  });

/**
 * Fires on invitation doc creation. Writes the `invitation_received` activity
 * notification + FCM push to the recipient (the coach or athlete the invitation
 * is addressed to). Handles both directions.
 *
 * If the recipient doesn't have an account yet, silently skips — the sibling
 * `backfillInvitationsOnSignup` CF handles delivery when they eventually sign up.
 */
export const onInvitationCreated = functions.firestore
  .document('invitations/{invitationId}')
  .onCreate(async (snap, context) => {
    const inv = snap.data();
    const invitationId = context.params.invitationId;
    if (inv?.status && inv.status !== 'pending') return;

    if (inv.type === 'athlete_to_coach') {
      const coachUID = await lookupUserIDByEmail(inv.coachEmail || '');
      if (!coachUID) return;
      const athleteName: string = inv.athleteName || 'An athlete';
      const athleteID: string = inv.athleteID || '';
      const folderName: string = inv.folderName || `${athleteName}'s folder`;
      const body = `${athleteName} invited you to view their folder "${folderName}"`;
      await writeActivityNotification(
        coachUID,
        `invreceived_${invitationId}_${coachUID}`,
        {
          type: 'invitation_received',
          title: 'New Folder Invitation',
          body,
          senderName: athleteName,
          senderID: athleteID,
          targetID: invitationId,
          targetType: 'invitation',
        }
      );
      await sendPushNotification(
        coachUID,
        'New Folder Invitation',
        body,
        { type: 'invitation_received', invitationID: invitationId },
        'INVITATION'
      );
    } else if (inv.type === 'coach_to_athlete') {
      const athleteUID = await lookupUserIDByEmail(inv.athleteEmail || '');
      if (!athleteUID) return;
      const coachName: string = inv.coachName || 'A coach';
      const coachID: string = inv.coachID || '';
      const body = `${coachName} wants to connect with you on PlayerPath`;
      await writeActivityNotification(
        athleteUID,
        `invreceived_${invitationId}_${athleteUID}`,
        {
          type: 'invitation_received',
          title: 'New Coach Invitation',
          body,
          senderName: coachName,
          senderID: coachID,
          targetID: invitationId,
          targetType: 'invitation',
        }
      );
      await sendPushNotification(
        athleteUID,
        'New Coach Invitation',
        body,
        { type: 'invitation_received', invitationID: invitationId },
        'INVITATION'
      );
    }
  });

/**
 * Fires on invitation status transitions to `accepted`. Writes the paired
 * `invitation_accepted` activity notification + FCM push to the ORIGINAL SENDER
 * (the athlete for athlete_to_coach, the coach for coach_to_athlete).
 *
 * Replaces the earlier meta-trigger (onInvitationAcceptedNotification) which
 * fired off the client-written notification doc — centralizing here eliminates
 * the "many writers" coordination problem for invitation_accepted.
 */
export const onInvitationAccepted = functions.firestore
  .document('invitations/{invitationId}')
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    if (after.status !== 'accepted') return;

    // The acceptance callables (acceptAthleteToCoachInvitation /
    // acceptCoachToAthleteInvitation) write status='accepted' first, then
    // update folderID + folderName in a separate write after server-side
    // folder creation. onUpdate fires on both writes.
    //
    // Fire strategy differs by direction:
    //
    //   athlete_to_coach: WAIT for folderID. The folder is guaranteed to
    //     exist (legacy) or be created (new); deferring to the second fire
    //     yields the correct folder name. Legacy invitations have folderID
    //     pre-populated, so the first fire already has it — no wait needed.
    //
    //   coach_to_athlete: FIRE on the first update, regardless of folderID.
    //     The connection-only path (where folder creation fails or is not
    //     attempted) never produces a second update; waiting would silently
    //     drop the notification. Accepting "connected" text for Pro users
    //     on the first fire is a worse UX but not a broken one.
    const justAccepted = before.status !== 'accepted';
    const folderJustPopulated = !before.folderID && !!after.folderID;

    if (after.type === 'athlete_to_coach') {
      // Fire only on the update that has folderID present.
      if (!justAccepted && !folderJustPopulated) return;
      if (justAccepted && !after.folderID) return; // wait for second update
    } else {
      // coach_to_athlete: fire exactly once, on the first update.
      if (!justAccepted) return;
    }

    const invitationId = context.params.invitationId;
    const folderID: string = after.folderID || '';
    const folderName: string = after.folderName || '';

    if (after.type === 'athlete_to_coach') {
      // Coach accepted athlete's folder invite → notify athlete.
      const athleteID: string = after.athleteID || '';
      if (!athleteID) return;
      const resolvedFolderName = folderName || `${after.athleteName || 'your'} folder`;
      const coachID: string = after.acceptedByCoachID || '';
      let coachName = 'Your coach';
      if (coachID) {
        try {
          const coachDoc = await admin.firestore().collection('users').doc(coachID).get();
          const d = coachDoc.data();
          coachName = d?.displayName || d?.email || coachName;
        } catch { /* fall back to default */ }
      }
      const body = `${coachName} accepted your invitation to "${resolvedFolderName}"`;
      await writeActivityNotification(
        athleteID,
        `invaccepted_${invitationId}_${athleteID}`,
        {
          type: 'invitation_accepted',
          title: 'Coach Joined Your Folder',
          body,
          senderName: coachName,
          senderID: coachID,
          targetID: folderID || invitationId,
          targetType: folderID ? 'folder' : 'invitation',
          folderID: folderID || undefined,
        }
      );
      await sendPushNotification(
        athleteID,
        'Coach Joined Your Folder',
        body,
        { type: 'invitation_accepted', folderID: folderID || '' },
        'INVITATION'
      );
    } else if (after.type === 'coach_to_athlete') {
      // Athlete accepted coach's invite → notify coach.
      const coachID: string = after.coachID || '';
      if (!coachID) return;
      const athleteName: string = after.athleteName || 'An athlete';
      const athleteID: string = after.athleteUserID || '';
      const body = folderID && folderName
        ? `${athleteName} accepted your invitation and shared "${folderName}" with you`
        : `${athleteName} accepted your invitation and is now connected with you`;
      await writeActivityNotification(
        coachID,
        `invaccepted_${invitationId}_${coachID}`,
        {
          type: 'invitation_accepted',
          title: 'Athlete Accepted Your Invitation',
          body,
          senderName: athleteName,
          senderID: athleteID,
          targetID: folderID || invitationId,
          targetType: folderID ? 'folder' : 'invitation',
          folderID: folderID || undefined,
        }
      );
      await sendPushNotification(
        coachID,
        'Athlete Accepted Your Invitation',
        body,
        { type: 'invitation_accepted', folderID: folderID || '' },
        'INVITATION'
      );
    }
  });

/**
 * Fires on invitation status transitions to `declined` or `cancelled`.
 *
 *   declined  (the RECIPIENT said no)        → notify the original SENDER, and
 *                                               clear the recipient's own
 *                                               `invitation_received` notice.
 *   cancelled (the SENDER pulled it back)    → silently clear the RECIPIENT's
 *                                               stale `invitation_received` notice
 *                                               so they don't tap a dead invite.
 *                                               No new ping — a cancel the
 *                                               recipient may never have seen
 *                                               isn't worth a notification.
 *
 * Direction handling mirrors onInvitationCreated/onInvitationAccepted. Best-effort
 * throughout: a recipient with no account yet (invite to an unregistered email)
 * simply has nothing to clear.
 */
export const onInvitationResolvedNegatively = functions.firestore
  .document('invitations/{invitationId}')
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    const status = after.status;
    if (status !== 'declined' && status !== 'cancelled') return;
    if (before.status === status) return; // only on the transition into this state

    const invitationId = context.params.invitationId;
    const db = admin.firestore();

    // Resolve sender + recipient for this direction.
    let senderID = '';
    let recipientUID: string | null = null;
    let recipientName = '';
    let recipientIsCoach = false;
    if (after.type === 'athlete_to_coach') {
      senderID = after.athleteID || '';
      recipientUID = await lookupUserIDByEmail(after.coachEmail || '');
      recipientName = after.coachName || '';
      recipientIsCoach = true;
    } else if (after.type === 'coach_to_athlete') {
      senderID = after.coachID || '';
      recipientUID = (after.athleteUserID as string) || await lookupUserIDByEmail(after.athleteEmail || '');
      recipientName = after.athleteName || '';
    } else {
      return;
    }

    // Both decline and cancel clear the recipient's stale "invitation received" notice.
    if (recipientUID) {
      try {
        await db.collection('notifications').doc(recipientUID)
          .collection('items').doc(`invreceived_${invitationId}_${recipientUID}`).delete();
      } catch { /* nothing to clear */ }
    }

    // Only a decline produces a new notification — to the original sender.
    if (status === 'declined' && senderID) {
      if (recipientUID && !recipientName) {
        try {
          const rDoc = await db.collection('users').doc(recipientUID).get();
          const rd = rDoc.data();
          recipientName = (rd?.displayName as string) || (rd?.email as string)?.split('@')[0] || '';
        } catch { /* fall back below */ }
      }
      const who = recipientName || (recipientIsCoach ? 'A coach' : 'An athlete');
      const folderName: string = after.folderName || '';
      const title = 'Invitation Declined';
      const body = recipientIsCoach
        ? (folderName
            ? `${who} declined your invitation to "${folderName}"`
            : `${who} declined your folder invitation`)
        : `${who} declined your invitation to connect`;
      await writeActivityNotification(
        senderID,
        `invdeclined_${invitationId}_${senderID}`,
        {
          type: 'invitation_declined',
          title,
          body,
          senderName: who,
          senderID: recipientUID || 'system',
          targetID: invitationId,
          targetType: 'invitation',
        }
      );
      await sendPushNotification(
        senderID,
        title,
        body,
        { type: 'invitation_declined', invitationID: invitationId },
        'INVITATION'
      );
    }
  });

/**
 * Resolves the set of user IDs that should be notified when a coach/athlete
 * leaves feedback on a shared-folder video. Author is always excluded.
 * Falls back to the video uploader for non-shared videos.
 */
async function resolveFeedbackRecipients(
  video: admin.firestore.DocumentData,
  authorId: string,
  authorRole: string | undefined
): Promise<string[]> {
  const folderID = video.sharedFolderID;
  if (folderID) {
    const folderDoc = await admin.firestore().collection('sharedFolders').doc(folderID).get();
    if (folderDoc.exists) {
      const folder = folderDoc.data()!;
      // Coach feedback → athlete (folder owner). Athlete feedback → all coaches.
      if (authorRole === 'coach') {
        const athleteID = folder.ownerAthleteID;
        return athleteID && athleteID !== authorId ? [athleteID] : [];
      }
      if (authorRole === 'athlete') {
        const coachIDs: string[] = folder.sharedWithCoachIDs || [];
        return coachIDs.filter(id => id !== authorId);
      }
      // Unknown role — notify everyone on the folder except the author.
      const everyone = [folder.ownerAthleteID, ...(folder.sharedWithCoachIDs || [])].filter(Boolean);
      return everyone.filter((id: string) => id !== authorId);
    }
  }
  // Non-shared video — fall back to uploader.
  if (video.uploadedBy && video.uploadedBy !== authorId) {
    return [video.uploadedBy];
  }
  return [];
}

/**
 * When a comment is added to a video, push-notify the opposite party
 * (coach → athlete, athlete → coaches) on shared folders.
 */
export const onNewComment = functions.firestore
  .document('videos/{videoId}/comments/{commentId}')
  .onCreate(async (snap, context) => {
    const comment = snap.data();
    const videoId = context.params.videoId;
    const commentId = context.params.commentId;

    const videoDoc = await admin.firestore().collection('videos').doc(videoId).get();
    if (!videoDoc.exists) return;
    const video = videoDoc.data()!;

    const recipients = await resolveFeedbackRecipients(
      video,
      comment.authorId,
      comment.authorRole
    );
    if (recipients.length === 0) return;

    const commenterName: string = comment.authorName || 'Someone';
    const commenterID: string = comment.authorId || '';
    const preview: string = (comment.text || '').substring(0, 80);
    const folderID: string = video.sharedFolderID || '';
    const clipRef: string = clipDescription(video);

    await sendPushToMultipleUsers(
      recipients,
      'New Comment',
      `${commenterName}: ${preview}`,
      {
        type: 'coach_comment',
        folderID,
        videoID: videoId,
      },
      'COACH_COMMENT'
    );
    // Matches client postCoachCommentNotification for the coach→athlete direction.
    // Athlete→coach comments previously had only an FCM push with no in-app record;
    // we now write an in-app record in both directions for parity.
    const title = comment.authorRole === 'coach'
      ? `Coach Feedback on ${clipRef}`
      : `New Comment on ${clipRef}`;
    await writeActivityNotifications(
      recipients,
      (rid) => `comment_${videoId}_${commentId}_${rid}`,
      {
        type: 'coach_comment',
        title,
        body: `${commenterName}: ${preview}`,
        senderName: commenterName,
        senderID: commenterID,
        targetID: videoId,
        targetType: 'video',
        folderID: folderID || undefined,
      }
    );
  });

/**
 * When a timestamped annotation is added to a video, push-notify the opposite
 * party. Annotations are already mirrored to comments/ by iOS, but direct
 * writes (e.g. drawing annotations) skip the mirror — this covers them.
 * Deduplication with onNewComment is acceptable: APNs coalesces by thread ID
 * and the worst case is one extra push per coach action.
 */
export const onNewAnnotation = functions.firestore
  .document('videos/{videoId}/annotations/{annotationId}')
  .onCreate(async (snap, context) => {
    const annotation = snap.data();
    const videoId = context.params.videoId;
    const annotationId = context.params.annotationId;

    // Skip annotations mirrored to comments — onNewComment will handle those.
    // Drawings and non-coach annotations still fire here.
    if (annotation.type !== 'drawing' && annotation.isCoachComment === true) return;

    const videoDoc = await admin.firestore().collection('videos').doc(videoId).get();
    if (!videoDoc.exists) return;
    const video = videoDoc.data()!;

    // Draft annotations on still-private coach clips must not page the athlete;
    // onVideoPublished sends a single cohesive push when the clip is shared.
    if (video.visibility === 'private') return;

    const authorRole = annotation.isCoachComment === true ? 'coach' : 'athlete';
    const recipients = await resolveFeedbackRecipients(
      video,
      annotation.userID,
      authorRole
    );
    if (recipients.length === 0) return;

    const authorName: string = annotation.userName || 'Someone';
    const authorID: string = annotation.userID || '';
    const isDrawing = annotation.type === 'drawing';
    const body = isDrawing
      ? `${authorName} added a drawing`
      : `${authorName}: ${(annotation.text || '').substring(0, 80)}`;
    const folderID: string = video.sharedFolderID || '';
    const clipRef: string = clipDescription(video);

    await sendPushToMultipleUsers(
      recipients,
      'New Feedback',
      body,
      {
        type: 'coach_comment',
        folderID,
        videoID: videoId,
      },
      'COACH_COMMENT'
    );
    const title = authorRole === 'coach'
      ? `Coach Feedback on ${clipRef}`
      : `New Feedback on ${clipRef}`;
    await writeActivityNotifications(
      recipients,
      (rid) => `annotation_${videoId}_${annotationId}_${rid}`,
      {
        type: 'coach_comment',
        title,
        body,
        senderName: authorName,
        senderID: authorID,
        targetID: videoId,
        targetType: 'video',
        folderID: folderID || undefined,
      }
    );
  });

/**
 * When a coach updates the plain `coachNote` field on a video, push-notify the
 * athlete. Covers the "Instruction Notes" path from ClipReviewSheet and the
 * note edit path from CoachVideoPlayerView.
 */
export const onCoachNoteUpdated = functions.firestore
  .document('videos/{videoId}')
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();

    const beforeNote = (before.coachNote || '').trim();
    const afterNote = (after.coachNote || '').trim();
    // Only fire on a non-empty note that changed.
    if (!afterNote || afterNote === beforeNote) return;

    const authorId: string = after.coachNoteAuthorID || after.uploadedBy || '';
    const authorName: string = after.coachNoteAuthorName || after.uploadedByName || 'Your coach';

    const recipients = await resolveFeedbackRecipients(after, authorId, 'coach');
    if (recipients.length === 0) return;

    const videoId = context.params.videoId;
    const folderID: string = after.sharedFolderID || '';
    const clipRef: string = clipDescription(after);
    const preview = afterNote.substring(0, 80);

    await sendPushToMultipleUsers(
      recipients,
      'New Coach Note',
      `${authorName}: ${preview}`,
      {
        type: 'coach_comment',
        folderID,
        videoID: videoId,
      },
      'COACH_COMMENT'
    );
    // Note updates: one doc per (video, recipient). Re-edits don't resurface
    // the notification — the initial note-add drives the notification; later
    // typo fixes silently hit ALREADY_EXISTS. Acceptable for v1.
    await writeActivityNotifications(
      recipients,
      (rid) => `note_${videoId}_${rid}`,
      {
        type: 'coach_comment',
        title: `Coach Feedback on ${clipRef}`,
        body: `${authorName}: ${preview}`,
        senderName: authorName,
        senderID: authorId,
        targetID: videoId,
        targetType: 'video',
        folderID: folderID || undefined,
      }
    );
  });

/**
 * When a drill card is added to a video, notify the folder owner.
 */
export const onNewDrillCard = functions.firestore
  .document('videos/{videoId}/drillCards/{cardId}')
  .onCreate(async (snap, context) => {
    const card = snap.data();
    const videoId = context.params.videoId;
    const cardId = context.params.cardId;

    const videoDoc = await admin.firestore().collection('videos').doc(videoId).get();
    if (!videoDoc.exists) return;
    const video = videoDoc.data()!;

    // Draft drill cards on still-private coach clips must not page the athlete;
    // onVideoPublished sends a single cohesive push when the clip is shared.
    if (video.visibility === 'private') return;

    if (!video.sharedFolderID) return;

    const folderDoc = await admin.firestore().collection('sharedFolders').doc(video.sharedFolderID).get();
    if (!folderDoc.exists) return;
    const folder = folderDoc.data()!;

    const coachName: string = card.coachName || 'Your coach';
    const coachID: string = card.coachID || '';
    const folderID: string = video.sharedFolderID;
    const templateName: string = card.templateName || 'drill card';
    const clipRef: string = clipDescription(video);

    // Notify the athlete (folder owner)
    if (folder.ownerAthleteID && folder.ownerAthleteID !== card.coachID) {
      const athleteID: string = folder.ownerAthleteID;
      await sendPushNotification(
        athleteID,
        'New Drill Card',
        `${coachName} added a drill card to your video`,
        {
          type: 'drill_card',
          folderID,
          videoID: videoId,
        },
        'DRILL_CARD'
      );
      // Matches client postDrillCardNotification: type 'coach_comment' (not 'drill_card').
      await writeActivityNotification(
        athleteID,
        `drillcard_${videoId}_${cardId}_${athleteID}`,
        {
          type: 'coach_comment',
          title: 'New Drill Card',
          body: `${coachName} added a ${templateName} to ${clipRef}`,
          senderName: coachName,
          senderID: coachID,
          targetID: videoId,
          targetType: 'video',
          folderID,
        }
      );
    }
  });

/**
 * Backfills in-app notifications for invitations sent to an email BEFORE the user
 * had an account. When a new Firebase Auth user is created, we look up any pending
 * coach→athlete invitations keyed on their email and write matching
 * `invitation_received` notifications into their notifications feed so the bell,
 * badge, and banner surface normally.
 *
 * The client-side listener in AthleteInvitationManager also surfaces the banner
 * directly, but this ensures the activity feed stays consistent with users who
 * signed up AFTER the invitation was sent.
 */
export const backfillInvitationsOnSignup = functions.auth.user().onCreate(async (user) => {
  if (!user.email) return;
  const email = user.email.toLowerCase().trim();
  try {
    // Coach → Athlete: the new user was invited as an athlete
    const c2aSnap = await admin.firestore().collection('invitations')
      .where('type', '==', 'coach_to_athlete')
      .where('athleteEmail', '==', email)
      .where('status', '==', 'pending')
      .get();

    // Athlete → Coach: the new user was invited as a coach
    const a2cSnap = await admin.firestore().collection('invitations')
      .where('type', '==', 'athlete_to_coach')
      .where('coachEmail', '==', email)
      .where('status', '==', 'pending')
      .get();

    if (c2aSnap.empty && a2cSnap.empty) return;

    // Use the same deterministic IDs as onInvitationCreated so if a pending
    // invitation already has a notification written (e.g., signup raced the
    // onInvitationCreated trigger), .create() hits ALREADY_EXISTS and we skip.
    for (const doc of c2aSnap.docs) {
      const data = doc.data();
      const coachName = data.coachName || 'A coach';
      await writeActivityNotification(
        user.uid,
        `invreceived_${doc.id}_${user.uid}`,
        {
          type: 'invitation_received',
          title: 'New Coach Invitation',
          body: `${coachName} wants to connect with you on PlayerPath`,
          senderName: coachName,
          senderID: data.coachID || '',
          targetID: doc.id,
          targetType: 'invitation',
        }
      );
    }

    for (const doc of a2cSnap.docs) {
      const data = doc.data();
      const athleteName = data.athleteName || 'An athlete';
      const folderName = data.folderName || `${athleteName}'s folder`;
      await writeActivityNotification(
        user.uid,
        `invreceived_${doc.id}_${user.uid}`,
        {
          type: 'invitation_received',
          title: 'New Folder Invitation',
          body: `${athleteName} invited you to view their folder "${folderName}"`,
          senderName: athleteName,
          senderID: data.athleteID || '',
          targetID: doc.id,
          targetType: 'invitation',
        }
      );
    }

    console.log(`✅ Backfilled ${c2aSnap.size} coach→athlete and ${a2cSnap.size} athlete→coach invitation notification(s) for ${email}`);
  } catch (error) {
    console.warn('⚠️ backfillInvitationsOnSignup failed:', error);
  }
});

/**
 * Triggers when a new invitation is created in Firestore.
 * Routes to the appropriate email template based on invitation type:
 * - Athlete → Coach: sends coach a collaboration invite with folder/permissions
 * - Coach → Athlete: sends athlete/parent an invite to connect with a coach
 */
export const sendInvitationEmail = functions.firestore
  .document('invitations/{invitationId}')
  .onCreate(async (snap, context) => {
    const invitation = snap.data();
    const invitationId = context.params.invitationId;

    // Idempotency guard: skip if email was already sent (onCreate can fire more than once)
    if (invitation.emailSent === true) {
      console.log(`Email already sent for invitation ${invitationId}, skipping.`);
      return;
    }

    // Rate limit: check the sender (coach or athlete) hasn't exceeded email limits
    const senderUID = invitation.type === 'coach_to_athlete'
      ? invitation.coachID
      : invitation.athleteID;
    if (senderUID && !(await checkEmailRateLimit(senderUID))) {
      console.warn(`Rate limit exceeded for user ${senderUID}, skipping email for ${invitationId}`);
      await snap.ref.update({ emailError: 'Rate limit exceeded', emailSent: false });
      return;
    }

    try {
      if (invitation.type === 'coach_to_athlete') {
        // Coach → Athlete invitation
        await sendCoachToAthleteEmail(snap, invitation, invitationId);
      } else {
        // Athlete → Coach invitation (default / original flow)
        await sendAthleteToCoachEmail(snap, invitation, invitationId);
      }
    } catch (error) {
      console.error('Error sending invitation email:', error);

      await snap.ref.update({
        emailError: error instanceof Error ? error.message : 'Unknown error',
        emailSent: false
      });
    }
  });

/**
 * Sends email to a coach who has been invited by an athlete
 */
async function sendAthleteToCoachEmail(
  snap: functions.firestore.QueryDocumentSnapshot,
  invitation: any,
  invitationId: string
) {
  if (!invitation.coachEmail || !invitation.athleteName || !invitation.folderName) {
    console.error('Missing required athlete-to-coach invitation fields', invitationId);
    return;
  }

  const deepLink = `playerpath://invitation/${invitationId}`;
  const webLink = `https://playerpath.net/invitation/${invitationId}`;

  const msg = {
    to: invitation.coachEmail,
    from: 'PlayerPath <noreply@playerpath.net>',
    subject: `${invitation.athleteName} invited you to collaborate on PlayerPath`,
    text: generatePlainTextEmail(invitation, deepLink, webLink),
    html: generateHtmlEmail(invitation, deepLink, webLink),
  };

  await getResend().emails.send(msg);
  console.log(`✅ Invitation email sent for invitation ${invitationId}`);

  await snap.ref.update({
    emailSentAt: admin.firestore.FieldValue.serverTimestamp(),
    emailSent: true
  });
  // In-app notification + FCM push are handled by the onInvitationCreated
  // trigger on the same invitation doc — this function only owns email.
}

/**
 * Sends email to an athlete/parent who has been invited by a coach
 */
async function sendCoachToAthleteEmail(
  snap: functions.firestore.QueryDocumentSnapshot,
  invitation: any,
  invitationId: string
) {
  if (!invitation.athleteEmail || !invitation.coachName) {
    console.error('Missing required coach-to-athlete invitation fields', invitationId);
    return;
  }

  const deepLink = `playerpath://invitation/${invitationId}`;

  const msg = {
    to: invitation.athleteEmail,
    from: 'PlayerPath <noreply@playerpath.net>',
    subject: `Coach ${invitation.coachName} wants to connect on PlayerPath`,
    text: generateCoachToAthletePlainTextEmail(invitation, deepLink),
    html: generateCoachToAthleteHtmlEmail(invitation, deepLink),
  };

  await getResend().emails.send(msg);
  console.log(`✅ Coach-to-athlete email sent for invitation ${invitationId}`);

  await snap.ref.update({
    emailSentAt: admin.firestore.FieldValue.serverTimestamp(),
    emailSent: true
  });
  // In-app notification + FCM push are handled by the onInvitationCreated
  // trigger on the same invitation doc — this function only owns email.
}

/**
 * Generates plain text email for coaches without HTML support
 */
function generatePlainTextEmail(
  invitation: any,
  deepLink: string,
  webLink: string
): string {
  return `
Hi there,

${invitation.athleteName} has invited you to collaborate on PlayerPath!

You've been invited to access the shared folder: "${invitation.folderName}"

As a coach, you'll be able to:
${invitation.permissions?.canUpload ? '✓ Upload videos\n' : ''}${invitation.permissions?.canComment ? '✓ Add comments and feedback\n' : ''}${invitation.permissions?.canDelete ? '✓ Manage videos\n' : ''}
To accept this invitation:

1. Download PlayerPath from the App Store: ${APP_STORE_URL}
2. Sign up or sign in with this email address: ${invitation.coachEmail}
3. Your invitation will appear automatically — no further steps needed

Already have the app? Tap this link to open it directly:
${deepLink}

This invitation was sent to ${invitation.coachEmail}. If you didn't expect this invitation, you can safely ignore this email.

Thanks,
The PlayerPath Team

---
PlayerPath - Simplifying baseball video analysis for athletes and coaches
  `.trim();
}

/**
 * Generates HTML email with styled template
 */
function generateHtmlEmail(
  invitation: any,
  deepLink: string,
  webLink: string
): string {
  const permissions = [];
  if (invitation.permissions?.canUpload) permissions.push('Upload videos');
  if (invitation.permissions?.canComment) permissions.push('Add comments and feedback');
  if (invitation.permissions?.canDelete) permissions.push('Manage videos');

  return `
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>PlayerPath Coach Invitation</title>
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
      line-height: 1.6;
      color: #333;
      background-color: #f5f5f5;
      margin: 0;
      padding: 0;
    }
    .container {
      max-width: 600px;
      margin: 40px auto;
      background: white;
      border-radius: 12px;
      overflow: hidden;
      box-shadow: 0 2px 8px rgba(0,0,0,0.1);
    }
    .header {
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      color: white;
      padding: 40px 30px;
      text-align: center;
    }
    .header h1 {
      margin: 0;
      font-size: 28px;
      font-weight: 600;
    }
    .header p {
      margin: 10px 0 0 0;
      font-size: 16px;
      opacity: 0.9;
    }
    .content {
      padding: 40px 30px;
    }
    .folder-name {
      background: #f0f4ff;
      border-left: 4px solid #667eea;
      padding: 16px 20px;
      margin: 20px 0;
      border-radius: 4px;
    }
    .folder-name strong {
      color: #667eea;
      font-size: 18px;
    }
    .permissions {
      margin: 24px 0;
    }
    .permissions h3 {
      margin: 0 0 12px 0;
      font-size: 16px;
      color: #555;
    }
    .permission-list {
      list-style: none;
      padding: 0;
      margin: 0;
    }
    .permission-list li {
      padding: 8px 0;
      padding-left: 28px;
      position: relative;
    }
    .permission-list li:before {
      content: "✓";
      position: absolute;
      left: 0;
      color: #10b981;
      font-weight: bold;
      font-size: 18px;
    }
    .cta-button {
      display: inline-block;
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      color: white;
      text-decoration: none;
      padding: 16px 40px;
      border-radius: 8px;
      font-weight: 600;
      font-size: 16px;
      margin: 24px 0;
      text-align: center;
    }
    .cta-button:hover {
      opacity: 0.9;
    }
    .instructions {
      background: #f9fafb;
      border-radius: 8px;
      padding: 20px;
      margin: 24px 0;
    }
    .instructions h3 {
      margin: 0 0 12px 0;
      font-size: 16px;
      color: #555;
    }
    .instructions ol {
      margin: 0;
      padding-left: 20px;
    }
    .instructions li {
      margin: 8px 0;
      color: #666;
    }
    .footer {
      padding: 30px;
      text-align: center;
      color: #999;
      font-size: 14px;
      background: #f9fafb;
    }
    .footer a {
      color: #667eea;
      text-decoration: none;
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>🎾 You're Invited to PlayerPath</h1>
      <p>Coach collaboration invitation</p>
    </div>

    <div class="content">
      <p style="font-size: 16px; margin-bottom: 8px;">Hi there,</p>

      <p style="font-size: 16px; line-height: 1.8;">
        <strong>${escapeHtml(invitation.athleteName)}</strong> has invited you to collaborate on PlayerPath!
      </p>

      <div class="folder-name">
        <strong>"${escapeHtml(invitation.folderName)}"</strong>
      </div>

      ${permissions.length > 0 ? `
      <div class="permissions">
        <h3>As a coach, you'll be able to:</h3>
        <ul class="permission-list">
          ${permissions.map(p => `<li>${p}</li>`).join('')}
        </ul>
      </div>
      ` : ''}

      <div class="instructions">
        <h3>How to get started:</h3>
        <ol>
          <li>
            <strong>Download PlayerPath</strong> from the App Store:<br>
            <a href="${APP_STORE_URL}" style="color: #667eea;">${APP_STORE_URL}</a>
          </li>
          <li>Sign up or sign in using: <strong>${escapeHtml(invitation.coachEmail)}</strong></li>
          <li>Your invitation will appear automatically — no further steps needed</li>
        </ol>
      </div>

      <div style="text-align: center; margin: 32px 0;">
        <a href="${deepLink}" class="cta-button">Open in App (if already installed)</a>
      </div>

      <p style="font-size: 14px; color: #666; margin-top: 16px;">
        The button above only works if PlayerPath is already installed on your device.
      </p>

      <p style="font-size: 13px; color: #999; margin-top: 24px; padding-top: 24px; border-top: 1px solid #eee;">
        This invitation was sent to ${escapeHtml(invitation.coachEmail)}. If you didn't expect this invitation, you can safely ignore this email.
      </p>
    </div>

    <div class="footer">
      <p><strong>PlayerPath</strong></p>
      <p>Simplifying baseball video analysis for athletes and coaches</p>
      <p style="margin-top: 16px;">
        <a href="https://playerpath.net">Website</a> •
        <a href="https://playerpath.net/support">Support</a> •
        <a href="https://playerpath.net/privacy">Privacy</a>
      </p>
    </div>
  </div>
</body>
</html>
  `.trim();
}

/**
 * Generates plain text email for coach-to-athlete invitations
 */
function generateCoachToAthletePlainTextEmail(
  invitation: any,
  deepLink: string
): string {
  return `
Hi there,

Coach ${invitation.coachName} has invited ${invitation.athleteName} to connect on PlayerPath!

${invitation.message ? `Personal message from Coach ${invitation.coachName}:\n"${invitation.message}"\n` : ''}
Once you accept, Coach ${invitation.coachName} will be able to share practice videos, drills, and coaching feedback directly with you.

To accept this invitation:

1. Download PlayerPath from the App Store: ${APP_STORE_URL}
2. Sign up or sign in with this email address: ${invitation.athleteEmail}
3. Your invitation will appear automatically on your dashboard

Already have the app? Tap this link to open it directly:
${deepLink}

This invitation was sent to ${invitation.athleteEmail}. If you didn't expect this invitation, you can safely ignore this email.

Thanks,
The PlayerPath Team

---
PlayerPath - Simplifying baseball video analysis for athletes and coaches
  `.trim();
}

/**
 * Generates HTML email for coach-to-athlete invitations
 */
function generateCoachToAthleteHtmlEmail(
  invitation: any,
  deepLink: string
): string {
  return `
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>PlayerPath Coach Invitation</title>
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
      line-height: 1.6;
      color: #333;
      background-color: #f5f5f5;
      margin: 0;
      padding: 0;
    }
    .container {
      max-width: 600px;
      margin: 40px auto;
      background: white;
      border-radius: 12px;
      overflow: hidden;
      box-shadow: 0 2px 8px rgba(0,0,0,0.1);
    }
    .header {
      background: linear-gradient(135deg, #10b981 0%, #059669 100%);
      color: white;
      padding: 40px 30px;
      text-align: center;
    }
    .header h1 {
      margin: 0;
      font-size: 28px;
      font-weight: 600;
    }
    .header p {
      margin: 10px 0 0 0;
      font-size: 16px;
      opacity: 0.9;
    }
    .content {
      padding: 40px 30px;
    }
    .coach-name {
      background: #ecfdf5;
      border-left: 4px solid #10b981;
      padding: 16px 20px;
      margin: 20px 0;
      border-radius: 4px;
    }
    .coach-name strong {
      color: #059669;
      font-size: 18px;
    }
    .message-box {
      background: #f9fafb;
      border-radius: 8px;
      padding: 20px;
      margin: 20px 0;
      font-style: italic;
      color: #555;
    }
    .cta-button {
      display: inline-block;
      background: linear-gradient(135deg, #10b981 0%, #059669 100%);
      color: white;
      text-decoration: none;
      padding: 16px 40px;
      border-radius: 8px;
      font-weight: 600;
      font-size: 16px;
      margin: 24px 0;
      text-align: center;
    }
    .instructions {
      background: #f9fafb;
      border-radius: 8px;
      padding: 20px;
      margin: 24px 0;
    }
    .instructions h3 {
      margin: 0 0 12px 0;
      font-size: 16px;
      color: #555;
    }
    .instructions ol {
      margin: 0;
      padding-left: 20px;
    }
    .instructions li {
      margin: 8px 0;
      color: #666;
    }
    .footer {
      padding: 30px;
      text-align: center;
      color: #999;
      font-size: 14px;
      background: #f9fafb;
    }
    .footer a {
      color: #10b981;
      text-decoration: none;
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>Coach Invitation</h1>
      <p>A coach wants to connect with you</p>
    </div>

    <div class="content">
      <p style="font-size: 16px; margin-bottom: 8px;">Hi there,</p>

      <p style="font-size: 16px; line-height: 1.8;">
        <strong>Coach ${escapeHtml(invitation.coachName)}</strong> has invited <strong>${escapeHtml(invitation.athleteName)}</strong> to connect on PlayerPath!
      </p>

      <div class="coach-name">
        <strong>Coach ${escapeHtml(invitation.coachName)}</strong><br>
        <span style="font-size: 14px; color: #666;">${escapeHtml(invitation.coachEmail)}</span>
      </div>

      ${invitation.message ? `
      <div class="message-box">
        <p style="margin: 0 0 8px 0; font-style: normal; font-weight: 600; color: #333;">Message from Coach ${escapeHtml(invitation.coachName)}:</p>
        <p style="margin: 0;">"${escapeHtml(invitation.message)}"</p>
      </div>
      ` : ''}

      <p style="font-size: 16px; line-height: 1.8;">
        Once you accept, Coach ${escapeHtml(invitation.coachName)} will be able to share practice videos, drills, and coaching feedback directly with you through the app.
      </p>

      <div class="instructions">
        <h3>How to get started:</h3>
        <ol>
          <li>
            <strong>Download PlayerPath</strong> from the App Store:<br>
            <a href="${APP_STORE_URL}" style="color: #10b981;">${APP_STORE_URL}</a>
          </li>
          <li>Sign up or sign in using: <strong>${escapeHtml(invitation.athleteEmail)}</strong></li>
          <li>Your invitation will appear automatically on your dashboard</li>
        </ol>
      </div>

      <div style="text-align: center; margin: 32px 0;">
        <a href="${deepLink}" class="cta-button">Open in App (if already installed)</a>
      </div>

      <p style="font-size: 14px; color: #666; margin-top: 16px;">
        The button above only works if PlayerPath is already installed on your device.
      </p>

      <p style="font-size: 13px; color: #999; margin-top: 24px; padding-top: 24px; border-top: 1px solid #eee;">
        This invitation was sent to ${escapeHtml(invitation.athleteEmail)}. If you didn't expect this invitation, you can safely ignore this email.
      </p>
    </div>

    <div class="footer">
      <p><strong>PlayerPath</strong></p>
      <p>Simplifying baseball video analysis for athletes and coaches</p>
      <p style="margin-top: 16px;">
        <a href="https://playerpath.net">Website</a> •
        <a href="https://playerpath.net/support">Support</a> •
        <a href="https://playerpath.net/privacy">Privacy</a>
      </p>
    </div>
  </div>
</body>
</html>
  `.trim();
}

/**
 * Triggers when coach access is revoked from a folder
 * Sends an email notification to the coach
 */
export const sendCoachAccessRevokedEmail = functions.firestore
  .document('coach_access_revocations/{revocationId}')
  .onCreate(async (snap, context) => {
    const revocation = snap.data();
    const revocationId = context.params.revocationId;

    // Clients can't read other users' profiles (users/ is owner-read-only), so
    // revocation docs may arrive without coachEmail (athlete-initiated removal)
    // or athleteName (coach-initiated leave). Resolve the gaps via Admin SDK.
    try {
      if (!revocation.coachEmail && revocation.coachID) {
        const coachDoc = await admin.firestore().collection('users').doc(revocation.coachID).get();
        revocation.coachEmail = coachDoc.data()?.email || '';
      }
      if (!revocation.athleteName && revocation.athleteID) {
        const athleteDoc = await admin.firestore().collection('users').doc(revocation.athleteID).get();
        revocation.athleteName = athleteDoc.data()?.displayName || 'An athlete';
      }
    } catch (e) {
      console.warn(`Failed to resolve revocation parties for ${revocationId}:`, e);
    }

    // Recompute the coach's athlete counter authoritatively from current state.
    // A single disconnect creates one revocation doc per folder (Games + Lessons),
    // so a blind increment(-1) would over-decrement; recomputing from ground truth
    // is idempotent across both docs and self-heals any pre-existing drift.
    if (revocation.coachID) {
      try {
        const trueCount = await computeCoachConnectionCount(admin.firestore(), revocation.coachID);
        await admin.firestore().collection('users').doc(revocation.coachID).update({
          coachAthleteCount: trueCount,
        });
        // Lift the downgrade feedback gate immediately if this shed brought the
        // coach back within their limit (don't wait for the daily audit).
        await clearCoachDowngradeFlagsIfResolved(admin.firestore(), revocation.coachID, trueCount);
      } catch (e) {
        console.warn(`Failed to recompute coachAthleteCount for ${revocation.coachID}:`, e);
      }
    }

    // Deliberate athlete removal (no `reason`): the recompute above still counts a
    // Flow-B athlete via their persistent accepted coach→athlete invitation, so the
    // coach's slot wouldn't free. Once the coach shares no remaining folder with this
    // person, delete that lingering invitation and recompute. Downgrade already
    // deleted invites in batchRevokeCoachAccess. (reason:'lapse' docs are no longer
    // created — Pricing Model V2 removed the athlete-tier lapse pipeline.)
    if (!revocation.reason) {
      try {
        await cleanupStaleInvitationsAfterRevocation(admin.firestore(), revocation);
      } catch (e) {
        console.warn(`Failed stale-invitation cleanup for revocation ${revocationId}:`, e);
      }
    }

    // Coach-initiated downgrade: the coach knowingly shed this athlete in the
    // in-app selection flow, so a per-folder "your access was revoked" email to
    // them is redundant noise — and the generic copy wrongly blames the athlete.
    // (The athlete is notified separately, client-side.) The counter recompute
    // above still runs for downgrades; only the email + coach in-app notice are
    // skipped here.
    if (revocation.reason === 'downgrade') {
      return;
    }

    // Rate limit the revoking user
    const revokerUID = revocation.athleteID || revocation.revokedBy;
    if (revokerUID && !(await checkEmailRateLimit(revokerUID))) {
      console.warn(`Rate limit exceeded for user ${revokerUID}, skipping revocation email ${revocationId}`);
      await snap.ref.update({ emailError: 'Rate limit exceeded', emailSent: false });
      return;
    }

    try {
      // Validate revocation data. A missing email/name only skips the EMAIL —
      // the in-app notification + FCM below need just folderID/coachID and must
      // still fire (the client can't always supply these fields; see resolution
      // block above for why).
      if (!revocation.coachEmail || !revocation.athleteName || !revocation.folderName) {
        console.error('Missing required revocation fields', revocationId);
        await snap.ref.update({ emailSent: false, emailError: 'Missing required revocation fields' });
      } else {
        const msg = {
          to: revocation.coachEmail,
          from: 'PlayerPath <noreply@playerpath.net>',
          subject: `Access to "${revocation.folderName}" has been revoked`,
          text: generateRevokedAccessPlainTextEmail(revocation),
          html: generateRevokedAccessHtmlEmail(revocation),
        };

        await getResend().emails.send(msg);

        console.log(`✅ Access revoked email sent for revocation ${revocationId}`);

        // Update revocation with email sent timestamp
        await snap.ref.update({
          emailSentAt: admin.firestore.FieldValue.serverTimestamp(),
          emailSent: true
        });
      }
    } catch (error) {
      console.error('Error sending access revoked email:', error);

      // Log the error in Firestore for debugging
      await snap.ref.update({
        emailError: error instanceof Error ? error.message : 'Unknown error',
        emailSent: false
      });
    }

    // In-app activity notification + FCM.
    // Athlete-initiated revocation (no `reason` field or reason !== 'downgrade')
    // → notify the coach. Coach-initiated downgrades flow through a different
    // notification (athlete-side "Coach Access Ended") which the client still
    // writes today; that path will migrate in a later chunk.
    if (revocation.reason !== 'downgrade') {
      const folderID = revocation.folderID as string;
      const coachID = revocation.coachID as string;
      const athleteID = (revocation.athleteID as string) || '';
      const athleteName = (revocation.athleteName as string) || 'An athlete';
      const folderName = (revocation.folderName as string) || 'a folder';
      if (folderID && coachID) {
        const title = 'Folder Access Removed';
        const body = `${athleteName} has removed your access to "${folderName}"`;
        // Shares the `revoked_{folderID}_{coachID}` key with onSharedFolderDeleted
        // and the Swift client's postAccessRevokedNotification so a delete-cascade
        // revocation produces exactly one notification doc.
        await writeActivityNotification(
          coachID,
          `revoked_${folderID}_${coachID}`,
          {
            type: 'access_revoked',
            title,
            body,
            senderName: athleteName,
            senderID: athleteID,
            targetID: folderID,
            targetType: 'folder',
            folderID,
          }
        );
        await sendPushNotification(
          coachID,
          title,
          body,
          { type: 'access_revoked', folderID },
          'ACCESS_REVOKED'
        );
      }
    }
  });

/**
 * Generates plain text email for access revocation
 */
function generateRevokedAccessPlainTextEmail(revocation: any): string {
  return `
Hi there,

This is a notification that ${revocation.athleteName} has removed your access to the shared folder "${revocation.folderName}" on PlayerPath.

You will no longer be able to:
- View videos in this folder
- Upload new videos
- Add comments or feedback

If you believe this was done in error, please contact ${revocation.athleteName} directly.

Thanks,
The PlayerPath Team

---
PlayerPath - Simplifying baseball video analysis for athletes and coaches
  `.trim();
}

/**
 * Generates HTML email for access revocation
 */
function generateRevokedAccessHtmlEmail(revocation: any): string {
  const headerTitle = 'Access Revoked';
  const introHtml = `This is a notification that <strong>${escapeHtml(revocation.athleteName)}</strong> has removed your access to the following shared folder:`;
  const noticeHtml = `<strong>Note:</strong> If you believe this was done in error, please contact ${escapeHtml(revocation.athleteName)} directly.`;
  return `
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>PlayerPath Access Revoked</title>
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
      line-height: 1.6;
      color: #333;
      background-color: #f5f5f5;
      margin: 0;
      padding: 0;
    }
    .container {
      max-width: 600px;
      margin: 40px auto;
      background: white;
      border-radius: 12px;
      overflow: hidden;
      box-shadow: 0 2px 8px rgba(0,0,0,0.1);
    }
    .header {
      background: linear-gradient(135deg, #ef4444 0%, #dc2626 100%);
      color: white;
      padding: 40px 30px;
      text-align: center;
    }
    .header h1 {
      margin: 0;
      font-size: 28px;
      font-weight: 600;
    }
    .header p {
      margin: 10px 0 0 0;
      font-size: 16px;
      opacity: 0.9;
    }
    .content {
      padding: 40px 30px;
    }
    .folder-name {
      background: #fee2e2;
      border-left: 4px solid #ef4444;
      padding: 16px 20px;
      margin: 20px 0;
      border-radius: 4px;
    }
    .folder-name strong {
      color: #ef4444;
      font-size: 18px;
    }
    .notice {
      background: #fef3c7;
      border-left: 4px solid #f59e0b;
      padding: 16px 20px;
      margin: 24px 0;
      border-radius: 4px;
    }
    .notice p {
      margin: 0;
      color: #92400e;
    }
    .footer {
      padding: 30px;
      text-align: center;
      color: #999;
      font-size: 14px;
      background: #f9fafb;
    }
    .footer a {
      color: #667eea;
      text-decoration: none;
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>${headerTitle}</h1>
      <p>Folder access notification</p>
    </div>

    <div class="content">
      <p style="font-size: 16px; margin-bottom: 8px;">Hi there,</p>

      <p style="font-size: 16px; line-height: 1.8;">
        ${introHtml}
      </p>

      <div class="folder-name">
        <strong>"${escapeHtml(revocation.folderName)}"</strong>
      </div>

      <p style="font-size: 16px; line-height: 1.8; margin-top: 24px;">
        You will no longer be able to:
      </p>
      <ul style="margin: 12px 0; padding-left: 20px;">
        <li style="margin: 8px 0; color: #666;">View videos in this folder</li>
        <li style="margin: 8px 0; color: #666;">Upload new videos</li>
        <li style="margin: 8px 0; color: #666;">Add comments or feedback</li>
      </ul>

      <div class="notice">
        <p>
          ${noticeHtml}
        </p>
      </div>

      <p style="font-size: 13px; color: #999; margin-top: 32px; padding-top: 24px; border-top: 1px solid #eee;">
        This notification was sent to ${escapeHtml(revocation.coachEmail)}.
      </p>
    </div>

    <div class="footer">
      <p><strong>PlayerPath</strong></p>
      <p>Simplifying baseball video analysis for athletes and coaches</p>
      <p style="margin-top: 16px;">
        <a href="https://playerpath.net">Website</a> •
        <a href="https://playerpath.net/support">Support</a> •
        <a href="https://playerpath.net/privacy">Privacy</a>
      </p>
    </div>
  </div>
</body>
</html>
  `.trim();
}

/**
 * Secure server-side acceptance of athlete-to-coach invitations.
 * Reads permissions from the invitation document (not client-supplied)
 * to prevent privilege escalation.
 */
export const acceptAthleteToCoachInvitation = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Must be authenticated');
  }

  // Recipient identity is matched by email below — require a verified email so an
  // attacker can't squat an unclaimed address to claim someone else's invitation.
  // Mirrors the Firestore rules' email-matched branches (which require email_verified).
  // Apple Sign In tokens always carry email_verified == true.
  if (context.auth.token.email_verified !== true) {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Please verify your email address before accepting invitations.'
    );
  }

  const { invitationID } = data;
  if (!invitationID || typeof invitationID !== 'string') {
    throw new functions.https.HttpsError('invalid-argument', 'invitationID is required');
  }

  const coachID = context.auth.uid;
  const coachEmail = context.auth.token.email?.toLowerCase();
  const db = admin.firestore();

  // Pre-check: fast-path rejection if coach is clearly over limit (avoids transaction overhead).
  // The authoritative check happens inside the transaction below.
  const coachDoc = await db.collection('users').doc(coachID).get();
  const coachTier = coachDoc.data()?.coachSubscriptionTier || 'coach_free';
  const limit = getCoachAthleteLimit(coachTier);

  const foldersSnap = await db.collection('sharedFolders')
    .where('sharedWithCoachIDs', 'array-contains', coachID)
    .get();
  // Key by personGroupID (dual-sport person = one slot), falling back to
  // athleteUUID then ownerAthleteID. Matches the client's
  // SubscriptionGate.fullConnectedAthleteCount so a parent account with multiple
  // distinct people counts as N slots, not 1.
  const connectedAthletes = new Set<string>(
    foldersSnap.docs.map(d => (d.data().personGroupID as string) || (d.data().athleteUUID as string) || d.data().ownerAthleteID)
  );

  const acceptedSnap = await db.collection('invitations')
    .where('type', '==', 'coach_to_athlete')
    .where('coachID', '==', coachID)
    .where('status', '==', 'accepted')
    .get();
  for (const doc of acceptedSnap.docs) {
    const key = (doc.data().personGroupID as string) || (doc.data().athleteUUID as string) || doc.data().athleteUserID;
    if (key) connectedAthletes.add(key);
  }

  // Read the invitation to find the athlete for the "already connected" check
  const preCheckSnap = await db.collection('invitations').doc(invitationID).get();
  const preCheckData = preCheckSnap.data();

  // Pricing Model V2: no athlete-tier check — coach connections are paid for by
  // the coach's seat (the limit transaction below), never the athlete's tier.
  // Dual-sport key: re-read the athlete profile doc (authoritative) so two sport
  // profiles of one person collapse to a single coach slot. athleteID = owning
  // account UID. Falls back to athleteUUID for solo athletes.
  const resolvedPersonGroupID = await resolveAthletePersonGroupID(
    db, preCheckData?.athleteID, preCheckData?.athleteUUID, preCheckData?.personGroupID
  );
  const connectionKey: string | undefined =
    resolvedPersonGroupID || preCheckData?.athleteUUID || preCheckData?.athleteID || preCheckData?.athleteUserID;

  if (connectionKey && !connectedAthletes.has(connectionKey) && connectedAthletes.size >= limit) {
    // Update invitation status before throwing so client UI shows "rejected" instead of "pending"
    await db.collection('invitations').doc(invitationID).update({
      status: 'rejected_limit',
      rejectedReason: 'Coach athlete limit reached',
      rejectedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    throw new functions.https.HttpsError(
      'resource-exhausted',
      'You have reached your athlete limit. Upgrade your plan to accept more athletes.'
    );
  }

  // Transaction: validate and accept with atomic limit check.
  // Reading the coach doc inside the transaction serializes concurrent acceptances
  // for the same coach — Firestore retries on conflict, ensuring limit integrity.
  await db.runTransaction(async (transaction) => {
    const invRef = db.collection('invitations').doc(invitationID);
    const coachRef = db.collection('users').doc(coachID);
    const invSnap = await transaction.get(invRef);
    const coachSnap = await transaction.get(coachRef);

    if (!invSnap.exists) {
      throw new functions.https.HttpsError('not-found', 'Invitation not found');
    }

    const inv = invSnap.data()!;

    if (inv.type !== 'athlete_to_coach') {
      throw new functions.https.HttpsError('failed-precondition', 'Wrong invitation type');
    }

    // Allow re-accepting an invitation that was previously auto-rejected for the
    // coach's athlete limit — the coach can upgrade and retry from the "Limit
    // Reached" section. The pre-check above + the atomic check below re-reject if
    // the coach is still over limit.
    if (inv.status !== 'pending' && inv.status !== 'rejected_limit') {
      throw new functions.https.HttpsError('failed-precondition', 'This invitation has already been processed.');
    }

    if (inv.expiresAt && inv.expiresAt.toDate() < new Date()) {
      throw new functions.https.HttpsError('failed-precondition', 'This invitation has expired.');
    }

    if (inv.coachEmail?.toLowerCase() !== coachEmail) {
      throw new functions.https.HttpsError('permission-denied', 'You are not the intended recipient of this invitation.');
    }

    // Atomic limit check inside transaction. coachAthleteCount is maintained by
    // acceptance/revocation functions. Falls back to pre-check count for migration.
    // Connection key prefers personGroupID (dual-sport person = one slot), then
    // athleteUUID for parent-account-with-multiple-profiles cases. Reuses the
    // pre-transaction resolved value to stay consistent with connectedAthletes.
    const invConnectionKey: string | undefined =
      resolvedPersonGroupID || inv.athleteUUID || inv.athleteID || inv.athleteUserID;
    const isNewConnection = invConnectionKey && !connectedAthletes.has(invConnectionKey);
    if (isNewConnection) {
      const currentCount = coachSnap.data()?.coachAthleteCount ?? connectedAthletes.size;
      if (currentCount >= limit) {
        transaction.update(invRef, {
          status: 'rejected_limit',
          rejectedReason: 'Coach athlete limit reached',
          rejectedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        throw new functions.https.HttpsError(
          'resource-exhausted',
          'You have reached your athlete limit. Upgrade your plan to accept more athletes.'
        );
      }
      // Write an explicit value derived from the in-transaction read (not
      // increment()) so concurrent accepts serialize via the coach-doc
      // write-conflict, and a migration coach with no counter field is
      // initialized to its true total rather than to 1.
      transaction.update(coachRef, {
        coachAthleteCount: currentCount + 1,
      });
    }

    // If invitation has a legacy folderID, join the existing folder
    if (inv.folderID) {
      const folderRef = db.collection('sharedFolders').doc(inv.folderID);
      const folderSnap = await transaction.get(folderRef);
      if (folderSnap.exists) {
        const permissions = inv.permissions || { canUpload: false, canComment: true, canDelete: false };
        const coachDisplayName = coachDoc.data()?.displayName || coachEmail?.split('@')[0] || 'Coach';
        transaction.update(folderRef, {
          sharedWithCoachIDs: admin.firestore.FieldValue.arrayUnion(coachID),
          [`sharedWithCoachNames.${coachID}`]: coachDisplayName,
          [`permissions.${coachID}`]: permissions,
          // Backfill/refresh the dual-sport key on this legacy/client-made folder.
          ...(resolvedPersonGroupID ? { personGroupID: resolvedPersonGroupID } : {}),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        // Clear any prior revocation so canAccessFolder doesn't deny the re-added coach.
        // Deterministic doc ID: "<folderID>_<coachID>".
        const revocationRef = db.collection('coach_access_revocations')
          .doc(`${inv.folderID}_${coachID}`);
        transaction.delete(revocationRef);
      }
    }

    transaction.update(invRef, {
      status: 'accepted',
      acceptedAt: admin.firestore.FieldValue.serverTimestamp(),
      acceptedByCoachID: coachID,
      // Clear any prior limit-rejection markers when re-accepting after upgrade.
      rejectedReason: admin.firestore.FieldValue.delete(),
      rejectedAt: admin.firestore.FieldValue.delete(),
      // Stamp the dual-sport key so the accepted-invitation merge in the count
      // sites agrees with the folder doc (same key → no double-count).
      ...(resolvedPersonGroupID ? { personGroupID: resolvedPersonGroupID } : {}),
    });
  });

  // Create shared folders after transaction (Admin SDK bypasses security rules).
  // For new invitations (no folderID), create Games + Lessons folders.
  // For legacy invitations (with folderID), folders already exist — skip creation.
  const invAfter = await db.collection('invitations').doc(invitationID).get();
  const invData = invAfter.data()!;

  if (invData.folderID) {
    // Legacy invitation — folder was created by the client before sending
    return { success: true, gamesFolderID: invData.folderID, lessonsFolderID: null };
  }

  const athleteName = invData.athleteName || 'Athlete';
  const athleteID = invData.athleteID;
  const athleteUUID = invData.athleteUUID;
  if (typeof athleteUUID !== 'string' || athleteUUID.length === 0) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'Invitation is missing athleteUUID. Ask the athlete to resend from an updated app version.'
    );
  }
  const permissions = invData.permissions || { canUpload: true, canComment: true, canDelete: false };
  const coachDisplayName = coachDoc.data()?.displayName || coachEmail?.split('@')[0] || 'Coach';

  // Reuse the athlete's existing folders (and their clips) on re-invite; only
  // create the ones that don't already exist.
  const { gamesFolderID, lessonsFolderID } = await reuseOrCreateSharedFolders(db, {
    coachID,
    athleteUUID,
    personGroupID: resolvedPersonGroupID || athleteUUID,
    ownerAthleteID: athleteID,
    athleteName,
    coachPermissions: permissions,
    coachDisplayName,
  });

  // Folder creation failed entirely — don't leave the coach "accepted + slot
  // consumed + no folder + no retry". Roll the acceptance back to pending and
  // surface a retryable error instead of returning a phantom success. (A partial
  // success — one folder created — is left as a usable connection.)
  if (!gamesFolderID && !lessonsFolderID) {
    await rollbackAcceptedInvitationOnFolderFailure(db, invitationID, coachID, ['acceptedByCoachID']);
    throw new functions.https.HttpsError(
      'unavailable',
      'Could not set up the shared folders for this connection. Please try again.'
    );
  }

  // Link folder IDs back to the invitation
  const primaryFolderID = gamesFolderID || lessonsFolderID;
  const primaryFolderName = gamesFolderID ? `${athleteName}'s Games` : `${athleteName}'s Lessons`;
  if (primaryFolderID) {
    try {
      await withRetry(() => db.collection('invitations').doc(invitationID).update({
        folderID: primaryFolderID,
        folderName: primaryFolderName,
      }));
    } catch (e) {
      console.error('Failed to update invitation with folder IDs:', e);
    }
  }

  return { success: true, gamesFolderID, lessonsFolderID };
});

/**
 * Accepts a coach-to-athlete invitation with server-side validation.
 * The athlete calls this instead of writing directly to Firestore.
 * Validates: caller identity, invitation state, expiration, and coach athlete limit.
 * Creates Games + Lessons shared folders server-side (Admin SDK bypasses Pro tier rule)
 * so any athlete can accept regardless of subscription tier.
 */
export const acceptCoachToAthleteInvitation = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Must be authenticated');
  }

  // Recipient identity is matched by email below — require a verified email so an
  // attacker can't squat an unclaimed address to claim someone else's invitation.
  // Mirrors the Firestore rules' email-matched branches (which require email_verified).
  // Apple Sign In tokens always carry email_verified == true.
  if (context.auth.token.email_verified !== true) {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Please verify your email address before accepting invitations.'
    );
  }

  const { invitationID, athleteName: clientAthleteName, athleteUUID: clientAthleteUUID, personGroupID: clientPersonGroupID } = data;
  if (!invitationID || typeof invitationID !== 'string') {
    throw new functions.https.HttpsError('invalid-argument', 'invitationID is required');
  }
  let athleteUUID: string | null =
    typeof clientAthleteUUID === 'string' && clientAthleteUUID.length > 0 ? clientAthleteUUID : null;

  const athleteUserID = context.auth.uid;
  const athleteEmail = context.auth.token.email?.toLowerCase();
  const db = admin.firestore();

  // Pre-check: read invitation and coach tier outside the transaction
  const invSnap = await db.collection('invitations').doc(invitationID).get();
  if (!invSnap.exists) {
    throw new functions.https.HttpsError('not-found', 'Invitation not found');
  }
  const invData = invSnap.data()!;
  const coachID = invData.coachID;

  if (!coachID) {
    throw new functions.https.HttpsError('failed-precondition', 'Invitation missing coachID');
  }

  // Fallback: live v5.0 clients don't send athleteUUID on this call. If the
  // invitation doc already carries one, use it. Fail hard if neither source has a value.
  if (!athleteUUID) {
    const invAthleteUUID = invData.athleteUUID;
    if (typeof invAthleteUUID === 'string' && invAthleteUUID.length > 0) {
      athleteUUID = invAthleteUUID;
    }
  }
  if (!athleteUUID) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'athleteUUID is required. Please update the app to the latest version.'
    );
  }

  // Validate the accepting athlete's account exists. No tier check — Pricing
  // Model V2: coach connections are paid for by the coach's seat (the limit
  // transaction below), never the athlete's tier.
  const athleteDoc = await db.collection('users').doc(athleteUserID).get();
  if (!athleteDoc.exists) {
    throw new functions.https.HttpsError(
      'not-found',
      'Athlete profile not found. Please ensure your account is set up.'
    );
  }

  // Pre-check: fast-path rejection if coach is clearly over limit (avoids transaction overhead).
  // The authoritative check happens inside the transaction below.
  const coachDoc = await db.collection('users').doc(coachID).get();
  const coachTier = coachDoc.data()?.coachSubscriptionTier || 'coach_free';
  const limit = getCoachAthleteLimit(coachTier);

  const foldersSnap = await db.collection('sharedFolders')
    .where('sharedWithCoachIDs', 'array-contains', coachID)
    .get();
  // Key by personGroupID (dual-sport person = one slot), falling back to
  // athleteUUID then ownerAthleteID (matches client).
  const connectedAthletes = new Set<string>(
    foldersSnap.docs.map(d => (d.data().personGroupID as string) || (d.data().athleteUUID as string) || d.data().ownerAthleteID)
  );

  const acceptedSnap = await db.collection('invitations')
    .where('type', '==', 'coach_to_athlete')
    .where('coachID', '==', coachID)
    .where('status', '==', 'accepted')
    .get();
  for (const doc of acceptedSnap.docs) {
    const key = (doc.data().personGroupID as string) || (doc.data().athleteUUID as string) || doc.data().athleteUserID;
    if (key) connectedAthletes.add(key);
  }

  // Dual-sport key: re-read the accepting athlete's profile doc (authoritative)
  // so two sport profiles of one person collapse to a single coach slot. The
  // caller (athleteUserID) is the owning account. Falls back to the resolved
  // athleteUUID (validated above), then athleteUserID.
  // Fallback prefers the client-supplied value (computed on the accepting
  // athlete's own device) over the coach-set invitation value, covering the race
  // where a just-created spinoff profile's personGroupID hasn't synced yet.
  const resolvedPersonGroupID = await resolveAthletePersonGroupID(
    db, athleteUserID, athleteUUID, clientPersonGroupID || invData.personGroupID
  );
  const incomingKey = resolvedPersonGroupID || athleteUUID || athleteUserID;

  if (!connectedAthletes.has(incomingKey) && connectedAthletes.size >= limit) {
    // Leave the invitation PENDING (do NOT mark rejected_limit). Unlike the
    // athlete→coach flow — where the COACH accepts and recovers a rejected invite
    // from their own "Couldn't Accept" list — here the ATHLETE is accepting and
    // can't act on the coach's limit. Marking it rejected_limit would drop it from
    // the athlete's (pending-only) list AND block re-accept (the transaction below
    // requires status==='pending'). Keeping it pending lets the athlete simply try
    // again once the coach upgrades or frees a seat.
    throw new functions.https.HttpsError(
      'resource-exhausted',
      'This coach has reached their athlete limit. Ask them to upgrade or free a spot, then try again.'
    );
  }

  // Transaction: validate and accept with atomic limit check.
  // Reading the coach doc inside the transaction serializes concurrent acceptances
  // for the same coach — Firestore retries on conflict, ensuring limit integrity.
  await db.runTransaction(async (transaction) => {
    const invRef = db.collection('invitations').doc(invitationID);
    const coachRef = db.collection('users').doc(coachID);
    const freshSnap = await transaction.get(invRef);
    const coachSnap = await transaction.get(coachRef);

    if (!freshSnap.exists) {
      throw new functions.https.HttpsError('not-found', 'Invitation not found');
    }

    const inv = freshSnap.data()!;

    if (inv.type !== 'coach_to_athlete') {
      throw new functions.https.HttpsError('failed-precondition', 'Wrong invitation type');
    }

    if (inv.status !== 'pending') {
      throw new functions.https.HttpsError('failed-precondition', 'This invitation has already been processed.');
    }

    if (inv.expiresAt && inv.expiresAt.toDate() < new Date()) {
      throw new functions.https.HttpsError('failed-precondition', 'This invitation has expired.');
    }

    // Verify the caller is the intended recipient by matching emails.
    // Apple "Hide My Email" uses @privaterelay.appleid.com which won't match the
    // real email the coach typed. For relay users, resolve the real email from
    // Firebase Auth provider data or the user's Firestore profile.
    const invEmail = inv.athleteEmail?.toLowerCase();
    let emailMatch = (invEmail === athleteEmail);

    if (!emailMatch && athleteEmail?.endsWith('@privaterelay.appleid.com')) {
      try {
        const userRecord = await admin.auth().getUser(athleteUserID);
        const realEmails = userRecord.providerData
          .map(p => p.email?.toLowerCase())
          .filter((e): e is string => !!e);
        emailMatch = realEmails.some(e => e === invEmail);

        if (!emailMatch) {
          const userDoc = await db.collection('users').doc(athleteUserID).get();
          const profileEmail = userDoc.data()?.email?.toLowerCase();
          if (profileEmail && profileEmail === invEmail) {
            emailMatch = true;
          }
        }
      } catch (e) {
        console.warn('Failed to resolve Apple relay email:', e);
        emailMatch = false;
      }
    }

    if (!emailMatch) {
      throw new functions.https.HttpsError('permission-denied', 'You are not the intended recipient of this invitation.');
    }

    // Atomic limit check inside transaction. coachAthleteCount is maintained by
    // acceptance/revocation functions. Falls back to pre-check count for migration.
    const isNewConnection = !connectedAthletes.has(incomingKey);
    if (isNewConnection) {
      const currentCount = coachSnap.data()?.coachAthleteCount ?? connectedAthletes.size;
      if (currentCount >= limit) {
        // Leave PENDING (see the pre-check note above) — throwing aborts the
        // transaction with no write, so the athlete can retry once the coach
        // makes room, instead of the invite becoming a dead rejected_limit doc.
        throw new functions.https.HttpsError(
          'resource-exhausted',
          'This coach has reached their athlete limit. Ask them to upgrade or free a spot, then try again.'
        );
      }
      // Explicit value from the in-transaction read (not increment()) so
      // concurrent accepts serialize and migration coaches initialize correctly.
      transaction.update(coachRef, {
        coachAthleteCount: currentCount + 1,
      });
    }

    transaction.update(invRef, {
      status: 'accepted',
      acceptedAt: admin.firestore.FieldValue.serverTimestamp(),
      athleteUserID: athleteUserID,
      athleteUUID: athleteUUID,
      // Stamp the dual-sport key so the accepted-invitation merge in the count
      // sites agrees with the folder doc (same key → no double-count).
      ...(resolvedPersonGroupID ? { personGroupID: resolvedPersonGroupID } : {}),
    });
  });

  // Create shared folders after transaction succeeds (Admin SDK bypasses security rules).
  // Uses the athlete's self-chosen name from the client, falling back to the name
  // the coach typed when creating the invitation.
  const name = clientAthleteName || invData.athleteName || 'Athlete';
  const coachDisplayName = coachDoc.data()?.displayName || invData.coachName || invData.coachEmail?.split('@')[0] || 'Coach';
  const defaultPerms = { canUpload: true, canComment: true, canDelete: false };

  // Reuse the athlete's existing folders (and their clips) on re-invite; only
  // create the ones that don't already exist.
  const { gamesFolderID, lessonsFolderID } = await reuseOrCreateSharedFolders(db, {
    coachID,
    athleteUUID,
    personGroupID: resolvedPersonGroupID || athleteUUID,
    ownerAthleteID: athleteUserID,
    athleteName: name,
    coachPermissions: defaultPerms,
    coachDisplayName,
  });

  // Folder creation failed entirely — don't leave the connection "accepted + slot
  // consumed + no folder + no retry". Roll the acceptance back to pending and
  // surface a retryable error instead of returning a phantom success. (A partial
  // success — one folder created — is left as a usable connection.)
  if (!gamesFolderID && !lessonsFolderID) {
    await rollbackAcceptedInvitationOnFolderFailure(db, invitationID, coachID, ['athleteUserID']);
    throw new functions.https.HttpsError(
      'unavailable',
      'Could not set up the shared folders for this connection. Please try again.'
    );
  }

  // Link folder IDs back to the invitation document
  const folderID = gamesFolderID || lessonsFolderID;
  const folderName = gamesFolderID ? `${name}'s Games` : lessonsFolderID ? `${name}'s Lessons` : null;
  if (folderID && folderName) {
    try {
      await withRetry(() => db.collection('invitations').doc(invitationID).update({
        folderID,
        folderName,
      }));
    } catch (e) {
      console.error('Failed to update invitation with folder IDs:', e);
    }
  }

  return { success: true, gamesFolderID, lessonsFolderID };
});

/**
 * HTTP endpoint to manually resend an invitation email (for debugging/support)
 */
export const resendInvitationEmail = functions.https.onCall(async (data, context) => {
  // Verify the user is authenticated
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Must be authenticated');
  }

  const { invitationId } = data;

  if (!invitationId) {
    throw new functions.https.HttpsError('invalid-argument', 'Missing invitationId');
  }

  // Rate limit: max 10 emails per user per hour
  if (!(await checkEmailRateLimit(context.auth.uid))) {
    throw new functions.https.HttpsError('resource-exhausted', 'Too many emails. Try again later.');
  }

  try {
    const invitationRef = admin.firestore().collection('invitations').doc(invitationId);
    const invitationSnap = await invitationRef.get();

    if (!invitationSnap.exists) {
      throw new functions.https.HttpsError('not-found', 'Invitation not found');
    }

    const invitation = invitationSnap.data();
    if (!invitation) {
      throw new functions.https.HttpsError('not-found', 'Invitation data is empty');
    }

    // Verify the user owns this invitation (athlete or coach depending on type)
    const isOwner = invitation.type === 'coach_to_athlete'
      ? invitation.coachID === context.auth.uid
      : invitation.athleteID === context.auth.uid;
    if (!isOwner) {
      throw new functions.https.HttpsError('permission-denied', 'Not authorized');
    }

    if (invitation.status !== 'pending') {
      throw new functions.https.HttpsError('failed-precondition', 'Can only resend emails for pending invitations');
    }

    const deepLink = `playerpath://invitation/${invitationId}`;

    let msg;
    if (invitation?.type === 'coach_to_athlete') {
      msg = {
        to: invitation.athleteEmail,
        from: 'PlayerPath <noreply@playerpath.net>',
        subject: `Coach ${invitation.coachName} wants to connect on PlayerPath`,
        text: generateCoachToAthletePlainTextEmail(invitation, deepLink),
        html: generateCoachToAthleteHtmlEmail(invitation, deepLink),
      };
    } else {
      const webLink = `https://playerpath.net/invitation/${invitationId}`;
      msg = {
        to: invitation.coachEmail,
        from: 'PlayerPath <noreply@playerpath.net>',
        subject: `${invitation.athleteName} invited you to collaborate on PlayerPath`,
        text: generatePlainTextEmail(invitation, deepLink, webLink),
        html: generateHtmlEmail(invitation, deepLink, webLink),
      };
    }

    await getResend().emails.send(msg);

    // Update timestamp
    await invitationRef.update({
      emailResentAt: admin.firestore.FieldValue.serverTimestamp(),
      emailSent: true
    });

    return { success: true, message: 'Email resent successfully' };

  } catch (error) {
    console.error('Error resending invitation email:', error);
    throw new functions.https.HttpsError('internal', 'Failed to resend email');
  }
});

// =============================================================================
// SIGNED URL GENERATION
// Requires the Cloud Functions service account to have the Storage Object Admin
// IAM role granted in the Firebase console (IAM & Admin → IAM).
// =============================================================================

/**
 * Returns a time-limited signed URL for a shared folder video.
 * Verifies the caller is the folder owner or a shared coach before signing.
 */
export const getSignedVideoURL = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
  }

  const { folderID, fileName, expirationHours = 24 } = data;
  if (!folderID || !fileName) {
    throw new functions.https.HttpsError('invalid-argument', 'folderID and fileName are required');
  }

  const safeFileName = sanitizeFileName(fileName);

  const db = admin.firestore();
  const folderDoc = await db.collection('sharedFolders').doc(folderID).get();
  if (!folderDoc.exists) {
    throw new functions.https.HttpsError('not-found', 'Folder not found');
  }

  const folder = folderDoc.data()!;
  const sharedCoachIDs: string[] = folder.sharedWithCoachIDs || [];
  const hasAccess = context.auth.uid === folder.ownerAthleteID || sharedCoachIDs.includes(context.auth.uid);
  if (!hasAccess) {
    throw new functions.https.HttpsError('permission-denied', 'Access denied to this folder');
  }

  // Enforce subscription tier for coaches accessing shared videos
  if (context.auth.uid !== folder.ownerAthleteID) {
    const userDoc = await db.collection('users').doc(context.auth.uid).get();
    if (!userDoc.exists) {
      throw new functions.https.HttpsError('permission-denied', 'User profile not found');
    }
    const userData = userDoc.data()!;
    if (userData.role === 'coach' && !userData.coachSubscriptionTier) {
      throw new functions.https.HttpsError('permission-denied', 'Active coach subscription required');
    }
  }

  const expiresAt = new Date();
  expiresAt.setHours(expiresAt.getHours() + clampExpiration(expirationHours));

  try {
    const bucket = admin.storage().bucket();
    const [signedUrl] = await bucket.file(`shared_folders/${folderID}/${safeFileName}`).getSignedUrl({
      action: 'read',
      expires: expiresAt,
    });
    return { signedURL: signedUrl, expiresAt: expiresAt.toISOString() };
  } catch (error) {
    console.error('getSignedVideoURL error:', error);
    throw new functions.https.HttpsError('internal', 'Failed to generate signed URL');
  }
});

/**
 * Returns a time-limited signed URL for a shared folder video thumbnail.
 */
export const getSignedThumbnailURL = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
  }

  const { folderID, videoFileName, expirationHours = 168 } = data;
  if (!folderID || !videoFileName) {
    throw new functions.https.HttpsError('invalid-argument', 'folderID and videoFileName are required');
  }

  const safeVideoFileName = sanitizeFileName(videoFileName);

  const db = admin.firestore();
  const folderDoc = await db.collection('sharedFolders').doc(folderID).get();
  if (!folderDoc.exists) {
    throw new functions.https.HttpsError('not-found', 'Folder not found');
  }

  const folder = folderDoc.data()!;
  const sharedCoachIDs: string[] = folder.sharedWithCoachIDs || [];
  const hasAccess = context.auth.uid === folder.ownerAthleteID || sharedCoachIDs.includes(context.auth.uid);
  if (!hasAccess) {
    throw new functions.https.HttpsError('permission-denied', 'Access denied to this folder');
  }

  // Enforce subscription tier for coaches accessing shared content
  if (context.auth.uid !== folder.ownerAthleteID) {
    const userDoc = await db.collection('users').doc(context.auth.uid).get();
    if (!userDoc.exists) {
      throw new functions.https.HttpsError('permission-denied', 'User profile not found');
    }
    const userData = userDoc.data()!;
    if (userData.role === 'coach' && !userData.coachSubscriptionTier) {
      throw new functions.https.HttpsError('permission-denied', 'Active coach subscription required');
    }
  }

  const baseName = safeVideoFileName.replace(/\.[^/.]+$/, '');
  const thumbnailFileName = `${baseName}_thumbnail.jpg`;
  const expiresAt = new Date();
  expiresAt.setHours(expiresAt.getHours() + clampExpiration(expirationHours));

  try {
    const bucket = admin.storage().bucket();
    const [signedUrl] = await bucket
      .file(`shared_folders/${folderID}/thumbnails/${thumbnailFileName}`)
      .getSignedUrl({ action: 'read', expires: expiresAt });
    return { signedURL: signedUrl, expiresAt: expiresAt.toISOString() };
  } catch (error) {
    console.error('getSignedThumbnailURL error:', error);
    throw new functions.https.HttpsError('internal', 'Failed to generate thumbnail signed URL');
  }
});

/**
 * Returns signed URLs for multiple videos in a shared folder (batch).
 */
export const getBatchSignedVideoURLs = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
  }

  const { folderID, fileNames, expirationHours = 24 } = data;
  if (!folderID || !Array.isArray(fileNames)) {
    throw new functions.https.HttpsError('invalid-argument', 'folderID and fileNames array are required');
  }

  if (fileNames.length > MAX_BATCH_SIZE) {
    throw new functions.https.HttpsError('invalid-argument', `Maximum ${MAX_BATCH_SIZE} files per batch request`);
  }

  const db = admin.firestore();
  const folderDoc = await db.collection('sharedFolders').doc(folderID).get();
  if (!folderDoc.exists) {
    throw new functions.https.HttpsError('not-found', 'Folder not found');
  }

  const folder = folderDoc.data()!;
  const sharedCoachIDs: string[] = folder.sharedWithCoachIDs || [];
  const hasAccess = context.auth.uid === folder.ownerAthleteID || sharedCoachIDs.includes(context.auth.uid);
  if (!hasAccess) {
    throw new functions.https.HttpsError('permission-denied', 'Access denied to this folder');
  }

  // Enforce subscription tier for coaches accessing shared content
  if (context.auth.uid !== folder.ownerAthleteID) {
    const userDoc = await db.collection('users').doc(context.auth.uid).get();
    if (!userDoc.exists) {
      throw new functions.https.HttpsError('permission-denied', 'User profile not found');
    }
    const userData = userDoc.data()!;
    if (userData.role === 'coach' && !userData.coachSubscriptionTier) {
      throw new functions.https.HttpsError('permission-denied', 'Active coach subscription required');
    }
  }

  const expiresAt = new Date();
  expiresAt.setHours(expiresAt.getHours() + clampExpiration(expirationHours));
  const bucket = admin.storage().bucket();

  const urls = await Promise.all(
    (fileNames as string[]).map(async (fileName: string) => {
      try {
        const safeFileName = sanitizeFileName(fileName);
        const [signedUrl] = await bucket
          .file(`shared_folders/${folderID}/${safeFileName}`)
          .getSignedUrl({ action: 'read', expires: expiresAt });
        return { fileName, signedURL: signedUrl, expiresAt: expiresAt.toISOString() };
      } catch (error) {
        console.error(`Error signing ${fileName}:`, error);
        return { fileName, error: 'Failed to generate URL' };
      }
    })
  );

  return { urls };
});

/**
 * Returns a time-limited signed URL for a personal athlete video.
 * Only the owning user may request their own video URLs.
 */
export const getPersonalVideoSignedURL = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
  }

  const { ownerUID, fileName, expirationHours = 24 } = data;
  if (!ownerUID || !fileName) {
    throw new functions.https.HttpsError('invalid-argument', 'ownerUID and fileName are required');
  }

  const safeFileName = sanitizeFileName(fileName);

  if (context.auth.uid !== ownerUID) {
    throw new functions.https.HttpsError('permission-denied', 'Cannot access another user\'s videos');
  }

  const expiresAt = new Date();
  expiresAt.setHours(expiresAt.getHours() + clampExpiration(expirationHours));

  try {
    const bucket = admin.storage().bucket();
    const [signedUrl] = await bucket
      .file(`athlete_videos/${ownerUID}/${safeFileName}`)
      .getSignedUrl({ action: 'read', expires: expiresAt });
    return { signedURL: signedUrl, expiresAt: expiresAt.toISOString() };
  } catch (error) {
    console.error('getPersonalVideoSignedURL error:', error);
    throw new functions.https.HttpsError('internal', 'Failed to generate signed URL');
  }
});

// =============================================================================
// VIDEO STORAGE CLEANUP & QUOTA ENFORCEMENT
// =============================================================================

// Tier storage limits in bytes — must match SubscriptionTier.storageLimitGB in the app
const TIER_LIMITS: Record<string, number> = {
  free: 2 * 1024 * 1024 * 1024,         // 2 GB
  plus: 25 * 1024 * 1024 * 1024,        // 25 GB
  pro:  100 * 1024 * 1024 * 1024,       // 100 GB
};

/**
 * Server-side storage quota enforcement + cross-device usage sync.
 *
 * Triggers on every upload to athlete_videos/ or athlete_photos/. Computes the
 * authoritative per-user total (videos summed from Firestore docs, photos
 * summed from bucket listing since FirestorePhoto has no fileSize field). If
 * the total exceeds the user's tier limit, the just-uploaded file is deleted.
 *
 * In all cases the function writes the computed total back to
 * users/{uid}.cloudStorageUsedBytes so other devices signed into the same
 * account see the same usage on their next profile fetch — closes the
 * multi-device quota gap (project_multi_device_todos.md #2).
 */
export const enforceStorageQuota = functions.storage
  .object()
  .onFinalize(async (object) => {
    const filePath = object.name;
    if (!filePath) return;

    const isVideo = filePath.startsWith('athlete_videos/');
    const isPhoto = filePath.startsWith('athlete_photos/');
    if (!isVideo && !isPhoto) return;

    const newFileSize = parseInt(object.size, 10) || 0;
    // Extract ownerUID from path: athlete_{videos|photos}/{ownerUID}/{fileName}
    const parts = filePath.split('/');
    if (parts.length < 3) return;
    const ownerUID = parts[1];

    const db = admin.firestore();
    const bucket = admin.storage().bucket();

    // Look up the user's tier from their Firestore profile
    const userSnap = await db.collection('users').doc(ownerUID).get();
    const tier = userSnap.exists ? (userSnap.data()?.subscriptionTier || 'free') : 'free';
    const limitBytes = TIER_LIMITS[tier] || TIER_LIMITS['free'];

    // Sum non-deleted video sizes from Firestore (videos collection uses
    // "uploadedBy" as the owner field; "fileSize" is written by the client).
    // Filter isDeleted in code rather than with a Firestore `!=` inequality:
    // the inequality requires a composite (uploadedBy, isDeleted, __name__)
    // index AND silently drops docs that have no isDeleted field at all,
    // which would under-count storage. An equality-only query needs no
    // composite index and correctly counts docs where isDeleted is
    // missing or false.
    const videosSnap = await db.collection('videos')
      .where('uploadedBy', '==', ownerUID)
      .select('fileSize', 'isDeleted')
      .get();
    let videosTotal = 0;
    videosSnap.forEach(doc => {
      const data = doc.data();
      if (data.isDeleted === true) return; // skip soft-deleted
      videosTotal += (data.fileSize || 0);
    });

    // Sum photo sizes by listing the bucket prefix. FirestorePhoto has no
    // fileSize field, so the bucket is the source of truth. Bounded by the
    // user's photo count.
    let photosTotal = 0;
    try {
      const [photoFiles] = await bucket.getFiles({ prefix: `athlete_photos/${ownerUID}/` });
      for (const f of photoFiles) {
        photosTotal += Number(f.metadata.size) || 0;
      }
    } catch (err) {
      console.warn(`⚠️ Photo prefix listing failed for ${ownerUID}; quota may undercount photos:`, err);
    }

    // For videos: the metadata-first upload writes the Firestore doc before
    // the file completes, so the new file's fileSize is already in videosTotal
    // most of the time. Add object.size on top to stay conservative (matches
    // pre-existing behavior — errs toward enforcing the cap).
    //
    // For photos: bucket listing happens AFTER onFinalize, so the new file is
    // already counted in photosTotal. Don't add it again.
    let totalBytes = videosTotal + photosTotal + (isVideo ? newFileSize : 0);

    if (totalBytes > limitBytes) {
      console.warn(`⚠️ Storage quota exceeded: ${totalBytes} bytes > ${limitBytes} bytes (tier: ${tier}). Deleting ${filePath}.`);
      try {
        await bucket.file(filePath).delete();
        console.log(`🗑️ Deleted over-quota file: ${filePath}`);
        // Subtract the now-deleted file from the running total for the
        // write-back so devices don't see an inflated number.
        totalBytes = Math.max(0, totalBytes - newFileSize);
      } catch (err) {
        console.error(`❌ Failed to delete over-quota file ${filePath}:`, err);
      }
    }

    // Write authoritative total back to users/{uid} so other devices converge
    // on the same value on their next profile fetch. Best-effort — never throw
    // past the trigger boundary.
    try {
      await db.collection('users').doc(ownerUID).set(
        { cloudStorageUsedBytes: totalBytes },
        { merge: true }
      );
    } catch (err) {
      console.error(`❌ Failed to write cloudStorageUsedBytes for ${ownerUID}:`, err);
    }
  });

// =============================================================================
// SUBSCRIPTION TIER SYNC (server-side receipt validation)
// =============================================================================

// Product ID → tier mapping (must match SubscriptionModels.swift)
const ATHLETE_PRODUCT_TIERS: Record<string, string> = {
  'com.playerpath.plus.monthly': 'plus',
  'com.playerpath.plus.annual':  'plus',
  'com.playerpath.pro.monthly':  'pro',
  'com.playerpath.pro.annual':   'pro',
};

const COACH_PRODUCT_TIERS: Record<string, string> = {
  'com.playerpath.coach.instructor.monthly':    'coach_instructor',
  'com.playerpath.coach.instructor.annual':     'coach_instructor',
  'com.playerpath.coach.proinstructor.monthly':  'coach_pro_instructor',
  'com.playerpath.coach.annual.proinstructor':   'coach_pro_instructor',
};

// Tier rank for comparison (higher = better)
const ATHLETE_TIER_RANK: Record<string, number> = { free: 0, plus: 1, pro: 2 };
const COACH_TIER_RANK: Record<string, number> = {
  coach_free: 0, coach_instructor: 1, coach_pro_instructor: 2, coach_academy: 3,
};

/**
 * Verifies an array of StoreKit 2 Transaction JWS tokens and derives the
 * highest active athlete and coach subscription tiers from the product IDs.
 * Only non-expired, non-revoked transactions are considered.
 */
interface ActiveTransactionRef {
  originalTransactionId: string;
  productId: string;
  appAccountToken?: string;
}

async function resolveTransactionTiers(
  transactionTokens: string[],
  verifier: SignedDataVerifier,
): Promise<{ athleteTier: string; coachTier: string; activeTransactions: ActiveTransactionRef[] }> {
  let athleteTier = 'free';
  let coachTier = 'coach_free';
  const activeTransactions: ActiveTransactionRef[] = [];
  const now = Date.now();

  for (const token of transactionTokens) {
    let tx: JWSTransactionDecodedPayload;
    try {
      tx = await verifier.verifyAndDecodeTransaction(token);
    } catch (e) {
      console.warn('⚠️ Skipping unverifiable transaction token:', e);
      continue;
    }

    // Skip revoked transactions
    if (tx.revocationDate) continue;

    // Skip expired transactions
    if (tx.expiresDate && tx.expiresDate < now) continue;

    const productId = tx.productId ?? '';

    // Record the still-active subscription transaction so the App Store Server
    // Notifications webhook can later map a refund/expiry/revoke back to this user.
    if (tx.originalTransactionId && (ATHLETE_PRODUCT_TIERS[productId] || COACH_PRODUCT_TIERS[productId])) {
      activeTransactions.push({
        originalTransactionId: tx.originalTransactionId,
        productId,
        appAccountToken: tx.appAccountToken,
      });
    }

    // Check athlete products
    const aTier = ATHLETE_PRODUCT_TIERS[productId];
    if (aTier && (ATHLETE_TIER_RANK[aTier] ?? 0) > (ATHLETE_TIER_RANK[athleteTier] ?? 0)) {
      athleteTier = aTier;
    }

    // Check coach products
    const cTier = COACH_PRODUCT_TIERS[productId];
    if (cTier && (COACH_TIER_RANK[cTier] ?? 0) > (COACH_TIER_RANK[coachTier] ?? 0)) {
      coachTier = cTier;
    }
  }

  return { athleteTier, coachTier, activeTransactions };
}

/**
 * Syncs a user's subscription tier to Firestore after validating
 * StoreKit 2 Transaction JWS tokens server-side. The server derives the
 * tier from verified product IDs — it does NOT trust client-provided strings.
 *
 * The client sends:
 *   - receiptData: base64-encoded AppTransaction JWS (app-level authenticity proof)
 *   - transactionTokens: array of JWS strings from Transaction.currentEntitlements
 *
 * Comped tier preservation is handled server-side: if the resolved tier is "free"
 * but the user's Firestore tier is higher, the higher tier is preserved (manual comp).
 * Legacy clients that omit transactionTokens will be rejected.
 */
export const syncSubscriptionTier = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
  }

  const uid = context.auth.uid;
  const { receiptData, transactionTokens } = data;

  if (!Array.isArray(transactionTokens)) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'transactionTokens array is required. Please update your app.'
    );
  }

  // Create both production and sandbox verifiers. TestFlight uses sandbox-signed
  // tokens, so we try production first then fall back to sandbox.
  const verifiers = createVerifiers();
  let activeVerifier: SignedDataVerifier = verifiers.production;

  // --- Step 1: Verify AppTransaction (proves the app binary is legitimate) ---
  // Always try production first, then sandbox (TestFlight uses sandbox-signed tokens).
  // A missing receiptData is honored ONLY in the local emulator (handled below);
  // in any deployed environment it is rejected. Individual transaction JWS tokens
  // are still verified in Step 2.
  if (!receiptData || typeof receiptData !== 'string') {
    // No AppTransaction receipt. A legitimate release OR TestFlight client ALWAYS
    // sends a verified AppTransaction — the no-receipt payload is a #if DEBUG-only
    // client path (see FirestoreManager+UserProfile.swift). In a deployed function
    // the only callers that reach here are crafted requests trying to skip Step-1
    // app verification and force the SANDBOX verifier, which would then accept a
    // free, genuinely-Apple-signed sandbox transaction for a paid product and write
    // that tier for $0. Only allow the sandbox fallback when running locally in the
    // emulator; reject it in production/TestFlight.
    if (!process.env.FUNCTIONS_EMULATOR) {
      console.error('❌ syncSubscriptionTier called without an AppTransaction receipt in a deployed environment — rejecting.');
      throw new functions.https.HttpsError('permission-denied', 'App Store receipt required.');
    }
    console.log('⚠️ No AppTransaction receipt — emulator/local dev only, using sandbox verifier.');
    activeVerifier = verifiers.sandbox;
  } else {
    let verified = false;
    for (const [envName, verifier] of [['production', verifiers.production], ['sandbox', verifiers.sandbox]] as const) {
      try {
        const appTransaction = await verifier.verifyAndDecodeAppTransaction(receiptData);
        if (!appTransaction.bundleId || appTransaction.bundleId !== APP_BUNDLE_ID) {
          throw new Error(`Bundle ID mismatch: expected ${APP_BUNDLE_ID}, got ${appTransaction.bundleId ?? 'undefined'}`);
        }
        console.log(`✅ Verified AppTransaction (${envName}): bundleId=${appTransaction.bundleId}`);
        activeVerifier = verifier;
        verified = true;
        break;
      } catch (e) {
        console.log(`AppTransaction verification failed for ${envName}: ${e}`);
      }
    }
    if (!verified) {
      console.error('❌ App Store verification failed for both production and sandbox environments.');
      throw new functions.https.HttpsError('permission-denied', 'Invalid App Store transaction token');
    }
  }

  // --- Step 2: Verify individual Transaction tokens and derive tiers ---
  const { athleteTier, coachTier, activeTransactions } = await resolveTransactionTiers(transactionTokens, activeVerifier);

  console.log(`🔍 Server-derived tiers: athlete=${athleteTier}, coach=${coachTier}`);

  // --- Step 3: Build the Firestore update, respecting overrides ---
  const updateData: Record<string, any> = {
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  // Read current Firestore state to detect manual comps (server-side detection).
  // athleteTierSource tracks who last wrote the tier: 'storekit' (this function)
  // or absent/other (admin SDK comp). When a subscription expires, athleteTier
  // resolves to 'free' but currentAthleteTier is still 'pro' — we need tierSource
  // to distinguish "admin comp" from "expired subscription".
  const userDoc = await admin.firestore().collection('users').doc(uid).get();
  const currentAthleteTier = userDoc.data()?.subscriptionTier ?? 'free';
  const athleteTierSource = userDoc.data()?.athleteTierSource;
  const currentCoachTier = userDoc.data()?.coachSubscriptionTier ?? 'coach_free';
  const coachTierSource = userDoc.data()?.coachTierSource;

  // Preserve manually-granted (comped) athlete tier when server resolves "free"
  if (athleteTier !== 'free') {
    updateData.subscriptionTier = athleteTier;
    updateData.athleteTierSource = 'storekit';
  } else if (currentAthleteTier === 'free' || athleteTierSource === 'storekit') {
    // Either already free, or last tier was written by StoreKit (subscription expired)
    updateData.subscriptionTier = 'free';
    updateData.athleteTierSource = 'storekit';
  }
  // else: currentAthleteTier > free AND tierSource !== 'storekit' = admin comp, preserve it

  // Coach tier: symmetric to the athlete logic above, with extra protection for
  // the manually-granted Academy tier (rank 3, no StoreKit product) which must
  // outrank any purchasable tier. coachTierSource tracks who last wrote the tier:
  // 'storekit' (this function) vs absent/other (an admin-SDK comp). Previously this
  // block only ever wrote UP, so a coach who bought then cancelled Instructor kept
  // that tier — and its athlete limit — in Firestore forever.
  const currentCoachRank = COACH_TIER_RANK[currentCoachTier] ?? 0;
  const resolvedCoachRank = COACH_TIER_RANK[coachTier] ?? 0;
  // A manual grant is a non-free tier this function did NOT write.
  const coachIsManualGrant = currentCoachTier !== 'coach_free' && coachTierSource !== 'storekit';

  if (coachTier !== 'coach_free') {
    // StoreKit resolved a paid coach tier (upgrade, renewal, or a paid→paid change).
    // Take it UNLESS a higher manual grant (e.g. Academy) should be preserved.
    if (coachIsManualGrant && resolvedCoachRank < currentCoachRank) {
      // Keep the higher manual grant; don't downgrade a comp to a purchase.
    } else {
      updateData.coachSubscriptionTier = coachTier;
      updateData.coachTierSource = 'storekit';
    }
  } else if (currentCoachTier === 'coach_free' || coachTierSource === 'storekit') {
    // Resolved free AND (already free OR last tier was StoreKit-written): a purchased
    // coach subscription expired/cancelled — write the downgrade authoritatively so
    // the client (CoachDowngradeManager) and the limit checks see the lower tier.
    updateData.coachSubscriptionTier = 'coach_free';
    updateData.coachTierSource = 'storekit';
  }
  // else: resolved free, current is a manual grant (Academy/comp) → preserve it.

  // If a coach-downgrade backstop is active, lift it when the (possibly upgraded)
  // coach tier now covers the connected count — so buying a higher tier instantly
  // restores feedback delivery without waiting for the daily audit. Only pay the
  // recompute cost when a flag is actually set.
  const hadDowngradeFlags = userDoc.data()?.downgradeUnresolved === true
    || userDoc.data()?.coachDowngradeGraceStartedAt !== undefined;
  if (hadDowngradeFlags) {
    const effectiveCoachTier = (updateData.coachSubscriptionTier as string | undefined) ?? currentCoachTier;
    try {
      const count = await computeCoachConnectionCount(admin.firestore(), uid);
      if (count <= getCoachAthleteLimit(effectiveCoachTier)) {
        updateData.downgradeUnresolved = admin.firestore.FieldValue.delete();
        updateData.coachDowngradeGraceStartedAt = admin.firestore.FieldValue.delete();
      }
    } catch (e) {
      console.warn(`syncSubscriptionTier: downgrade-flag reconcile failed for ${uid}:`, e);
    }
  }

  try {
    await admin.firestore().collection('users').doc(uid).set(updateData, { merge: true });
    console.log(`✅ Synced tiers for ${uid}: athlete=${athleteTier}, coach=${coachTier}`);

    // Persist originalTransactionId -> uid so the App Store Server Notifications
    // webhook can map a future refund/expiry/revoke back to this user. Best-effort:
    // a mapping failure must not fail the tier sync the client is awaiting.
    if (activeTransactions.length > 0) {
      try {
        const mapBatch = admin.firestore().batch();
        for (const t of activeTransactions) {
          mapBatch.set(
            admin.firestore().collection('appleSubscriptions').doc(t.originalTransactionId),
            {
              uid,
              productId: t.productId,
              appAccountToken: t.appAccountToken ?? null,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true },
          );
        }
        await mapBatch.commit();
      } catch (mapErr) {
        console.error('⚠️ Failed to persist appleSubscriptions mapping (non-fatal):', mapErr);
      }
    }

    return { success: true, athleteTier, coachTier };
  } catch (error) {
    console.error('❌ Failed to sync tiers:', error);
    throw new functions.https.HttpsError('internal', 'Failed to update subscription tier');
  }
});

/**
 * App Store Server Notifications V2 webhook.
 *
 * Apple POSTs server-authoritative subscription events here (refunds, expiries,
 * revocations, grace-period expiries) independently of whether the client ever
 * reopens the app. Without this, a refund or silent expiry left the user's
 * Firestore tier — and any coach access / storage / athlete-limit it grants —
 * stuck at the paid value indefinitely.
 *
 * SETUP (manual, one-time): set this function's trigger URL as BOTH the Production
 * and Sandbox "App Store Server Notifications V2" URL in App Store Connect →
 * your app → App Information → App Store Server Notifications.
 *
 * We act only on terminal downgrade events, and only when the affected tier was
 * StoreKit-sourced (athleteTierSource/coachTierSource === 'storekit'), so admin
 * comps (Academy, manual Pro) are preserved. The user is resolved via the
 * originalTransactionId -> uid mapping written by syncSubscriptionTier.
 */
export const appStoreServerNotifications = functions.https.onRequest(async (req, res) => {
  if (req.method !== 'POST') {
    res.status(405).send('Method Not Allowed');
    return;
  }

  const signedPayload = req.body?.signedPayload;
  if (!signedPayload || typeof signedPayload !== 'string') {
    res.status(400).send('Missing signedPayload');
    return;
  }

  // Verify the notification signature. Production notifications are production-signed;
  // Sandbox/TestFlight notifications are sandbox-signed — try both environments.
  const verifiers = createVerifiers();
  let payload: Awaited<ReturnType<SignedDataVerifier['verifyAndDecodeNotification']>> | undefined;
  let activeVerifier: SignedDataVerifier | undefined;
  for (const v of [verifiers.production, verifiers.sandbox]) {
    try {
      payload = await v.verifyAndDecodeNotification(signedPayload);
      activeVerifier = v;
      break;
    } catch (e) {
      // Try the other environment.
    }
  }
  if (!payload || !activeVerifier) {
    console.error('❌ ASSN: signature verification failed for both environments.');
    res.status(401).send('Invalid signature');
    return;
  }

  const notificationType = payload.notificationType;
  const subtype = payload.subtype;
  console.log(`🔔 ASSN received: ${notificationType}${subtype ? '/' + subtype : ''}`);

  if (!notificationType) {
    res.status(200).send('OK (no type)');
    return;
  }

  // Apple sends a TEST notification when the URL is configured — ack it.
  if (notificationType === NotificationTypeV2.TEST) {
    res.status(200).send('OK');
    return;
  }

  // Only terminal downgrade events change entitlement. AUTO_RENEW_DISABLED
  // (DID_CHANGE_RENEWAL_STATUS) is NOT terminal — the sub stays active until EXPIRED.
  const terminalDowngrades: string[] = [
    NotificationTypeV2.REFUND,
    NotificationTypeV2.REVOKE,
    NotificationTypeV2.EXPIRED,
    NotificationTypeV2.GRACE_PERIOD_EXPIRED,
  ];
  if (!terminalDowngrades.includes(notificationType)) {
    res.status(200).send('OK (no action)');
    return;
  }

  const signedTx = payload.data?.signedTransactionInfo;
  if (!signedTx) {
    res.status(200).send('OK (no transaction)');
    return;
  }

  let tx: JWSTransactionDecodedPayload;
  try {
    tx = await activeVerifier.verifyAndDecodeTransaction(signedTx);
  } catch (e) {
    console.error('❌ ASSN: transaction decode failed:', e);
    res.status(200).send('OK');
    return;
  }

  // Resolve the user: prefer the originalTransactionId mapping, then appAccountToken.
  let uid: string | undefined;
  if (tx.originalTransactionId) {
    const mapDoc = await admin.firestore()
      .collection('appleSubscriptions').doc(tx.originalTransactionId).get();
    uid = mapDoc.data()?.uid;
  }
  if (!uid && tx.appAccountToken) {
    const q = await admin.firestore().collection('appleSubscriptions')
      .where('appAccountToken', '==', tx.appAccountToken).limit(1).get();
    if (!q.empty) uid = q.docs[0].data()?.uid;
  }
  if (!uid) {
    console.warn(`⚠️ ASSN: no user mapping for originalTransactionId=${tx.originalTransactionId}, product=${tx.productId}. The user's next in-app sync will reconcile.`);
    res.status(200).send('OK (unmapped)');
    return;
  }

  const productId = tx.productId ?? '';
  const isAthleteProduct = !!ATHLETE_PRODUCT_TIERS[productId];
  const isCoachProduct = !!COACH_PRODUCT_TIERS[productId];

  const userRef = admin.firestore().collection('users').doc(uid);
  try {
    const userSnap = await userRef.get();
    const u = userSnap.data() ?? {};
    const update: Record<string, any> = {};

    // Downgrade only the affected axis, and only when it was StoreKit-sourced —
    // admin comps (athleteTierSource/coachTierSource !== 'storekit') are preserved.
    // Athlete tier changes do NOT touch coach access (Pricing Model V2: coach
    // connections are paid for by the coach's seat, never the athlete's tier).
    if (isAthleteProduct && (u.subscriptionTier ?? 'free') !== 'free' && u.athleteTierSource === 'storekit') {
      update.subscriptionTier = 'free';
      update.athleteTierSource = 'storekit';
    }
    if (isCoachProduct && (u.coachSubscriptionTier ?? 'coach_free') !== 'coach_free' && u.coachTierSource === 'storekit') {
      update.coachSubscriptionTier = 'coach_free';
      update.coachTierSource = 'storekit';
    }

    if (Object.keys(update).length > 0) {
      update.updatedAt = admin.firestore.FieldValue.serverTimestamp();
      await userRef.set(update, { merge: true });
      console.log(`✅ ASSN ${notificationType}: downgraded ${uid} ${JSON.stringify(update)}`);
    } else {
      console.log(`ℹ️ ASSN ${notificationType}: no downgrade applied for ${uid} (admin comp or already free).`);
    }
    res.status(200).send('OK');
  } catch (e) {
    // 500 so Apple retries — this is a transient Firestore failure, not a bad request.
    console.error(`❌ ASSN: failed to apply downgrade for ${uid}:`, e);
    res.status(500).send('Internal error');
  }
});

/**
 * Firestore trigger that enforces per-tier athlete limits on the server.
 * Runs whenever a new athlete document is created under /users/{uid}/athletes.
 *
 * Tier limits:
 *   free → 1 athlete
 *   plus → 3 athletes
 *   pro  → 5 athletes
 *
 * If the user exceeds their tier's limit, the newly created document is deleted.
 * The client-side check in AddAthleteView provides the primary UX gate; this
 * function is a server-side backstop against bypasses.
 */
export const enforceAthleteLimit = functions.firestore
  .document('users/{uid}/athletes/{athleteID}')
  .onCreate(async (snap, context) => {
    const { uid } = context.params;
    const db = admin.firestore();

    try {
      // Look up the user's current subscription tier
      const userDoc = await db.collection('users').doc(uid).get();
      const tier = userDoc.data()?.subscriptionTier ?? 'free';

      const tierLimits: Record<string, number> = {
        free: 1,
        plus: 3,
        pro: 5,
      };
      const limit = tierLimits[tier] ?? 1;

      // Count existing athletes (excluding soft-deleted ones). Linked
      // sport-variant profiles share a `personGroupID` and count as ONE
      // slot — dedup via Set. Pre-V24 athletes lack the field; fall back
      // to the doc ID so they behave like singletons.
      const athletesSnap = await db.collection('users').doc(uid)
        .collection('athletes').where('isDeleted', '!=', true).get();
      const personGroups = new Set<string>(
        athletesSnap.docs.map((d) =>
          (d.data().personGroupID as string | undefined) ?? d.id
        )
      );
      const count = personGroups.size;

      if (count > limit) {
        console.warn(
          `⚠️ Athlete limit exceeded: ${count}/${limit} (tier=${tier}). Deleting athlete document.`
        );
        await snap.ref.delete();
        return;
      }

      // Dual-sport abuse guard. A personGroupID group represents ONE person
      // playing multiple sports — it is capped at one profile per sport
      // (Sport.allCases = baseball/softball/golf = 3) and may not contain two
      // profiles of the same sport. Solo athletes (no personGroupID) are their
      // own singleton group and are exempt. This is a server-side backstop;
      // Athlete.canAddSportProfile is the primary client gate.
      const newGroupID = snap.data().personGroupID as string | undefined;
      if (newGroupID) {
        const SPORT_CAP = 3; // baseball, softball, golf
        const groupDocs = athletesSnap.docs.filter(
          (d) => (d.data().personGroupID as string | undefined) === newGroupID
        );
        const newSport = (snap.data().sport as string | undefined) ?? 'baseball';
        const sameSportCount = groupDocs.filter(
          (d) => ((d.data().sport as string | undefined) ?? 'baseball') === newSport
        ).length;
        const duplicateSport = sameSportCount > 1;
        if (groupDocs.length > SPORT_CAP || duplicateSport) {
          console.warn(
            `⚠️ personGroup ${newGroupID} guard tripped (size=${groupDocs.length}, ` +
            `sport=${newSport}, duplicateSport=${duplicateSport}). Deleting athlete document.`
          );
          await snap.ref.delete();
        }
      }
    } catch (error) {
      console.error('❌ enforceAthleteLimit failed:', error);
      // Don't rethrow — allow the athlete to persist rather than crash the function.
      // The client-side limit check is the primary gate.
    }
  });

// =============================================================================
// COACH ATHLETE LIMIT ENFORCEMENT
// =============================================================================

// Coach tier athlete limits — must match CoachSubscriptionTier.athleteLimit in the app
function getCoachAthleteLimit(tier: string): number {
  switch (tier) {
    case 'coach_instructor': return 10;
    case 'coach_pro_instructor': return 30;
    case 'coach_academy': return Number.MAX_SAFE_INTEGER;
    default: return 2; // coach_free
  }
}

/**
 * Authoritative count of distinct athletes connected to a coach, merging two
 * sources: shared folders and accepted coach→athlete invitations.
 *
 * Reconciliation is UUID-aware, NOT a flat both-axes union — see memory
 * project_athlete_count_reconcile. The same real athlete can appear keyed by an
 * `athleteUUID` in one source and only by an account ID in the other (legacy/
 * stale data); a naive union double-counts them. The dedup axis is
 * `personGroupID || athleteUUID` so a dual-sport person (two profiles sharing one
 * personGroupID) collapses to ONE slot. Rule: each distinct group/UUID key is one
 * slot (a parent account hosting N distinct people counts as N),
 * plus one slot per account that NEVER carried a UUID anywhere (legacy data is
 * single-profile). An account that appears both with and without a UUID
 * reconciles onto the UUID.
 *
 * Revoked coaches are already stripped from `sharedWithCoachIDs`, so the folder
 * query reflects current access without a separate revocations lookup. Used both
 * as the accept-time pre-check and as the authoritative recompute on revocation
 * (self-heals counter drift).
 */
async function computeCoachConnectionCount(
  db: admin.firestore.Firestore,
  coachID: string
): Promise<number> {
  return (await computeCoachConnectionKeys(db, coachID)).size;
}

/**
 * The resolved SET of distinct connected-athlete keys behind
 * computeCoachConnectionCount (which is just `.size` of this). Exposed so a
 * caller can also ask "is THIS person already counted?" — a person already on
 * the roster (e.g. via a persistent accepted coach→athlete invitation) must not
 * be treated as a new seat. Each returned key is a folder/invite's
 * `personGroupID || athleteUUID` (the UUID axis), plus the account UID for legacy
 * entries that never carried a UUID anywhere — so a membership test on a folder's
 * `personGroupID ?? athleteUUID ?? ownerAthleteID` lines up exactly.
 */
async function computeCoachConnectionKeys(
  db: admin.firestore.Firestore,
  coachID: string
): Promise<Set<string>> {
  const uuids = new Set<string>();            // distinct athlete UUIDs
  const accountsWithUUID = new Set<string>(); // accounts that have a UUID-bearing entry
  const accountsNoUUID = new Set<string>();   // accounts seen only without a UUID

  const consider = (uuid: unknown, account: unknown) => {
    const u = typeof uuid === 'string' && uuid.length > 0 ? uuid : undefined;
    const a = typeof account === 'string' && account.length > 0 ? account : undefined;
    if (u) {
      uuids.add(u);
      if (a) accountsWithUUID.add(a);
    } else if (a) {
      accountsNoUUID.add(a);
    }
  };

  const foldersSnap = await db.collection('sharedFolders')
    .where('sharedWithCoachIDs', 'array-contains', coachID)
    .get();
  for (const d of foldersSnap.docs) {
    consider(d.data().personGroupID || d.data().athleteUUID, d.data().ownerAthleteID);
  }

  const acceptedSnap = await db.collection('invitations')
    .where('type', '==', 'coach_to_athlete')
    .where('coachID', '==', coachID)
    .where('status', '==', 'accepted')
    .get();
  for (const doc of acceptedSnap.docs) {
    consider(doc.data().personGroupID || doc.data().athleteUUID, doc.data().athleteUserID);
  }

  // Legacy accounts that never carried a UUID anywhere count once each;
  // accounts that also appear with a UUID reconcile onto that UUID.
  const keys = new Set<string>(uuids);
  for (const acc of accountsNoUUID) {
    if (!accountsWithUUID.has(acc)) keys.add(acc);
  }
  return keys;
}

// ---------------------------------------------------------------------------
// Coach downgrade backstop (server-authoritative grace + feedback gate)
// ---------------------------------------------------------------------------
// The client (CoachDowngradeManager) runs the 7-day grace + selection sheet, but
// shedding was 100% client-driven: a coach who never opened the sheet kept full
// access forever, and the grace lived in UserDefaults so a reinstall reset it.
// These two CF-managed fields on users/{coachID} make the grace server-authoritative
// and gate FEEDBACK DELIVERY (not viewing) once it expires while still over limit:
//   - coachDowngradeGraceStartedAt: Timestamp — when the over-limit grace began.
//   - downgradeUnresolved: bool — true once grace expired and still over limit.
// firestore.rules (coachDowngradeBlocked) blocks coach publish/comment/annotation/
// drill-card writes when downgradeUnresolved is true; reads + signed URLs are
// untouched. The server never picks who to drop — the coach still chooses in the
// selection sheet. Cleared the instant the coach is back within limit.
const COACH_DOWNGRADE_GRACE_MS = 7 * 24 * 60 * 60 * 1000;

/**
 * Lift the downgrade backstop when the coach is back within their limit. Called
 * from every site that recomputes coachAthleteCount so the feedback gate clears
 * immediately (don't wait for the next daily audit). Reads the coach doc to get
 * the tier and to avoid a needless write when no flag is set. Best-effort.
 */
async function clearCoachDowngradeFlagsIfResolved(
  db: admin.firestore.Firestore,
  coachID: string,
  count: number
): Promise<void> {
  try {
    const snap = await db.collection('users').doc(coachID).get();
    const data = snap.data() || {};
    const tier = data.coachSubscriptionTier || 'coach_free';
    if (count > getCoachAthleteLimit(tier)) return;
    if (data.downgradeUnresolved === undefined && data.coachDowngradeGraceStartedAt === undefined) return;
    await db.collection('users').doc(coachID).update({
      downgradeUnresolved: admin.firestore.FieldValue.delete(),
      coachDowngradeGraceStartedAt: admin.firestore.FieldValue.delete(),
    });
  } catch (e) {
    console.warn(`Failed to clear coach downgrade flags for ${coachID}:`, e);
  }
}

/**
 * Daily backstop for the coach-downgrade shed flow. Recomputes each coach's
 * authoritative connection count (NOT the cached coachAthleteCount, to avoid
 * false positives from drift). Over limit with no grace yet → start the
 * server-authoritative grace. Over limit past 7 days → set downgradeUnresolved
 * (gates feedback delivery in firestore.rules). Back within limit → clear both.
 */
export const auditCoachDowngrades = functions.pubsub
  .schedule('every 24 hours')
  .onRun(async () => {
    const db = admin.firestore();
    const now = Date.now();
    let gracedStarted = 0, flagged = 0, cleared = 0;

    // Single-field role query (no composite index needed); the cheap
    // coachAthleteCount/flag pre-filter below avoids recomputing for coaches with
    // nothing connected and no backstop state to clear.
    const coachSnap = await db.collection('users').where('role', '==', 'coach').get();

    for (const doc of coachSnap.docs) {
      const data = doc.data();
      const hasFlags = data.downgradeUnresolved === true || data.coachDowngradeGraceStartedAt !== undefined;
      // Skip only when the count is explicitly zero (genuinely no connections) and
      // there's no backstop state to clear. A MISSING coachAthleteCount (legacy doc)
      // falls through to the authoritative recompute below, so a legacy over-limit
      // coach still gets graced — one extra count per such coach per day.
      if (data.coachAthleteCount === 0 && !hasFlags) continue;

      const coachID = doc.id;
      const limit = getCoachAthleteLimit(data.coachSubscriptionTier || 'coach_free');

      let count: number;
      try {
        count = await computeCoachConnectionCount(db, coachID);
      } catch (e) {
        console.warn(`auditCoachDowngrades: count failed for ${coachID}:`, e);
        continue;
      }

      const graceStartedAt = data.coachDowngradeGraceStartedAt as admin.firestore.Timestamp | undefined;
      const unresolved = data.downgradeUnresolved === true;

      if (count > limit) {
        if (!graceStartedAt) {
          // Start a fresh grace window. Note: a coach who drops within limit gets
          // both fields cleared below, so coming back over later starts a NEW 7-day
          // window (lenient restart), not a resume of the old one. A coach who stays
          // continuously over keeps the original timestamp (no restart).
          await doc.ref.update({ coachDowngradeGraceStartedAt: admin.firestore.FieldValue.serverTimestamp() })
            .then(() => { gracedStarted++; })
            .catch(e => console.warn(`auditCoachDowngrades: set grace failed for ${coachID}:`, e));
        } else if (!unresolved && (now - graceStartedAt.toMillis()) >= COACH_DOWNGRADE_GRACE_MS) {
          await doc.ref.update({ downgradeUnresolved: true })
            .then(() => { flagged++; })
            .catch(e => console.warn(`auditCoachDowngrades: set unresolved failed for ${coachID}:`, e));
        }
      } else if (graceStartedAt || unresolved) {
        await doc.ref.update({
          downgradeUnresolved: admin.firestore.FieldValue.delete(),
          coachDowngradeGraceStartedAt: admin.firestore.FieldValue.delete(),
        })
          .then(() => { cleared++; })
          .catch(e => console.warn(`auditCoachDowngrades: clear failed for ${coachID}:`, e));
      }
    }

    console.log(`✅ auditCoachDowngrades: ${gracedStarted} grace-started, ${flagged} flagged, ${cleared} cleared`);
    return null;
  });

/**
 * Server mirror of Swift `SubscriptionGate.personMatches`: a UUID-bearing row
 * matches ONLY on the UUID axis (personGroupID/athleteUUID) and never falls
 * through to the shared account axis — that would catch a sibling profile hosted
 * under the same parent account. A legacy UUID-less row matches on the account
 * axis. `revokeSet` is the identifying-key set of the person whose access was just
 * revoked.
 */
function personMatchesKeys(
  personGroupID: unknown,
  athleteUUID: unknown,
  accountID: unknown,
  revokeSet: Set<string>
): boolean {
  const pg = typeof personGroupID === 'string' && personGroupID.length > 0 ? personGroupID : undefined;
  const uuid = typeof athleteUUID === 'string' && athleteUUID.length > 0 ? athleteUUID : undefined;
  const acc = typeof accountID === 'string' && accountID.length > 0 ? accountID : undefined;
  if (pg && revokeSet.has(pg)) return true;
  if (uuid) return revokeSet.has(uuid); // UUID row = this profile only
  if (acc) return revokeSet.has(acc);
  return false;
}

/**
 * On a DELIBERATE coach removal by an athlete (a coach_access_revocations doc with
 * no `reason` — not 'lapse', not 'downgrade'), the everyday client path
 * (removeCoachFromFolder) strips the coach from the folder but never deletes the
 * persistent accepted invitation. For a Flow-B connection (the coach invited the
 * athlete), computeCoachConnectionKeys keeps counting that athlete via the lingering
 * accepted coach_to_athlete invitation, so the coach's slot never frees. Mirror what
 * batchRevokeCoachAccess (the coach-downgrade path) already does: once the coach
 * shares NO remaining folder with this person, delete the accepted invitation(s) and
 * recompute the authoritative count.
 *
 * Gated on "no remaining folder" so a per-folder removal (coach kept on the other
 * folder) and the two-revocation-docs-per-removal sequence (Games + Lessons) both
 * behave correctly — the invitation is deleted only when the connection truly ends.
 */
async function cleanupStaleInvitationsAfterRevocation(
  db: admin.firestore.Firestore,
  revocation: admin.firestore.DocumentData
): Promise<void> {
  const coachID = revocation.coachID;
  const folderID = revocation.folderID;
  if (typeof coachID !== 'string' || !coachID) return;
  if (typeof folderID !== 'string' || !folderID) return;

  // Resolve the revoked person's identifying keys from the (still-present) folder
  // doc — removeCoachFromFolder only strips the coach, leaving the folder's keys
  // intact. A UUID-bearing person must NOT include the account axis (siblings).
  const folderSnap = await db.collection('sharedFolders').doc(folderID).get();
  if (!folderSnap.exists) {
    // Folder gone (folder-deletion race): we can't safely resolve the UUID, and
    // matching invitations by account UID alone could delete a sibling profile's
    // invite. Skip — no regression vs. prior behavior.
    console.warn(`cleanupStaleInvitations: folder ${folderID} missing; skipping invite cleanup`);
    return;
  }
  const folder = folderSnap.data()!;
  const revokeSet = new Set<string>();
  if (typeof folder.personGroupID === 'string' && folder.personGroupID.length > 0) revokeSet.add(folder.personGroupID);
  if (typeof folder.athleteUUID === 'string' && folder.athleteUUID.length > 0) revokeSet.add(folder.athleteUUID);
  if (revokeSet.size === 0 && typeof folder.ownerAthleteID === 'string' && folder.ownerAthleteID.length > 0) {
    revokeSet.add(folder.ownerAthleteID); // legacy UUID-less row → account axis
  }
  if (revokeSet.size === 0) return;

  // Does the coach still share ANY folder with this person? The just-revoked folder
  // already had the coach arrayRemove'd, so it won't appear in this query.
  const remainingSnap = await db.collection('sharedFolders')
    .where('sharedWithCoachIDs', 'array-contains', coachID)
    .get();
  const stillConnected = remainingSnap.docs.some(d =>
    personMatchesKeys(d.data().personGroupID, d.data().athleteUUID, d.data().ownerAthleteID, revokeSet)
  );
  if (stillConnected) return; // per-folder removal, or the other half not yet stripped

  // Connection ended: delete the persistent accepted invitation(s) for this pair.
  let deletedAny = false;

  const c2aSnap = await db.collection('invitations')
    .where('type', '==', 'coach_to_athlete')
    .where('coachID', '==', coachID)
    .where('status', '==', 'accepted')
    .get();
  for (const doc of c2aSnap.docs) {
    if (personMatchesKeys(doc.data().personGroupID, doc.data().athleteUUID, doc.data().athleteUserID, revokeSet)) {
      try { await doc.ref.delete(); deletedAny = true; }
      catch (e) { console.warn(`cleanupStaleInvitations: failed to delete coach_to_athlete ${doc.id}:`, e); }
    }
  }

  const a2cSnap = await db.collection('invitations')
    .where('type', '==', 'athlete_to_coach')
    .where('acceptedByCoachID', '==', coachID)
    .where('status', '==', 'accepted')
    .get();
  for (const doc of a2cSnap.docs) {
    if (personMatchesKeys(doc.data().personGroupID, doc.data().athleteUUID, doc.data().athleteID, revokeSet)) {
      try { await doc.ref.delete(); deletedAny = true; }
      catch (e) { console.warn(`cleanupStaleInvitations: failed to delete athlete_to_coach ${doc.id}:`, e); }
    }
  }

  // Recompute now that the lingering invitation(s) are gone so coachAthleteCount
  // reflects the truly-ended connection and the coach's slot frees.
  if (deletedAny) {
    try {
      const trueCount = await computeCoachConnectionCount(db, coachID);
      await db.collection('users').doc(coachID).update({ coachAthleteCount: trueCount });
      await clearCoachDowngradeFlagsIfResolved(db, coachID, trueCount);
    } catch (e) {
      console.warn(`cleanupStaleInvitations: failed to recompute coachAthleteCount for ${coachID}:`, e);
    }
  }
}

/**
 * Authoritative resolution of an athlete's `personGroupID` — the dual-sport
 * coach-billing key. A person who plays two sports is two `Athlete` rows sharing
 * one `personGroupID` and must count as ONE coach slot. We re-read the athlete
 * profile doc rather than trusting the invitation snapshot (which may predate the
 * field or be stale): athlete docs have random IDs with the UUID in the `id`
 * field, mirroring backfillFolderPersonGroupID. Falls back to the invitation's
 * value, then to the athlete UUID itself (a solo athlete's group is their own
 * UUID — the same value the count keys fall back to, so behavior is unchanged).
 */
async function resolveAthletePersonGroupID(
  db: admin.firestore.Firestore,
  ownerAccountID: unknown,
  athleteUUID: unknown,
  invitationPersonGroupID: unknown
): Promise<string | undefined> {
  const uuid = typeof athleteUUID === 'string' && athleteUUID.length > 0 ? athleteUUID : undefined;
  const owner = typeof ownerAccountID === 'string' && ownerAccountID.length > 0 ? ownerAccountID : undefined;
  if (owner && uuid) {
    try {
      const snap = await db.collection('users').doc(owner)
        .collection('athletes')
        .where('id', '==', uuid)
        .limit(1)
        .get();
      if (!snap.empty) {
        const pg = snap.docs[0].data().personGroupID;
        if (typeof pg === 'string' && pg.length > 0) return pg;
      }
    } catch (e) {
      console.warn('resolveAthletePersonGroupID: athlete lookup failed', e);
    }
  }
  if (typeof invitationPersonGroupID === 'string' && invitationPersonGroupID.length > 0) {
    return invitationPersonGroupID;
  }
  return uuid;
}

/**
 * Retries a best-effort async write a few times with short exponential backoff,
 * rethrowing the last error only if every attempt fails. Used for the transient
 * Firestore writes during invitation acceptance (folder create/reattach and the
 * folderID link-back) so a momentary blip doesn't strand a connection.
 */
async function withRetry<T>(
  fn: () => Promise<T>,
  attempts = 3,
  baseDelayMs = 200
): Promise<T> {
  let lastErr: unknown;
  for (let i = 0; i < attempts; i++) {
    try {
      return await fn();
    } catch (e) {
      lastErr = e;
      if (i < attempts - 1) {
        await new Promise<void>(resolve => setTimeout(resolve, baseDelayMs * Math.pow(2, i)));
      }
    }
  }
  throw lastErr;
}

/**
 * Rolls back an invitation acceptance whose shared-folder creation failed
 * entirely, so the connection isn't left "accepted + slot consumed + no folder +
 * no recovery". Reverts the invitation to `pending` (re-acceptable, and also drops
 * it out of the accepted-invitation count) and clears the accept-only fields, then
 * re-trues the coach's athlete counter from ground truth via
 * computeCoachConnectionCount. The caller throws a retryable error afterward.
 */
async function rollbackAcceptedInvitationOnFolderFailure(
  db: admin.firestore.Firestore,
  invitationID: string,
  coachID: string,
  clearFields: string[]
): Promise<void> {
  const revert: Record<string, unknown> = {
    status: 'pending',
    acceptedAt: admin.firestore.FieldValue.delete(),
  };
  for (const f of clearFields) revert[f] = admin.firestore.FieldValue.delete();
  // Retry the revert — this is the critical write that re-enables re-accept; a
  // transient failure here is what would re-strand the connection.
  await withRetry(() => db.collection('invitations').doc(invitationID).update(revert));

  // Re-true the stored counter from current state (the now-pending invite and the
  // failed folders are both excluded). Best-effort: if this throws, the counter
  // self-heals on the next accept/revoke/restore recompute.
  try {
    const trueCount = await computeCoachConnectionCount(db, coachID);
    await db.collection('users').doc(coachID).update({ coachAthleteCount: trueCount });
  } catch (e) {
    console.warn(`Failed to recompute coachAthleteCount after folder-failure rollback for ${coachID}:`, e);
  }
}

/**
 * Reattaches a coach to an athlete's existing Games/Lessons folders, creating
 * only the ones that don't yet exist. Athlete folders (and their clips) survive
 * coach removal, so a re-invite must reuse them — unconditionally creating a new
 * pair would orphan the original clips behind invisible duplicates. Reattaching
 * also clears the deterministic revocation doc so `canAccessFolder` stops denying
 * the re-added coach.
 */
async function reuseOrCreateSharedFolders(
  db: admin.firestore.Firestore,
  params: {
    coachID: string;
    athleteUUID: string;
    personGroupID: string;
    ownerAthleteID: string;
    athleteName: string;
    coachPermissions: Record<string, boolean>;
    coachDisplayName?: string;
  }
): Promise<{ gamesFolderID: string | null; lessonsFolderID: string | null }> {
  const { coachID, athleteUUID, personGroupID, ownerAthleteID, athleteName, coachPermissions, coachDisplayName } = params;

  const existingSnap = await db.collection('sharedFolders')
    .where('athleteUUID', '==', athleteUUID)
    .get();
  const existingByType = new Map<string, admin.firestore.QueryDocumentSnapshot>();
  for (const d of existingSnap.docs) {
    const t = d.data().folderType as string | undefined;
    if (t && !existingByType.has(t)) existingByType.set(t, d);
  }

  const folderBase: Record<string, unknown> = {
    ownerAthleteID,
    ownerAthleteName: athleteName,
    athleteUUID,
    personGroupID,
    sharedWithCoachIDs: [coachID],
    permissions: { [coachID]: coachPermissions },
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    videoCount: 0,
  };
  if (coachDisplayName) folderBase.sharedWithCoachNames = { [coachID]: coachDisplayName };

  const result: { games: string | null; lessons: string | null } = { games: null, lessons: null };

  for (const folderType of ['games', 'lessons'] as const) {
    const name = folderType === 'games' ? `${athleteName}'s Games` : `${athleteName}'s Lessons`;
    const existing = existingByType.get(folderType);
    if (existing) {
      const update: Record<string, unknown> = {
        sharedWithCoachIDs: admin.firestore.FieldValue.arrayUnion(coachID),
        [`permissions.${coachID}`]: coachPermissions,
        // Backfill/refresh the dual-sport key on reused (possibly legacy) folders.
        personGroupID,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };
      if (coachDisplayName) update[`sharedWithCoachNames.${coachID}`] = coachDisplayName;
      try {
        // The reattach is the meaningful op — record success immediately so a
        // best-effort revocation-cleanup hiccup can't falsely null an
        // already-reattached folder (which would trip the caller's rollback).
        await withRetry(() => existing.ref.update(update));
        result[folderType] = existing.id;
        await withRetry(() => db.collection('coach_access_revocations').doc(`${existing.id}_${coachID}`).delete());
      } catch (e) {
        console.error(`Failed to reattach coach to ${folderType} folder:`, e);
      }
    } else {
      try {
        const ref = await withRetry(() => db.collection('sharedFolders').add({ ...folderBase, name, folderType }));
        result[folderType] = ref.id;
      } catch (e) {
        console.error(`Failed to create ${folderType} folder:`, e);
      }
    }
  }

  return { gamesFolderID: result.games, lessonsFolderID: result.lessons };
}

/**
 * Server-side backstop: when a coach-to-athlete invitation is created,
 * verify the coach hasn't exceeded their tier's athlete limit.
 * Counts connected athletes (accepted invitations + shared folders)
 * plus pending outbound invitations.
 * If over limit, the invitation is deleted immediately.
 */
export const enforceCoachAthleteLimit = functions.firestore
  .document('invitations/{invitationID}')
  .onCreate(async (snap, context) => {
    const data = snap.data();
    if (data.type !== 'coach_to_athlete') return;

    const coachID = data.coachID;
    const invitationID = context.params.invitationID;
    const db = admin.firestore();

    try {
      // Look up the coach's tier
      const coachDoc = await db.collection('users').doc(coachID).get();
      const coachTier = coachDoc.data()?.coachSubscriptionTier || 'coach_free';
      const limit = getCoachAthleteLimit(coachTier);

      // Count unique athletes from shared folders. Keyed by personGroupID (so a
      // dual-sport person's two profiles count as ONE slot), falling back to
      // athleteUUID then ownerAthleteID — matches client SubscriptionGate so a
      // parent account with multiple distinct people counts as N slots.
      const foldersSnap = await db.collection('sharedFolders')
        .where('sharedWithCoachIDs', 'array-contains', coachID)
        .get();
      const folderAthletes = new Set<string>(
        foldersSnap.docs.map(d => (d.data().personGroupID as string) || (d.data().athleteUUID as string) || d.data().ownerAthleteID)
      );

      // Count pending outbound invitations (exclude the one that just triggered)
      const pendingSnap = await db.collection('invitations')
        .where('type', '==', 'coach_to_athlete')
        .where('coachID', '==', coachID)
        .where('status', '==', 'pending')
        .get();
      const pendingCount = pendingSnap.docs.filter(d => d.id !== invitationID).length;

      // Count accepted invitations (athletes not yet in folders)
      const acceptedSnap = await db.collection('invitations')
        .where('type', '==', 'coach_to_athlete')
        .where('coachID', '==', coachID)
        .where('status', '==', 'accepted')
        .get();
      for (const doc of acceptedSnap.docs) {
        const athleteUID = (doc.data().personGroupID as string) || (doc.data().athleteUUID as string) || doc.data().athleteUserID;
        if (athleteUID) folderAthletes.add(athleteUID);
      }

      const totalCommitted = folderAthletes.size + pendingCount;

      if (totalCommitted >= limit) {
        console.warn(
          `⚠️ Coach athlete limit exceeded: ${totalCommitted}/${limit} (tier=${coachTier}). Deleting invitation ${invitationID}.`
        );
        await snap.ref.delete();
      }
    } catch (error) {
      console.error(`❌ enforceCoachAthleteLimit failed for invitation ${invitationID}:`, error);
    }
  });

/**
 * Server-side backstop: when any invitation is accepted (status changes to
 * "accepted"), verify the coach is still within their tier's athlete limit.
 *
 * DISABLED: Both acceptance callables (acceptCoachToAthleteInvitation and
 * acceptAthleteToCoachInvitation) now enforce the coach athlete limit via a
 * pre-check before accepting. This trigger previously ran as an async backstop,
 * but it caused a race condition: the callable would return success to the client,
 * then this trigger would fire and revert the status to "rejected_limit". The
 * client would show "accepted" while the other side saw nothing (the invitation
 * vanished from the UI because rejectedLimit wasn't displayed).
 *
 * The pre-checks in the callables are sufficient for normal operation. The only
 * gap is concurrent acceptances (two athletes accepted by the same coach at the
 * exact same moment), which is rare enough that it doesn't justify the race
 * condition this trigger introduces. If stricter enforcement is needed later,
 * use a distributed counter or a Firestore-native constraint instead.
 */
export const enforceCoachAthleteLimitOnAccept = functions.firestore
  .document('invitations/{invitationID}')
  .onUpdate(async (_change, _context) => {
    // Both invitation flows now enforce limits in their respective callables.
    // This trigger is kept as a deployed function stub to avoid breaking existing
    // deployments (removing an exported function requires explicit deletion).
    return;
  });

// App bundle ID — must match the client app's bundle identifier
const APP_BUNDLE_ID = 'RZR.DT3';

// Apple App ID (numeric) — required for production verification.
// Find this in App Store Connect → General → App Information → Apple ID.
// Set via environment variable; optional in sandbox mode.
const APP_APPLE_ID = process.env.APP_APPLE_ID
    ? parseInt(process.env.APP_APPLE_ID, 10)
    : undefined;

/**
 * Loads Apple root certificates from the certs/ directory.
 * These are used to verify that JWS tokens were signed by Apple.
 */
function loadAppleRootCAs(): Buffer[] {
  const certsDir = path.join(__dirname, '..', 'certs');
  const certFiles = ['AppleIncRootCertificate.cer', 'AppleRootCA-G2.cer', 'AppleRootCA-G3.cer'];
  return certFiles.map(file => fs.readFileSync(path.join(certsDir, file)));
}

/**
 * Creates a SignedDataVerifier for validating Apple JWS tokens.
 *
 * IMPORTANT: In production, APP_APPLE_ID must be set or verification will fail.
 * Set it via: firebase functions:secrets:set APP_APPLE_ID
 * Find it in App Store Connect → General → App Information → Apple ID (numeric).
 */
function createVerifier(environment?: Environment): SignedDataVerifier {
  const rootCAs = loadAppleRootCAs();
  const isEmulator = !!process.env.FUNCTIONS_EMULATOR;

  if (!isEmulator && APP_APPLE_ID === undefined) {
    throw new Error(
      'APP_APPLE_ID environment variable is required in production. '
      + 'Set it to your numeric Apple ID from App Store Connect.'
    );
  }

  const env = environment ?? (isEmulator ? Environment.SANDBOX : Environment.PRODUCTION);
  return new SignedDataVerifier(rootCAs, true, env, APP_BUNDLE_ID, APP_APPLE_ID);
}

/**
 * Creates both production and sandbox verifiers. TestFlight uses sandbox-signed
 * tokens, so we need to try both environments when verifying.
 */
function createVerifiers(): { production: SignedDataVerifier; sandbox: SignedDataVerifier } {
  return {
    production: createVerifier(Environment.PRODUCTION),
    sandbox: createVerifier(Environment.SANDBOX),
  };
}


/**
 * Scheduled cleanup function that runs daily to:
 * 1. Purge Storage files for soft-deleted videos older than 30 days
 * 2. Process pending deletions that failed on the client
 * 3. Delete expired invitations older than 30 days past their expiry
 */
export const dailyStorageCleanup = functions.pubsub
  .schedule('every 24 hours')
  .onRun(async () => {
    const db = admin.firestore();
    const bucket = admin.storage().bucket();
    const thirtyDaysAgo = new Date();
    thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

    let purgedCount = 0;
    let pendingCount = 0;

    // --- 1. Purge soft-deleted videos older than 30 days ---
    try {
      const softDeletedSnap = await db.collection('videos')
        .where('isDeleted', '==', true)
        .where('deletedAt', '<=', admin.firestore.Timestamp.fromDate(thirtyDaysAgo))
        .limit(500)
        .get();

      for (const doc of softDeletedSnap.docs) {
        const data = doc.data();
        const ownerUID = data.uploadedBy;
        const fileName = data.fileName;

        if (ownerUID && fileName) {
          try {
            await bucket.file(`athlete_videos/${ownerUID}/${fileName}`).delete();
            purgedCount++;
          } catch (err: any) {
            // File may already be gone — that's fine
            if (err?.code !== 404) {
              console.error(`Failed to delete Storage file for ${doc.id}:`, err);
            }
          }
        }

        // Remove the Firestore document
        await doc.ref.delete();
      }

      console.log(`✅ Purged ${purgedCount} soft-deleted videos older than 30 days`);
    } catch (err) {
      console.error('Error purging soft-deleted videos:', err);
    }

    // --- 2. Process pending deletions from client failures ---
    try {
      const pendingSnap = await db.collection('pendingDeletions')
        .limit(500)
        .get();

      for (const doc of pendingSnap.docs) {
        const data = doc.data();
        const storagePath = data.storagePath;
        const ownerUID = data.ownerUID;

        // storagePath is client-supplied. Only ever delete inside the owner's own
        // namespace — the legitimate client writes athlete_videos/<uid>/.. or
        // athlete_photos/<uid>/.. (VideoCloudManager / VideoCloudManager+Photos).
        // Anything else is a malformed or abusive record (a cross-user deletion
        // attempt): drop it without acting on it. Deleting with the Admin SDK
        // bypasses Storage rules, so this is the only authorization boundary here.
        const validPath =
          typeof storagePath === 'string' &&
          typeof ownerUID === 'string' &&
          !storagePath.includes('..') &&
          (storagePath.startsWith(`athlete_videos/${ownerUID}/`) ||
           storagePath.startsWith(`athlete_photos/${ownerUID}/`));

        if (!validPath) {
          console.warn(`Skipping pendingDeletion ${doc.id}: storagePath '${storagePath}' outside owner '${ownerUID}' namespace`);
          await doc.ref.delete();
          continue;
        }

        try {
          await bucket.file(storagePath).delete();
          pendingCount++;
        } catch (err: any) {
          if (err?.code !== 404) {
            console.error(`Failed to delete pending file ${storagePath}:`, err);
            continue; // Keep the record for next run
          }
        }

        // Remove the pending deletion record (either succeeded or file already gone)
        await doc.ref.delete();
      }

      console.log(`✅ Processed ${pendingCount} pending deletions`);
    } catch (err) {
      console.error('Error processing pending deletions:', err);
    }

    // --- 3. Delete expired invitations older than 30 days past expiry ---
    let expiredCount = 0;
    try {
      const expiredSnap = await db.collection('invitations')
        .where('expiresAt', '<=', admin.firestore.Timestamp.fromDate(thirtyDaysAgo))
        .limit(500)
        .get();

      for (const doc of expiredSnap.docs) {
        await doc.ref.delete();
        expiredCount++;
      }

      console.log(`✅ Deleted ${expiredCount} expired invitations`);
    } catch (err) {
      console.error('Error deleting expired invitations:', err);
    }

    // --- 4. Clean up orphaned uploads (metadata-first pattern) ---
    // Videos with uploadStatus "pending" or "failed" older than 24 hours
    // indicate interrupted uploads whose metadata was written but file never completed.
    let orphanedUploadCount = 0;
    try {
      const twentyFourHoursAgo = new Date();
      twentyFourHoursAgo.setHours(twentyFourHoursAgo.getHours() - 24);

      const orphanedSnap = await db.collection('videos')
        .where('uploadStatus', 'in', ['pending', 'failed'])
        .where('createdAt', '<=', admin.firestore.Timestamp.fromDate(twentyFourHoursAgo))
        .limit(200)
        .get();

      for (const doc of orphanedSnap.docs) {
        const data = doc.data();
        const fileName = data.fileName as string;
        const folderID = data.sharedFolderID as string;

        // Attempt to delete any partial Storage file (may not exist)
        if (fileName && folderID) {
          try {
            await bucket.file(`shared_folders/${folderID}/${fileName}`).delete();
          } catch (err: any) {
            if (err?.code !== 404) {
              console.warn(`Failed to delete orphaned Storage file ${fileName}:`, err);
            }
          }
        }

        // Delete the metadata doc
        await doc.ref.delete();
        orphanedUploadCount++;
      }

      console.log(`✅ Cleaned up ${orphanedUploadCount} orphaned upload metadata docs`);
    } catch (err) {
      console.error('Error cleaning up orphaned uploads:', err);
    }

    return null;
  });

// ============================================================================
// ONE-SHOT MIGRATIONS — PR 1 lockdown
// ============================================================================

/**
 * One-shot: backfills `athleteUUID` on legacy sharedFolders. Resolves each
 * folder's UUID from the originating invitation matched by
 * (folderID|ownerAthleteID|coachID). Logs unresolvable folders rather than
 * guessing — required for parent accounts hosting multiple athlete profiles.
 *
 * Invocation: callable, restricted to caller UID in ALLOWED_ADMIN_UIDS.
 * Pass { dryRun: true } first to see counts before writing.
 */
const ALLOWED_ADMIN_UIDS: string[] = [
  'dnLLmgNqBAgSRdWJBsqYc7MrryF2', // Trey (treyschill@gmail.com)
];

export const backfillFolderAthleteUUID = functions.https.onCall(async (data, context) => {
  if (!context.auth || !ALLOWED_ADMIN_UIDS.includes(context.auth.uid)) {
    throw new functions.https.HttpsError('permission-denied', 'Admin only');
  }
  const dryRun = data?.dryRun !== false;
  const db = admin.firestore();

  const foldersSnap = await db.collection('sharedFolders').get();
  let scanned = 0;
  let alreadySet = 0;
  let resolved = 0;
  let unresolvable = 0;
  const writes: Array<{ ref: FirebaseFirestore.DocumentReference; uuid: string }> = [];

  for (const folderDoc of foldersSnap.docs) {
    scanned++;
    const folder = folderDoc.data();
    if (typeof folder.athleteUUID === 'string' && folder.athleteUUID.length > 0) {
      alreadySet++;
      continue;
    }
    const ownerAthleteID = folder.ownerAthleteID as string | undefined;
    if (!ownerAthleteID) {
      unresolvable++;
      console.warn(`backfill: folder ${folderDoc.id} missing ownerAthleteID`);
      continue;
    }

    // Look for the originating invitation. Prefer ones referencing this folderID.
    const a2cInvs = await db.collection('invitations')
      .where('athleteID', '==', ownerAthleteID)
      .where('status', '==', 'accepted')
      .limit(20)
      .get();
    let matched: string | null = null;
    for (const invDoc of a2cInvs.docs) {
      const inv = invDoc.data();
      if (inv.folderID === folderDoc.id && typeof inv.athleteUUID === 'string' && inv.athleteUUID) {
        matched = inv.athleteUUID;
        break;
      }
    }
    if (!matched) {
      const c2aInvs = await db.collection('invitations')
        .where('athleteUserID', '==', ownerAthleteID)
        .where('status', '==', 'accepted')
        .limit(20)
        .get();
      for (const invDoc of c2aInvs.docs) {
        const inv = invDoc.data();
        if (inv.folderID === folderDoc.id && typeof inv.athleteUUID === 'string' && inv.athleteUUID) {
          matched = inv.athleteUUID;
          break;
        }
      }
    }

    if (matched) {
      resolved++;
      writes.push({ ref: folderDoc.ref, uuid: matched });
    } else {
      unresolvable++;
      console.warn(`backfill: folder ${folderDoc.id} (owner ${ownerAthleteID}) — no matching invitation`);
    }
  }

  if (!dryRun) {
    const batchSize = 400;
    for (let i = 0; i < writes.length; i += batchSize) {
      const batch = db.batch();
      for (const w of writes.slice(i, i + batchSize)) {
        batch.update(w.ref, { athleteUUID: w.uuid });
      }
      await batch.commit();
    }
  }

  return { scanned, alreadySet, resolved, unresolvable, dryRun };
});

/**
 * One-shot: rewrites legacy random-ID `coach_access_revocations` docs as
 * deterministic `<folderID>_<coachID>` IDs. Keeps the latest by `revokedAt`
 * when duplicates collapse. Required before the canAccessFolder rule starts
 * honoring revocation docs.
 */
export const migrateRevocationDocIDsToDeterministic = functions.https.onCall(async (data, context) => {
  if (!context.auth || !ALLOWED_ADMIN_UIDS.includes(context.auth.uid)) {
    throw new functions.https.HttpsError('permission-denied', 'Admin only');
  }
  const dryRun = data?.dryRun !== false;
  const db = admin.firestore();

  const allSnap = await db.collection('coach_access_revocations').get();
  type RevDoc = { id: string; folderID: string; coachID: string; revokedAt: admin.firestore.Timestamp };
  const groups = new Map<string, RevDoc[]>();

  for (const doc of allSnap.docs) {
    const d = doc.data();
    const folderID = d.folderID as string | undefined;
    const coachID = d.coachID as string | undefined;
    if (!folderID || !coachID) continue;
    const key = `${folderID}_${coachID}`;
    const entry: RevDoc = {
      id: doc.id,
      folderID,
      coachID,
      revokedAt: d.revokedAt as admin.firestore.Timestamp,
    };
    const list = groups.get(key) ?? [];
    list.push(entry);
    groups.set(key, list);
  }

  let migrated = 0;
  let alreadyDeterministic = 0;
  let removedDuplicates = 0;

  for (const [key, entries] of groups) {
    entries.sort((a, b) => (b.revokedAt?.toMillis?.() ?? 0) - (a.revokedAt?.toMillis?.() ?? 0));
    const latest = entries[0];
    const targetRef = db.collection('coach_access_revocations').doc(key);

    if (latest.id === key) {
      alreadyDeterministic++;
    } else {
      if (!dryRun) {
        const srcRef = db.collection('coach_access_revocations').doc(latest.id);
        const snap = await srcRef.get();
        if (snap.exists) {
          await targetRef.set(snap.data()!, { merge: true });
          await srcRef.delete();
        }
      }
      migrated++;
    }

    // Drop older duplicates
    for (const dup of entries.slice(1)) {
      if (dup.id !== key) {
        if (!dryRun) {
          await db.collection('coach_access_revocations').doc(dup.id).delete();
        }
        removedDuplicates++;
      }
    }
  }

  return {
    totalGroups: groups.size,
    migrated,
    alreadyDeterministic,
    removedDuplicates,
    dryRun,
  };
});

/**
 * One-shot: backfills `personGroupID` on legacy sharedFolders so the coach
 * dedup key can collapse a dual-sport person's two folders into ONE coach slot
 * (PR-C/PR-D). New folders self-stamp personGroupID at creation; this only
 * touches pre-PR-A docs.
 *
 * Resolution: a folder's `ownerAthleteID` is the owning account UID and
 * `athleteUUID` is the athlete profile's UUID (Athlete.id). Athlete docs use
 * random auto-doc-ids with the UUID stored in the `id` FIELD, so we QUERY
 * users/{ownerAthleteID}/athletes where id == athleteUUID (a doc-get by UUID
 * would resolve nothing). We write `personGroupID = athleteDoc.personGroupID ??
 * athleteUUID` — i.e. the group ID for grouped profiles, or the athlete's own
 * UUID for solo athletes (identical to the PR-C fallback, written explicitly).
 *
 * Folders missing athleteUUID are left unresolved (logged): the PR-C key falls
 * back to athleteUUID || ownerAthleteID, so an absent personGroupID is safe —
 * we do not guess. MUST complete before PR-C/PR-D flip the coach dedup key.
 *
 * Invocation: callable, restricted to caller UID in ALLOWED_ADMIN_UIDS.
 * Pass { dryRun: true } first to see counts before writing.
 */
export const backfillFolderPersonGroupID = functions.https.onCall(async (data, context) => {
  if (!context.auth || !ALLOWED_ADMIN_UIDS.includes(context.auth.uid)) {
    throw new functions.https.HttpsError('permission-denied', 'Admin only');
  }
  const dryRun = data?.dryRun !== false;
  const db = admin.firestore();

  const foldersSnap = await db.collection('sharedFolders').get();
  let scanned = 0;
  let alreadySet = 0;
  let resolvedGrouped = 0; // athlete had a personGroupID (real dual-sport collapse)
  let resolvedSolo = 0; // personGroupID defaulted to athleteUUID
  let unresolvable = 0;
  const writes: Array<{ ref: FirebaseFirestore.DocumentReference; personGroupID: string }> = [];

  for (const folderDoc of foldersSnap.docs) {
    scanned++;
    const folder = folderDoc.data();
    if (typeof folder.personGroupID === 'string' && folder.personGroupID.length > 0) {
      alreadySet++;
      continue;
    }
    const ownerAthleteID = folder.ownerAthleteID as string | undefined; // owning account UID
    const athleteUUID = folder.athleteUUID as string | undefined; // Athlete profile UUID
    if (!ownerAthleteID || !athleteUUID) {
      unresolvable++;
      console.warn(
        `personGroupID backfill: folder ${folderDoc.id} missing ownerAthleteID/athleteUUID — skipped`
      );
      continue;
    }

    // Athlete docs have random IDs; the UUID lives in the `id` field.
    const athleteQuery = await db.collection('users').doc(ownerAthleteID)
      .collection('athletes')
      .where('id', '==', athleteUUID)
      .limit(1)
      .get();

    let personGroupID = athleteUUID; // solo default
    let grouped = false;
    if (!athleteQuery.empty) {
      const a = athleteQuery.docs[0].data();
      const pg = a.personGroupID;
      if (typeof pg === 'string' && pg.length > 0) {
        personGroupID = pg;
        grouped = true;
      }
    } else {
      console.warn(
        `personGroupID backfill: folder ${folderDoc.id} owner ${ownerAthleteID} has no athlete ` +
        `doc matching ${athleteUUID}; defaulting personGroupID=athleteUUID`
      );
    }

    if (grouped) {
      resolvedGrouped++;
    } else {
      resolvedSolo++;
    }
    writes.push({ ref: folderDoc.ref, personGroupID });
  }

  if (!dryRun) {
    const batchSize = 400;
    for (let i = 0; i < writes.length; i += batchSize) {
      const batch = db.batch();
      for (const w of writes.slice(i, i + batchSize)) {
        batch.update(w.ref, { personGroupID: w.personGroupID });
      }
      await batch.commit();
    }
  }

  return { scanned, alreadySet, resolvedGrouped, resolvedSolo, unresolvable, dryRun };
});

/**
 * One-shot companion to backfillFolderPersonGroupID: stamps `personGroupID` on
 * pre-PR-A invitation docs. Required because the coach count sites (PR-C) merge
 * ACCEPTED invitations alongside folders — if a dual-sport person's folder keys
 * by personGroupID (G) but its accepted invitation only carries athleteUUID (U),
 * the merge re-splits the person into two slots. New accepts now stamp the
 * invitation in-transaction; this closes the gap for invitations accepted before
 * that change. Pending coach_to_athlete invitations lack an owning account UID
 * until accepted, so they self-stamp on accept and are skipped here.
 *
 * Resolution mirrors the folder backfill: owner account = athleteUserID (coach→
 * athlete, set on accept) ?? athleteID (athlete→coach); profile UUID = athleteUUID.
 * Query users/{owner}/athletes where id == athleteUUID; write
 * personGroupID = athleteDoc.personGroupID ?? athleteUUID.
 *
 * Invocation: callable, restricted to ALLOWED_ADMIN_UIDS. Pass { dryRun: true }
 * first. Run AFTER backfillFolderPersonGroupID and BEFORE relying on PR-C counts.
 */
export const backfillInvitationPersonGroupID = functions.https.onCall(async (data, context) => {
  if (!context.auth || !ALLOWED_ADMIN_UIDS.includes(context.auth.uid)) {
    throw new functions.https.HttpsError('permission-denied', 'Admin only');
  }
  const dryRun = data?.dryRun !== false;
  const db = admin.firestore();

  const invSnap = await db.collection('invitations').get();
  let scanned = 0;
  let alreadySet = 0;
  let resolvedGrouped = 0; // athlete had a personGroupID (real dual-sport collapse)
  let resolvedSolo = 0; // personGroupID defaulted to athleteUUID
  let unresolvable = 0; // no owner account or no athleteUUID yet (e.g. pending coach→athlete)
  const writes: Array<{ ref: FirebaseFirestore.DocumentReference; personGroupID: string }> = [];
  const diag: Array<Record<string, unknown>> = []; // dryRun-only breakdown of unresolvable docs

  for (const invDoc of invSnap.docs) {
    scanned++;
    const inv = invDoc.data();
    if (typeof inv.personGroupID === 'string' && inv.personGroupID.length > 0) {
      alreadySet++;
      continue;
    }
    const ownerAccountID = (inv.athleteUserID as string | undefined) || (inv.athleteID as string | undefined);
    const athleteUUID = inv.athleteUUID as string | undefined;
    const folderID = inv.folderID as string | undefined;

    let personGroupID: string | undefined;
    let grouped = false;

    // Path 1 (authoritative): the athlete profile doc, when the invitation
    // carries both a profile UUID and an owning account.
    if (ownerAccountID && athleteUUID) {
      const athleteQuery = await db.collection('users').doc(ownerAccountID)
        .collection('athletes')
        .where('id', '==', athleteUUID)
        .limit(1)
        .get();
      if (!athleteQuery.empty) {
        const pg = athleteQuery.docs[0].data().personGroupID;
        if (typeof pg === 'string' && pg.length > 0) {
          personGroupID = pg;
          grouped = true;
        }
      }
      if (!personGroupID) personGroupID = athleteUUID; // solo default
    }

    // Path 2: derive from the already-stamped folder. Covers accepted v5.0-era
    // invitations that never recorded athleteUUID on the invitation doc — the
    // folder carries personGroupID (set by backfillFolderPersonGroupID). Without
    // this the accepted-invitation merge keys such a doc by athleteUserID while
    // its folder keys by personGroupID, re-splitting a dual-sport person.
    if (!personGroupID && folderID) {
      const fSnap = await db.collection('sharedFolders').doc(folderID).get();
      const f = fSnap.data();
      const fpg = f?.personGroupID as string | undefined;
      if (typeof fpg === 'string' && fpg.length > 0) {
        personGroupID = fpg;
        grouped = fpg !== (f?.athleteUUID as string | undefined);
      }
    }

    if (!personGroupID) {
      unresolvable++;
      if (dryRun && diag.length < 20) {
        diag.push({
          id: invDoc.id,
          type: inv.type ?? null,
          status: inv.status ?? null,
          hasAthleteUUID: !!inv.athleteUUID,
          hasAthleteUserID: !!inv.athleteUserID,
          hasAthleteID: !!inv.athleteID,
          hasFolderID: !!inv.folderID,
        });
      }
      continue;
    }

    if (grouped) {
      resolvedGrouped++;
    } else {
      resolvedSolo++;
    }
    writes.push({ ref: invDoc.ref, personGroupID });
  }

  if (!dryRun) {
    const batchSize = 400;
    for (let i = 0; i < writes.length; i += batchSize) {
      const batch = db.batch();
      for (const w of writes.slice(i, i + batchSize)) {
        batch.update(w.ref, { personGroupID: w.personGroupID });
      }
      await batch.commit();
    }
  }

  return { scanned, alreadySet, resolvedGrouped, resolvedSolo, unresolvable, dryRun, diag };
});
