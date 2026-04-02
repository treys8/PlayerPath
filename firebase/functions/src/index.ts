import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import { Resend } from 'resend';
import { SignedDataVerifier, Environment, JWSTransactionDecodedPayload } from '@apple/app-store-server-library';
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

    const message: admin.messaging.MulticastMessage = {
      tokens: fcmTokens,
      notification: { title, body },
      data: { ...data, type: data.type || '' },
      apns: {
        payload: {
          aps: {
            sound: 'default',
            badge: 1,
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
// FCM Triggers for Coach/Athlete Events
// ============================================================

/**
 * When a new video is added to a shared folder, push-notify relevant users.
 * - Athlete uploads → notify all coaches with folder access
 * - Coach uploads with visibility "shared" → notify the folder owner (athlete)
 */
export const onNewSharedVideo = functions.firestore
  .document('videos/{videoId}')
  .onCreate(async (snap) => {
    const video = snap.data();
    const folderID = video.sharedFolderID;
    if (!folderID) return; // Personal video, not shared

    // Only notify for completed/visible videos
    if (video.uploadStatus === 'pending' || video.uploadStatus === 'failed') return;
    if (video.visibility === 'private') return;

    const folderDoc = await admin.firestore().collection('sharedFolders').doc(folderID).get();
    if (!folderDoc.exists) return;
    const folder = folderDoc.data()!;

    const uploaderName = video.uploadedByName || 'Someone';
    const uploaderType = video.uploadedByType; // "athlete" or "coach"

    if (uploaderType === 'athlete') {
      // Notify all coaches with folder access
      const coachIDs: string[] = folder.sharedWithCoachIDs || [];
      if (coachIDs.length > 0) {
        await sendPushToMultipleUsers(
          coachIDs,
          'New Video Shared',
          `${uploaderName} shared a new video in ${folder.name || 'a folder'}`,
          { type: 'new_video', folderID },
          'COACH_VIDEO'
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
  .onUpdate(async (change) => {
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

      const coachName = after.uploadedByName || 'Your coach';
      const athleteID = folder.ownerAthleteID;
      if (!athleteID) return;

      await sendPushNotification(
        athleteID,
        'New Session Video',
        `${coachName} shared a lesson clip with you`,
        { type: 'new_video', folderID },
        'COACH_VIDEO'
      );
    }
  });

/**
 * When a comment is added to a video, notify the video uploader.
 */
export const onNewComment = functions.firestore
  .document('videos/{videoId}/comments/{commentId}')
  .onCreate(async (snap, context) => {
    const comment = snap.data();
    const videoId = context.params.videoId;

    const videoDoc = await admin.firestore().collection('videos').doc(videoId).get();
    if (!videoDoc.exists) return;
    const video = videoDoc.data()!;

    // Don't notify if the commenter is the video uploader, or if uploader is unknown
    if (!video.uploadedBy) return;
    if (comment.authorId === video.uploadedBy) return;

    const commenterName = comment.authorName || 'Someone';
    const preview = (comment.text || '').substring(0, 80);

    await sendPushNotification(
      video.uploadedBy,
      'New Comment',
      `${commenterName}: ${preview}`,
      {
        type: 'coach_comment',
        folderID: video.sharedFolderID || '',
        videoID: videoId,
      },
      'COACH_COMMENT'
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

    const videoDoc = await admin.firestore().collection('videos').doc(videoId).get();
    if (!videoDoc.exists) return;
    const video = videoDoc.data()!;

    if (!video.sharedFolderID) return;

    const folderDoc = await admin.firestore().collection('sharedFolders').doc(video.sharedFolderID).get();
    if (!folderDoc.exists) return;
    const folder = folderDoc.data()!;

    const coachName = card.coachName || 'Your coach';

    // Notify the athlete (folder owner)
    if (folder.ownerAthleteID && folder.ownerAthleteID !== card.coachID) {
      await sendPushNotification(
        folder.ownerAthleteID,
        'New Drill Card',
        `${coachName} added a drill card to your video`,
        {
          type: 'drill_card',
          folderID: video.sharedFolderID,
          videoID: videoId,
        },
        'DRILL_CARD'
      );
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

  // Also send FCM push to coach (if they already have an account)
  const coachSnap = await admin.firestore().collection('users')
    .where('email', '==', invitation.coachEmail.toLowerCase())
    .limit(1)
    .get();
  if (!coachSnap.empty) {
    await sendPushNotification(
      coachSnap.docs[0].id,
      'New Invitation',
      `${invitation.athleteName} invited you to collaborate on PlayerPath`,
      { type: 'invitation_received', invitationID: invitationId },
      'INVITATION'
    );
  }
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

  // Write an in-app notification so the athlete sees it immediately via
  // ActivityNotificationService's real-time Firestore listener.
  await writeInvitationNotification(
    invitation.athleteEmail,
    invitation.coachName,
    invitation.coachID,
    invitationId
  );

  // Also send FCM push to athlete (if they have an account)
  const athleteSnap = await admin.firestore().collection('users')
    .where('email', '==', invitation.athleteEmail.toLowerCase())
    .limit(1)
    .get();
  if (!athleteSnap.empty) {
    await sendPushNotification(
      athleteSnap.docs[0].id,
      'New Coach Invitation',
      `Coach ${invitation.coachName} wants to connect with you on PlayerPath`,
      { type: 'invitation_received', invitationID: invitationId },
      'INVITATION'
    );
  }
}

/**
 * Writes an in-app notification to Firestore for an athlete who received
 * a coach invitation. The athlete's ActivityNotificationService listener
 * picks this up in real-time and shows a banner/badge.
 * Gracefully skips if the athlete doesn't have an account yet.
 */
async function writeInvitationNotification(
  athleteEmail: string,
  coachName: string,
  coachID: string,
  invitationId: string
) {
  try {
    const usersSnap = await admin.firestore().collection('users')
      .where('email', '==', athleteEmail.toLowerCase())
      .limit(1)
      .get();

    if (usersSnap.empty) {
      console.log(`ℹ️ No user found for ${athleteEmail} — skipping in-app notification`);
      return;
    }

    const athleteUserID = usersSnap.docs[0].id;

    await admin.firestore()
      .collection('notifications').doc(athleteUserID)
      .collection('items').add({
        type: 'invitation_received',
        title: 'New Coach Invitation',
        body: `${coachName} wants to connect with you on PlayerPath`,
        senderName: coachName,
        senderID: coachID,
        targetID: invitationId,
        targetType: 'invitation',
        isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

    console.log(`✅ In-app notification written for ${athleteEmail}`);
  } catch (error) {
    // Best-effort — don't fail the invitation flow
    console.warn('⚠️ Failed to write in-app notification:', error);
  }
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

    // Decrement the coach's atomic athlete counter (mirrors the increment in acceptance functions).
    // This runs on every revocation doc creation — both athlete-initiated removal and coach downgrade.
    // Only decrement if the counter exists (> 0) to avoid going negative during migration
    // from pre-counter connections.
    if (revocation.coachID) {
      try {
        const coachDoc = await admin.firestore().collection('users').doc(revocation.coachID).get();
        const currentCount = coachDoc.data()?.coachAthleteCount;
        if (typeof currentCount === 'number' && currentCount > 0) {
          await admin.firestore().collection('users').doc(revocation.coachID).update({
            coachAthleteCount: admin.firestore.FieldValue.increment(-1),
          });
        }
      } catch (e) {
        console.warn(`Failed to decrement coachAthleteCount for ${revocation.coachID}:`, e);
      }
    }

    // Rate limit the revoking user
    const revokerUID = revocation.athleteID || revocation.revokedBy;
    if (revokerUID && !(await checkEmailRateLimit(revokerUID))) {
      console.warn(`Rate limit exceeded for user ${revokerUID}, skipping revocation email ${revocationId}`);
      await snap.ref.update({ emailError: 'Rate limit exceeded', emailSent: false });
      return;
    }

    try {
      // Validate revocation data
      if (!revocation.coachEmail || !revocation.athleteName || !revocation.folderName) {
        console.error('Missing required revocation fields', revocationId);
        return;
      }

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

    } catch (error) {
      console.error('Error sending access revoked email:', error);

      // Log the error in Firestore for debugging
      await snap.ref.update({
        emailError: error instanceof Error ? error.message : 'Unknown error',
        emailSent: false
      });
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
      <h1>Access Revoked</h1>
      <p>Folder access notification</p>
    </div>

    <div class="content">
      <p style="font-size: 16px; margin-bottom: 8px;">Hi there,</p>

      <p style="font-size: 16px; line-height: 1.8;">
        This is a notification that <strong>${escapeHtml(revocation.athleteName)}</strong> has removed your access to the following shared folder:
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
          <strong>Note:</strong> If you believe this was done in error, please contact ${escapeHtml(revocation.athleteName)} directly.
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
  const connectedAthletes = new Set(foldersSnap.docs.map(d => d.data().ownerAthleteID));

  const acceptedSnap = await db.collection('invitations')
    .where('type', '==', 'coach_to_athlete')
    .where('coachID', '==', coachID)
    .where('status', '==', 'accepted')
    .get();
  for (const doc of acceptedSnap.docs) {
    const uid = doc.data().athleteUserID;
    if (uid) connectedAthletes.add(uid);
  }

  // Read the invitation to find the athlete for the "already connected" check
  const preCheckSnap = await db.collection('invitations').doc(invitationID).get();
  const preCheckData = preCheckSnap.data();
  const ownerAthleteID = preCheckData?.athleteID || preCheckData?.athleteUserID;

  if (ownerAthleteID && !connectedAthletes.has(ownerAthleteID) && connectedAthletes.size >= limit) {
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

    if (inv.status !== 'pending') {
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
    const invAthleteID = inv.athleteID || inv.athleteUserID;
    const isNewConnection = invAthleteID && !connectedAthletes.has(invAthleteID);
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
      transaction.update(coachRef, {
        coachAthleteCount: admin.firestore.FieldValue.increment(1),
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
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    }

    transaction.update(invRef, {
      status: 'accepted',
      acceptedAt: admin.firestore.FieldValue.serverTimestamp(),
      acceptedByCoachID: coachID,
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
  const permissions = invData.permissions || { canUpload: true, canComment: true, canDelete: false };
  const folderBase = {
    ownerAthleteID: athleteID,
    ownerAthleteName: athleteName,
    sharedWithCoachIDs: [coachID],
    permissions: { [coachID]: permissions },
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    videoCount: 0,
  };

  let gamesFolderID: string | null = null;
  let lessonsFolderID: string | null = null;

  try {
    const gamesRef = await db.collection('sharedFolders').add({
      ...folderBase,
      name: `${athleteName}'s Games`,
      folderType: 'games',
    });
    gamesFolderID = gamesRef.id;
  } catch (e) {
    console.error('Failed to create Games folder:', e);
  }

  try {
    const lessonsRef = await db.collection('sharedFolders').add({
      ...folderBase,
      name: `${athleteName}'s Lessons`,
      folderType: 'lessons',
    });
    lessonsFolderID = lessonsRef.id;
  } catch (e) {
    console.error('Failed to create Lessons folder:', e);
  }

  // Link folder IDs back to the invitation
  const primaryFolderID = gamesFolderID || lessonsFolderID;
  const primaryFolderName = gamesFolderID ? `${athleteName}'s Games` : `${athleteName}'s Lessons`;
  if (primaryFolderID) {
    try {
      await db.collection('invitations').doc(invitationID).update({
        folderID: primaryFolderID,
        folderName: primaryFolderName,
      });
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

  const { invitationID, athleteName: clientAthleteName } = data;
  if (!invitationID || typeof invitationID !== 'string') {
    throw new functions.https.HttpsError('invalid-argument', 'invitationID is required');
  }

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

  // Check athlete has Pro subscription tier (coach sharing is a Pro feature)
  const athleteDoc = await db.collection('users').doc(athleteUserID).get();
  if (!athleteDoc.exists) {
    throw new functions.https.HttpsError(
      'not-found',
      'Athlete profile not found. Please ensure your account is set up.'
    );
  }
  const athleteTier = athleteDoc.data()?.subscriptionTier;
  if (athleteTier !== 'pro') {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Pro subscription required to accept coach invitations'
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
  const connectedAthletes = new Set(foldersSnap.docs.map(d => d.data().ownerAthleteID));

  const acceptedSnap = await db.collection('invitations')
    .where('type', '==', 'coach_to_athlete')
    .where('coachID', '==', coachID)
    .where('status', '==', 'accepted')
    .get();
  for (const doc of acceptedSnap.docs) {
    const uid = doc.data().athleteUserID;
    if (uid) connectedAthletes.add(uid);
  }

  if (!connectedAthletes.has(athleteUserID) && connectedAthletes.size >= limit) {
    await db.collection('invitations').doc(invitationID).update({
      status: 'rejected_limit',
      rejectedReason: 'Coach athlete limit reached',
      rejectedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    throw new functions.https.HttpsError(
      'resource-exhausted',
      'This coach has reached their athlete limit. The invitation cannot be accepted.'
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
    const isNewConnection = !connectedAthletes.has(athleteUserID);
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
          'This coach has reached their athlete limit. The invitation cannot be accepted.'
        );
      }
      transaction.update(coachRef, {
        coachAthleteCount: admin.firestore.FieldValue.increment(1),
      });
    }

    transaction.update(invRef, {
      status: 'accepted',
      acceptedAt: admin.firestore.FieldValue.serverTimestamp(),
      athleteUserID: athleteUserID,
    });
  });

  // Create shared folders after transaction succeeds (Admin SDK bypasses security rules).
  // Uses the athlete's self-chosen name from the client, falling back to the name
  // the coach typed when creating the invitation.
  const name = clientAthleteName || invData.athleteName || 'Athlete';
  const coachDisplayName = coachDoc.data()?.displayName || invData.coachName || invData.coachEmail?.split('@')[0] || 'Coach';
  const defaultPerms = { canUpload: true, canComment: true, canDelete: false };
  const folderBase = {
    ownerAthleteID: athleteUserID,
    ownerAthleteName: name,
    sharedWithCoachIDs: [coachID],
    sharedWithCoachNames: { [coachID]: coachDisplayName },
    permissions: { [coachID]: defaultPerms },
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    videoCount: 0,
  };

  let gamesFolderID: string | null = null;
  let lessonsFolderID: string | null = null;

  try {
    const gamesRef = await db.collection('sharedFolders').add({
      ...folderBase,
      name: `${name}'s Games`,
      folderType: 'games',
    });
    gamesFolderID = gamesRef.id;
  } catch (e) {
    console.error('Failed to create Games folder:', e);
  }

  try {
    const lessonsRef = await db.collection('sharedFolders').add({
      ...folderBase,
      name: `${name}'s Lessons`,
      folderType: 'lessons',
    });
    lessonsFolderID = lessonsRef.id;
  } catch (e) {
    console.error('Failed to create Lessons folder:', e);
  }

  // Link folder IDs back to the invitation document
  const folderID = gamesFolderID || lessonsFolderID;
  const folderName = gamesFolderID ? `${name}'s Games` : lessonsFolderID ? `${name}'s Lessons` : null;
  if (folderID && folderName) {
    try {
      await db.collection('invitations').doc(invitationID).update({
        folderID,
        folderName,
      });
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
 * Server-side storage quota enforcement.
 * Runs when a new file is uploaded to athlete_videos/. If the user exceeds
 * their tier limit, the file is deleted immediately to prevent abuse.
 */
export const enforceStorageQuota = functions.storage
  .object()
  .onFinalize(async (object) => {
    const filePath = object.name;
    if (!filePath || !filePath.startsWith('athlete_videos/')) return;

    const fileSize = parseInt(object.size, 10) || 0;
    // Extract ownerUID from path: athlete_videos/{ownerUID}/{fileName}
    const parts = filePath.split('/');
    if (parts.length < 3) return;
    const ownerUID = parts[1];

    const db = admin.firestore();

    // Look up the user's tier from their Firestore profile
    const userSnap = await db.collection('users').doc(ownerUID).get();
    const tier = userSnap.exists ? (userSnap.data()?.subscriptionTier || 'free') : 'free';
    const limitBytes = TIER_LIMITS[tier] || TIER_LIMITS['free'];

    // Sum all non-deleted video sizes for this user from Firestore
    // Video docs use "uploadedBy" as the owner UID field
    const videosSnap = await db.collection('videos')
      .where('uploadedBy', '==', ownerUID)
      .where('isDeleted', '!=', true)
      .get();

    let totalBytes = 0;
    videosSnap.forEach(doc => {
      totalBytes += (doc.data().fileSize || 0);
    });

    // Include the file being uploaded (it may not have a Firestore doc yet)
    totalBytes += fileSize;

    if (totalBytes > limitBytes) {
      console.warn(`⚠️ Storage quota exceeded: ${totalBytes} bytes > ${limitBytes} bytes (tier: ${tier}). Deleting uploaded file.`);
      try {
        await admin.storage().bucket().file(filePath).delete();
        console.log(`🗑️ Deleted over-quota file: ${filePath}`);
      } catch (err) {
        console.error(`❌ Failed to delete over-quota file ${filePath}:`, err);
      }
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
  'com.playerpath.coach.proinstructor.annual':   'coach_pro_instructor',
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
async function resolveTransactionTiers(
  transactionTokens: string[],
  verifier: SignedDataVerifier,
): Promise<{ athleteTier: string; coachTier: string }> {
  let athleteTier = 'free';
  let coachTier = 'coach_free';
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

  return { athleteTier, coachTier };
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
  // If no receiptData is provided, skip AppTransaction verification — this handles
  // sandbox/Xcode testing where AppTransaction is unavailable. Individual transaction
  // JWS tokens are still verified in Step 2.
  if (!receiptData || typeof receiptData !== 'string') {
    console.log('⚠️ No AppTransaction receipt — skipping app verification, using sandbox verifier.');
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
  const { athleteTier, coachTier } = await resolveTransactionTiers(transactionTokens, activeVerifier);

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

  // Preserve manually-granted coach tier (e.g. "coach_academy") when server
  // resolves a lower or free tier. Always keep the HIGHER of the two values.
  if (coachTier !== 'coach_free') {
    const currentRank = COACH_TIER_RANK[currentCoachTier] ?? 0;
    const newRank = COACH_TIER_RANK[coachTier] ?? 0;
    if (newRank >= currentRank) {
      updateData.coachSubscriptionTier = coachTier;
    }
    // else: keep the existing higher tier (e.g. Academy)
  }
  // When coachTier resolves to "coach_free", don't write — preserves any manual grant

  try {
    await admin.firestore().collection('users').doc(uid).set(updateData, { merge: true });
    console.log(`✅ Synced tiers for ${uid}: athlete=${athleteTier}, coach=${coachTier}`);
    return { success: true, athleteTier, coachTier };
  } catch (error) {
    console.error('❌ Failed to sync tiers:', error);
    throw new functions.https.HttpsError('internal', 'Failed to update subscription tier');
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

      // Count existing athletes (excluding soft-deleted ones)
      const athletesSnap = await db.collection('users').doc(uid)
        .collection('athletes').where('isDeleted', '!=', true).get();
      const count = athletesSnap.size;

      if (count > limit) {
        console.warn(
          `⚠️ Athlete limit exceeded: ${count}/${limit} (tier=${tier}). Deleting athlete document.`
        );
        await snap.ref.delete();
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

      // Count unique athletes from shared folders
      const foldersSnap = await db.collection('sharedFolders')
        .where('sharedWithCoachIDs', 'array-contains', coachID)
        .get();
      const folderAthletes = new Set(foldersSnap.docs.map(d => d.data().ownerAthleteID));

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
        const athleteUID = doc.data().athleteUserID;
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

        if (storagePath) {
          try {
            await bucket.file(storagePath).delete();
            pendingCount++;
          } catch (err: any) {
            if (err?.code !== 404) {
              console.error(`Failed to delete pending file ${storagePath}:`, err);
              continue; // Keep the record for next run
            }
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
