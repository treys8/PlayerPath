# PlayerPath Coach Web Portal — Technical Handoff

This document provides everything needed to build a coach-facing web portal that mirrors the iOS app's Firebase backend. All field names, collection paths, and logic rules are extracted directly from the codebase.

---

## 1. Firestore Data Models

### Collection Hierarchy

```
/users/{userID}
├── /athletes/{athleteID}
│   └── /coaches/{coachID}
├── /seasons/{seasonID}
├── /games/{gameID}
└── /practices/{practiceID}
    └── /notes/{noteID}

/sharedFolders/{folderID}

/videos/{videoID}
├── /annotations/{annotationID}
├── /comments/{commentID}
├── /drillCards/{cardID}
└── /access_logs/{logID}

/photos/{photoID}

/invitations/{invitationID}

/coachSessions/{sessionID}

/coachTemplates/{coachID}
└── /quickCues/{cueID}

/notifications/{userID}
└── /items/{itemID}

/coach_access_revocations/{revocationID}

/pendingDeletions/{deletionID}

/appConfig/{docID}
```

### 1.1 `users/{userID}`

The root profile document for every user (athlete or coach).

| Field | Type | Optional | Notes |
|-------|------|----------|-------|
| `email` | string | no | Lowercase normalized |
| `displayName` | string | yes | |
| `role` | string | no | `"athlete"` or `"coach"` — immutable after creation |
| `subscriptionTier` | string | no | `"free"`, `"plus"`, `"pro"` (athletes). Default `"free"` |
| `coachSubscriptionTier` | string | yes | `"coach_free"`, `"coach_instructor"`, `"coach_pro_instructor"`, `"coach_academy"` |
| `coachAthleteCount` | int | yes | Server-managed; immutable via client rules |
| `athleteTierSource` | string | yes | Cannot be modified via client updates |
| `createdAt` | timestamp | yes | Server timestamp |
| `updatedAt` | timestamp | yes | Server timestamp |

### 1.2 `users/{userID}/athletes/{athleteID}`

Athletes tracked by a user account. Coaches don't have these — they access athlete data through shared folders.

| Field | Type | Optional | Notes |
|-------|------|----------|-------|
| `id` | string | no | SwiftData UUID (CodingKey maps `swiftDataId` → `id`) |
| `name` | string | no | |
| `primaryRole` | string | yes | |
| `userId` | string | no | FK → parent user |
| `createdAt` | timestamp | yes | |
| `updatedAt` | timestamp | yes | |
| `version` | int | no | Optimistic concurrency |
| `isDeleted` | bool | no | Soft delete flag |
| `deletedAt` | timestamp | yes | |

**Subcollection:** `coaches/` — stores coach records linked to this athlete.

### 1.3 `users/{userID}/athletes/{athleteID}/coaches/{coachID}`

Coach records linked to a specific athlete.

| Field | Type | Optional | Notes |
|-------|------|----------|-------|
| `id` | string | no | SwiftData UUID |
| `athleteId` | string | no | FK → parent athlete |
| `name` | string | no | Coach display name |
| `role` | string | yes | Default `"coach"` |
| `email` | string | no | Coach email |
| `phone` | string | yes | |
| `notes` | string | yes | |
| `firebaseCoachID` | string | yes | FK → `users/{coachID}` when coach is registered |
| `invitationStatus` | string | yes | `"pending"`, `"accepted"`, `"declined"` |
| `createdAt` | timestamp | yes | |
| `updatedAt` | timestamp | yes | |
| `isDeleted` | bool | no | |
| `deletedAt` | timestamp | yes | |

### 1.4 `users/{userID}/seasons/{seasonID}`

| Field | Type | Optional | Notes |
|-------|------|----------|-------|
| `id` | string | no | SwiftData UUID |
| `name` | string | no | |
| `athleteId` | string | no | FK → athlete |
| `startDate` | timestamp | yes | |
| `endDate` | timestamp | yes | |
| `isActive` | bool | no | |
| `sport` | string | no | |
| `notes` | string | yes | Default `""` |
| `createdAt` | timestamp | yes | |
| `updatedAt` | timestamp | yes | |
| `version` | int | no | |
| `isDeleted` | bool | no | |
| `deletedAt` | timestamp | yes | |

### 1.5 `users/{userID}/games/{gameID}`

| Field | Type | Optional | Notes |
|-------|------|----------|-------|
| `id` | string | no | SwiftData UUID |
| `athleteId` | string | no | FK → athlete |
| `seasonId` | string | yes | FK → season |
| `tournamentId` | string | yes | |
| `opponent` | string | no | |
| `date` | timestamp | yes | |
| `year` | int | no | |
| `isLive` | bool | no | Live game flag |
| `isComplete` | bool | no | |
| `location` | string | yes | |
| `notes` | string | yes | |
| `createdAt` | timestamp | yes | |
| `updatedAt` | timestamp | yes | |
| `version` | int | no | |
| `isDeleted` | bool | no | |
| `deletedAt` | timestamp | yes | |

### 1.6 `users/{userID}/practices/{practiceID}`

| Field | Type | Optional | Notes |
|-------|------|----------|-------|
| `id` | string | no | SwiftData UUID |
| `athleteId` | string | no | FK → athlete |
| `seasonId` | string | yes | FK → season |
| `practiceType` | string | yes | |
| `date` | timestamp | yes | |
| `createdAt` | timestamp | yes | |
| `updatedAt` | timestamp | yes | |
| `version` | int | no | |
| `isDeleted` | bool | no | |
| `deletedAt` | timestamp | yes | |

**Subcollection:** `notes/` — practice notes.

### 1.7 `users/{userID}/practices/{practiceID}/notes/{noteID}`

| Field | Type | Optional | Notes |
|-------|------|----------|-------|
| `id` | string | yes | Firestore-generated |
| `swiftDataId` | string | yes | Original SwiftData UUID |
| `practiceId` | string | no | FK → parent practice |
| `content` | string | no | Note text |
| `createdAt` | timestamp | yes | |
| `updatedAt` | timestamp | yes | |
| `isDeleted` | bool | no | |
| `deletedAt` | timestamp | yes | |

### 1.8 `sharedFolders/{folderID}`

The bridge between coaches and athletes. Coaches access athlete content exclusively through these.

| Field | Type | Optional | Notes |
|-------|------|----------|-------|
| `id` | string | yes | Firestore doc ID |
| `name` | string | no | Display name |
| `ownerAthleteID` | string | no | FK → `users/{athleteID}` |
| `ownerAthleteName` | string | yes | Denormalized |
| `sharedWithCoachIDs` | string[] | no | Array of coach UIDs |
| `sharedWithCoachNames` | map<string, string> | yes | coachID → display name |
| `permissions` | map<string, map<string, bool>> | no | coachID → `{canUpload, canComment, canDelete}` |
| `createdAt` | timestamp | yes | |
| `updatedAt` | timestamp | yes | |
| `videoCount` | int | yes | Atomically incremented |
| `tags` | string[] | yes | |
| `folderType` | string | yes | `"games"`, `"lessons"`, or null (legacy) |

**Permissions model per coach:**
```json
{
  "coachUID123": {
    "canUpload": true,
    "canComment": true,
    "canDelete": false
  }
}
```

Default permissions: `{canUpload: true, canComment: true, canDelete: false}`
View-only: `{canUpload: false, canComment: true, canDelete: false}`

### 1.9 `videos/{videoID}`

Video metadata documents. Actual video files live in Firebase Storage (see Section 3).

| Field | Type | Optional | Notes |
|-------|------|----------|-------|
| `id` | string | yes | Firestore doc ID |
| `fileName` | string | no | Storage file name |
| `firebaseStorageURL` | string | no | Download URL |
| `thumbnail` | object | yes | `{standardURL, highQualityURL?, timestamp?, width?, height?}` |
| `thumbnailURL` | string | yes | **DEPRECATED** — use `thumbnail.standardURL` |
| `uploadedBy` | string | no | FK → `users/{uid}` |
| `uploadedByName` | string | no | Denormalized |
| `sharedFolderID` | string | no | FK → `sharedFolders/{id}` |
| `createdAt` | timestamp | yes | |
| `fileSize` | int64 | yes | Bytes |
| `duration` | double | yes | Seconds |
| `isHighlight` | bool | yes | |
| `uploadedByType` | string | yes | `"athlete"` or `"coach"` |
| `isOrphaned` | bool | yes | True if uploader deleted account |
| `orphanedAt` | timestamp | yes | |
| `annotationCount` | int | yes | Atomically incremented |
| `videoType` | string | yes | `"game"`, `"practice"`, `"highlight"` |
| `gameOpponent` | string | yes | |
| `gameDate` | timestamp | yes | |
| `practiceDate` | timestamp | yes | |
| `notes` | string | yes | |
| `tags` | string[] | yes | |
| `drillType` | string | yes | |
| `sessionID` | string | yes | FK → `coachSessions/{id}` |
| `visibility` | string | yes | `"shared"` (public) or `"private"` (coach only) |
| `instructionDate` | timestamp | yes | |
| `uploadStatus` | string | yes | `"pending"`, `"completed"`, `"failed"` |
| `uploadStartedAt` | timestamp | yes | |
| `viewCount` | int | yes | Atomically incremented |
| `lastViewedAt` | timestamp | yes | |
| `playResult` | string | yes | Hit type (single, double, etc.) |
| `pitchSpeed` | double | yes | MPH |
| `pitchType` | string | yes | |
| `seasonID` | string | yes | |
| `athleteName` | string | yes | Denormalized |

**Thumbnail nested object:**
```typescript
interface ThumbnailMetadata {
  standardURL: string;       // 480x270
  highQualityURL?: string;   // For highlights
  timestamp?: number;        // Seconds into video
  width?: number;
  height?: number;
}
```

### 1.10 `videos/{videoID}/annotations/{annotationID}`

Coach feedback attached to specific video timestamps.

| Field | Type | Optional | Notes |
|-------|------|----------|-------|
| `id` | string | yes | Firestore doc ID |
| `userID` | string | no | FK → users (author) |
| `userName` | string | no | Denormalized |
| `timestamp` | double | no | Seconds into video |
| `text` | string | no | |
| `createdAt` | timestamp | yes | |
| `isCoachComment` | bool | no | |
| `category` | string | yes | `"mechanics"`, `"timing"`, `"approach"`, `"positive"`, `"correction"` |
| `templateID` | string | yes | FK → quick cue template |
| `type` | string | yes | `"note"` (default), `"drill_card"`, `"drawing"` |

### 1.11 `videos/{videoID}/comments/{commentID}`

General comments (not timestamp-linked).

| Field | Type | Optional | Notes |
|-------|------|----------|-------|
| `authorId` | string | no | FK → users |
| `authorName` | string | no | |
| `authorRole` | string | no | `"athlete"` or `"coach"` |
| `text` | string | no | Max 2000 chars |
| `content` | string | no | Same as text (legacy field) |
| `createdAt` | timestamp | no | |
| `category` | string | yes | AnnotationCategory value |

### 1.12 `videos/{videoID}/drillCards/{cardID}`

Structured coaching feedback with category ratings.

| Field | Type | Optional | Notes |
|-------|------|----------|-------|
| `id` | string | yes | Firestore doc ID |
| `coachID` | string | no | FK → users |
| `coachName` | string | no | Denormalized |
| `templateType` | string | no | `"batting_review"`, `"pitching_review"`, `"fielding_review"`, `"custom"` |
| `categories` | object[] | no | Array of `{name, rating, notes?}` |
| `overallRating` | int | yes | 1–5 |
| `summary` | string | yes | |
| `isVisibleToAthlete` | bool | yes | Default true |
| `createdAt` | timestamp | yes | |
| `updatedAt` | timestamp | yes | |

**Category object:**
```typescript
interface DrillCardCategory {
  name: string;     // e.g. "Stance", "Load", "Swing Path"
  rating: number;   // 1-5
  notes?: string;
}
```

**Default categories by template:**
- `batting_review`: Stance, Load, Swing Path, Contact Point, Follow Through
- `pitching_review`: Windup, Arm Slot, Release Point, Follow Through, Command
- `fielding_review`: Ready Position, First Step, Glove Work, Throwing, Footwork
- `custom`: empty (coach defines)

### 1.13 `videos/{videoID}/access_logs/{logID}`

Engagement tracking.

| Field | Type | Optional | Notes |
|-------|------|----------|-------|
| `userID` | string | no | FK → users |
| `userName` | string | no | |
| `userRole` | string | no | `"athlete"` or `"coach"` |
| `action` | string | no | `"view"`, `"play"`, `"pause"` |
| `folderID` | string | no | FK → sharedFolders |
| `timestamp` | timestamp | no | |

### 1.14 `invitations/{invitationID}`

Two types: `athlete_to_coach` and `coach_to_athlete`. Shared fields plus type-specific fields.

**Common fields:**

| Field | Type | Optional | Notes |
|-------|------|----------|-------|
| `id` | string | yes | Firestore doc ID |
| `type` | string | no | `"athlete_to_coach"` or `"coach_to_athlete"` |
| `status` | string | no | `"pending"`, `"accepted"`, `"declined"`, `"cancelled"`, `"rejected_limit"` |
| `expiresAt` | timestamp | no | 30 days from creation |
| `sentAt` | timestamp | yes | |
| `createdAt` | timestamp | yes | |

**Athlete-to-Coach additional fields:**

| Field | Type | Optional | Notes |
|-------|------|----------|-------|
| `athleteID` | string | no | FK → users |
| `athleteName` | string | no | |
| `coachEmail` | string | no | Lowercase |
| `folderID` | string | yes | FK → sharedFolders |
| `folderName` | string | yes | |
| `permissions` | map<string, bool> | yes | `{canUpload, canComment, canDelete}` |
| `acceptedByCoachID` | string | yes | Set on accept |
| `acceptedAt` | timestamp | yes | |
| `declinedAt` | timestamp | yes | |
| `cancelledAt` | timestamp | yes | |
| `rejectedReason` | string | yes | |

**Coach-to-Athlete additional fields:**

| Field | Type | Optional | Notes |
|-------|------|----------|-------|
| `coachID` | string | no | FK → users |
| `coachEmail` | string | no | Lowercase |
| `coachName` | string | no | |
| `athleteEmail` | string | no | Lowercase |
| `athleteName` | string | no | |
| `athleteUserID` | string | yes | Set when athlete accepts |
| `message` | string | yes | Optional message from coach |
| `folderID` | string | yes | Created server-side on accept |
| `folderName` | string | yes | |
| `acceptedAt` | timestamp | yes | |
| `declinedAt` | timestamp | yes | |
| `cancelledAt` | timestamp | yes | |
| `rejectedReason` | string | yes | |

### 1.15 `coachSessions/{sessionID}`

Live coaching session metadata.

| Field | Type | Optional | Notes |
|-------|------|----------|-------|
| `id` | string | yes | Firestore doc ID |
| `coachID` | string | no | FK → users |
| `coachName` | string | no | |
| `athleteIDs` | string[] | no | Array of athlete UIDs |
| `athleteNames` | map<string, string> | no | athleteID → name |
| `folderIDs` | map<string, string> | no | athleteID → folderID |
| `status` | string | no | `"scheduled"`, `"live"`, `"reviewing"`, `"completed"` |
| `startedAt` | timestamp | yes | |
| `endedAt` | timestamp | yes | |
| `clipCount` | int | no | Atomically incremented |
| `title` | string | yes | |
| `scheduledDate` | timestamp | yes | |
| `notes` | string | yes | |

### 1.16 `coachTemplates/{coachID}/quickCues/{cueID}`

Reusable coaching feedback snippets.

| Field | Type | Optional | Notes |
|-------|------|----------|-------|
| `id` | string | yes | Firestore doc ID |
| `text` | string | no | e.g. "Good follow-through" |
| `category` | string | no | `"mechanics"`, `"timing"`, `"approach"`, `"positive"`, `"correction"` |
| `usageCount` | int | no | Atomically incremented |
| `createdAt` | timestamp | yes | |

**Default cues seeded at coach signup:**
- "Good follow-through" (positive)
- "Elbow drop" (mechanics)
- "Stay back" (timing)
- "Good approach" (positive)
- "Check swing path" (mechanics)
- "Timing early" (timing)
- "Timing late" (timing)
- "Nice rep" (positive)

### 1.17 `notifications/{userID}/items/{itemID}`

| Field | Type | Optional | Notes |
|-------|------|----------|-------|
| `senderID` | string | no | FK → users |
| `type` | string | no | `"new_video"`, `"coach_comment"`, `"invitation_received"`, `"invitation_accepted"`, `"access_revoked"`, `"access_lapsed"` |
| `title` | string | no | |
| `body` | string | no | |
| `targetType` | string | yes | `"folder"` or `"invitation"` |
| `targetID` | string | yes | FK → target entity |
| `folderID` | string | yes | FK → sharedFolders |
| `isRead` | bool | no | |
| `createdAt` | timestamp | no | |

### 1.18 `coach_access_revocations/{revocationID}`

Audit trail when a coach loses folder access.

| Field | Type | Optional | Notes |
|-------|------|----------|-------|
| `folderID` | string | no | FK → sharedFolders |
| `folderName` | string | no | |
| `coachID` | string | no | FK → users |
| `coachEmail` | string | no | |
| `athleteID` | string | no | FK → users |
| `athleteName` | string | no | |
| `revokedAt` | timestamp | no | |
| `emailSent` | bool | no | |
| `reason` | string | yes | e.g. "downgrade" |

### Denormalized / Mirrored Fields

These fields are duplicated across collections to avoid joins:

| Field | Canonical Source | Duplicated In |
|-------|------------------|---------------|
| Athlete display name | `users/{uid}.displayName` | `sharedFolders.ownerAthleteName`, `invitations.athleteName`, `videos.athleteName` |
| Coach display name | `users/{uid}.displayName` | `sharedFolders.sharedWithCoachNames`, `invitations.coachName`, `annotations.userName`, `drillCards.coachName`, `coachSessions.coachName` |
| Video count | Count of docs in `/videos` | `sharedFolders.videoCount` (atomic counter) |
| Annotation count | Count of docs in `/annotations` | `videos.annotationCount` (atomic counter) |

---

## 2. User Roles & Permissions

### Coach Subscription Tiers

| Tier | Athlete Limit | Product IDs | Notes |
|------|:------------:|-------------|-------|
| **Free** | 2 | — | Default at signup |
| **Instructor** | 10 | `com.playerpath.coach.instructor.monthly`, `com.playerpath.coach.instructor.annual` | |
| **Pro Instructor** | 30 | `com.playerpath.coach.proinstructor.monthly`, `com.playerpath.coach.proinstructor.annual` | |
| **Academy** | Unlimited | — | Manually granted via Firestore (no StoreKit product) |

Tiers are `Comparable`: `free < instructor < proInstructor < academy`.

**Athlete limit = count of unique athlete user IDs across:**
1. `sharedFolders` where coach is in `sharedWithCoachIDs`
2. Accepted `coach_to_athlete` invitations

### Coach-Athlete Connection Flow

**Direction 1: Athlete invites Coach**
```
1. Athlete creates shared folder (requires Pro tier)
2. Athlete enters coach email → creates invitation (type: "athlete_to_coach", status: "pending")
3. Coach signs in, app queries invitations WHERE coachEmail = {email} AND status = "pending"
4. Coach accepts → Cloud Function atomically:
   - Sets invitation.status = "accepted"
   - Adds coachID to sharedFolders/{id}.sharedWithCoachIDs
   - Sets permissions in sharedFolders/{id}.permissions
```

**Direction 2: Coach invites Athlete**
```
1. Coach enters athlete name + parent email + optional message
2. Creates invitation (type: "coach_to_athlete", status: "pending")
3. Athlete signs in, app queries invitations WHERE athleteEmail = {email} AND status = "pending"
4. Athlete accepts (requires Pro tier) → Cloud Function atomically:
   - Creates TWO shared folders: "{Name}'s Games" and "{Name}'s Lessons"
   - Adds coachID to both folders' sharedWithCoachIDs
   - Sets invitation.status = "accepted"
```

**Invitation rules:**
- 30-day expiration enforced both client-side and in Firestore rules
- Duplicate prevention: can't create a new invitation if one is already pending/accepted
- Email matching is case-insensitive (lowercased at write time)

### What a Coach Can See vs. What Is Private

| Data | Coach Access | Notes |
|------|:-----------:|-------|
| Athlete profile (games, seasons, stats) | **No** | Coaches have zero access to user subcollections |
| Shared folder metadata | **Yes** | Only folders where `sharedWithCoachIDs` contains their UID |
| Videos in shared folders | **Yes** | Except `visibility: "private"` videos uploaded by other coaches |
| Video annotations/comments | **Yes** | Can read all; can create if `canComment` permission |
| Drill cards | **Yes** | Can create own; can read all on accessible videos |
| Other coaches on same folder | **No** | `sharedWithCoachIDs` array is readable but coach identities are not exposed in UI |
| Athlete's personal (non-shared) videos | **No** | |
| Athlete's statistics | **No** | Stats are computed locally on athlete's device from SwiftData |

### Folder Permission Matrix

| Action | Owner (Athlete) | Coach with default perms | Coach with view-only |
|--------|:-:|:-:|:-:|
| Read folder | Yes | Yes | Yes |
| Upload video | Yes | Yes | No |
| Comment/annotate | Yes | Yes | Yes |
| Delete video | Yes | No | No |
| Add/remove coach | Yes | No | No |
| Delete folder | Yes | No | No |
| Leave folder | — | Yes (self-remove) | Yes (self-remove) |

---

## 3. Video & Session Model

### Firebase Storage Paths

```
# Athlete personal videos
athlete_videos/{ownerUID}/{fileName}

# Shared folder videos
shared_folders/{folderID}/videos/{fileName}

# Thumbnails
shared_folders/{folderID}/thumbnails/{videoFileName}_thumbnail.jpg
shared_folders/{folderID}/thumbnails/{videoFileName}_hq.jpg    # High-quality variant
```

Content type for videos: `video/quicktime`

### Video Upload Flow (Coach)

```
1. Coach records clip via DirectCameraRecorderView
2. Video saved to local Documents/coach_pending_uploads/
3. Thumbnail generated locally (1-second frame, 480x270)
4. Thumbnail uploaded to Storage: shared_folders/{folderID}/thumbnails/{name}
5. Video uploaded to Storage: shared_folders/{folderID}/videos/{name}
6. Firestore metadata document created in /videos/{id}
   - uploadStatus: "completed"
   - visibility: "private" (coach reviews before sharing)
   - sessionID: references the active coaching session
7. sharedFolders/{folderID}.videoCount atomically incremented
```

**Upload queue:**
- Max 2 concurrent uploads
- Retry: up to 10 attempts with exponential backoff (5s → 1h)
- Persisted to SwiftData; survives app crashes
- Background processing via BGProcessingTask

### Video Visibility Model

Videos have a `visibility` field:
- `"private"` — Only the uploader can see it. Used by coaches for unreviewed clips.
- `"shared"` — Visible to all folder members. Default for athlete uploads.

The "Review" tab in a lessons folder shows private coach videos. When a coach "shares" a clip, visibility changes from `"private"` to `"shared"`.

### Metadata-First Upload Pattern

For reliability, Firestore metadata can be created before the Storage upload completes:
- `uploadStatus: "pending"` — metadata exists, file upload in progress
- `uploadStatus: "completed"` — file upload successful
- `uploadStatus: "failed"` — file upload failed
- UI queries filter out non-completed uploads

### Coach Sessions

**Lifecycle:**
```
scheduled → live → reviewing → completed
```

| Transition | Trigger | What Happens |
|-----------|---------|--------------|
| → `scheduled` | Coach creates session | `coachSessions/{id}` created with athlete list |
| `scheduled` → `live` | Coach starts session | `startedAt` set; camera opens |
| `live` → `reviewing` | Coach ends recording | `endedAt` set; review tab opens |
| `reviewing` → `completed` | Coach finishes review | Session archived |

**Constraints:**
- One active session per coach (starting a new one ends the current)
- Sessions > 24 hours auto-cleaned
- `clipCount` atomically incremented per recorded video
- Athletes selected at creation; cannot be added mid-session
- Each athlete in the session maps to a specific `folderID` (the athlete's lessons folder)

### Annotations (Timestamped Feedback)

Stored at `videos/{videoID}/annotations/{id}`:
- Linked to a specific `timestamp` (seconds into video)
- Categorized: mechanics, timing, approach, positive, correction
- Can reference a quick cue template via `templateID`
- `annotationCount` on the video document is atomically maintained

### Drill Cards (Structured Evaluation)

Stored at `videos/{videoID}/drillCards/{id}`:
- Template-driven: batting, pitching, fielding, or custom
- Each category rated 1–5 with optional notes
- Overall rating 1–5 with summary text
- `isVisibleToAthlete` controls whether athlete sees it (default true)

---

## 4. Stats Model

### What Stats Are Tracked

Stats are computed **locally on the athlete's device** from SwiftData. They are **not stored in Firestore** and are **not accessible to coaches**.

**Batting stats:**
- `atBats`, `hits`, `singles`, `doubles`, `triples`, `homeRuns`
- `runs`, `rbis`, `walks`, `strikeouts`
- `groundOuts`, `flyOuts`, `hitByPitches`

**Pitching stats:**
- `totalPitches`, `balls`, `strikes`
- `pitchingStrikeouts`, `pitchingWalks`, `wildPitches`, `hitByPitches`
- `fastballPitchCount`, `fastballSpeedTotal`
- `offspeedPitchCount`, `offspeedSpeedTotal`

**Computed metrics:**
- Batting average = hits / atBats
- OBP = (hits + walks + HBP) / (atBats + walks + HBP)
- Slugging = totalBases / atBats
- OPS = OBP + SLG
- Average fastball/offspeed speed

### How Stats Link to Video

Each `VideoClip` can have:
- `playResult` — a `PlayResultType` enum (single, double, strikeout, etc.)
- `pitchType` — "fastball" or "offspeed"
- `pitchSpeed` — MPH

**Recalculation hierarchy:**
```
Game stats = sum of PlayResults from all VideoClips in that game
Season stats = aggregate of all completed game stats + practice video results
Career stats = aggregate of all season stats
```

### What Coaches Can See

Coaches see **per-video play result tags** on shared videos (the `playResult`, `pitchType`, `pitchSpeed` fields on `videos/{id}`). They do **not** see aggregated batting averages, OBP, or any computed statistics — those exist only on the athlete's device.

**For the web portal:** If you want to show coaches aggregated stats, you would need to compute them from the video metadata in the shared folders (counting play results across videos).

---

## 5. Coach Dashboard — Key Screens to Replicate

### 5.1 Coach Dashboard (`CoachDashboardView`)

**Purpose:** Home screen — quick actions, active sessions, review queue, athlete overview.

**Data reads:**
- `sharedFolders` WHERE `sharedWithCoachIDs` contains coachUID → folder list with `videoCount`, `updatedAt`
- `coachSessions` WHERE `coachID` = coachUID → active and completed sessions
- `videos` WHERE `sharedFolderID` in coachFolders AND `visibility` = "private" AND `uploadedBy` = coachUID → review queue
- `notifications/{coachUID}/items` WHERE `isRead` = false → unread count

**Displays:**
- Live session card (status, athlete count, clip count)
- Review queue: unreviewed private clips grouped by folder
- Upcoming scheduled sessions
- Quick actions: "New Session", "Invite Athlete"
- Recent athletes (horizontal scroll)
- This-week stats: sessions completed, clips recorded, athletes worked with
- Summary: total athletes, folders, shared videos

**Actions:**
- Start new session → `StartSessionSheet`
- Invite athlete → `InviteAthleteSheet`
- Resume active session → camera or folder review tab
- End/complete session
- Cancel scheduled session

**Subscription gates:**
- Over-limit banner if connected athletes > tier limit (still functional, just shows upgrade prompt)

### 5.2 Athletes Tab (`CoachAthletesTab`)

**Purpose:** Browse all connected athletes and their folders.

**Data reads:**
- `sharedFolders` WHERE `sharedWithCoachIDs` contains coachUID → grouped by `ownerAthleteID`
- `invitations` WHERE `coachID` = coachUID AND `status` = "pending" → pending count badge

**Displays:**
- Athletes grouped as collapsible sections
- Each folder shows: name, video count, permission icons (upload/comment), unread badge
- Search by athlete name or folder name (200ms debounce)
- Active vs. archived folder toggle
- Pending invitations banner

**Actions:**
- Tap folder → navigate to folder detail
- Record clip quick action
- Invite athlete
- View multi-athlete comparison

### 5.3 Folder Detail (`CoachFolderDetailView`)

**Purpose:** View and manage videos in a specific athlete's folder.

**Data reads:**
- `sharedFolders/{folderID}` → folder metadata, permissions
- `videos` WHERE `sharedFolderID` = folderID → paginated video list
- For lessons folders: filtered by `visibility` ("private" = Review tab, "shared" = Shared tab)

**Displays:**
- Header: athlete name, video count, last updated
- **Lessons folders:** Two tabs — "Review" (private/unreviewed) and "Shared" (published)
- **Games folders:** Flat video list (no tabs)
- Tag filter bar
- Each video: thumbnail, title, duration, uploaded by, tags, drill type
- Empty state: "All Caught Up"

**Actions:**
- Switch Review/Shared tabs (lessons only)
- Filter by tags
- "Share All" — bulk-publish all review clips
- Tap video → video player or clip review sheet
- Upload video
- Archive/unarchive folder
- Leave folder (with confirmation)

**Subscription gates:** None (all tiers can view accessible folders)

### 5.4 Video Player (`CoachVideoPlayerView`)

**Purpose:** Watch video, add timestamped notes, create drill cards.

**Data reads:**
- Video file from `firebaseStorageURL`
- `videos/{videoID}/annotations` → all notes ordered by timestamp (limit 50)
- `coachTemplates/{coachUID}/quickCues` → quick cue suggestions ordered by usage
- `videos/{videoID}/drillCards` → drill card evaluations (limit 10)

**Displays three tabs:**

1. **Notes tab:**
   - Timeline of annotations with timestamp, author, category color
   - Add Note form: timestamp (auto-filled from playhead), category picker, quick cue bar, free text
   - Tap note → seek video to that timestamp
   - Delete own notes

2. **Drill Card tab:**
   - List of drill cards with 5-star category ratings
   - New Drill Card form: template picker, category ratings, overall rating, summary
   - Coach name and date on each card

3. **Info tab:**
   - File name, uploaded by, date, duration, file size
   - Game opponent (if applicable)
   - Highlight badge

**Actions:**
- Play/pause/seek video
- Playback speed: 0.25x, 0.5x, 1x, 1.5x, 2x
- Add annotation (timestamp + text + category)
- Add quick cue (one-tap annotation from saved cues)
- Create/edit drill card
- Save video to device
- Delete own annotations

**Permissions:** `canComment` required for adding notes and drill cards.

### 5.5 Clip Review Sheet (`ClipReviewSheet`)

**Purpose:** Quick review of private clips before sharing with athlete.

**Data reads:**
- Video metadata (from folder video list)
- Video file (signed URL, cached locally)

**Displays:**
- Video player (4:3 aspect)
- Instruction notes editor
- Metadata: recorded date, file size

**Actions:**
- Watch video
- Edit instruction notes
- Share with athlete → changes `visibility` to "shared", sends notification
- Discard clip → deletes from Storage and Firestore

### 5.6 Invite Athlete Sheet (`InviteAthleteSheet`)

**Purpose:** Send invitation to connect with a new athlete.

**Data reads:**
- `authManager.coachAthleteLimit` — tier limit
- Current connected athlete count

**Displays:**
- Form: athlete name, parent email, personal message (optional)
- Info box explaining the athlete receives an email
- Limit warning if at capacity

**Actions:**
- Send invitation → creates `invitations/{id}` doc
- Upgrade prompt if at limit → paywall

**Subscription gates:**
- At athlete limit → shows warning + "Upgrade" button
- Over limit → disabled with paywall

### 5.7 Start Session Sheet (`StartSessionSheet`)

**Purpose:** Create a new coaching session.

**Data reads:**
- Athletes with upload permission (from shared folders where `canUpload` = true)

**Displays:**
- Multi-select athlete list with initials avatars
- Optional scheduled date/time picker
- Optional session notes field

**Actions:**
- Select athletes → create session (`coachSessions/{id}`)
- If no athletes → shows "Invite an Athlete" prompt

### 5.8 Coach Profile

**Purpose:** Account settings, manage subscription, view invitations.

**Data reads:**
- `users/{coachUID}` → profile, tier info
- `invitations` WHERE `coachEmail` = email AND type = "athlete_to_coach" AND status = "pending"

**Actions:**
- View/manage subscription tier
- View pending invitations
- Accept/decline invitations
- Edit profile (display name)
- Sign out

---

## 6. Authentication

### Firebase Auth Structure

- **Methods:** Email/password + Apple Sign In
- **No custom claims** — role stored in Firestore `users/{uid}.role` field, not in JWT
- **Email verification** required for accounts created after March 25, 2026 (grandfathered accounts exempt, Apple Sign In exempt)
- **Account lockout** after 5 failed attempts: 60s → 120s → 240s exponential backoff

### Role Identification

```
users/{uid}
├── role: "athlete" | "coach"              ← immutable after creation
├── subscriptionTier: "free"|"plus"|"pro"  ← athlete tiers (synced from StoreKit)
└── coachSubscriptionTier: "coach_free"|"coach_instructor"|"coach_pro_instructor"|"coach_academy"
                                           ← coach tiers
```

**How the iOS app determines role at login:**
1. `signIn()` → fetches `users/{uid}` from Firestore
2. Reads `role` field → routes to athlete or coach UI
3. Falls back to UserDefaults-cached role if Firestore is temporarily unavailable
4. Firestore is always authoritative

**For the web portal:** Query `users/{uid}` after Firebase Auth login. If `role !== "coach"`, deny access.

### Firestore Security Rule Helpers

```javascript
function isAuthenticated() {
  return request.auth != null;
}

function hasCoachTier() {
  // Reads the user's Firestore profile to check coach tier
  return get(/databases/$(database)/documents/users/$(request.auth.uid))
    .data.coachSubscriptionTier in ["coach_instructor", "coach_pro_instructor", "coach_academy"];
}

function hasProTier() {
  return get(/databases/$(database)/documents/users/$(request.auth.uid))
    .data.subscriptionTier == "pro";
}

function canAccessFolder(folderID) {
  let folder = get(/databases/$(database)/documents/sharedFolders/$(folderID));
  return folder.data.ownerAthleteID == request.auth.uid
    || request.auth.uid in folder.data.sharedWithCoachIDs;
}

function hasPermission(folderID, permission) {
  let folder = get(/databases/$(database)/documents/sharedFolders/$(folderID));
  return folder.data.permissions[request.auth.uid][permission] == true;
}
```

---

## 7. Web Portal Priorities

Based on the codebase analysis, these 5 coach workflows would deliver the most value on web:

### Priority 1: Video Review & Annotation

**Why web wins:** Coaches review dozens of clips per session. A larger screen with keyboard shortcuts for playback speed, timestamp entry, and quick cue shortcuts dramatically speeds up review. The iOS app already has landscape mode with a side-by-side annotation panel — this maps naturally to a web layout.

**Scope:** Video player with timestamped annotations, quick cue bar, drill card creation. Read `videos/{id}` + subcollections. Write to `annotations/` and `drillCards/`.

### Priority 2: Folder & Athlete Management Dashboard

**Why web wins:** Coaches managing 10–30 athletes need an overview that doesn't fit on a phone. A web dashboard can show all athletes, their folders, video counts, last activity, and unread items in a single table view with sorting/filtering. The iOS app already groups folders by athlete — a web table with expandable rows replaces multiple navigation taps.

**Scope:** Read `sharedFolders` + `notifications`. Display athlete list, folder details, video counts. Navigate to folder detail and video player.

### Priority 3: Invitation Management

**Why web wins:** Coaches sending invitations need to type emails and names — a keyboard-first experience is faster. Bulk invitations (inviting a whole team) are painful one-at-a-time on mobile. The web portal could add batch invite that the iOS app doesn't have.

**Scope:** Read/write `invitations/`. Create `coach_to_athlete` invitations. Accept `athlete_to_coach` invitations. Show pending/accepted/declined status.

### Priority 4: Session Planning & Review

**Why web wins:** Scheduling sessions, reviewing session clips, and writing session notes are planning tasks better suited to a desk. The session → review → share workflow involves multiple steps that benefit from persistent state on a larger screen.

**Scope:** Read/write `coachSessions/`. Read session videos from `videos/` WHERE `sessionID`. Transition session status. The recording step stays mobile-only (camera required).

### Priority 5: Quick Cue & Template Management

**Why web wins:** Building and organizing a library of coaching cues is a one-time setup task. A web CRUD interface for quick cues and drill card templates is more ergonomic than the iOS sheet-based UI. Coaches could also import/export cue libraries.

**Scope:** Read/write `coachTemplates/{coachID}/quickCues/`. CRUD operations on cue text, category, ordering. Could add import/export that doesn't exist on iOS.

---

## Appendix: Key Firestore Query Patterns for Web

```typescript
// Get all folders for a coach
db.collection('sharedFolders')
  .where('sharedWithCoachIDs', 'array-contains', coachUID)

// Get videos in a folder (paginated)
db.collection('videos')
  .where('sharedFolderID', '==', folderID)
  .where('uploadStatus', '==', 'completed')  // exclude pending uploads
  .orderBy('createdAt', 'desc')
  .limit(20)

// Get review queue (private coach videos)
db.collection('videos')
  .where('sharedFolderID', '==', folderID)
  .where('visibility', '==', 'private')
  .where('uploadedBy', '==', coachUID)
  .orderBy('createdAt', 'desc')

// Get annotations for a video
db.collection('videos').doc(videoID)
  .collection('annotations')
  .orderBy('timestamp', 'asc')
  .limit(50)

// Get pending invitations for a coach (by email)
db.collection('invitations')
  .where('type', '==', 'athlete_to_coach')
  .where('coachEmail', '==', coachEmail.toLowerCase())
  .where('status', '==', 'pending')

// Get coach's quick cues
db.collection('coachTemplates').doc(coachUID)
  .collection('quickCues')
  .orderBy('usageCount', 'desc')

// Get active sessions
db.collection('coachSessions')
  .where('coachID', '==', coachUID)
  .where('status', 'in', ['scheduled', 'live', 'reviewing'])

// Get unread notifications
db.collection('notifications').doc(coachUID)
  .collection('items')
  .where('isRead', '==', false)
  .orderBy('createdAt', 'desc')
```

### Composite Indexes Required

These queries will need composite Firestore indexes (check `firestore.indexes.json` or create manually):

1. `videos`: `sharedFolderID` ASC + `uploadStatus` ASC + `createdAt` DESC
2. `videos`: `sharedFolderID` ASC + `visibility` ASC + `uploadedBy` ASC + `createdAt` DESC
3. `invitations`: `type` ASC + `coachEmail` ASC + `status` ASC
4. `coachSessions`: `coachID` ASC + `status` ASC

### Cloud Functions the Web Portal Will Need

The iOS app calls these HTTPS Callable functions (in `firebase/functions/src/index.ts`):

1. **`acceptAthleteToCoachInvitation`** — Accepts an athlete-to-coach invitation (validates expiry, tier, atomically updates folder)
2. **`acceptCoachToAthleteInvitation`** — Accepts a coach-to-athlete invitation (creates two folders, validates athlete Pro tier)

These are already deployed and can be called from the web client using the Firebase JS SDK's `httpsCallable()`.
