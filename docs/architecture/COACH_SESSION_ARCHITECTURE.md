# Coach Live Instruction Session Architecture

**Last Updated:** March 27, 2026

Documents the coach live instruction session system -- lifecycle, clip capture, review flow, and dashboard integration.

---

## Overview

Live Instruction Sessions allow coaches to record, review, and share video clips during in-person lessons. Sessions support multiple athletes, integrate with shared folders, and flow through a defined state machine.

**Purpose:** Personal instruction (hitting/pitching lessons), not team practices. Coaches analyze lesson-to-game carryover by reviewing clips alongside game footage in shared folders.

---

## Data Model

**Firestore Collection:** `coachSessions`

```
CoachSession {
    id: String?
    coachID: String
    coachName: String
    athleteIDs: [String]
    athleteNames: [String: String]      // athleteID -> display name
    folderIDs: [String: String]         // athleteID -> shared folder ID
    status: SessionStatus               // scheduled | live | reviewing | completed
    startedAt: Date?
    endedAt: Date?
    clipCount: Int
    title: String?
    scheduledDate: Date?
    notes: String?
}
```

**Status Lifecycle:**

```
SCHEDULED  -->  LIVE  -->  REVIEWING  -->  COMPLETED
  (blue)       (red)      (orange)        (green)
```

- `isActive` returns `true` for both `.live` and `.reviewing`
- Only one session can be `.live` at a time (one-active constraint)
- Sessions `.live` for >24 hours are auto-ended by `cleanupAbandonedSessions()`

---

## Session Lifecycle

### Phase 1: Create / Schedule

**Entry:** `StartSessionSheet.swift` -- coach selects 1+ athletes, optionally sets date and notes.

**Call:** `CoachSessionManager.shared.scheduleSession(...)`
- Validates coach hasn't exceeded athlete tier limit
- Creates Firestore document with status `.scheduled`
- Stores athlete ID -> name/folder ID mappings
- Posts `.sessionScheduled` notification

### Phase 2: Go Live

**Trigger:** Coach taps "Go Live" on `UpcomingSessionCard`, or creates session without date (immediate).

**Call:** `startScheduledSession(sessionID:)`
- Ends any existing active session (one-active constraint)
- Updates Firestore: status -> `.live`, sets `startedAt`
- Moves session from `scheduledSessions` -> `sessions` array
- Sets as `activeSession`
- Posts `.sessionBecameLive` notification

**UI:** `LiveSessionCard` appears on dashboard with pulsing red "LIVE" indicator, athlete names, clip count, elapsed timer, and "End" button.

### Phase 3: Record Clips

**View:** `DirectCameraRecorderView` opens with `coachContext` parameter.

Recording flow:
1. `ModernCameraView` opens full-screen with "LIVE SESSION" badge overlay
2. Video recorded -> calls `onVideoRecorded(videoURL)`
3. **Trimming:** If >15s or `skipTrimmerForShortClips` disabled -> `PreUploadTrimmerView`
4. **Athlete tagging:**
   - Multi-athlete session -> `SessionAthletePickerOverlay` (horizontal scroll of athlete names)
   - Single-athlete session -> auto-save without picker
5. Calls `saveCoachClip(videoURL:athleteID:context:)`

### Phase 4: Upload & Processing

**Upload path:**
1. Validate connectivity (show offline alert if needed)
2. Copy video to stable Documents path: `coach_pending_uploads/instruction_[date]_[UUID].mov`
3. Enqueue via `UploadQueueManager.shared.enqueueCoachUpload()` with `.normal` priority
4. Queue handles retries, background tasks, persistence via `PendingUpload` SwiftData model

**Processing** (`CoachVideoProcessingService`):
- Extract video duration via `AVURLAsset`
- Generate thumbnail locally
- Upload thumbnail to Firebase Storage
- Returns `ProcessedVideo(duration, thumbnailURL)`
- Thumbnail failure is non-fatal (clip still uploads)

**Firestore metadata** (in `videos` collection):
- `sessionID` links clip to session
- `uploadedByType: .coach`
- `visibility: nil` (private until shared)
- Duration, thumbnail, createdAt, fileSize

**Clip count:** Incremented atomically via `FieldValue.increment` on `CoachSession.clipCount`.

### Phase 5: End Session

**Trigger:** Coach taps "End" on `LiveSessionCard`.

**Call:** `endSession(sessionID:)`
- Updates Firestore: status -> `.reviewing`, sets `endedAt`
- Posts `.sessionEnded` notification

**UI:** Card shows orange "REVIEW" badge with "Review Clips" and "Complete" buttons.

### Phase 6: Review & Share

**Location:** `CoachFolderDetailView` -> "Needs Review" tab.

Clips with `visibility == nil` (coach-private) are listed. For each clip:

**`ClipReviewSheet`:**
- Shows thumbnail, duration, file size, recorded date
- Coach adds/edits instruction notes
- Two actions:
  - **Share with Athlete:** `FirestoreManager.publishPrivateVideo()` -> sets `visibility` to "shared", posts activity notification
  - **Discard:** `FirestoreManager.deleteCoachPrivateVideo()` -> removes from folder

**Bulk Share:** "Share All" button publishes all clips at once.

### Phase 7: Complete

**Call:** `completeSession(sessionID:)`
- Updates Firestore: status -> `.completed`
- Clears `activeSession`
- Session removed from dashboard, moved to history

---

## Dashboard Integration

`CoachDashboardView` sections related to sessions:

| Section | Content |
|---------|---------|
| Live Session Card | Pulsing indicator, athlete names, clip count, timer. Tap resumes recording. |
| Upcoming Sessions | Chronological list of `.scheduled` sessions with "Go Live" / "Cancel" actions |
| Quick Actions | "Resume Session" (if active) or "New Session" button |
| This Week Activity | Cached stats: session count, clip count, athlete count |
| Recent Athletes | Quick access to recently worked-with folders |

---

## Key Files

| Component | Path |
|-----------|------|
| Session Manager | `PlayerPath/Services/CoachSessionManager.swift` |
| Video Processing | `PlayerPath/Services/CoachVideoProcessingService.swift` |
| Data Model | `PlayerPath/FirestoreModels.swift` (CoachSession) |
| Status Enum | `PlayerPath/Models/SessionStatus.swift` |
| Dashboard UI | `PlayerPath/CoachDashboardView.swift` |
| Folder Detail | `PlayerPath/CoachFolderDetailView.swift` |
| Session Creation | `PlayerPath/Views/Coach/StartSessionSheet.swift` |
| Live Card | `PlayerPath/Views/Coach/LiveSessionCard.swift` |
| Upcoming Card | `PlayerPath/Views/Coach/UpcomingSessionCard.swift` |
| Clip Review | `PlayerPath/Views/Coach/ClipReviewSheet.swift` |
| Camera Recorder | `PlayerPath/DirectCameraRecorderView.swift` |
| Athlete Picker | `PlayerPath/Views/Coach/SessionAthletePickerOverlay.swift` |

---

## Architectural Notes

1. **One-active-session constraint** -- starting a new session auto-ends the previous one
2. **Multi-athlete support** -- single session supports 1+ athletes; clips tagged to specific athlete post-recording
3. **Upload resilience** -- videos copied to stable Documents path before queuing; survives app backgrounding
4. **Non-fatal errors** -- thumbnail failures don't block upload; clips still recorded without thumbnails
5. **Tier enforcement** -- athlete limits checked at session creation time
6. **Activity notifications** -- sharing clips triggers athlete notifications via `ActivityNotificationService`
7. **Access revocation** -- sessions auto-end if coach loses upload permission mid-session
