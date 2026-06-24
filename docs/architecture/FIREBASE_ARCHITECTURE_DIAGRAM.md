# Firebase Architecture Diagram

**Last Updated:** March 27, 2026

Visual guide to Firestore collections, Firebase Storage structure, Cloud Functions, and security rules.

---

## Firestore Collections Structure

```
Firestore Database
|
|-- users/{userID}
|   |-- email: String
|   |-- role: "athlete" | "coach"
|   |-- displayName: String
|   |-- subscriptionTier: String (free/plus/pro)
|   |-- coachSubscriptionTier: String (free/instructor/proInstructor/academy)
|   |-- tierExpirationDate: Timestamp?
|   |-- coachTierExpirationDate: Timestamp?
|   |-- cloudStorageUsedBytes: Number
|   |-- createdAt: Timestamp
|   |-- updatedAt: Timestamp
|   |
|   |-- athletes/{athleteID}
|   |   |-- name, sport, position, jerseyNumber, etc.
|   |   |-- firestoreId, version, needsSync, isDeletedRemotely
|   |   |-- createdAt, updatedAt
|   |
|   |-- seasons/{seasonID}
|   |   |-- name, sport, year, startDate, endDate, isActive
|   |   |-- athleteID, firestoreId, version
|   |
|   |-- golfTournaments/{tournamentID}   (golf — groups rounds, sits above Game)
|   |   |-- name, location, startDate, endDate, notes
|   |   |-- athleteId, firestoreId, version
|   |
|   |-- highlightReels/{reelID}          (golf — virtual birdie reels, clip refs)
|   |   |-- athleteID, ordered clip refs, version
|   |
|   |-- games/{gameID}
|   |   |-- opponent, date, location, isHome, score, opponentScore
|   |   |-- liveStartDate, seasonID, athleteID
|   |   |-- tournamentId?, roundNumber?  (golf — links round to a tournament)
|   |   |-- firestoreId, version, needsSync
|   |   |
|   |   |-- holes/{holeNumber}            (golf — per-hole score, doc id = hole #)
|   |       |-- par, score, putts, fairwayHit, greenInRegulation, penalties
|   |       |-- shots/{shotID}            (golf — shot-by-shot rows)
|   |
|   |-- practices/{practiceID}
|       |-- date, location, practiceType (general/batting/fielding/bullpen/team)
|       |-- athleteID, seasonID, firestoreId, version
|       |
|       |-- notes/{noteID}
|       |   |-- text, createdAt, firestoreId, version
|       |
|       |-- holes/{holeNumber}            (golf — per-hole score for practice rounds)
|           |-- par, score, putts, fairwayHit, greenInRegulation, penalties
|           |-- shots/{shotID}            (golf — shot-by-shot rows)
|
|-- sharedFolders/{folderID}
|   |-- name: String
|   |-- ownerAthleteID: String
|   |-- ownerUserID: String
|   |-- sharedWithCoachIDs: [String]
|   |-- permissions: { coachID: { canUpload, canComment, canDelete } }
|   |-- folderType: "games" | "lessons"
|   |-- tags: [String]
|   |-- videoCount: Number
|   |-- createdAt: Timestamp
|   |-- updatedAt: Timestamp
|
|-- videos/{videoID}
|   |-- fileName: String
|   |-- firebaseStorageURL: String
|   |-- thumbnailURL: String?
|   |-- thumbnail: { standardURL, highQualityURL, timestamp, dimensions }
|   |-- uploadedBy: String (userID)
|   |-- uploadedByName: String
|   |-- uploadedByType: "athlete" | "coach"
|   |-- sharedFolderID: String
|   |-- sessionID: String?
|   |-- fileSize: Number
|   |-- duration: Number?
|   |-- isHighlight: Boolean
|   |-- visibility: String? (nil = coach-private, "shared" = visible)
|   |-- isOrphaned: Boolean
|   |-- orphanedAt: Timestamp?
|   |-- viewCount: Number
|   |-- annotationCount: Number
|   |-- tags: [String]
|   |-- drillType: String?
|   |-- createdAt: Timestamp
|   |
|   |-- comments/{commentID}
|   |   |-- userID, userName, authorRole ("athlete"/"coach")
|   |   |-- text, createdAt
|   |
|   |-- annotations/{annotationID}
|   |   |-- userID, userName
|   |   |-- text, timestamp (seconds)
|   |   |-- category (mechanics/timing/approach/positive/correction)
|   |   |-- templateID?, type (note/drill_card/drawing)
|   |   |-- isCoachComment: Boolean
|   |   |-- createdAt
|   |
|   |-- drillCards/{drillCardID}
|   |   |-- rating, categories, notes
|   |   |-- templateID?, createdAt
|   |
|   |-- access_logs/{logID}
|       |-- userID, action (view/download), timestamp
|
|-- invitations/{invitationID}
|   |-- athleteID, athleteName
|   |-- coachEmail
|   |-- folderID, folderName
|   |-- status: "pending" | "accepted" | "declined" | "cancelled" | "rejectedLimit"
|   |-- sentAt: Timestamp
|   |-- expiresAt: Timestamp (30-day window)
|   |-- type: "athleteToCoach" | "coachToAthlete"
|
|-- coachSessions/{sessionID}
|   |-- coachID, coachName
|   |-- athleteIDs: [String]
|   |-- athleteNames: { athleteID: name }
|   |-- folderIDs: { athleteID: folderID }
|   |-- status: "scheduled" | "live" | "reviewing" | "completed"
|   |-- startedAt, endedAt, clipCount
|   |-- title?, scheduledDate?, notes?
|
|-- coachTemplates/{coachID}
|   |-- quickCues/{cueID}
|       |-- text, category, sortOrder, createdAt
|
|-- notifications/{userID}
|   |-- items/{itemID}
|       |-- type (newVideo/coachComment/invitation_received/invitation_accepted/access_revoked/access_lapsed)
|       |-- title, body, metadata
|       |-- isRead: Boolean
|       |-- createdAt
|
|-- photos/{photoID}
|   |-- athleteID, cloudURL, thumbnailURL
|   |-- tags, firestoreId, version
|
|-- appConfig/current
|   |-- minimumVersion, latestVersion
|   |-- whatsNewItems, featureFlags
|
|-- pendingDeletions/{id}
|   |-- storagePaths, status, createdAt
|
|-- coach_access_revocations/{id}
|   |-- coachID, folderID, revokedAt, reason
|
|-- emailRateLimits/{userID}
    |-- count, windowStart (10 emails/hour)
```

---

## Firebase Storage Structure

```
Firebase Storage
|
|-- athletes/{athleteID}/
|   |-- videos/{clipID}/{fileName}.mov
|   |-- photos/{photoID}/{fileName}.jpg
|
|-- shared_folders/{folderID}/
|   |-- {fileName}.mov
|   |-- thumbnails/
|       |-- {fileName}_thumbnail.jpg
|
|-- profile_images/{userID}/
    |-- profile.jpg
```

---

## Cloud Functions (~32 exported)

`firebase/functions/src/index.ts` (~4,732 lines). Beyond email, these handle StoreKit/subscription sync, the App Store Server Notifications V2 webhook, athlete-limit transactions, coach-downgrade auditing, storage cleanup/quota, GDPR deletion, and one-off backfill/migration jobs.

### Firestore Triggers

| Function | Trigger | Purpose |
|----------|---------|---------|
| `onNewSharedVideo` | Video created in shared folder | Notify coaches/athletes |
| `onVideoPublished` | Coach-private video published (visibility → shared) | Notify athlete |
| `onSharedFolderDeleted` | Shared folder deleted | Decrement coach counts, clean up access |
| `onNewComment` | Comment added to video | Notify video uploader |
| `onNewAnnotation` | Annotation added to video | Notify athlete |
| `onCoachNoteUpdated` | Coach note changed on a video | Notify athlete |
| `onNewDrillCard` | Drill card added to video | Notify athlete |
| `onInvitationCreated` | Invitation created | Kick off email + bookkeeping |
| `onInvitationAccepted` | Invitation accepted | Post-accept bookkeeping |
| `onInvitationResolvedNegatively` | Invitation declined/cancelled | Notify sender |
| `sendInvitationEmail` | Invitation created | Email via SendGrid (both directions) |
| `sendCoachAccessRevokedEmail` | Access revoked | Email notification + stale-invite cleanup |
| `enforceAthleteLimit` | Athlete created | Enforce tier-based athlete count |
| `enforceCoachAthleteLimit` | Coach folder accepted | Enforce coach athlete limits |
| `enforceCoachAthleteLimitOnAccept` | Invitation accepted | Prevent over-limit accept |
| `enforceStorageQuota` | Video uploaded | Enforce per-user storage quota |
| `appStoreServerNotifications` | App Store Server Notifications V2 webhook | Subscription state changes (HTTPS endpoint) |
| `auditCoachDowngrades` | Scheduled (cron) | Backstop for over-limit coaches who skip the shed flow |
| `dailyStorageCleanup` | Scheduled (daily) | Clean pending deletions (namespace-checked) |

### Callable Functions (HTTPS)

| Function | Parameters | Purpose |
|----------|-----------|---------|
| `acceptAthleteToCoachInvitation` | invitationID | Accept athlete's coach invite (server-side folder share, athlete-limit transaction) |
| `acceptCoachToAthleteInvitation` | invitationID | Accept coach's athlete invite (athlete-limit transaction) |
| `resendInvitationEmail` | invitationID | Resend invitation email |
| `getSignedVideoURL` | folderID, fileName, expirationHours | Signed download URL (24hr default) |
| `getSignedThumbnailURL` | folderID, videoFileName, expirationHours | Signed thumbnail URL (7-day default) |
| `getBatchSignedVideoURLs` | folderID, fileNames[], expirationHours | Batch signed URLs (max 50) |
| `getPersonalVideoSignedURL` | athleteID, fileName | Personal video download URL |
| `syncSubscriptionTier` | receipt data | Sync App Store receipt/subscription tier to Firestore |
| `backfillInvitationsOnSignup` | — | Reattach pending invitations to a newly signed-up user |

### Backfill / Migration Jobs (one-off)

| Function | Purpose |
|----------|---------|
| `backfillFolderAthleteUUID` | Backfill `athleteUUID` onto legacy shared folders |
| `backfillFolderPersonGroupID` | Backfill `personGroupID` onto folders (dual-sport dedupe) |
| `backfillInvitationPersonGroupID` | Backfill `personGroupID` onto invitations |
| `migrateRevocationDocIDsToDeterministic` | Migrate `coach_access_revocations` to deterministic `<folderID>_<coachID>` IDs |

---

## Security Rules Summary

### Tier-Based Gating

- **Any athlete tier can create shared folders.** Under Pricing Model V2 the old Pro-only gate was removed — the coach now pays for the seat, so athletes on Free/Plus/Pro may all share. New folders must be created with an empty `sharedWithCoachIDs`/`permissions` (no pre-seeded coaches).
- Active coach tier required to access shared folder content as coach (`hasCoachTier()` is a role/tier identity check only — it does NOT count the coach's athlete limit; that lives in the Cloud Function transactions).
- **Coach addition to `sharedFolders.sharedWithCoachIDs` is exclusive to Cloud Functions (Admin SDK).** The owner-update branch of the rule allows REMOVALS only (subset / size − 1 check), so a direct client write cannot bypass the CF athlete-limit transaction.
- `coach_access_revocations` (deterministic `<folderID>_<coachID>` IDs) is read by `canAccessFolder()` to deny re-added-but-since-revoked coaches.

### Permission Model

Three folder permissions: `canUpload`, `canComment`, `canDelete`

| Action | Athlete (Owner) | Coach (w/ Upload) | Coach (View Only) |
|--------|----------------|-------------------|-------------------|
| View Folder | Yes | Yes | Yes |
| Upload Video | Yes | Yes | No |
| Delete Own Video | Yes | Yes | Yes |
| Delete Other's Video | Yes | Only with canDelete | No |
| Add Comment | Yes | Yes | Yes |
| Delete Own Comment | Yes | Yes | Yes |
| Delete Other's Comment | Yes | No | No |
| Modify Folder Settings | Yes | No | No |
| Delete Folder | Yes | No | No |

### Invitation Security

- 30-day expiration window with ~3-day buffer for clock skew
- Enforced at acceptance/decline time, not read time
- Status transitions are one-way (pending -> accepted/declined/cancelled)

### Immutable Fields

- User role and subscription tiers (Cloud Function exclusive)
- Video uploader identity after creation
- Invitation type and sender

---

## FirestoreManager Extensions

| Extension File | Key Methods |
|---------------|-------------|
| `+SharedFolders` | createSharedFolder, fetchSharedFolders (athlete/coach), verifyFolderAccess, deleteSharedFolder, batchRevokeCoachAccess, updateFolderTags |
| `+VideoMetadata` | uploadVideoMetadata, fetchVideos (folder/session), listenToVideos, uploadThumbnail(s), publishPrivateVideo, deleteCoachPrivateVideo, updateVideoTags, logVideoAccess |
| `+Annotations` | addAnnotation, fetchAnnotations, deleteAnnotation |
| `+Invitations` | createInvitation, acceptInvitation, declineInvitation, createCoachToAthleteInvitation, acceptCoachToAthleteInvitation, fetchPendingInvitations, cancelInvitation |
| `+UserProfile` | fetchUserProfile, updateUserProfile, syncSubscriptionTiers, deleteUserProfile, fetchCoachInfo |
| `+EntitySync` | CRUD for Athletes, Seasons, Games, Practices, PracticeNotes, Photos, Coaches (31+ methods) |
| `+DrillCards` | createDrillCard, updateDrillCard, fetchDrillCards, deleteDrillCard |

---

## Data Relationships

```
User (Athlete)
  |-- owns --> SharedFolder(s)
  |                |-- shared with --> User (Coach)
  |                |-- contains --> Video(s)
  |                |                    |-- comments/
  |                |                    |-- annotations/
  |                |                    |-- drillCards/
  |                |                    |-- access_logs/
  |                |-- linked to --> CoachSession(s)
  |
  |-- has --> Athlete(s)
                |-- Season(s)
                      |-- Game(s) --> VideoClip(s) --> PlayResult(s)
                      |-- Practice(s) --> PracticeNote(s)
```

---

## Deployment

```bash
# Deploy all
firebase deploy

# Deploy specific
firebase deploy --only firestore:rules
firebase deploy --only storage:rules
firebase deploy --only functions

# View function logs
firebase functions:log

# Check function status
firebase functions:list
```

**Config file:** `GoogleService-Info.plist`
**Security rules:** `firestore.rules` (954 lines)
**Cloud Functions:** `firebase/functions/src/index.ts` (Node.js — ~32 functions: SendGrid email, StoreKit/subscription sync, App Store Server Notifications V2 webhook, athlete-limit transactions, coach-downgrade audit, storage cleanup/quota, GDPR deletion, backfill/migration jobs)
