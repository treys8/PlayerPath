# Notifications Architecture

Authoritative reference for how activity notifications flow between client and server in PlayerPath. If you're adding a new notification type or chasing a bug in an existing one, start here.

## The rule

**Cloud Functions are the single writer for activity notifications.**

Clients only write notifications for events the server cannot observe from Firestore state. Everything else — new videos, comments, annotations, drill cards, coach notes, invitations, folder-access revocations — is written by a source-triggered Cloud Function that fires on the underlying Firestore change.

## Why

Before this refactor, multiple client paths and server paths wrote the same notification types. This produced:

- Race conditions on deterministic IDs (client and server writing the same doc)
- Parity drift (athlete side gained a feature; coach side forgot)
- "Why didn't my coach get the notification?" debugging in ~15 places
- New notification types requiring 4+ touch points

With a single writer per type:

- One place to read, one place to fix
- No client/server race
- Security rules can deny client writes (defense in depth)
- Adding a new type = 1 Cloud Function + 1 test

## Data path

```
Firestore event (video create, comment add, invitation status change, etc.)
  └── Cloud Function (firebase/functions/src/index.ts)
        ├── Writes notification doc to notifications/{recipientID}/items/{deterministicID}
        │   via writeActivityNotification() helper
        └── Sends FCM push to recipient via sendPushNotification() helper
                ↓
           APNS → user's device
                    ↓
              Foreground: iOS app's ActivityNotificationService listener picks up
                          the Firestore doc. Filters suppress the duplicate system
                          banner (source: 'activity' tag on FCM payload).
              Background: system banner appears on lock screen. In-app banner
                          is suppressed on next foreground (lastForegroundAt check)
                          to prevent a duplicate prompt for the same event.
```

## Notification types

| Type | Source event | Cloud Function | Recipient |
|---|---|---|---|
| `new_video` | `videos/{id}` onCreate, `videos/{id}` onUpdate (visibility → shared) | `onNewSharedVideo`, `onVideoPublished` | Coaches (athlete upload) or athlete (coach upload) |
| `coach_comment` | `videos/{id}/comments/{cid}` onCreate | `onNewComment` | Opposite party on the shared folder |
| `coach_comment` (annotation) | `videos/{id}/annotations/{aid}` onCreate | `onNewAnnotation` | Opposite party on the shared folder |
| `coach_comment` (note) | `videos/{id}` onUpdate (coachNote field) | `onCoachNoteUpdated` | Athlete |
| `coach_comment` (drill card) | `videos/{id}/drillCards/{did}` onCreate | `onNewDrillCard` | Athlete |
| `invitation_received` | `invitations/{id}` onCreate | `onInvitationCreated` | The recipient named in the invitation (coach or athlete) |
| `invitation_received` (backfill) | Auth user onCreate | `backfillInvitationsOnSignup` | The new user for any pending invitations |
| `invitation_accepted` | `invitations/{id}` onUpdate (status → accepted) | `onInvitationAccepted` | The original sender |
| `access_revoked` (single coach) | `coach_access_revocations/{id}` onCreate | `sendCoachAccessRevokedEmail` | The removed coach |
| `access_revoked` (folder delete) | `sharedFolders/{id}` onDelete | `onSharedFolderDeleted` | All coaches who had folder access |

## Client-side exceptions (two types)

These notifications are written by the Swift client because the triggering event doesn't produce a Firestore document change for a CF to react to:

| Type | Writer | Trigger | Recipient |
|---|---|---|---|
| `upload_failed` | `UploadQueueManager` via `postClipUploadFailedNotification` | Coach's upload queue exhausted retries | The coach (self, for their own feed) |
| `access_revoked` (permission-loss variant) | `CoachSessionManager` via `postClipUploadFailedPermissionNotification` | Coach detects mid-upload that their folder access was removed | The coach (self) |

Two tier-change notifications are also currently client-written, pending a future migration to a `users/{id}` onUpdate CF:

| Type | Writer | Trigger | Recipient |
|---|---|---|---|
| `access_revoked` (coach downgrade) | `CoachDowngradeSelectionView` via `postCoachAccessLostNotification` | Coach voluntarily drops tier and loses folder access | Affected athlete |
| `access_lapsed` | `AthleteDowngradeManager` via `postAccessLapsedNotification` | Athlete subscription lapses | Coaches with access to affected folders |

## Deterministic ID scheme

Every server-authored notification uses a deterministic doc ID so duplicate writes collapse to one doc. Client writes that preceded the server-write centralization used matching IDs during the shadow-mode window; after chunk 2b those client writes are gone, but the scheme remains the contract.

| Type | ID format |
|---|---|
| `new_video` | `newvideo_{videoID}_{recipientID}` |
| `coach_comment` (comment) | `comment_{videoID}_{commentID}_{recipientID}` |
| `coach_comment` (annotation) | `annotation_{videoID}_{annotationID}_{recipientID}` |
| `coach_comment` (note) | `note_{videoID}_{recipientID}` |
| `coach_comment` (drill card) | `drillcard_{videoID}_{cardID}_{recipientID}` |
| `invitation_received` | `invreceived_{invitationID}_{recipientID}` |
| `invitation_accepted` | `invaccepted_{invitationID}_{recipientID}` |
| `access_revoked` (folder delete / single coach) | `revoked_{folderID}_{coachID}` |
| `upload_failed` | `upload_failed_{uploadID}` |

## FCM delivery

All Cloud Functions that write a notification also send an FCM push via `sendPushNotification(userID, title, body, data, category)`. The FCM payload includes `source: 'activity'` — the iOS `PushNotificationService` foreground handler uses this to suppress the system banner when the app is active (the in-app `ActivityNotificationBanner` already surfaces the same event).

For background→foreground transitions, `ActivityNotificationService.attachListener` uses a `lastForegroundAt` timestamp + 2s grace window to skip the in-app banner for notifications the user already saw as an FCM lock-screen banner.

## Security rules

`firestore.rules` enforces the "server is single writer" principle:

- `allow create:` on `notifications/{userID}/items/{itemID}` rejects all types EXCEPT the four client-only exceptions listed above
- `allow update:` is limited to toggling `isRead` (no rewriting title/body/type)
- `allow read/delete:` scoped to the recipient

If a future regression accidentally reintroduces a client write for a server-owned type, Firestore will reject it.

## iOS read path

`ActivityNotificationService` (SwiftUI singleton) is the single read-side. It:

1. Attaches a real-time listener to `notifications/{currentUserID}/items/` (ordered by createdAt desc, limit 50) on auth success
2. Decodes docs to `ActivityNotification` structs
3. Recomputes published state: `unreadCount`, `unreadFolderVideoCount`, `unreadCountByFolder`, `unreadVideoIDs`, `recentNotifications`
4. Surfaces a fresh notification as `incomingBanner` if created after the last foreground transition (minus grace window)
5. Exposes a small set of `markXxxRead` helpers that filter the local cache and batch-update Firestore `isRead: true`

Views read from the published properties — they never query Firestore directly for notifications.

## Adding a new notification type

1. Pick a source event. Every notification type should correspond to a Firestore doc change.
2. Add a Cloud Function in `firebase/functions/src/index.ts` that triggers on that event. Use `writeActivityNotification` to create the notification doc and `sendPushNotification` to push FCM.
3. Choose a deterministic ID that uniquely identifies the event for each recipient.
4. If it's a new `NotificationType` raw value, add it to both:
   - Swift: `ActivityNotification.NotificationType` enum in `ActivityNotificationService.swift`
   - Rules: the allowlist in `firestore.rules` IF it's a client-authored type (most new types shouldn't be)
5. Add the type and its source event to the table in this doc.
6. Deploy the CF. No iOS client code change should be needed for server-authored types.

## Adding a client-only exception (rare)

Only add if the event genuinely cannot be observed from Firestore state — runtime failures, in-process state. Before adding, check whether writing an intermediate doc (like `coach_access_revocations`) and triggering a CF would work instead.

If a client write is truly required:

1. Update `firestore.rules` `allow create:` to permit the new type for the narrow writer profile.
2. Document it in the "Client-side exceptions" table above.
3. Prefer targeting `userID == request.auth.uid` (self-authored to own feed) to minimize blast radius.

## Files of record

- `firebase/functions/src/index.ts` — all server-side CFs and helpers
- `PlayerPath/Services/ActivityNotificationService.swift` — iOS read side + two client-authored exception writers
- `PlayerPath/PushNotificationService.swift` — FCM handling, foreground suppression
- `firestore.rules` — notification collection rules (search for `/notifications/`)
