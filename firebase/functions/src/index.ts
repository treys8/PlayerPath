import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import * as sgMail from '@sendgrid/mail';

// Initialize Firebase Admin
admin.initializeApp();

// Initialize SendGrid with API key from environment variable
const sendgridApiKey = functions.config().sendgrid?.key;
if (sendgridApiKey) {
  sgMail.setApiKey(sendgridApiKey);
}

// App Store download link — update with the actual App Store ID once published
const APP_STORE_URL = 'https://apps.apple.com/us/app/playerpath/id6742426618';

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
  const webLink = `https://playerpath.app/invitation/${invitationId}`;

  const msg = {
    to: invitation.coachEmail,
    from: {
      email: 'noreply@playerpath.app',
      name: 'PlayerPath'
    },
    subject: `${invitation.athleteName} invited you to collaborate on PlayerPath`,
    text: generatePlainTextEmail(invitation, deepLink, webLink),
    html: generateHtmlEmail(invitation, deepLink, webLink),
  };

  await sgMail.send(msg);
  console.log(`✅ Invitation email sent to ${invitation.coachEmail} for invitation ${invitationId}`);

  await snap.ref.update({
    emailSentAt: admin.firestore.FieldValue.serverTimestamp(),
    emailSent: true
  });
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
    from: {
      email: 'noreply@playerpath.app',
      name: 'PlayerPath'
    },
    subject: `Coach ${invitation.coachName} wants to connect on PlayerPath`,
    text: generateCoachToAthletePlainTextEmail(invitation, deepLink),
    html: generateCoachToAthleteHtmlEmail(invitation, deepLink),
  };

  await sgMail.send(msg);
  console.log(`✅ Coach-to-athlete email sent to ${invitation.athleteEmail} for invitation ${invitationId}`);

  await snap.ref.update({
    emailSentAt: admin.firestore.FieldValue.serverTimestamp(),
    emailSent: true
  });
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
        <a href="https://playerpath.app">Website</a> •
        <a href="https://playerpath.app/support">Support</a> •
        <a href="https://playerpath.app/privacy">Privacy</a>
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
        <a href="https://playerpath.app">Website</a> •
        <a href="https://playerpath.app/support">Support</a> •
        <a href="https://playerpath.app/privacy">Privacy</a>
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

    try {
      // Validate revocation data
      if (!revocation.coachEmail || !revocation.athleteName || !revocation.folderName) {
        console.error('Missing required revocation fields', revocationId);
        return;
      }

      // Email content
      const msg = {
        to: revocation.coachEmail,
        from: {
          email: 'noreply@playerpath.app',
          name: 'PlayerPath'
        },
        subject: `Access to "${revocation.folderName}" has been revoked`,
        text: generateRevokedAccessPlainTextEmail(revocation),
        html: generateRevokedAccessHtmlEmail(revocation),
      };

      // Send email via SendGrid
      await sgMail.send(msg);

      console.log(`✅ Access revoked email sent to ${revocation.coachEmail} for revocation ${revocationId}`);

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
        <a href="https://playerpath.app">Website</a> •
        <a href="https://playerpath.app/support">Support</a> •
        <a href="https://playerpath.app/privacy">Privacy</a>
      </p>
    </div>
  </div>
</body>
</html>
  `.trim();
}

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

    const deepLink = `playerpath://invitation/${invitationId}`;

    let msg;
    if (invitation?.type === 'coach_to_athlete') {
      msg = {
        to: invitation.athleteEmail,
        from: { email: 'noreply@playerpath.app', name: 'PlayerPath' },
        subject: `Coach ${invitation.coachName} wants to connect on PlayerPath`,
        text: generateCoachToAthletePlainTextEmail(invitation, deepLink),
        html: generateCoachToAthleteHtmlEmail(invitation, deepLink),
      };
    } else {
      const webLink = `https://playerpath.app/invitation/${invitationId}`;
      msg = {
        to: invitation.coachEmail,
        from: { email: 'noreply@playerpath.app', name: 'PlayerPath' },
        subject: `${invitation.athleteName} invited you to collaborate on PlayerPath`,
        text: generatePlainTextEmail(invitation, deepLink, webLink),
        html: generateHtmlEmail(invitation, deepLink, webLink),
      };
    }

    await sgMail.send(msg);

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
  free: 1 * 1024 * 1024 * 1024,         // 1 GB
  plus: 5 * 1024 * 1024 * 1024,         // 5 GB
  pro:  15 * 1024 * 1024 * 1024,        // 15 GB
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
      console.warn(`⚠️ Storage quota exceeded for ${ownerUID}: ${totalBytes} bytes > ${limitBytes} bytes (tier: ${tier}). Deleting uploaded file.`);
      try {
        await admin.storage().bucket().file(filePath).delete();
        console.log(`🗑️ Deleted over-quota file: ${filePath}`);
      } catch (err) {
        console.error(`❌ Failed to delete over-quota file ${filePath}:`, err);
      }
    }
  });

/**
 * Scheduled cleanup function that runs daily to:
 * 1. Purge Storage files for soft-deleted videos older than 30 days
 * 2. Process pending deletions that failed on the client
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

    return null;
  });
