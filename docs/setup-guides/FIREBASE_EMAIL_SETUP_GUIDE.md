# Firebase Cloud Functions Email Setup Guide

Complete guide to deploying email notifications for PlayerPath coach invitations.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [SendGrid Setup](#sendgrid-setup)
3. [Firebase Cloud Functions Setup](#firebase-cloud-functions-setup)
4. [Testing](#testing)
5. [Monitoring](#monitoring)
6. [Troubleshooting](#troubleshooting)

---

## Prerequisites

Before you begin, make sure you have:

- [ ] Firebase project created ([console.firebase.google.com](https://console.firebase.google.com))
- [ ] Firebase CLI installed (`npm install -g firebase-tools`)
- [ ] Node.js 18+ installed
- [ ] Billing enabled on your Firebase project (required for Cloud Functions)

---

## SendGrid Setup

### Step 1: Create SendGrid Account

1. Go to [sendgrid.com](https://sendgrid.com)
2. Sign up for a free account (allows 100 emails/day for free)
3. Complete email verification

### Step 2: Verify Sender Email

1. In SendGrid dashboard, go to **Settings** → **Sender Authentication**
2. Click **Verify a Single Sender**
3. Enter:
   - **From Name**: `PlayerPath`
   - **From Email**: `noreply@playerpath.app` (or your domain)
   - **Reply To**: `support@playerpath.app` (or your support email)
4. Complete verification

> **Note**: For production, you should set up **Domain Authentication** instead of single sender verification for better deliverability.

### Step 3: Create API Key

1. Go to **Settings** → **API Keys**
2. Click **Create API Key**
3. Name: `PlayerPath Cloud Functions`
4. Permissions: **Full Access** (or **Mail Send** only)
5. Click **Create & View**
6. **IMPORTANT**: Copy the API key immediately (you won't see it again!)

```bash
# Save this key - you'll need it in the next section
SG.xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

---

## Firebase Cloud Functions Setup

### Step 1: Install Dependencies

```bash
cd /Users/Trey/Desktop/PlayerPath/firebase/functions
npm install
```

Expected output:
```
added 156 packages in 12s
```

### Step 2: Configure SendGrid API Key

Set the SendGrid API key in Firebase Functions config:

```bash
firebase functions:config:set sendgrid.key="SG.your-api-key-here"
```

Verify the config was set:

```bash
firebase functions:config:get
```

Expected output:
```json
{
  "sendgrid": {
    "key": "SG.xxxxx..."
  }
}
```

### Step 3: Update Email Sender Address

Edit `firebase/functions/src/index.ts` and update the sender email (line ~55):

```typescript
from: {
  email: 'noreply@playerpath.app',  // ← Change to your verified email
  name: 'PlayerPath'
},
```

### Step 4: Build Functions

```bash
npm run build
```

Expected output:
```
Compiled successfully
```

### Step 5: Deploy to Firebase

```bash
firebase deploy --only functions
```

Expected output:
```
✔  functions[sendCoachInvitationEmail]: Successful create operation.
✔  functions[resendInvitationEmail]: Successful create operation.
Function URL (resendInvitationEmail): https://us-central1-your-project.cloudfunctions.net/resendInvitationEmail
```

**Save the function URLs** - you may need them for debugging.

---

## Testing

### Test 1: Create Invitation from iOS App

1. Open PlayerPath app
2. Go to **Shared Folders** → Create a folder
3. Tap **Invite Coach**
4. Enter a coach's email (use your own for testing)
5. Set permissions and tap **Send Invitation**

Expected behavior:
- ✅ Invitation created in Firestore
- ✅ Email sent within 1-2 seconds
- ✅ Coach receives styled HTML email

### Test 2: Check Firestore

1. Open Firebase Console → Firestore
2. Navigate to `coach_invitations` collection
3. Find your test invitation
4. Verify these fields exist:
   ```
   - emailSent: true
   - emailSentAt: [timestamp]
   ```

### Test 3: Verify Email Delivery

1. Check the inbox of the email you invited
2. You should see an email from "PlayerPath"
3. Click "Accept Invitation" button
4. Should open PlayerPath app (if installed)

### Test 4: Deep Link Testing

Test the deep link manually:

```bash
# On simulator
xcrun simctl openurl booted "playerpath://invitation/TEST_INVITATION_ID"

# On device (via Safari)
# Just paste this into Safari address bar:
playerpath://invitation/TEST_INVITATION_ID
```

Expected behavior:
- ✅ App opens
- ✅ Invitation detail sheet appears
- ✅ Shows athlete name and folder details

---

## Monitoring

### View Function Logs

```bash
firebase functions:log
```

Or in Firebase Console:
1. Go to **Functions** tab
2. Click on `sendCoachInvitationEmail`
3. View **Logs** tab

### Check SendGrid Activity

1. SendGrid Dashboard → **Activity**
2. Filter by recipient email
3. View delivery status (Delivered, Bounced, etc.)

### Common Log Messages

**Success:**
```
✅ Invitation email sent to coach@example.com for invitation abc123
```

**Failure:**
```
Error sending invitation email: Unauthorized
→ Check your SendGrid API key
```

```
Error sending invitation email: Sender not verified
→ Verify sender email in SendGrid
```

---

## Troubleshooting

### Issue: Emails Not Sending

**Check 1: Firestore Trigger**
```bash
firebase functions:log --only sendCoachInvitationEmail
```

If you don't see logs, the trigger isn't firing. Check:
- Firestore collection name is `coach_invitations`
- Document is being created (check Firebase Console)

**Check 2: SendGrid API Key**
```bash
firebase functions:config:get
```

If empty, run:
```bash
firebase functions:config:set sendgrid.key="YOUR_KEY"
firebase deploy --only functions
```

**Check 3: Sender Verification**

Go to SendGrid → Sender Authentication → verify `noreply@playerpath.app` is verified.

### Issue: Deep Links Not Working

**iOS Simulator:**
```bash
# Test deep link
xcrun simctl openurl booted "playerpath://invitation/test123"
```

**Check Info.plist:**
```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>playerpath</string>  ← Must be present
        </array>
    </dict>
</array>
```

**Check DeepLinkIntent Parsing:**

Add debug print in `PlayerPathApp.swift`:
```swift
.onOpenURL { url in
    print("🔗 Received URL: \(url)")
    print("🔗 Scheme: \(url.scheme)")
    print("🔗 Host: \(url.host)")
    print("🔗 Path: \(url.path)")
    // ... rest of code
}
```

### Issue: Email Goes to Spam

**Solutions:**
1. Set up Domain Authentication in SendGrid (not just single sender)
2. Add SPF and DKIM records to your domain DNS
3. Warm up sending reputation (start with small volume)
4. Avoid spam trigger words ("free", "click here", etc.)

### Issue: Function Timeout

If emails take too long to send:

1. Increase timeout in `firebase/functions/src/index.ts`:
```typescript
export const sendCoachInvitationEmail = functions
  .runWith({ timeoutSeconds: 60 })  // ← Add this
  .firestore
  .document('coach_invitations/{invitationId}')
  .onCreate(async (snap, context) => {
    // ... function code
  });
```

2. Redeploy:
```bash
firebase deploy --only functions
```

---

## Cost Estimates

### SendGrid (Free Tier)

- **100 emails/day** - Free
- Upgrade to 40,000/month - $19.95/month

### Firebase Cloud Functions

- **2M invocations/month** - Free
- **400,000 GB-seconds** - Free
- Typical cost: $0-5/month for moderate usage

### Firestore

- **50K reads/day** - Free
- **20K writes/day** - Free
- **1GB storage** - Free

**Total estimated monthly cost for < 1000 users: $0**

---

## Next Steps

### Production Enhancements

1. **Domain Authentication**
   - Set up custom domain for emails
   - Add SPF, DKIM, and DMARC records
   - Improves deliverability significantly

2. **Email Templates**
   - Create multiple templates (invitation, reminder, etc.)
   - Use SendGrid Dynamic Templates
   - Easier to update without redeploying functions

3. **Retry Logic**
   - Add exponential backoff for failed sends
   - Queue failed emails for retry
   - Log all failures to Firestore

4. **Analytics**
   - Track open rates (SendGrid provides this)
   - Track invitation acceptance rates
   - A/B test different email content

5. **Unsubscribe**
   - Add unsubscribe link to footer
   - Maintain unsubscribe list in Firestore
   - Required by anti-spam laws (CAN-SPAM, GDPR)

---

## Security Best Practices

### API Key Security

✅ **DO:**
- Store API keys in Firebase Functions config
- Rotate keys periodically
- Use environment-specific keys (dev/prod)
- Limit API key permissions to minimum required

❌ **DON'T:**
- Commit API keys to source control
- Share keys in plain text
- Use production keys in development

### Email Security

✅ **DO:**
- Validate email addresses before sending
- Rate limit invitation sends per user
- Implement CAPTCHA for public invitation forms
- Log all email sends with timestamps

❌ **DON'T:**
- Allow unlimited invitations per user
- Send to unverified email addresses
- Include sensitive data in email content

---

## Support

### Resources

- [Firebase Functions Docs](https://firebase.google.com/docs/functions)
- [SendGrid API Docs](https://docs.sendgrid.com/)
- [iOS Deep Linking Guide](https://developer.apple.com/documentation/xcode/defining-a-custom-url-scheme-for-your-app)

### Getting Help

1. Check Firebase Functions logs
2. Check SendGrid activity feed
3. Search [Stack Overflow](https://stackoverflow.com/questions/tagged/firebase-cloud-functions)
4. Ask in [Firebase Discord](https://discord.gg/firebase)

---

## Appendix: Quick Reference

### Deploy Commands

```bash
# Deploy everything
firebase deploy

# Deploy only functions
firebase deploy --only functions

# Deploy specific function
firebase deploy --only functions:sendCoachInvitationEmail

# View logs
firebase functions:log

# View config
firebase functions:config:get

# Set config
firebase functions:config:set sendgrid.key="YOUR_KEY"
```

### Test URLs

```bash
# Deep link (custom scheme)
playerpath://invitation/{invitationId}

# Universal link (web)
https://playerpath.app/invitation/{invitationId}

# Folder deep link
playerpath://folder/{folderId}
```

### Email Template Variables

Available in the Cloud Function:

- `invitation.coachEmail` - Recipient email
- `invitation.athleteName` - Sender's name
- `invitation.folderName` - Shared folder name
- `invitation.permissions.canUpload` - Upload permission
- `invitation.permissions.canComment` - Comment permission
- `invitation.permissions.canDelete` - Delete permission
- `invitationId` - Firestore document ID

---

**Last Updated:** December 5, 2024
**Version:** 1.0.0
**Author:** PlayerPath Team
