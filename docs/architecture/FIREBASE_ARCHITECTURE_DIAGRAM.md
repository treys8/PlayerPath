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
|   |-- games/{gameID}
|   |   |-- opponent, date, location, isHome, score, opponentScore
|   |   |-- liveStartDate, seasonID, athleteID
|   |   |-- firestoreId, version, needsSync
|   |
|   |-- practices/{practiceID}
|       |-- date, location, practiceType (general/batting/fielding/bullpen/team)
|       |-- athleteID, seasonID, firestoreId, version
|       |
|       |-- notes/{noteID}
|           |-- text, createdAt, firestoreId, version
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

## Cloud Functions (14 total)

### Firestore Triggers

| Function | Trigger | Purpose |
|----------|---------|---------|
| `onNewSharedVideo` | Video created in shared folder | Notify coaches/athletes |
| `onNewComment` | Comment added to video | Notify video uploader |
| `onNewDrillCard` | Drill card added to video | Notify athlete |
| `sendInvitationEmail` | Invitation created | Email via SendGrid (both directions) |
| `sendCoachAccessRevokedEmail` | Access revoked | Email notification |
| `enforceAthleteLimit` | Athlete created | Enforce tier-based athlete count |
| `enforceCoachAthleteLimit` | Coach folder accepted | Enforce coach athlete limits |
| `enforceCoachAthleteLimitOnAccept` | Invitation accepted | Prevent over-limit accept |
| `dailyStorageCleanup` | Scheduled (daily) | Clean pending deletions |
| `enforceStorageQuota` | Video uploaded | Enforce per-user storage quota |

### Callable Functions (HTTPS)

| Function | Parameters | Purpose |
|----------|-----------|---------|
| `acceptAthleteToCoachInvitation` | invitationID | Accept athlete's coach invite (server-side folder creation) |
| `acceptCoachToAthleteInvitation` | invitationID | Accept coach's athlete invite |
| `resendInvitationEmail` | invitationID | Resend invitation email |
| `getSignedVideoURL` | folderID, fileName, expirationHours | Signed download URL (24hr default) |
| `getSignedThumbnailURL` | folderID, videoFileName, expirationHours | Signed thumbnail URL (7-day default) |
| `getBatchSignedVideoURLs` | folderID, fileNames[], expirationHours | Batch signed URLs (max 50) |
| `getPersonalVideoSignedURL` | athleteID, fileName | Personal video download URL |
| `syncSubscriptionTier` | receipt data | Sync App Store receipt to Firestore |

---

## Security Rules Summary

### Tier-Based Gating

- Pro tier athletes required to create shared folders
- Active coach tier required to access shared folder content as coach
- Free athletes can only have personal videos

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
**Security rules:** `firestore.rules` (~500 lines)
**Cloud Functions:** `firebase/functions/src/index.ts` (Node.js + SendGrid)
