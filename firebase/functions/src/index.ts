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

/**
 * Triggers when a new coach invitation is created in Firestore
 * Sends an email notification to the invited coach
 */
export const sendCoachInvitationEmail = functions.firestore
  .document('coach_invitations/{invitationId}')
  .onCreate(async (snap, context) => {
    const invitation = snap.data();
    const invitationId = context.params.invitationId;

    try {
      // Validate invitation data
      if (!invitation.coachEmail || !invitation.athleteName || !invitation.folderName) {
        console.error('Missing required invitation fields', invitationId);
        return;
      }

      // Create deep link for the invitation
      // Format: playerpath://invitation/{invitationId}
      const deepLink = `playerpath://invitation/${invitationId}`;
      const webLink = `https://playerpath.app/invitation/${invitationId}`; // Fallback web link

      // Email content
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

      // Send email via SendGrid
      await sgMail.send(msg);

      console.log(`✅ Invitation email sent to ${invitation.coachEmail} for invitation ${invitationId}`);

      // Update invitation with email sent timestamp
      await snap.ref.update({
        emailSentAt: admin.firestore.FieldValue.serverTimestamp(),
        emailSent: true
      });

    } catch (error) {
      console.error('Error sending invitation email:', error);

      // Log the error in Firestore for debugging
      await snap.ref.update({
        emailError: error instanceof Error ? error.message : 'Unknown error',
        emailSent: false
      });
    }
  });

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

1. Download the PlayerPath app from the App Store if you haven't already
2. Sign up or sign in with this email: ${invitation.coachEmail}
3. Your pending invitation will appear automatically

Or tap this link to open the invitation directly:
${deepLink}

Web link: ${webLink}

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
        <strong>${invitation.athleteName}</strong> has invited you to collaborate on PlayerPath!
      </p>

      <div class="folder-name">
        <strong>"${invitation.folderName}"</strong>
      </div>

      ${permissions.length > 0 ? `
      <div class="permissions">
        <h3>As a coach, you'll be able to:</h3>
        <ul class="permission-list">
          ${permissions.map(p => `<li>${p}</li>`).join('')}
        </ul>
      </div>
      ` : ''}

      <div style="text-align: center; margin: 32px 0;">
        <a href="${deepLink}" class="cta-button">Accept Invitation</a>
      </div>

      <div class="instructions">
        <h3>How to get started:</h3>
        <ol>
          <li>Download the PlayerPath app from the App Store (if you haven't already)</li>
          <li>Sign up or sign in using: <strong>${invitation.coachEmail}</strong></li>
          <li>Your invitation will appear automatically in the app</li>
        </ol>
      </div>

      <p style="font-size: 14px; color: #666; margin-top: 32px;">
        If the button above doesn't work, copy and paste this link into your browser:<br>
        <a href="${webLink}" style="color: #667eea; word-break: break-all;">${webLink}</a>
      </p>

      <p style="font-size: 13px; color: #999; margin-top: 24px; padding-top: 24px; border-top: 1px solid #eee;">
        This invitation was sent to ${invitation.coachEmail}. If you didn't expect this invitation, you can safely ignore this email.
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
    const invitationRef = admin.firestore().collection('coach_invitations').doc(invitationId);
    const invitationSnap = await invitationRef.get();

    if (!invitationSnap.exists) {
      throw new functions.https.HttpsError('not-found', 'Invitation not found');
    }

    const invitation = invitationSnap.data();

    // Verify the user owns this invitation
    if (invitation?.athleteID !== context.auth.uid) {
      throw new functions.https.HttpsError('permission-denied', 'Not authorized');
    }

    // Create deep link
    const deepLink = `playerpath://invitation/${invitationId}`;
    const webLink = `https://playerpath.app/invitation/${invitationId}`;

    // Send email
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
